#!/usr/bin/env python3
"""Synthetic traffic generator for the BPA-Demo web shop.

Continuously cycles through the demo user roster (seeded in
helm/php-demo/sql/seed.sql), logging in as each one in turn and performing
a randomized sequence of shop actions -- browsing, viewing products, using
the basket, checking out, and (for the admin account) visiting the admin
diagnostic pages. Cycling through every user on every pass guarantees the
`trouble`, `empty_basket`, and `locked` demo use cases (see CLAUDE.md's
"Demo use cases" section) all get exercised regularly, not just by chance.

Uses only the standard library -- no third-party dependencies, so there's
nothing to fetch at build time and the resulting image stays minimal.

Configuration is via environment variables; see the Dockerfile/README for
the full list and their defaults.
"""

import http.client
import http.cookiejar
import logging
import os
import random
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

# == Configuration ============================================================
# TRAFFIC_ENABLED=false keeps the container up but idle -- same pattern as
# APMIA_DEPLOY in src/dx-o2-agents/entrypoint.sh -- for when traffic is
# wanted off temporarily without editing docker-compose.yml/values.yaml.
TRAFFIC_ENABLED = os.environ.get("TRAFFIC_ENABLED", "true").lower() == "true"
BASE_URL = os.environ.get("TARGET_URL", "http://apachephp:8080").rstrip("/")
MIN_ACTION_DELAY_SECS = float(os.environ.get("MIN_ACTION_DELAY_SECS", "1"))
MAX_ACTION_DELAY_SECS = float(os.environ.get("MAX_ACTION_DELAY_SECS", "4"))
MIN_SESSION_DELAY_SECS = float(os.environ.get("MIN_SESSION_DELAY_SECS", "2"))
MAX_SESSION_DELAY_SECS = float(os.environ.get("MAX_SESSION_DELAY_SECS", "8"))
MIN_ACTIONS_PER_SESSION = int(os.environ.get("MIN_ACTIONS_PER_SESSION", "3"))
MAX_ACTIONS_PER_SESSION = int(os.environ.get("MAX_ACTIONS_PER_SESSION", "9"))
REQUEST_TIMEOUT_SECS = float(os.environ.get("REQUEST_TIMEOUT_SECS", "15"))
STARTUP_WAIT_TIMEOUT_SECS = float(os.environ.get("STARTUP_WAIT_TIMEOUT_SECS", "120"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("traffic-generator")

# Demo accounts, seeded in helm/php-demo/sql/seed.sql. All share the same
# password. trouble/empty/locked carry pre-assigned use cases (5000
# sequential DB reads per request, basket total always shown as 0, and
# login blocked, respectively) -- see CLAUDE.md's "Demo use cases" section.
PASSWORD = "demo123"
USERS = [
    "admin", "trouble", "empty", "alice", "bob", "charlie", "diana",
    "eve", "frank", "grace", "henry", "iris", "jack", "locked",
]

BRAND_SLUGS = ["shelly", "sonoff", "tuya"]
CAPABILITY_SLUGS = ["wifi", "zigbee", "matter", "z-wave", "bluetooth"]

# A handful of well-known, publicly documented Luhn-valid test card numbers
# (not real accounts) -- good enough to pass checkout.php's Luhn check.
TEST_CARD_NUMBERS = ["4532015112830366", "4539578763621486", "5425233430109903"]

CSRF_TOKEN_RE = re.compile(r'name="csrf_token" value="([^"]+)"')
PRODUCT_SLUG_RE = re.compile(r'/product\?slug=([a-z0-9-]+)')
PRODUCT_ID_RE = re.compile(r'name="product_id" value="(\d+)"')

NETWORK_ERRORS = (urllib.error.URLError, http.client.HTTPException, socket.timeout, OSError)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Disables automatic redirect-following so callers can inspect a
    3xx response's status/Location header themselves, matching how a
    caller would need to detect e.g. a successful login (302) versus a
    re-rendered form (200/403) -- urllib follows redirects by default,
    which would otherwise hide that distinction.
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


@dataclass
class BrowsingSession:
    """Per-user state carried between actions within one login session,
    mirroring what a real browser tab would remember: the cookie jar
    (via its opener), the product ids/slugs visible on the last page
    rendered, and whether the basket is believed to hold anything
    (best-effort -- the app is the source of truth, this is only used to
    decide which actions make sense to attempt next).
    """

    opener: urllib.request.OpenerDirector
    username: str
    is_admin: bool = False
    csrf_token: str = ""
    known_product_ids: list = field(default_factory=list)
    known_slugs: list = field(default_factory=list)
    basket_has_items: bool = False


@dataclass
class Response:
    """Minimal stand-in for the bits of an HTTP response this generator
    actually reads, since urllib returns a fresh, differently-shaped
    object depending on whether a redirect was followed.
    """

    status: int
    text: str
    location: str = ""


def new_session(username: str) -> BrowsingSession:
    cookiejar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        NoRedirect, urllib.request.HTTPCookieProcessor(cookiejar)
    )
    return BrowsingSession(opener=opener, username=username)


def _remember_page(session: BrowsingSession, html: str) -> None:
    """Updates session state from a freshly rendered page's HTML: the
    current CSRF token (regenerated by the app on login/logout, so it
    must always be re-read rather than cached across sessions) and any
    product ids/slugs newly visible, so later actions have something real
    to act on instead of guessing.
    """
    token = CSRF_TOKEN_RE.search(html)
    if token:
        session.csrf_token = token.group(1)
    session.known_product_ids = list(set(PRODUCT_ID_RE.findall(html))) or session.known_product_ids
    session.known_slugs = list(set(PRODUCT_SLUG_RE.findall(html))) or session.known_slugs


def _do_request(session: BrowsingSession, req: urllib.request.Request) -> Response:
    try:
        with session.opener.open(req, timeout=REQUEST_TIMEOUT_SECS) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return Response(status=resp.status, text=body, location=resp.headers.get("Location", ""))
    except urllib.error.HTTPError as err:
        # Any non-2xx status lands here, not in the `with` block above --
        # urllib raises HTTPError for these regardless of NoRedirect, even
        # though NoRedirect's job is specifically to let a 3xx through
        # un-followed. The app's own 403 (e.g. the `locked` use case) and
        # 404 (e.g. a missing product) responses land here too. All of
        # these are normal, expected outcomes this generator needs to
        # inspect the status/body of, not failures -- HTTPError itself is
        # a valid response-like object (status/headers/read()).
        body = err.read().decode("utf-8", errors="replace")
        return Response(status=err.code, text=body, location=err.headers.get("Location", ""))


def get(session: BrowsingSession, path: str) -> Response:
    """Issues a GET request and updates session state from the response."""
    resp = _do_request(session, urllib.request.Request(f"{BASE_URL}{path}"))
    log.debug("[%s] GET %s -> %s", session.username, path, resp.status)
    _remember_page(session, resp.text)
    return resp


def post(session: BrowsingSession, path: str, fields: dict) -> Response:
    """Issues a CSRF-protected POST request with the session's current
    token. Redirects are not followed (see NoRedirect) so callers can
    inspect the target themselves -- the app POST-Redirect-GETs on success.
    """
    body = {"csrf_token": session.csrf_token, **fields}
    data = urllib.parse.urlencode(body).encode("utf-8")
    req = urllib.request.Request(f"{BASE_URL}{path}", data=data, method="POST")
    resp = _do_request(session, req)
    log.debug("[%s] POST %s -> %s", session.username, path, resp.status)
    return resp


def sleep_between(min_secs: float, max_secs: float) -> None:
    time.sleep(random.uniform(min_secs, max_secs))


def wait_for_app() -> bool:
    """Blocks until the app answers /health, or STARTUP_WAIT_TIMEOUT_SECS
    elapses. The app container may still be starting when this one does --
    depends_on: service_healthy only guarantees the *container* passed its
    healthcheck, which races with this container's own startup.

    @return bool
      True once the app responds, False if the timeout was reached.
    """
    deadline = time.monotonic() + STARTUP_WAIT_TIMEOUT_SECS
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{BASE_URL}/health", timeout=5) as resp:
                if resp.status == 200:
                    return True
        except NETWORK_ERRORS:
            pass
        log.info("Waiting for %s to become reachable...", BASE_URL)
        time.sleep(3)
    return False


def login(username: str) -> BrowsingSession | None:
    """Attempts to log in as `username`.

    @return BrowsingSession|None
      A ready-to-use session on success. None on a failed login attempt --
      wrong credentials or the `locked` use case blocking it are both
      realistic, expected outcomes this generator tolerates rather than
      treats as an error.
    """
    session = new_session(username)
    get(session, "/shop")
    if not session.csrf_token:
        log.warning("[%s] no CSRF token found on /shop -- skipping this user", username)
        return None

    resp = post(session, "/login", {"username": username, "password": PASSWORD})
    if resp.status != 302:
        log.info(
            "[%s] login did not redirect (status %s) -- likely blocked (e.g. the "
            "'locked' use case) or a use-case-driven slowdown timed out; moving on",
            username, resp.status,
        )
        return None

    session.is_admin = username == "admin"
    get(session, resp.location or "/shop")
    log.info("[%s] logged in%s", username, " (admin)" if session.is_admin else "")
    return session


def action_browse_shop(session: BrowsingSession) -> None:
    """Views the shop listing, occasionally with a random filter applied
    (brand, capability, or page number) to vary the traffic pattern
    instead of always hitting the bare listing.
    """
    params = []
    roll = random.random()
    if roll < 0.15:
        params.append(f"brand={random.choice(BRAND_SLUGS)}")
    elif roll < 0.30:
        params.append(f"cap={random.choice(CAPABILITY_SLUGS)}")
    elif roll < 0.40:
        params.append(f"p={random.randint(2, 4)}")
    path = "/shop" + (f"?{'&'.join(params)}" if params else "")
    get(session, path)


def action_view_product(session: BrowsingSession) -> None:
    """Views a single product's detail page, picked from slugs seen on a
    previously rendered page. Falls back to browsing the shop first if no
    slug is known yet.
    """
    if not session.known_slugs:
        action_browse_shop(session)
    if session.known_slugs:
        get(session, f"/product?slug={random.choice(session.known_slugs)}")


def action_add_to_basket(session: BrowsingSession) -> None:
    """Adds a random known product to the basket. Falls back to browsing
    the shop first if no product id is known yet.
    """
    if not session.known_product_ids:
        action_browse_shop(session)
    if session.known_product_ids:
        product_id = random.choice(session.known_product_ids)
        post(session, "/basket", {
            "action": "add",
            "product_id": product_id,
            "qty": str(random.randint(1, 3)),
        })
        session.basket_has_items = True


def action_view_basket(session: BrowsingSession) -> None:
    get(session, "/basket")


def action_checkout(session: BrowsingSession) -> None:
    """Completes a checkout if the basket is believed to hold items.
    checkout.php redirects straight to /basket for an empty basket, so an
    empty attempt is harmless -- this still exercises that path some of
    the time when basket_has_items is stale/wrong.
    """
    resp = get(session, "/checkout")
    if resp.status != 200 or "billing_name" not in resp.text:
        return  # Redirected to /basket (empty) or page shape unexpected.

    year = time.gmtime().tm_year + 3
    resp = post(session, "/checkout", {
        "billing_name": f"{session.username.capitalize()} Demo",
        "billing_email": f"{session.username}@bpa.demo",
        "cc_number": random.choice(TEST_CARD_NUMBERS),
        "cc_expiry": f"12/{year % 100:02d}",
        "cc_cvv": str(random.randint(100, 999)),
    })
    if resp.status == 302:
        session.basket_has_items = False
        get(session, resp.location or "/shop")


def action_visit_admin_pages(session: BrowsingSession) -> None:
    """Admin-only diagnostic pages -- only called for the admin account."""
    get(session, random.choice(["/admin", "/info", "/db", "/dxo2"]))


# Weighted so basket/checkout activity (the interesting business flow) is
# common without crowding out plain browsing, which should still dominate.
WEIGHTED_ACTIONS = (
    [action_browse_shop] * 4
    + [action_view_product] * 3
    + [action_add_to_basket] * 3
    + [action_view_basket] * 2
    + [action_checkout] * 1
)


def run_user_session(username: str) -> None:
    """Logs in as `username`, performs a random number of random actions,
    then logs out. Any failure is caught by the caller -- one bad session
    must not stop the generator from moving on to the next user.
    """
    session = login(username)
    if session is None:
        return

    action_count = random.randint(MIN_ACTIONS_PER_SESSION, MAX_ACTIONS_PER_SESSION)
    actions = list(WEIGHTED_ACTIONS)
    if session.is_admin:
        actions = actions + [action_visit_admin_pages] * 2

    for _ in range(action_count):
        action = random.choice(actions)
        action(session)
        sleep_between(MIN_ACTION_DELAY_SECS, MAX_ACTION_DELAY_SECS)

    get(session, "/logout")
    log.info("[%s] session complete (%d actions)", username, action_count)


def main() -> None:
    if not TRAFFIC_ENABLED:
        log.info("TRAFFIC_ENABLED=false -- staying idle.")
        while True:
            time.sleep(3600)

    log.info("Traffic generator starting -- target %s", BASE_URL)
    if not wait_for_app():
        log.error("Timed out waiting for %s to become reachable -- exiting.", BASE_URL)
        sys.exit(1)

    while True:
        cycle_users = USERS.copy()
        random.shuffle(cycle_users)
        log.info("Starting a full user cycle (%d users)", len(cycle_users))
        for username in cycle_users:
            try:
                run_user_session(username)
            except NETWORK_ERRORS as exc:
                log.warning("[%s] request failed: %s", username, exc)
            except Exception:  # noqa: BLE001 - a single bad session must never kill the loop.
                log.exception("[%s] unexpected error during session", username)
            sleep_between(MIN_SESSION_DELAY_SECS, MAX_SESSION_DELAY_SECS)


if __name__ == "__main__":
    main()
