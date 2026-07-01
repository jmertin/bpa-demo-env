# Bug Report: PHP Probe Browser Agent Not Injecting into BPA-Demo App

**Date:** 2026-07-01  
**Status:** Resolved  
**Component:** `wily_php_agent` (DX O2 PHP Probe) — browser-agent auto-injection  

---

## Summary

The PHP probe's browser-agent snippet was not injected into any BPA-Demo page response, despite the probe being loaded, all INI properties being configured, and a test `info.php` (`<?php phpinfo(); ?>`) receiving injection successfully on the same server.

---

## Environment

| Item | Value |
|---|---|
| PHP probe | `wily_php_agent.so` (DX O2 PHP Agent) |
| PHP | 8.1 (mod_php / Apache SAPI) |
| Web server | Apache 2.4 |
| OS | Ubuntu 22.04 |
| App | BPA-Demo front-controller (single `index.php` entry point) |
| Deployment | Docker Compose |

---

## Observed Behaviour

- `http://bpa-demo.local:8080/info.php` (`<?php phpinfo(); ?>`) — snippet **injected** into response.
- `http://bpa-demo.local:8080/` (BPA-Demo app, front controller) — snippet **not injected**.
- `http://bpa-demo.local:8080/index.php` (same app, direct filename) — snippet **not injected**.

INI settings were confirmed correct via `/dxo2` status page:
- `wily_php_agent.enable.browseragent.response.decoration = 1` (master switch)
- `wily_php_agent.enable.browseragent.snippet.autoInjection = 1`
- `wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength = 30000`
- `wily_php_agent.browseragent.autoInjection.snippetString` set

---

## Diagnosis

### Step 1 — Enable debug logging

Set `wily_php_agent.logLevel = 1` (DEBUG) and restarted Apache to capture per-request probe decisions.

### Step 2 — Compare probe logs for the two URLs

**`/info.php` (injection works) — probe log:**
```
Frontend start: /info.php
Frontend URI: /info.php
BA Correlation  Content-type Header: Content-type: text/html; charset=UTF-8 and length 38
BA Correlation  cookie x-apm-brtm-servertime set successfully
BA Correlation  cookie x-apm-brtm-response-bt-page-info.php set successfully
BA Correlation  Search length is 30000
BA Correlation  head : pointer is 137
```

**`/` and `/index.php` (injection skipped) — probe log:**
```
Looking for include operation, current op = 61
Looking for include operation, current op = 62
Looking for include operation, current op = 62
Looking for include operation, current op = 62
SqlTracer:PDO  DB values parsed -> host : mariadb ,name : phpapp,port: 3306
Looking for include operation, current op = 136
BA Correlation  last seg of url : (null) and request_info.no_headers : 0
Request end
```

No `Frontend start:` line appears for `index.php`. The probe logs `last seg of url : (null)` and exits without injection.

### Step 3 — Root cause

The probe uses two mechanisms to decide whether to inject:

1. **Frontend start detection:** hooks PHP opcodes `ZEND_INCLUDE_OR_EVAL` (op codes 61, 62, 136) to identify "frontend pages". For a single-file request like `info.php` (no includes), this path is skipped and the probe falls back to URL-based detection → emits `Frontend start: /info.php`. For `index.php`, the probe sees multiple `require_once` calls (ops 61/62/136) and tracks includes instead of emitting a `Frontend start`.

2. **BA Correlation URL segment check:** regardless of how `Frontend start` was determined, the probe extracts the **last path segment of `REQUEST_URI`** to name its browser-agent response cookie (`x-apm-brtm-response-bt-page-<segment>`). It **explicitly treats both `/` and `index.php` as null segments** and skips BA injection when the result is null.

This means:
- `/info.php` → last segment = `info.php` → injection proceeds ✓
- `/` → last segment = `(null)` → injection skipped ✗
- `/index.php` → last segment = `(null)` (probe treats `index.php` same as bare `/`) → injection skipped ✗
- `/?page=shop` → path is `/`, last segment = `(null)` → injection skipped ✗

The probe was designed for traditional PHP apps where each page is a separate `.php` file. A front-controller pattern (all requests through `index.php`) is fundamentally incompatible with its URL-segment detection, because:
- The probe specifically ignores `index.php` as a meaningless segment.
- All `?page=` query-string variants route through the same null-segment path.

---

## Additional Bugs Found During Investigation

These were found by comparing `entrypoint.sh` against the official `installer.sh` from the DX O2 PHP agent archive.

### Bug 1 — `response.decoration=1` missing (master switch)

The official installer sets `wily_php_agent.enable.browseragent.response.decoration=1` when enabling browser agent. This is the module-level master switch; without it, `snippet.autoInjection=1` is silently ignored. The BPA-Demo entrypoint did not set this property.

**Fix:** Added `response.decoration=1` (set when `APMIA_BROWSER_SNIPPET` is non-empty, `0` when empty) to `entrypoint.sh`.

### Bug 2 — Wrong property name for `maxSearchingLength`

Entrypoint used:
```
wily_php_agent.enable.browseragent.snippet.maxSearchingLength
```
Correct property name (per official INI):
```
wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength
```
The wrong name was silently ignored; the property defaulted to 3000 bytes. With `</head>` at byte 239 this was technically sufficient, but 30000 is the documented maximum and gives 125× headroom.

**Fix:** Corrected property name; value set to `30000`.

### Bug 3 — `maxSearchingLength` value out of range

Even with the wrong name, the value was `32768`, which exceeds the documented valid range of `100–30000`. The probe clamps out-of-range values, resulting in undefined behaviour.

**Fix:** Changed to `30000`.

### Bug 4 — `logLevel` written as string instead of number

`wily_php_agent.logLevel` accepts only numeric values `0–5` (`0=trace, 1=debug, 2=info, 3=warning, 4=error, 5=fatal`). The entrypoint was writing the string `'INFO'` directly, which the probe silently ignores (reverts to default).

**Fix:** Added a `case` statement in `entrypoint.sh` that maps string names to their numeric equivalents before writing the INI property.

---

## Fix for Main Bug — Clean URLs via mod_rewrite

To give the probe a meaningful URL segment on every page request, Apache mod_rewrite was added to `vhost.conf` to route clean URLs through the front controller:

```apache
RewriteEngine On
# Redirect the bare root to /shop so the probe sees a meaningful URL segment.
RewriteRule ^$ /shop [R=302,L]
# Route clean page URLs through the front controller.
# REQUEST_URI stays as /shop, /basket, /product, etc. — the PHP probe reads
# this and extracts a meaningful last segment for browser-agent cookie naming
# (avoids the null-segment skip triggered by index.php and bare / URLs).
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^([a-z][a-z0-9_-]*)$ /index.php?page=$1 [L,QSA]
```

**How it works:**
- Apache rewrites `/shop` to `index.php?page=shop` **internally** — `REQUEST_URI` stays as `/shop` from the client's perspective (and what the probe reads).
- `$_GET['page']` is set to `shop` by the rewrite rule — front-controller routing is unchanged.
- `[QSA]` (Query String Append) preserves filter parameters: `/shop?brand=aeroqube` → QUERY_STRING `page=shop&brand=aeroqube`.
- The probe reads `REQUEST_URI = /shop` → last segment = `shop` → names cookie `x-apm-brtm-response-bt-page-shop` → injection proceeds.

All `href="?page=xxx"` links and `header('Location: ?page=xxx')` redirects across 12 PHP files were updated to absolute clean URLs (`/shop`, `/basket`, `/product`, `/login`, etc.).

**Files changed:**
- `src/apache-php/config/vhost.conf` — RewriteEngine rules
- `app/src/templates/layout.php` — all navigation links
- `app/src/pages/shop.php` — filter form action, product links, pagination, basket form
- `app/src/pages/product.php` — breadcrumb, form action, redirect
- `app/src/pages/basket.php` — PRG redirect, shop/product/checkout links
- `app/src/pages/checkout.php` — redirects, basket link
- `app/src/pages/order.php` — redirect, shop/order-detail links
- `app/src/pages/login.php` — post-login redirects
- `app/src/pages/logout.php` — redirect
- `app/src/pages/admin.php` — PRG redirect
- `app/src/lib/auth.php` — `auth_require_login()` redirect
- `app/src/usecases/locked.php` — eviction redirect

---

## Expected Behaviour After Fix

| URL | `REQUEST_URI` last segment | BA cookie name | Injection |
|---|---|---|---|
| `/shop` | `shop` | `x-apm-brtm-response-bt-page-shop` | ✓ |
| `/shop?brand=aeroqube` | `shop` | `x-apm-brtm-response-bt-page-shop` | ✓ |
| `/product?slug=shelly-plug-s` | `product` | `x-apm-brtm-response-bt-page-product` | ✓ |
| `/basket` | `basket` | `x-apm-brtm-response-bt-page-basket` | ✓ |
| `/checkout` | `checkout` | `x-apm-brtm-response-bt-page-checkout` | ✓ |
| `/order` | `order` | `x-apm-brtm-response-bt-page-order` | ✓ |
| `/login` | `login` | `x-apm-brtm-response-bt-page-login` | ✓ |
| `/admin` | `admin` | `x-apm-brtm-response-bt-page-admin` | ✓ |
| `/dxo2` | `dxo2` | `x-apm-brtm-response-bt-page-dxo2` | ✓ |

---

## Verification

After rebuild (`build-scripts/build.sh && build-scripts/compose.sh up -d`):

1. Set `APMIA_PHP_LOG_LEVEL=DEBUG` temporarily in `.config`.
2. Visit `http://bpa-demo.local:8080/shop`.
3. Check probe log in `/var/log/php-probe/wily_php_agent_<pid>.log`:
   ```
   Frontend start: /shop
   BA Correlation  cookie x-apm-brtm-response-bt-page-shop set successfully
   BA Correlation  head : pointer is <N>
   ```
4. Inspect the HTTP response body — the `<script>` snippet should appear inside `<head>`.
5. Restore `APMIA_PHP_LOG_LEVEL=INFO`.
