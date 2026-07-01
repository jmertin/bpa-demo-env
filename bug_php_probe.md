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

### Step 3 — First attempted fix (REQUEST_URI — insufficient)

Added mod_rewrite rules to `vhost.conf` to route `/shop` → `index.php?page=shop`.
The probe's `last seg of url` check reads `REQUEST_URI = /shop` → segment `shop` — but injection still did not occur.

The probe also requires a `Frontend start` event to be established. Because `index.php` opens with `require_once` calls (PHP opcodes 61/62/136 — include-type), the probe never emits `Frontend start` for `index.php`. Without `Frontend start`, the probe does not proceed to BA injection regardless of `REQUEST_URI`.

### Step 4 — Root cause (SCRIPT_NAME + Frontend start)

The probe has two independent gates that must both be satisfied for BA injection:

**Gate 1 — Frontend start detection:**
The probe hooks PHP's opcode executor. When the very first opcode of a script is a non-include opcode, the probe establishes `Frontend start: <SCRIPT_NAME>`. When the very first opcode is an include (op 61/62/136), the probe enters include-tracking mode and never emits `Frontend start`. Without `Frontend start`, BA injection is skipped entirely.

`index.php` opens with multiple `require_once` calls → the probe sees op=61,62,62,62,136... as the first opcodes → no `Frontend start` → BA skip.

`info.php` has only `<?php phpinfo(); ?>` → `DO_ICALL` is the first opcode (non-include) → `Frontend start: /info.php` → BA proceeds.

**Gate 2 — BA Correlation URL segment check:**
Once `Frontend start` is established, the probe reads `SCRIPT_NAME` to determine the cookie name.
It explicitly treats `index.php` and bare `/` as **null segments** and skips BA injection for those URLs.

With mod_rewrite mapping `/shop` → `index.php?page=shop`:
- `SCRIPT_NAME = /index.php` → last segment = `index.php` → **null** → BA skip regardless of REQUEST_URI

Both gates must pass. The previous fix addressed REQUEST_URI but not SCRIPT_NAME, and did not address the Frontend start detection at all.

---

## Fix — Per-Page Wrapper Files

The correct fix requires per-page wrapper PHP files at the document root so that:

1. `SCRIPT_NAME = /shop.php` → last segment `shop` (not `index.php`) → passes Gate 2
2. A non-include opcode runs as the very first opcode → probe emits `Frontend start: /shop.php` → passes Gate 1

**Wrapper pattern** (`app/src/shop.php`, `basket.php`, etc.):
```php
<?php
$_GET['page'] ??= basename(__FILE__, '.php'); // non-include opcode: forces PHP probe Frontend start
require __DIR__ . '/index.php';
```

The `$_GET['page'] ??= ...` line compiles to FETCH_IS + QM_ASSIGN opcodes (non-include). These execute before the `require`, triggering `Frontend start: /shop.php`. A bare `require` as the very first line would compile to op=61 (include) and defeat Gate 1.

The `??= basename(__FILE__, '.php')` also provides a defensive fallback: if someone accesses `/shop.php` directly (bypassing the rewrite), `$_GET['page']` is set from the filename.

**Updated vhost.conf rewrite** routes to wrapper files instead of `index.php`:
```apache
RewriteRule ^([a-z][a-z0-9_-]*)$ /$1.php?page=$1 [L,QSA]
```

With this:
- `SCRIPT_NAME = /shop.php` → last segment `shop` ✓
- `REQUEST_URI = /shop` (stays as the original clean URL) → probe uses this for the BA cookie name → `x-apm-brtm-response-bt-page-shop`

**Confirmed working — probe log after fix:**
```
Frontend start: /shop.php
Frontend URI: /shop
BA Correlation  cookie x-apm-brtm-response-bt-page-shop set successfully
BA Correlation  Search length is 4142
BA Correlation  head : pointer is 33
BA Correlation  Response written length is 4683 and total length parsed 4142
```

HTTP response body confirmed to contain `<script type="text/javascript" id="ca_eum_ba" src="...">`.

**Files created/modified:**
- `src/apache-php/config/vhost.conf` — rewrite target `/$1.php?page=$1` (was `/index.php?page=$1`)
- `app/src/shop.php` — new wrapper
- `app/src/basket.php` — new wrapper
- `app/src/product.php` — new wrapper
- `app/src/checkout.php` — new wrapper
- `app/src/order.php` — new wrapper
- `app/src/login.php` — new wrapper
- `app/src/logout.php` — new wrapper
- `app/src/admin.php` — new wrapper
- `app/src/info.php` — new wrapper
- `app/src/db.php` — new wrapper
- `app/src/dxo2.php` — new wrapper

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

## Expected Behaviour After Fix

| URL | `SCRIPT_NAME` | `REQUEST_URI` last seg | BA cookie name | Injection |
|---|---|---|---|---|
| `/shop` | `/shop.php` | `shop` | `x-apm-brtm-response-bt-page-shop` | ✓ |
| `/shop?brand=aeroqube` | `/shop.php` | `shop` | `x-apm-brtm-response-bt-page-shop` | ✓ |
| `/product?slug=shelly-plug-s` | `/product.php` | `product` | `x-apm-brtm-response-bt-page-product` | ✓ |
| `/basket` | `/basket.php` | `basket` | `x-apm-brtm-response-bt-page-basket` | ✓ |
| `/checkout` | `/checkout.php` | `checkout` | `x-apm-brtm-response-bt-page-checkout` | ✓ |
| `/order` | `/order.php` | `order` | `x-apm-brtm-response-bt-page-order` | ✓ |
| `/login` | `/login.php` | `login` | `x-apm-brtm-response-bt-page-login` | ✓ |
| `/admin` | `/admin.php` | `admin` | `x-apm-brtm-response-bt-page-admin` | ✓ |
| `/dxo2` | `/dxo2.php` | `dxo2` | `x-apm-brtm-response-bt-page-dxo2` | ✓ |

---

## Verification

After rebuild (`build-scripts/build.sh && build-scripts/compose.sh up -d`):

1. Set `APMIA_PHP_LOG_LEVEL=DEBUG` temporarily in `.config`.
2. Visit `http://bpa-demo.local:8080/shop`.
3. Check probe log in `/var/log/php-probe/wily_php_agent_<pid>.log`:
   ```
   Frontend start: /shop.php
   Frontend URI: /shop
   BA Correlation  cookie x-apm-brtm-response-bt-page-shop set successfully
   BA Correlation  head : pointer is <N>
   ```
4. Inspect the HTTP response body — the `<script>` snippet should appear inside `<head>`.
5. Restore `APMIA_PHP_LOG_LEVEL=INFO`.

---

## Recommended Probe Changes (Vendor)

The two workarounds above (wrapper files + altered rewrite target) are entirely caused by probe-side design decisions. The following changes to `wily_php_agent` would make front-controller applications work without any application-level adaptation.

### Fix 1 — Gate 1: establish Frontend start unconditionally for HTTP SAPI entry scripts

**Current behaviour:** the probe inspects the first opcode of the executing script. If it is an include-type opcode (61/62/136), the probe enters include-tracking mode and never emits `Frontend start`. BA injection is then skipped entirely.

**Problem:** In the Apache mod_php / FastCGI SAPI, the script identified by `SCRIPT_FILENAME` is always the HTTP entry point — it was dispatched by the web server, not included by another PHP file. Applying include-detection logic to it conflates "is the first thing this script does an include?" with "is this script itself an include?", which are different questions. The answer to the first is meaningless for determining whether BA injection should occur.

**Requested change:** in the HTTP SAPI (`php_sapi_name() === 'apache2handler'` or equivalent), establish `Frontend start` unconditionally for the script identified by `SCRIPT_FILENAME`, regardless of its first opcode. The include-tracking heuristic is only meaningful for CLI or for files genuinely included by another front-end script; it should not suppress BA injection at the request level.

A configuration escape hatch would also be acceptable:
```ini
; Treat the named script as a frontend entry point regardless of first opcode.
wily_php_agent.frontend.entryScript = index.php
```

---

### Fix 2 — Gate 2: use REQUEST_URI (not SCRIPT_NAME) for page identification; do not null-skip index.php

**Current behaviour:** the probe reads `SCRIPT_NAME` to extract the page-name segment for BA cookie naming. It explicitly treats `index.php` and bare `/` as null segments and skips BA injection when either is encountered.

**Problem 1 — wrong variable:** `SCRIPT_NAME` is a filesystem implementation detail (which `.php` file Apache is executing). `REQUEST_URI` is what the user actually requested and what identifies the logical page in any front-controller application. Naming the cookie after `REQUEST_URI` is correct; naming it after `SCRIPT_NAME` couples the probe to a particular directory layout.

**Problem 2 — null-skipping index.php is too aggressive:** `index.php` is the single most common PHP entry point name. Treating it as a null segment causes silent BA skip for the majority of PHP applications that follow standard naming conventions. If the probe must exclude degenerate cases, bare `/` is the only justifiable one; `index.php` should either be a valid segment or, if skipped, should fall back to `REQUEST_URI` rather than abandoning injection entirely.

**Requested change — preferred:** read `REQUEST_URI` (not `SCRIPT_NAME`) for page identification and cookie naming. Strip the query string, extract the last path segment, and proceed. With this change, `/shop`, `/basket`, etc. all yield meaningful segments naturally, with no application adaptation required.

**Requested change — minimal:** keep `SCRIPT_NAME` as primary, but when it yields a null/excluded segment (`index.php` or `/`), fall back to the last segment of `REQUEST_URI` before skipping. This is a one-line fallback that makes front-controller applications work without any probe architecture change.

---

### Summary table

| Gate | Current probe behaviour | Impact | Requested fix |
|---|---|---|---|
| Frontend start (Gate 1) | Skips BA if first opcode is include-type | Front-controllers that open with `require` never get BA | Establish Frontend start unconditionally for HTTP SAPI entry scripts |
| Page identification (Gate 2) | Reads `SCRIPT_NAME`; nulls `index.php` and `/` | All requests through `index.php` silently skipped | Use `REQUEST_URI` for page naming; or fall back to `REQUEST_URI` when `SCRIPT_NAME` segment is null |
