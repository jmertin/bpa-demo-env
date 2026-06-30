# Version Compatibility Matrix – BPA-Demo / DX O2 Integration

Updated: 2026-06-17
Status: All action items resolved; stack is at its target baseline.

---

## 1. Deployed Stack

| Component | Image / Package | Version | Notes |
|---|---|---|---|
| Web server | apache2 (ubuntu:22.04 repos) | 2.4.x | mod_php; replaced former nginx + php-fpm pair |
| PHP | libapache2-mod-php8.1 (ubuntu:22.04 repos) | 8.1 | Within DX O2 PHP Agent ceiling ≤ 8.4 |
| Base OS | ubuntu:22.04 (Jammy LTS) | glibc 2.35 | Confirmed compatible with APMIA binary |
| Database | mariadb:11 (Docker Hub) | 11.x | Official image, pinned major |
| DX O2 agent | PHP_apmia_*.tar (DX O2 interface) | tenant-specific | Bundled JRE; pre-configured profile |
| BTL | Business_Transaction_Listener.zip | tenant-specific | Co-located in dx-o2-agents container |
| BPA plugin | Business_Payload_Analyzer_WebServer_Plugins.zip | tenant-specific | Apache mod_*.so + nginx variants |

---

## 2. Broadcom DX O2 Agent Compatibility Ceilings

| Agent / Plugin | Ceiling | Project version | Status |
|---|---|---|---|
| PHP Agent (`wily_php_agent`) | PHP **8.4** | PHP 8.1 | ✅ within ceiling |
| BPA WebServer Plugin (Apache `mod_*.so`) | Apache 2.4.x | Apache 2.4.x | ✅ within ceiling |
| BPA WebServer Plugin (nginx `ngx_http_ca_*`) | NGINX **1.29.x** | n/a (Apache stack) | — |
| Infrastructure Agent binary | Ubuntu 20.04 / 22.04 (glibc ≥ 2.17) | ubuntu:22.04 (glibc 2.35) | ✅ confirmed |
| Business Transaction Listener | Same OS as Infra Agent | ubuntu:22.04 | ✅ confirmed |
| DB Monitor (MySQL/MariaDB) | MariaDB / MySQL compatible | mariadb:11 | ✅ compatible |

Sources: Broadcom DX APM Compatibility Guide.

---

## 3. Base Image Selection Rationale

**Selected: `ubuntu:22.04` (Jammy Jellyfish, LTS until April 2027)**

| Criterion | ubuntu:22.04 | ubuntu:24.04 | ubuntu:26.04 |
|---|---|---|---|
| APMIA binary compatibility | ✅ Confirmed | ⚠️ Partial (recent builds) | ❌ Unverified |
| Default PHP version | 8.1 (≤ 8.4 ✅) | 8.3 (≤ 8.4 ✅) | 8.4–8.5 (may exceed ceiling) |
| Default Apache version | 2.4.x (✅) | 2.4.x (✅) | 2.4.x (✅) |
| glibc version | 2.35 | 2.39 | 2.41+ |
| LTS support remaining | Until Apr 2027 | Until Apr 2029 | Until Apr 2031 |

---

## 4. Web Server Migration History

The project originally used **nginx 1.18 + php-fpm** as two separate containers.
This was replaced with a **single apache-php container** (Apache 2.4 + mod_php 8.1)
for the following reasons:

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
| `wily_php_agent.logLevel` | Probe log verbosity | from `APMIA_PHP_LOG_LEVEL` (default `INFO`) |
| `wily_php_agent.agentName` | Probe identity in metric tree | from `APMIA_PHP_AGENT_NAME` (default `bpa-demo-php-probe`) |
| `wily_php_agent.hostname` | Probe hostname in metric path | set to `APMIA_PHP_AGENT_NAME` — overrides OS `gethostname()` |
| `wily_php_agent.enable.browseragent.snippet.autoInjection` | Enable browser agent | `1` = on, `0` = off |
| `wily_php_agent.enable.browseragent.snippet.maxSearchingLength` | Browser-agent scan window | always `32768`; `</head>` is at byte ~239 with external CSS |
| `wily_php_agent.browseragent.autoInjection.snippetString` | Browser snippet value | single-quoted `'<script ...>'` |
| `wily_php_agent.browseragent.autoInjection.enabled` | **Legacy — not used** | removed by entrypoint |

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
| `/etc/php/8.1/apache2/conf.d/99-disable-opcache.ini` | `opcache.enable` | `0` |
| `/etc/php/8.1/apache2/conf.d/99-disable-opcache.ini` | `opcache.enable_cli` | `0` |

The drop-in is written unconditionally — if `php8.1-opcache` is not installed the file is harmless; if it is installed, the extension is loaded but immediately disabled.

Verify at runtime:

```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  php8.1 -r 'echo ini_get("opcache.enable"), "\n";'
# expected: 0
```

### 7.2 Web-server cache

`mod_cache` and `mod_cache_disk` are not loaded (`a2enmod` in the Dockerfile only enables `rewrite`, `headers`, and `php8.1`). No server-side caching is active.

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
