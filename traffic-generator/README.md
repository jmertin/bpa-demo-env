# traffic-generator

Synthetic user traffic generator for the BPA-Demo web shop. Runs continuously inside a single Docker container hosting both a headless Chromium service (**Browserless**) and a **Python Playwright** execution engine.

Every cycle assigns each demo user an authenticated session alongside a configurable ratio of anonymous guest sessions. Sessions execute real browser rendering and client-side JavaScript, simulating realistic global visitors with randomized locations, dynamic timezones, UUID-based session IDs, simulated network RTT latencies, and proxy IP headers for App Experience Analytics (AXA) GeoIP mapping.

## What It Does

Each cycle builds a shuffled queue of authenticated and guest sessions executed concurrently by worker threads:

* **Real Browser Engine:** Replaces standard HTTP libraries with headless Chromium connected over WebSockets (`ws://localhost:3000`) via Playwright, executing full client-side JavaScript, dynamic DOM updates, and analytics tracking tags.
* **AXA GeoIP Spoofing:** Injects regional public IP addresses (`X-Forwarded-For`, `X-Real-IP`, `Client-IP`, `CF-Connecting-IP`) into every browser context so downstream APM and App Experience Analytics (AXA) agents map traffic to real global regions.
* **Geographic & Timezone Emulation:** Configures browser contexts with regional geolocation coordinates, locales, and randomized IANA timezones (e.g., `Europe/Berlin`, `Asia/Tokyo`, `America/New_York`).
* **Cross-Continent Latency (RTT):** Uses Chrome DevTools Protocol (`Network.emulateNetworkConditions`) to apply realistic round-trip latencies (+40ms to +240ms RTT) based on the simulated continent.
* **Unique Session Tracing:** Appends unique UUIDs (`user-a1b2c3d4`, `guest-e5f6g7h8`) to session logs and HTTP headers (`X-Session-ID`) to distinguish individual visits.
* **Realistic User Behavior:** Cycles through demo users (`trouble`, `empty`, `locked`, `admin`, etc.) performing randomized shop actions (browsing, product viewing, basket management, checkout, and admin diagnostics) with randomized pacing and client slowdown bursts.



## Configuration

All configuration is managed via environment variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TARGET_URL` | `http://apachephp:8080` | Base URL of the target web application

 |
| `BROWSERLESS_URL` | `ws://localhost:3000` | WebSocket endpoint for the local Browserless Chromium service |
| `TRAFFIC_CONCURRENT_SESSIONS` | `3` | Number of concurrent browser worker threads running in parallel

 |
| `TRAFFIC_ANONYMOUS_RATIO` | `0.8` | Share of cycle sessions that browse anonymously without logging in

 |
| `MIN_ACTION_DELAY_SECS` / `MAX_ACTION_DELAY_SECS` | `1` / `4` | Pause duration between individual browser actions

 |
| `MIN_SESSION_DELAY_SECS` / `MAX_SESSION_DELAY_SECS` | `2` / `8` | Pause between a worker completing one session and starting the next

 |
| `MIN_ACTIONS_PER_SESSION` / `MAX_ACTIONS_PER_SESSION` | `3` / `9` | Action count per user session

 |
| `TRAFFIC_SLOWDOWN_PROBABILITY` | `0.12` | Chance an action gets an extra "slow network/client" delay

 |
| `TRAFFIC_SLOWDOWN_MIN_SECS` / `TRAFFIC_SLOWDOWN_MAX_SECS` | `3` / `12` | Delay range applied during a simulated slowdown burst

 |
| `STARTUP_WAIT_TIMEOUT_SECS` | `120` | Timeout waiting for the target app `/health` endpoint at startup

 |
| `LOG_LEVEL` | `INFO` | Logging level (`INFO` or `DEBUG`)

 |

## Apache Configuration for AXA GeoIP (`mod_remoteip`)

Because all requests originate from the Docker container's local IP address, the target Apache web server must be configured with `mod_remoteip` to process the `X-Forwarded-For` header spoofed by `generator.py`. This ensures PHP and App Experience Analytics (AXA) record the simulated global IPs.

Enable `mod_remoteip` and add the following block to your Apache configuration (`/etc/apache2/apache2.conf`):

```apache
<IfModule mod_remoteip_module>
    # Read true client IP from proxy headers sent by generator.py
    RemoteIPHeader X-Forwarded-For

    # Trust internal Docker network subnets
    RemoteIPInternalProxy 10.0.0.0/8
    RemoteIPInternalProxy 172.16.0.0/12
    RemoteIPInternalProxy 192.168.0.0/16
</IfModule>

```

## Corporate Firewall & Certificate Support

If building inside an enterprise network with SSL-inspecting proxies:

1. Place your corporate CA certificate file (`corporate-ca.crt`) in the root build directory alongside the `Dockerfile`.
2. The `Dockerfile` copies `corporate-ca.crt` to `/usr/local/share/ca-certificates/`, runs `update-ca-certificates`, and configures `SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE` so Playwright and Python validate HTTPS connections securely.

## Building and Running Standalone

**Build the All-in-One Container:**

```bash
docker build -t traffic-generator .

```

**Run Container:**

```bash
docker run --rm \
  -e TARGET_URL=http://localhost:8080 \
  -e BROWSERLESS_URL=ws://localhost:3000 \
  -p 3000:3000 \
  traffic-generator

