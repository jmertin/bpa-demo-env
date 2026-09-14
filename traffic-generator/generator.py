#!/usr/bin/env python3
"""Synthetic traffic generator using Browserless & Playwright.

Executes real browser rendering and client-side JavaScript execution via a 
Browserless container instance. Simulates realistic global user sessions with 
geographic location tagging (coordinates, locale), spoofed client proxy IP headers 
(X-Forwarded-For) for GeoIP identification in APM/AXA, randomized session identifiers 
(UUIDs), dynamic global timezones, and continent-based RTT latency adjustments via CDP.
"""

import logging
import os
import queue
import random
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from playwright.sync_api import sync_playwright, Page, BrowserContext

# == Configuration ============================================================
TRAFFIC_ENABLED = os.environ.get("TRAFFIC_ENABLED", "true").lower() == "true"
BASE_URL = os.environ.get("TARGET_URL", "http://apachephp:8080").rstrip("/")
BROWSERLESS_URL = os.environ.get("BROWSERLESS_URL", "ws://localhost:3000")
APP_TYPE = os.environ.get("APP_TYPE", "mp")

MIN_ACTION_DELAY_SECS = float(os.environ.get("MIN_ACTION_DELAY_SECS", "1"))
MAX_ACTION_DELAY_SECS = float(os.environ.get("MAX_ACTION_DELAY_SECS", "4"))
MIN_SESSION_DELAY_SECS = float(os.environ.get("MIN_SESSION_DELAY_SECS", "2"))
MAX_SESSION_DELAY_SECS = float(os.environ.get("MAX_SESSION_DELAY_SECS", "8"))
MIN_ACTIONS_PER_SESSION = int(os.environ.get("MIN_ACTIONS_PER_SESSION", "3"))
MAX_ACTIONS_PER_SESSION = int(os.environ.get("MAX_ACTIONS_PER_SESSION", "9"))
STARTUP_WAIT_TIMEOUT_SECS = float(os.environ.get("STARTUP_WAIT_TIMEOUT_SECS", "120"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

ANONYMOUS_RATIO = float(os.environ.get("TRAFFIC_ANONYMOUS_RATIO", "0.8"))
CONCURRENT_SESSIONS = int(os.environ.get("TRAFFIC_CONCURRENT_SESSIONS", "3"))

SLOWDOWN_PROBABILITY = float(os.environ.get("TRAFFIC_SLOWDOWN_PROBABILITY", "0.12"))
SLOWDOWN_MIN_SECS = float(os.environ.get("TRAFFIC_SLOWDOWN_MIN_SECS", "3"))
SLOWDOWN_MAX_SECS = float(os.environ.get("TRAFFIC_SLOWDOWN_MAX_SECS", "12"))

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("traffic-generator")

PASSWORD = "demo123"
USERS = [
    "admin", "trouble", "empty", "alice", "bob", "charlie", "diana",
    "eve", "frank", "grace", "henry", "iris", "jack", "locked",
]

BRAND_SLUGS = ["shelly", "sonoff", "tuya"]
CAPABILITY_SLUGS = ["wifi", "zigbee", "matter", "z-wave", "bluetooth"]
TEST_CARD_NUMBERS = ["4532015112830366", "4539578763621486", "5425233430109903"]


# == Dynamic Timezones & Geographic Profiles ==================================
TIMEZONES = [
    "America/New_York", "America/Los_Angeles", "America/Chicago",
    "Europe/London", "Europe/Paris", "Europe/Berlin",
    "Asia/Tokyo", "Asia/Singapore", "Asia/Kolkata",
    "Australia/Sydney", "America/Sao_Paulo", "Africa/Johannesburg",
]


@dataclass
class LocationProfile:
    name: str
    continent: str
    locale: str
    latitude: float
    longitude: float
    added_rtt_ms: int
    sample_ip: str  # Regional public IP for HTTP X-Forwarded-For spoofing


LOCATIONS = [
    LocationProfile("Local-EU", "Europe", "en-GB", 51.5074, -0.1278, added_rtt_ms=0, sample_ip="185.86.151.11"),
    LocationProfile("US-East", "North America", "en-US", 40.7128, -74.0060, added_rtt_ms=40, sample_ip="40.71.1.1"),
    LocationProfile("US-West", "North America", "en-US", 34.0522, -118.2437, added_rtt_ms=75, sample_ip="54.183.0.1"),
    LocationProfile("SA-SaoPaulo", "South America", "pt-BR", -23.5505, -46.6333, added_rtt_ms=130, sample_ip="177.131.0.1"),
    LocationProfile("Asia-Tokyo", "Asia", "ja-JP", 35.6762, 139.6503, added_rtt_ms=180, sample_ip="133.242.0.1"),
    LocationProfile("AU-Sydney", "Oceania", "en-AU", -33.8688, 151.2093, added_rtt_ms=240, sample_ip="139.130.4.5"),
]


def page_path(page: str, **params: str) -> str:
    if APP_TYPE != "plain":
        path = f"/{page}"
        query = "&".join(f"{k}={v}" for k, v in params.items())
        return f"{path}?{query}" if query else path
    all_params = {"page": page, **params}
    return f"/index.php?{'&'.join(f'{k}={v}' for k, v in all_params.items())}"


@dataclass
class BrowsingSession:
    context: BrowserContext
    page: Page
    username: str
    session_id: str
    location: LocationProfile
    timezone: str
    is_admin: bool = False


def sleep_between(min_secs: float, max_secs: float) -> None:
    time.sleep(random.uniform(min_secs, max_secs))


def sleep_with_shaping(min_secs: float, max_secs: float) -> None:
    sleep_between(min_secs, max_secs)
    if random.random() < SLOWDOWN_PROBABILITY:
        extra = random.uniform(SLOWDOWN_MIN_SECS, SLOWDOWN_MAX_SECS)
        log.debug("Simulating a slow client/network burst (+%.1fs)", extra)
        time.sleep(extra)


def wait_for_app() -> bool:
    deadline = time.monotonic() + STARTUP_WAIT_TIMEOUT_SECS
    with sync_playwright() as p:
        while time.monotonic() < deadline:
            try:
                browser = p.chromium.connect_over_cdp(BROWSERLESS_URL)
                page = browser.new_page()
                res = page.goto(f"{BASE_URL}/health", timeout=5000)
                browser.close()
                if res and res.status == 200:
                    return True
            except Exception:
                pass
            log.info("Waiting for %s to become reachable via Browserless...", BASE_URL)
            time.sleep(3)
    return False


def create_browser_session(p, username: str) -> BrowsingSession:
    """Connects to Browserless, creates a context configured with a random location,
    randomized IANA timezone, client IP headers (X-Forwarded-For), and unique per-session UUID.
    """
    location = random.choice(LOCATIONS)
    selected_timezone = random.choice(TIMEZONES)
    session_id = f"{username}-{uuid.uuid4().hex[:8]}"

    browser = p.chromium.connect_over_cdp(BROWSERLESS_URL)

    # Configure geographic, timezone, locale, and proxy IP headers
    context = browser.new_context(
        locale=location.locale,
        timezone_id=selected_timezone,
        geolocation={"latitude": location.latitude, "longitude": location.longitude},
        permissions=["geolocation"],
        extra_http_headers={
            "X-Simulated-Region": location.name,
            "X-Simulated-Continent": location.continent,
            "X-Session-ID": session_id,
            # Reverse proxy headers picked up by Apache mod_remoteip & AXA for GeoIP evaluation
            "X-Forwarded-For": location.sample_ip,
            "X-Real-IP": location.sample_ip,
            "Client-IP": location.sample_ip,
            "CF-Connecting-IP": location.sample_ip,
        },
    )

    page = context.new_page()

    # Emulate cross-continent network latency (RTT) via Chrome DevTools Protocol (CDP)
    if location.added_rtt_ms > 0:
        cdp = context.new_cdp_session(page)
        cdp.send(
            "Network.emulateNetworkConditions",
            {
                "offline": False,
                "latency": location.added_rtt_ms,
                "downloadThroughput": -1,
                "uploadThroughput": -1,
            },
        )

    log.debug(
        "[%s] Configured session: IP=%s, Timezone=%s, Geo=%s (%s), Latency=+%dms RTT",
        session_id, location.sample_ip, selected_timezone, location.name, location.continent, location.added_rtt_ms,
    )
    return BrowsingSession(
        context=context,
        page=page,
        username=username,
        session_id=session_id,
        location=location,
        timezone=selected_timezone,
    )


def login(session: BrowsingSession) -> bool:
    try:
        session.page.goto(f"{BASE_URL}{page_path('shop')}")
        session.page.goto(f"{BASE_URL}{page_path('login')}")

        # Verify client-side JS timezone execution context
        active_tz = session.page.evaluate("Intl.DateTimeFormat().resolvedOptions().timeZone")
        log.debug("[%s] Client JS verified timezone: %s", session.session_id, active_tz)

        session.page.fill('input[name="username"]', session.username)
        session.page.fill('input[name="password"]', PASSWORD)

        with session.page.expect_navigation(timeout=10000):
            session.page.click('button[type="submit"], input[type="submit"]')

        if "/login" in session.page.url:
            log.info("[%s] Login failed or blocked (e.g. 'locked' account)", session.session_id)
            return False

        session.is_admin = session.username == "admin"
        log.info(
            "[%s] Logged in successfully (%s) [IP: %s, Location: %s, TZ: %s, RTT +%dms]",
            session.session_id, "admin" if session.is_admin else "user",
            session.location.sample_ip, session.location.name, session.timezone, session.location.added_rtt_ms,
        )
        return True
    except Exception as exc:
        log.warning("[%s] Login error: %s", session.session_id, exc)
        return False


def action_browse_shop(session: BrowsingSession) -> None:
    params = {}
    roll = random.random()
    if roll < 0.15:
        params["brand"] = random.choice(BRAND_SLUGS)
    elif roll < 0.30:
        params["cap"] = random.choice(CAPABILITY_SLUGS)
    elif roll < 0.40:
        params["p"] = str(random.randint(2, 4))
    
    session.page.goto(f"{BASE_URL}{page_path('shop', **params)}")


def action_view_product(session: BrowsingSession) -> None:
    session.page.goto(f"{BASE_URL}{page_path('shop')}")
    product_links = session.page.locator('a[href*="product"]').all()
    if product_links:
        target_link = random.choice(product_links)
        target_link.click()
        session.page.wait_for_load_state("domcontentloaded")


def action_add_to_basket(session: BrowsingSession) -> None:
    session.page.goto(f"{BASE_URL}{page_path('shop')}")
    add_buttons = session.page.locator('form[action*="basket"] button, form[action*="basket"] input[type="submit"]').all()
    if add_buttons:
        random.choice(add_buttons).click()
        session.page.wait_for_load_state("domcontentloaded")


def action_view_basket(session: BrowsingSession) -> None:
    session.page.goto(f"{BASE_URL}{page_path('basket')}")


def action_checkout(session: BrowsingSession) -> None:
    session.page.goto(f"{BASE_URL}{page_path('checkout')}")
    if session.page.locator('input[name="billing_name"]').count() > 0:
        year = time.gmtime().tm_year + 3
        session.page.fill('input[name="billing_name"]', f"{session.username.capitalize()} Demo")
        session.page.fill('input[name="billing_email"]', f"{session.username}@bpa.demo")
        session.page.fill('input[name="cc_number"]', random.choice(TEST_CARD_NUMBERS))
        session.page.fill('input[name="cc_expiry"]', f"12/{year % 100:02d}")
        session.page.fill('input[name="cc_cvv"]', str(random.randint(100, 999)))
        
        session.page.click('button[type="submit"], input[type="submit"]')
        session.page.wait_for_load_state("domcontentloaded")


def action_visit_admin_pages(session: BrowsingSession) -> None:
    target = random.choice(["admin", "info", "db", "dxo2"])
    session.page.goto(f"{BASE_URL}{page_path(target)}")


WEIGHTED_ACTIONS = (
    [action_browse_shop] * 4
    + [action_view_product] * 3
    + [action_add_to_basket] * 3
    + [action_view_basket] * 2
    + [action_checkout] * 1
)


def _run_session_actions(session: BrowsingSession) -> int:
    action_count = random.randint(MIN_ACTIONS_PER_SESSION, MAX_ACTIONS_PER_SESSION)
    actions = list(WEIGHTED_ACTIONS)
    if session.is_admin:
        actions = actions + [action_visit_admin_pages] * 2

    for _ in range(action_count):
        action = random.choice(actions)
        try:
            action(session)
        except Exception as err:
            log.debug("[%s] Action error: %s", session.session_id, err)
        sleep_with_shaping(MIN_ACTION_DELAY_SECS, MAX_ACTION_DELAY_SECS)

    return action_count


def run_session(p, kind: str, ident: str) -> None:
    session = create_browser_session(p, ident)
    try:
        if kind == "auth":
            if not login(session):
                return
        else:
            session.page.goto(f"{BASE_URL}{page_path('shop')}")
            active_tz = session.page.evaluate("Intl.DateTimeFormat().resolvedOptions().timeZone")
            log.debug("[%s] Guest Client JS verified timezone: %s", session.session_id, active_tz)

        actions_done = _run_session_actions(session)
        
        if kind == "auth":
            session.page.goto(f"{BASE_URL}{page_path('logout')}")

        log.info(
            "[%s] %s session complete (%d actions) [IP: %s, Location: %s, TZ: %s]",
            session.session_id, kind, actions_done, session.location.sample_ip, session.location.name, session.timezone,
        )
    finally:
        session.context.close()


def _build_cycle_tasks() -> list[tuple[str, str]]:
    auth_tasks = [("auth", username) for username in USERS]
    guest_count = (
        len(auth_tasks) * 4
        if ANONYMOUS_RATIO >= 1.0
        else round(len(auth_tasks) * ANONYMOUS_RATIO / max(0.01, (1 - ANONYMOUS_RATIO)))
    )
    # Generate unique UUID-suffixed identifiers for guest sessions per cycle
    guest_tasks = [("guest", f"guest-{uuid.uuid4().hex[:6]}") for _ in range(guest_count)]

    tasks = auth_tasks + guest_tasks
    random.shuffle(tasks)
    return tasks


def _worker(task_queue: "queue.Queue[tuple[str, str]]") -> None:
    with sync_playwright() as p:
        while True:
            try:
                kind, ident = task_queue.get_nowait()
            except queue.Empty:
                return
            try:
                run_session(p, kind, ident)
            except Exception as exc:
                log.warning("[%s] Browser session error: %s", ident, exc)
            finally:
                task_queue.task_done()
            sleep_between(MIN_SESSION_DELAY_SECS, MAX_SESSION_DELAY_SECS)


def main() -> None:
    if not TRAFFIC_ENABLED:
        log.info("TRAFFIC_ENABLED=false -- staying idle.")
        while True:
            time.sleep(3600)

    log.info("Traffic generator starting via Browserless target %s", BROWSERLESS_URL)
    if not wait_for_app():
        log.error("Timed out waiting for target app -- exiting.")
        sys.exit(1)

    while True:
        tasks = _build_cycle_tasks()
        task_queue: "queue.Queue[tuple[str, str]]" = queue.Queue()
        for task in tasks:
            task_queue.put(task)

        workers = [
            threading.Thread(target=_worker, args=(task_queue,), daemon=True)
            for _ in range(max(1, CONCURRENT_SESSIONS))
        ]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join()


if __name__ == "__main__":
    main()
