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
    "America/Denver", "America/Phoenix", "America/Toronto",
    "America/Vancouver", "America/Mexico_City", "America/Buenos_Aires",
    "Europe/Madrid", "Europe/Rome", "Europe/Amsterdam", "Europe/Zurich",
    "Europe/Dublin", "Asia/Seoul", "Asia/Hong_Kong", "Asia/Taipei",
    "Asia/Dubai", "Asia/Bangkok", "Australia/Melbourne",
    "Pacific/Auckland", "Africa/Cairo", "Africa/Lagos",
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
    LocationProfile("US-Central-Denver", "North America", "en-US", 39.7392, -104.9903, added_rtt_ms=50, sample_ip="198.202.0.1"),
    LocationProfile("US-South-Atlanta", "North America", "en-US", 33.7490, -84.3880, added_rtt_ms=30, sample_ip="12.160.0.1"),
    LocationProfile("US-North-Seattle", "North America", "en-US", 47.6062, -122.3321, added_rtt_ms=70, sample_ip="205.175.0.1"),
    LocationProfile("CA-East-Toronto", "North America", "en-CA", 43.6532, -79.3832, added_rtt_ms=45, sample_ip="24.222.0.1"),
    LocationProfile("CA-West-Vancouver", "North America", "en-CA", 49.2827, -123.1207, added_rtt_ms=80, sample_ip="24.80.0.1"),
    LocationProfile("MX-Central-MexicoCity", "North America", "es-MX", 19.4326, -99.1332, added_rtt_ms=90, sample_ip="201.141.0.1"),
    LocationProfile("EU-DE-Frankfurt", "Europe", "de-DE", 50.1109, 8.6821, added_rtt_ms=10, sample_ip="80.156.0.1"),
    LocationProfile("EU-ES-Madrid", "Europe", "es-ES", 40.4168, -3.7038, added_rtt_ms=35, sample_ip="88.26.0.1"),
    LocationProfile("EU-IT-Rome", "Europe", "it-IT", 41.9028, 12.4964, added_rtt_ms=40, sample_ip="151.100.0.1"),
    LocationProfile("EU-NL-Amsterdam", "Europe", "nl-NL", 52.3676, 4.9041, added_rtt_ms=15, sample_ip="145.18.0.1"),
    LocationProfile("EU-CH-Zurich", "Europe", "de-CH", 47.3769, 8.5417, added_rtt_ms=20, sample_ip="193.134.0.1"),
    LocationProfile("EU-SE-Stockholm", "Europe", "sv-SE", 59.3293, 18.0686, added_rtt_ms=30, sample_ip="193.11.0.1"),
    LocationProfile("EU-NO-Oslo", "Europe", "nb-NO", 59.9139, 10.7522, added_rtt_ms=35, sample_ip="193.156.0.1"),
    LocationProfile("EU-DK-Copenhagen", "Europe", "da-DK", 55.6761, 12.5683, added_rtt_ms=25, sample_ip="192.38.0.1"),
    LocationProfile("EU-FI-Helsinki", "Europe", "fi-FI", 60.1699, 24.9384, added_rtt_ms=40, sample_ip="193.166.0.1"),
    LocationProfile("EU-PL-Warsaw", "Europe", "pl-PL", 52.2297, 21.0122, added_rtt_ms=35, sample_ip="212.77.0.1"),
    LocationProfile("EU-IE-Dublin", "Europe", "en-IE", 53.3498, -6.2603, added_rtt_ms=20, sample_ip="185.7.0.1"),
    LocationProfile("EU-BE-Brussels", "Europe", "nl-BE", 50.8503, 4.3517, added_rtt_ms=15, sample_ip="193.190.0.1"),
    LocationProfile("EU-AT-Vienna", "Europe", "de-AT", 48.2082, 16.3738, added_rtt_ms=25, sample_ip="193.170.0.1"),
    LocationProfile("EU-CZ-Prague", "Europe", "cs-CZ", 50.0755, 14.4378, added_rtt_ms=30, sample_ip="195.113.0.1"),
    LocationProfile("EU-HU-Budapest", "Europe", "hu-HU", 47.4979, 19.0402, added_rtt_ms=35, sample_ip="193.224.0.1"),
    LocationProfile("EU-GR-Athens", "Europe", "el-GR", 37.9838, 23.7275, added_rtt_ms=55, sample_ip="194.219.0.1"),
    LocationProfile("EU-PT-Lisbon", "Europe", "pt-PT", 38.7223, -9.1393, added_rtt_ms=45, sample_ip="193.136.0.1"),
    LocationProfile("EU-TR-Istanbul", "Europe", "tr-TR", 41.0082, 28.9784, added_rtt_ms=60, sample_ip="212.175.0.1"),
    LocationProfile("EU-RO-Bucharest", "Europe", "ro-RO", 44.4268, 26.1025, added_rtt_ms=50, sample_ip="193.226.0.1"),
    LocationProfile("EU-UA-Kyiv", "Europe", "uk-UA", 50.4501, 30.5234, added_rtt_ms=55, sample_ip="194.44.0.1"),
    LocationProfile("Asia-Seoul", "Asia", "ko-KR", 37.5665, 126.9780, added_rtt_ms=190, sample_ip="211.234.0.1"),
    LocationProfile("Asia-HongKong", "Asia", "zh-HK", 22.3193, 114.1694, added_rtt_ms=175, sample_ip="203.186.0.1"),
    LocationProfile("Asia-Taipei", "Asia", "zh-TW", 25.0330, 121.5654, added_rtt_ms=185, sample_ip="140.112.0.1"),
    LocationProfile("Asia-Beijing", "Asia", "zh-CN", 39.9042, 116.4074, added_rtt_ms=210, sample_ip="202.108.0.1"),
    LocationProfile("Asia-Shanghai", "Asia", "zh-CN", 31.2304, 121.4737, added_rtt_ms=205, sample_ip="202.96.209.1"),
    LocationProfile("Asia-Bangkok", "Asia", "th-TH", 13.7563, 100.5018, added_rtt_ms=200, sample_ip="202.44.0.1"),
    LocationProfile("Asia-Hanoi", "Asia", "vi-VN", 21.0285, 105.8542, added_rtt_ms=215, sample_ip="203.162.0.1"),
    LocationProfile("Asia-Jakarta", "Asia", "id-ID", -6.2088, 106.8456, added_rtt_ms=220, sample_ip="202.158.0.1"),
    LocationProfile("Asia-KualaLumpur", "Asia", "ms-MY", 3.1390, 101.6869, added_rtt_ms=195, sample_ip="202.184.0.1"),
    LocationProfile("Asia-Manila", "Asia", "fil-PH", 14.5995, 120.9842, added_rtt_ms=210, sample_ip="202.90.128.1"),
    LocationProfile("Asia-Mumbai", "Asia", "hi-IN", 19.0760, 72.8777, added_rtt_ms=160, sample_ip="115.240.0.1"),
    LocationProfile("Asia-Delhi", "Asia", "hi-IN", 28.6139, 77.2090, added_rtt_ms=165, sample_ip="122.160.0.1"),
    LocationProfile("ME-Dubai", "Middle East", "ar-AE", 25.2048, 55.2708, added_rtt_ms=140, sample_ip="185.93.0.1"),
    LocationProfile("ME-TelAviv", "Middle East", "he-IL", 32.0853, 34.7818, added_rtt_ms=120, sample_ip="192.114.0.1"),
    LocationProfile("ME-Riyadh", "Middle East", "ar-SA", 24.7136, 46.6753, added_rtt_ms=145, sample_ip="212.138.0.1"),
    LocationProfile("AF-Cairo", "Africa", "ar-EG", 30.0444, 31.2357, added_rtt_ms=130, sample_ip="197.32.0.1"),
    LocationProfile("AF-Nairobi", "Africa", "sw-KE", -1.2921, 36.8219, added_rtt_ms=190, sample_ip="196.201.0.1"),
    LocationProfile("AF-Lagos", "Africa", "en-NG", 6.5244, 3.3792, added_rtt_ms=170, sample_ip="197.210.0.1"),
    LocationProfile("SA-BuenosAires", "South America", "es-AR", -34.6037, -58.3816, added_rtt_ms=150, sample_ip="200.16.0.1"),
    LocationProfile("SA-Santiago", "South America", "es-CL", -33.4489, -70.6693, added_rtt_ms=160, sample_ip="200.1.0.1"),
    LocationProfile("SA-Bogota", "South America", "es-CO", 4.7110, -74.0721, added_rtt_ms=110, sample_ip="200.21.0.1"),
    LocationProfile("SA-Lima", "South America", "es-PE", -12.0464, -77.0428, added_rtt_ms=135, sample_ip="200.48.0.1"),
    LocationProfile("OC-Auckland", "Oceania", "en-NZ", -36.8485, 174.7633, added_rtt_ms=260, sample_ip="202.36.0.1"),
    LocationProfile("OC-Melbourne", "Oceania", "en-AU", -37.8136, 144.9631, added_rtt_ms=250, sample_ip="139.130.4.1"),
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
