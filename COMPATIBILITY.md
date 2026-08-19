# Version Compatibility Matrix – BPA-Demo / DX O2 Integration

Updated: 2026-08-19
Status: All action items resolved; stack is at its target baseline (ubuntu:24.04 / PHP 8.3, upgraded from ubuntu:22.04 / PHP 8.1).

---

## 1. Deployed Stack

| Component | Image / Package | Version | Notes |
|---|---|---|---|
| Web server | apache2 (ubuntu:24.04 repos) | 2.4.x | mod_php; replaced former nginx + php-fpm pair |
| PHP | libapache2-mod-php8.3 (ubuntu:24.04 repos) | 8.3 | Within DX O2 PHP Agent ceiling ≤ 8.4 |
| Base OS | ubuntu:24.04 (Noble LTS) | glibc 2.39 | Confirmed compatible with APMIA binary (see §2, §3) |
| Database | mariadb:11 (Docker Hub) | 11.x | Official image, pinned major |
| DX O2 agent (PHP Agent) | PHP_apmia_*.tar (DX O2 interface) | tenant-specific | Bundled JRE; pre-configured profile; base install |
| DX O2 agent (MySQL Monitor extension) | Infrastructure_Agent_apmia_*.tar (DX O2 interface, optional) | tenant-specific | Only its mysql-*.tar.gz is used, layered onto the PHP Agent install |
| BTL | Business_Transaction_Listener.zip (DX O2 interface) | tenant-specific | Co-located in dx-o2-agents container |
| BPA plugin | Business_Payload_Analyzer_WebServer_Plugins.zip (DX O2 interface, optional) | tenant-specific | Apache mod_*.so + nginx variants |

---

## 2. Broadcom DX O2 Agent Compatibility Ceilings

| Agent / Plugin | Ceiling | Project version | Status |
|---|---|---|---|
| PHP Agent (`wily_php_agent`) | PHP **8.4** | PHP 8.3 | ✅ within ceiling |
| BPA WebServer Plugin (Apache `mod_*.so`) | Apache 2.4.x | Apache 2.4.x | ✅ within ceiling |
| BPA WebServer Plugin (nginx `ngx_http_ca_*`) | NGINX **1.29.x** | n/a (Apache stack) | — |
| Infrastructure Agent binary | Ubuntu 20.04 / 22.04 / 24.04 (glibc ≥ 2.17) | ubuntu:24.04 (glibc 2.39) | ✅ confirmed — floor is glibc ≥ 2.17, 2.39 comfortably clears it |
| Business Transaction Listener | Same OS as Infra Agent | ubuntu:24.04 | ✅ confirmed |
| DB Monitor (MySQL/MariaDB) | MariaDB / MySQL compatible | mariadb:11 | ✅ compatible with `version=5_6x` (extension's default query set targets MySQL 5.7+ `performance_schema` tables MariaDB doesn't implement) |

Sources: Broadcom DX APM Compatibility Guide.

**PHP probe binary is per-minor-version, not forward/backward compatible.** `wily_php_agent.so` is compiled against a specific PHP minor version's Zend Module API — a mismatch fails to load with a PHP API version error, not a graceful fallback. Confirmed by inspecting the real downloaded `PHP_apmia_*.tar` archive (`tar -tf`): it ships prebuilt `.so` files for `php80` through `php84`, both `probe/lib/php<ver>/` (non-ZTS — matches Ubuntu's non-threaded mod_php) and `probe/lib-zts/php<ver>/` (unused here). `src/dx-o2-agents/Dockerfile` selects `probe/lib/php83/wily_php_agent.so` for this project's PHP 8.3 — this selection must always match `src/apache-php/entrypoint.sh`'s `PHP_VERSION` exactly, not just satisfy the ≤8.4 ceiling in the abstract.

---

## 3. Base Image Selection Rationale

**Selected: `ubuntu:24.04` (Noble Numbat, LTS until April 2029)** — upgraded 2026-08-19 from the prior `ubuntu:22.04` baseline. The table below is preserved from the original 22.04 selection, with the "Partial" APMIA-compatibility flag re-verified rather than just carried forward: the real downloaded `PHP_apmia_*.tar` archive was inspected directly (`tar -tf`) and confirmed to ship a prebuilt PHP-8.3 probe binary (`probe/lib/php83/wily_php_agent.so`), and the Infrastructure Agent's documented glibc floor (≥ 2.17, see §2) is comfortably met by 24.04's glibc 2.39. The original "⚠️ Partial (recent builds)" note had no cited source and predated this project actually having the archive on hand to check.

| Criterion | ubuntu:22.04 | ubuntu:24.04 | ubuntu:26.04 |
|---|---|---|---|
| APMIA binary compatibility | ✅ Confirmed | ✅ Confirmed (verified 2026-08-19 against the real `PHP_apmia_*.tar` and IA glibc floor — see above) | ❌ Unverified |
| Default PHP version | 8.1 (≤ 8.4 ✅) | 8.3 (≤ 8.4 ✅) | 8.4–8.5 (may exceed ceiling) |
| Default Apache version | 2.4.x (✅) | 2.4.x (✅) | 2.4.x (✅) |
| glibc version | 2.35 | 2.39 | 2.41+ |
| LTS support remaining | Until Apr 2027 | Until Apr 2029 | Until Apr 2031 |

---

## 4. Web Server Migration History

The project originally used **nginx 1.18 + php-fpm** as two separate containers.
This was replaced with a **single apache-php container** (Apache 2.4 + mod_php,
originally PHP 8.1, upgraded to PHP 8.3 — see §3) for the following reasons:

- Eliminates the FastCGI intermediary and all cross-container vhost configuration differences.
- Simplifies the DX O2 BPA plugin injection (single entrypoint; Apache's `LoadModule` mechanism).
- Reduces pod container count for the monitoring-free deployment (2 containers vs 3).
- The Broadcom BPA plugin ships both an Apache `mod_*.so` and nginx `.so` variants; the Apache
  variant is now used in this project.

The nginx BPA module variants (`ngx_http_ca_plugin_filter_module_<ver>.so`) are still extracted
by the Dockerfile and available in `extensions/WebServerPlugin/` for reference, but the
`apache-php` entrypoint only searches for `mod_*.so` files.

---

## 5. DX O2 wily_php_agent.ini Properties Reference

| Property | Usage | Notes |
|---|---|---|
| `wily_php_agent.collectorHost` | PHP probe → IA IPC address | 127.0.0.1 (K8s), dxo2 (Compose) |
| `wily_php_agent.collectorPort` | PHP probe → IA IPC port | default 5005 |
| `wily_php_agent.application.name` | App name in metric tree | from `APMIA_APP_NAME` |
| `wily_php_agent.logdir` | Probe log directory | set to `/var/log/php-probe` at runtime |
| `wily_php_agent.disableLogging` | Probe logging on/off | always `0` (enabled) |
| `wily_php_agent.logLevel` | Probe log verbosity | **numeric only**: 0=trace,1=debug,2=info,3=warning,4=error,5=fatal. `APMIA_PHP_LOG_LEVEL` accepts names or numbers; entrypoint maps to numeric before writing INI. Default: `INFO`→`2` |
| `wily_php_agent.agentName` | Probe identity in metric tree | from `APMIA_PHP_AGENT_NAME` (default `bpa-demo-php-probe`) |
| `wily_php_agent.hostname` | Probe hostname in metric path | set to `APMIA_PHP_AGENT_NAME` — overrides OS `gethostname()` |
| `wily_php_agent.enable.browseragent.response.decoration` | Browser agent master switch | `1` = module active, `0` = off; **required** before snippet injection works |
| `wily_php_agent.enable.browseragent.snippet.autoInjection` | Enable JS snippet injection | `1` = on, `0` = off; requires `response.decoration=1` |
| `wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength` | Browser-agent scan window | `30000` (probe-documented max); `</head>` is at byte ~239 with external CSS |
| `wily_php_agent.browseragent.autoInjection.snippetString` | Browser snippet value | single-quoted `'<script ...>'` |
| `wily_php_agent.browseragent.autoInjection.enabled` | **Legacy — not used** | removed by entrypoint |

> **Browser-agent Frontend start + SCRIPT_NAME requirement:** the PHP probe has two gates for BA injection. (1) The very first PHP opcode in the entry script must be a non-include opcode; otherwise the probe enters include-tracking mode and skips BA entirely. (2) `SCRIPT_NAME` (not `REQUEST_URI`) must not be `index.php` or bare `/` — the probe treats those as null segments. BPA-Demo uses per-page wrapper files (`shop.php`, `basket.php`, etc.) at the document root; each runs `$_GET['page'] ??= basename(__FILE__, '.php')` (a non-include opcode) before `require __DIR__ . '/index.php'`. `vhost.conf` routes `/shop` → `shop.php?page=shop` so `SCRIPT_NAME=/shop.php` and `REQUEST_URI=/shop` — the probe names its cookie `x-apm-brtm-response-bt-page-shop` from `REQUEST_URI`.

---

## 6. APMENV_* Environment Variables Reference

The APMIA agent reads `APMENV_*` vars at startup and overrides the corresponding
`introscope.*` profile properties without modifying `IntroscopeAgent.profile`.

| APMENV_* variable | Maps to introscope.* property |
|---|---|
| `APMENV_INTROSCOPE_AGENT_AGENTNAME` | `introscope.agent.agentName` |
| `APMENV_INTROSCOPE_AGENT_APPLICATION_NAME` | `introscope.agent.application.name` |
| `APMENV_INTROSCOPE_AGENT_HOSTNAME` | `introscope.agent.hostName` |
| `APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME` | `introscope.agent.customProcessName` |
| `APMENV_LOG4J_LOGGER_INTROSCOPEAGENT` | log4j logger spec, e.g. `"INFO, logfile"` |
| `APMENV_INTROSCOPE_AGENT_URLGROUP_FRONTEND_URL_CLAMP` | `introscope.agent.urlgroup.frontend.url.clamp` (fixed: `50`) |
| `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES` | DB Monitor profile list |
| `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_<PROFILE>_HOSTNAME` | DB hostname |
| `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_<PROFILE>_PORT` | DB port |
| `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_<PROFILE>_USERNAME` | DB username |
| `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_<PROFILE>_PASSWORD` | DB password |
| `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_<PROFILE>_INSTANCENAME` | DB instance display name |

---

## 7. Runtime Cache Configuration

All caching is intentionally disabled so every request exercises the full stack (PHP parse → DB query → response) and APM telemetry reflects real latency.

### 7.1 PHP OPcache

Disabled at image build time via a PHP ini drop-in written by the Dockerfile:

| File | Property | Value |
|---|---|---|
| `/etc/php/8.3/apache2/conf.d/99-disable-opcache.ini` | `opcache.enable` | `0` |
| `/etc/php/8.3/apache2/conf.d/99-disable-opcache.ini` | `opcache.enable_cli` | `0` |

The drop-in is written unconditionally — if `php8.3-opcache` is not installed the file is harmless; if it is installed, the extension is loaded but immediately disabled.

Verify at runtime:

```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  php8.3 -r 'echo ini_get("opcache.enable"), "\n";'
# expected: 0
```

### 7.2 Web-server cache

`mod_cache` and `mod_cache_disk` are not loaded (`a2enmod` in the Dockerfile only enables `rewrite`, `headers`, and `php8.3`). No server-side caching is active.

### 7.3 Browser cache (HTTP headers)

`vhost.conf` sends the following headers on **every** response — PHP pages, `/css/app.css`, and `/health` — via `mod_headers` (`Header always set`):

| Header | Value | Purpose |
|---|---|---|
| `Cache-Control` | `no-store, no-cache, must-revalidate, max-age=0` | Prevent storage and require fresh fetch |
| `Pragma` | `no-cache` | HTTP/1.0 backward compatibility |
| `Expires` | `Thu, 01 Jan 1970 00:00:00 GMT` | Mark response as immediately expired |
| `ETag` | *(removed)* | `Header unset ETag` — prevents conditional GET revalidation |
| `Last-Modified` | *(removed)* | `Header unset Last-Modified` — same reason |

`FileETag None` also instructs Apache not to generate ETags for static files at the filesystem level.

Verify on a live response:

```bash
curl -sI http://localhost:8080/ | grep -iE "cache-control|pragma|expires|etag|last-modified"
# expected: Cache-Control: no-store, no-cache, must-revalidate, max-age=0
#           Pragma: no-cache
#           Expires: Thu, 01 Jan 1970 00:00:00 GMT
# (ETag and Last-Modified should be absent)
```
