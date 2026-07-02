# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

BPA-Demo is a PHP 8.1 + Apache 2.4 + MariaDB web shop (300 smart-home products, three brands) used as a Broadcom DX O2 APM demonstration target. Deployed via Helm/Kubernetes or Docker Compose with an optional APMIA monitoring sidecar.

---

## Build & deploy commands

```bash
build-scripts/build.sh                # package app, docker build all images
build-scripts/build.sh --push         # build + push to registry in one step
build-scripts/push.sh                 # push only (--skip-dxo2 if dxo2 not built)
build-scripts/deploy.sh               # helm upgrade; generates + deletes values.local.yaml
build-scripts/deploy.sh --skip-init   # skip post-deploy kubectl exec DB check
build-scripts/compose.sh up -d        # local dev stack
build-scripts/compose.sh down -v      # tear down + wipe DB volume
```

There is no test suite and no linter. Verify changes by running the app locally with `compose.sh up -d`.

All scripts source `.config` from the project root (copy from `.config.example`; never commit `.config`).

---

## PHP application architecture

### Front controller

`app/src/index.php` is the single entry point for all requests. It:
1. Bootstraps session and CSRF via `config/app.php`.
2. Opens the PDO singleton via `config/database.php`.
3. Resolves `?page=<slug>` against a static `$routes` array. Apache mod_rewrite maps clean URLs (`/shop`, `/basket`, `/product`, etc.) to the corresponding per-page wrapper (`shop.php?page=shop`, etc.) via `vhost.conf`, so `$_GET['page']` is always set by the time the front controller runs.
4. Emits `X-Page-ID: page_<slug>` as a baseline header (e.g. `page_dxo2`) so every response carries a human-readable page identifier. Pages that call `set_monitoring_headers()` override this with a richer value.
5. Calls `usecase_run($ctx)` to apply any behaviour modifier assigned to the current user.
6. Requires the resolved page file.

### Library layer (`app/src/lib/`)

Plain functions in the global namespace — no classes, no autoloader.

| File | Key public API |
|---|---|
| `auth.php` | `auth_login()`, `auth_logout()`, `auth_user()`, `auth_require_admin()`, `auth_is_admin()` |
| `usecase.php` | `usecase_run(&$ctx)` — loads `usecases/<name>.php`, calls `usecase_<name>($db, &$ctx)` |
| `basket.php` | Session-backed basket (no DB persistence) |
| `product.php` | PDO queries for product listing and detail |
| `order.php` | Order creation, item insertion, order history |
| `validate.php` | `validate_slug()`, `validate_luhn()`, input sanitisation |
| `page_id.php` | `set_page_id()` — writes `X-Page-ID`; `set_monitoring_headers()` — writes `X-Page-ID`, `X-User-Role`, `X-Basket-Total`, `X-Alert`, `X-Use-Case` |

### Page rendering pattern

Pages set `$pageTitle`, then `require templates/layout.php` (outputs `<head>` through opening content div) and `require templates/footer.php` (closes layout). No templating engine.

### Use case system

Files in `app/src/usecases/` each define one function: `usecase_<name>(PDO $db, array &$ctx): void`. `usecase_run()` loads the matching file and calls it on every request for the assigned user. Adding a use case only requires creating the file — no registration step.

### Authentication

`auth.php` handles two password formats:
- `$SETUP$<plain>` — seed format; verified plain-text, upgraded to bcrypt on first successful login.
- `$2y$…` — standard bcrypt.

Session is regenerated on login/logout. CSRF token is one-per-session, generated in `config/app.php`, verified in `csrf_verify()` on every POST.

### Caching policy (intentionally disabled)

All caching is disabled at every layer so APM tooling sees genuine request latency and every page load hits PHP and the database fresh:

| Layer | Mechanism | Configuration |
|---|---|---|
| PHP OPcache | Disabled | `/etc/php/8.1/apache2/conf.d/99-disable-opcache.ini` (`opcache.enable=0`) — written by Dockerfile |
| Web-server cache | Not enabled | `mod_cache`/`mod_cache_disk` are never loaded; no caching directives in `vhost.conf` |
| Browser cache | No-cache headers | `vhost.conf`: `Cache-Control: no-store, no-cache, must-revalidate, max-age=0`; `Pragma: no-cache`; `Expires: Thu, 01 Jan 1970 00:00:00 GMT`; ETags and `Last-Modified` stripped |

The headers are applied via `Header always set` in `vhost.conf` (requires `mod_headers`, enabled in the Dockerfile) and cover **all** responses: PHP pages, the static CSS file, and `/health`.

---

## PHP coding standards (mandatory — Backdrop CMS)

- **Indent:** 2 spaces, no tabs.
- **Braces:** K&R — opening brace on the same line. `else` / `catch` on their own line after `}`.
- **Strings:** single quotes for literals without interpolation. No closing `?>` in pure-PHP files.
- **PHPDoc on every function**, including private helpers. Minimum: one-sentence description + `@param` / `@return` (with type and description on an indented line).

```php
/**
 * One-sentence description.
 *
 * @param string $name
 *   Description.
 *
 * @return string
 *   Description.
 */
function example(string $name): string {
  // 2-space indent
}
```

Reference: https://docs.backdropcms.org/php-standards

---

## Shell scripting standards (mandatory — OWF)

Every script in `build-scripts/` must open with:

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
```

- `readonly` for all top-level constants; `local [-r]` for function-local variables.
- `info()` for progress, `fatal()` for unrecoverable errors. `-h|--help` on every script.
- No credentials on the command line: `printf '%s' "${VAR}" | --password-stdin`.

---

## Entrypoint coding style

Both `src/apache-php/entrypoint.sh` and `src/dx-o2-agents/entrypoint.sh` must be **ASCII-only**. Section separators use:

```bash
# == Section title ============================================================
```

No box-drawing (`─`), en/em dashes (`–`, `—`), or arrows (`→`). Verify: `grep -Pc '[^\x00-\x7F]' entrypoint.sh` must print `0`.

---

## Security rules (non-negotiable)

1. **`.config`** is the single source of truth for all credentials, image tags, registry URLs. Never hardcode. Never commit.
2. **`values.local.yaml`** is generated by `deploy.sh` and deleted immediately after `helm upgrade`. Never commit.
3. **Registry login:** `printf '%s' "${REGISTRY_PASSWORD}" | docker login --password-stdin`. Never `echo`.
4. **`automountServiceAccountToken: false`** on the Kubernetes ServiceAccount.
5. **`allowPrivilegeEscalation: false`** on every container and initContainer.
6. **DB Monitor credentials** in Kubernetes via `secretKeyRef` — never plain-text in values files.
7. **No secrets or credentials** in CHANGELOG, README, or any tracked doc.

---

## Build versioning

The build counter is owned **exclusively by `package-app.sh`**. Running it standalone increments `.build_number` and updates `IMAGE_TAG` in `.config` to the new `b<N>` tag:

1. **`compute_build_tag()`** — increments counter in memory, sets globals `FULL_TAG` (e.g. `1.0.0b7`) and `BUILD_NUM`. No file is written.
2. Archive is created.
3. **`commit_build_tag()`** — writes `BUILD_NUM` to `.build_number` and updates `IMAGE_TAG` in `.config` via `sed -i`.

`build.sh` and `compose.sh` always pass `--no-bump` when calling `package-app.sh` internally and read `IMAGE_TAG` from `.config` as-is. This ensures the counter advances exactly once per new app package, regardless of how many docker builds follow.

Never manually set `IMAGE_TAG` to include `b<N>` — set the base version only (e.g. `IMAGE_TAG="1.0.0"`).

---

## DX O2 agent injection pattern

The APMIA agent is never baked into application images. At pod startup:

1. **`dxo2-init` initContainer** copies `/opt/apmia/` from the `dx-o2-agents` image into an `emptyDir` volume (`apmia-share`).
2. **`dx-o2-agent` sidecar** mounts `apmia-share` at `/opt/apmia` (read-write) — mirroring how Docker Compose mounts `apmia_data`. The IA writes `IntroscopeAgent.log` and the BTL writes `BTListener.log` into `apmia-share/logs/`, which `apache-php` reads via its existing read-only mount of the same volume. Without this shared mount the logs would be written to the container's private overlay filesystem and remain invisible to the `?page=dxo2` status page. The entrypoint starts the IA (`APMIAgent.sh console`) and BTL (`BTListener.sh start` — `start` is required; omitting it prints usage and exits). Before starting BTL the entrypoint replaces `/opt/btlistener/logs/` with a symlink to `/opt/apmia/logs/` so BTL writes `BTListener.log` into the shared volume. A `_btl_watchdog` background loop polls via `pgrep -f 'BTListener'` every 30 s and restarts if dead. After both daemons are started, `_await_and_tail()` streams `IntroscopeAgent.log` and `BTListener.log` to stdout (waiting up to 60 s for each file to appear) so that `kubectl logs` and `docker compose logs` show live agent output. Shutdown order: kill watchdog → kill IA → `pkill -f BTListener` → kill log tailers.
3. **`apache-php` container** mounts `apmia-share` read-only at `/opt/apmia`. Its entrypoint performs opportunistic injection and starts cleanly when the volume is absent.

All DX O2 behaviour is gated on `dxo2.enabled` in `values.yaml`. The sidecar is activated when `APMIA_EM_HOST` is non-empty in `.config`.

### PHP probe injection

`apache-php/entrypoint.sh`:
- Copies `wily_php_agent.so` into PHP's `extension_dir`.
- Copies `wily_php_agent.ini` to `/etc/php/8.1/mods-available/`; symlinks as `99-wily_php_agent.ini` into `/etc/php/8.1/apache2/conf.d/`.
- Patches `collectorHost`, `collectorPort`, `application.name`, `agentName`, `hostname` via `sed -i`. `agentName` and `hostname` are both set to `APMIA_PHP_AGENT_NAME` (default `bpa-demo-php-probe`) — `hostname` overrides OS `gethostname()` so the PHP probe appears with a recognisable name in the metric path instead of an auto-generated pod ID.
- Sets `logdir="/var/log/php-probe"`, `disableLogging=0`, `logLevel=<N>` (numeric). `APMIA_PHP_LOG_LEVEL` accepts a name (TRACE/DEBUG/INFO/WARN/WARNING/ERROR/FATAL) or a number (0–5); the entrypoint maps the name to its numeric equivalent before writing the INI because `wily_php_agent.logLevel` only accepts `0=trace,1=debug,2=info,3=warning,4=error,5=fatal`. The log directory is created in the Dockerfile and owned by `www-data` so the Apache process can write logs without privilege escalation.
- Writes browser-agent INI properties when `APMIA_BROWSER_SNIPPET` is set (enclose in single quotes in `.config` because the value contains double-quotes). Three properties are set: `response.decoration=1` (master switch — activates the browser agent module; required by the PHP probe before `autoInjection` is honoured), `snippet.autoInjection=1`, and `browseragent.autoInjection.snippetString='...'`. When `APMIA_BROWSER_SNIPPET` is empty all three are disabled/removed. Also sets `wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength=30000` unconditionally — `<head>` is at byte 33 and `</head>`/`<body>` at byte ~239/247 (CSS is a separate static file), well within the probe's 100–30000 valid range. **Important — Frontend start and SCRIPT_NAME:** the PHP probe has two independent gates for BA injection. (1) It hooks PHP opcodes: if the very first opcode of a script is an include (op 61/62/136), the probe enters include-tracking mode and never emits `Frontend start` — BA injection is skipped entirely. (2) It extracts the last segment of `SCRIPT_NAME` (not `REQUEST_URI`) to name the BA cookie; it treats `index.php` and bare `/` as null segments and skips injection for those. A plain front-controller pattern (all requests through `index.php`) fails both gates. The fix: per-page wrapper files (`shop.php`, `basket.php`, etc.) at the document root, each containing one non-include opcode (`$_GET['page'] ??= basename(__FILE__, '.php')`) before the `require __DIR__ . '/index.php'`. The non-include opcode triggers `Frontend start: /shop.php`; `SCRIPT_NAME=/shop.php` passes Gate 2; `REQUEST_URI=/shop` is used for the actual cookie name (`x-apm-brtm-response-bt-page-shop`). `vhost.conf` routes `/shop` → `shop.php?page=shop` (not `index.php?page=shop`).

### BPA Apache module injection

- Finds `mod_*.so` in `extensions/WebServerPlugin/`. Derives module name: `mod_<name>.so → <name>_module`.
- Writes `LoadModule`, `SetEnv APMIA_WEB_AGENT_NAME`, `TcpClientHostAndPort ${APMIA_BTL_HOST}:${APMIA_BTL_PORT}`, and `TcpClientWaitTimeForReconnectInSecs 30` to `/etc/apache2/conf-enabled/bpa.conf`. `TcpClientHostAndPort` is the native module directive (per Broadcom TechDocs) that tells the module where the BTL is listening. The BPA module has no documented log-file output mechanism — do not add `SetEnv APMIA_WEB_AGENT_LOG_*` directives (they are unsupported).
- Validates with `apache2ctl configtest`; disables on rejection.
- The module always registers internally as **`caplugin_module`**, detected via `apache2ctl -t -D DUMP_MODULES`.

### MySQL/MariaDB Monitor Extension

The APMIA DB Monitor extension for MySQL/MariaDB is installed from a separate archive:

- **Source archive:** `src/dx-o2-agents/installers/Infrastructure_Agent_apmia_*.tar` (download from DX O2 → Agents → Infrastructure Agent → Linux; distinct from the `PHP_apmia_*.tar` used for the main agent).
- **Dockerfile step:** extracts `apmia/extensions/deploy/mysql-*.tar.gz` from the Infrastructure archive and places it at `/opt/apmia/extensions/deploy/`. Optional/non-fatal: if the archive is absent, the container starts without DB monitoring.
- **APMIA auto-deploy:** on startup the APMIA extracts any `.tar.gz` in `extensions/deploy/` into `extensions/<bundle-name>/` and registers it in `Extensions.profile`. The mysql extension appears as `extensions/mysql-*/`.
- **`_db_monitor_setup()` in `dx-o2-agents/entrypoint.sh`:** runs before the IA starts. If `MYSQL_MONITOR=true` (default): extracts the mysql `.tar.gz`, patches `bundle.properties` with connection details from `APMENV_*` vars, and repacks. Also patches the already-deployed directory if it exists (for Docker named-volume persistence across container restarts). If `MYSQL_MONITOR=false`: removes the `.tar.gz` and any deployed directory so the APMIA never loads the extension.
- **`bundle.properties` configuration:** profile name, hostname, port, username, password, instanceName, and version are all read from `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_<PROFILE>_*` variables. The sed patching uses `@` as delimiter — passwords containing `@` are not supported.
- **JDBC driver:** `mariadb-java-client.jar` ships in the `PHP_apmia_*.tar` archive and is already at `/opt/apmia/lib/`. The mysql extension bundles its own `lib/mysql.jar` (MySQL Connector/J) used for the extension's internal queries.
- **Monitor login verification (`_ensure_monitor_user()` in `entrypoint.sh`):** the extension authenticates as the configured `_db_user`; if that login does not exist in MariaDB, connections fail silently and no metrics are gathered. Before patching `bundle.properties`, the entrypoint connects to MariaDB as root (`MARIADB_ROOT_USER`/`MARIADB_ROOT_PASSWORD`, default user `root`), waiting up to 60s for the server to accept connections, and checks `mysql.user` for the login. It then runs `CREATE USER IF NOT EXISTS '<user>'@'%' IDENTIFIED BY '<password>'` plus `GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.*` (the privileges the DB Monitor extension needs to query `SHOW GLOBAL STATUS`/`VARIABLES`, `INFORMATION_SCHEMA`/`performance_schema`, and the process list) and `FLUSH PRIVILEGES` — **every start, whether the login is new or pre-existing**. This matters because `${_db_user}` is commonly the same account MariaDB's own `MARIADB_USER` bootstrapping already created, scoped only to its own database (e.g. `phpapp`); without the (re-)applied global grant the extension fails with `SELECT command denied ... for table performance_schema.global_variables`. `CREATE USER IF NOT EXISTS` is a no-op (including the password clause) when the login already exists, so an existing password is never overwritten. The `mariadb` CLI (`mariadb-client` package) is installed in the `dx-o2-agents` image solely for this check. Requires the `mariadb` package in Dockerfile and root credentials in the container env — see `.config` and Helm `secretKeyRef` wiring for `MARIADB_ROOT_PASSWORD` below. Username/password may not contain a single quote — same limitation as the `@` sed delimiter above.
- **MariaDB schema compatibility (`version` property):** even with correct grants, the extension's *default* query set targets MySQL 5.7+ and queries `performance_schema.global_variables`/`global_status`, tables MariaDB does not implement (`ERROR 1146: Table 'performance_schema.global_variables' doesn't exist`). The extension bundles an alternate query set for this — `config/schema5_6x.json` — that queries `information_schema.global_variables`/`global_status` instead, which MariaDB does implement. Selecting it is a `bundle.properties` property, not a code change: `introscope.agent.dbmonitor.mysql.profiles.<profile>.version=5_6x`, sourced from `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_<PROFILE>_VERSION` (docker-compose.yml hardcodes `"5_6x"`; Helm reads `dxo2.dbMonitor.schemaVersion`, default `"5_6x"`). Despite the "5_6x" (MySQL 5.6.x) name, this is the correct/only working setting for MariaDB, not a version match.
- **Stale calculated-metric term (`_patch_schema5_6x_calc()` in `entrypoint.sh`):** `schema5_6x.json`'s "Resource Utilization:Total Size of Shared Buffers(KB)" metric sums five MySQL variables via `show global variables`, including `innodb_additional_mem_pool_size` — removed from MySQL since 5.6.3 and never implemented in MariaDB. Since the query returns no row for it, the JSONPath filter for that term is emitted unresolved into the calculation string and the Nashorn expression evaluator fails to parse it (`javax.script.ScriptException: Expected an operand but found ?`), logged as an `[ERROR] [IntroscopeAgent.DBMonitor]` every query interval. `_patch_schema5_6x_calc()` removes just that `+ $.resultSet[?(@.VARIABLE_NAME == 'innodb_additional_mem_pool_size')].VARIABLE_VALUE` term from `config/schema5_6x.json` (same tar.gz + already-deployed-directory double-patch pattern as `_patch_bundle_props()`) so the remaining four variables still sum correctly. Verified via `python3 -m json.tool` that the patched file remains valid JSON.

### APMENV_* identity mechanism

Agent identity is configured via `APMENV_*` environment variables — the native APMIA Docker mechanism. These override `introscope.*` profile properties at startup without touching the profile file. **Never patch or overwrite `core/config/IntroscopeAgent.profile`** — it contains the tenant JWT and WSS EM URL from the DX O2 installer.

| `APMENV_*` variable | Property overridden |
|---|---|
| `APMENV_INTROSCOPE_AGENT_AGENTNAME` | `introscope.agent.agentName` |
| `APMENV_INTROSCOPE_AGENT_APPLICATION_NAME` | `introscope.agent.application.name` |
| `APMENV_INTROSCOPE_AGENT_HOSTNAME` | `introscope.agent.hostName` |
| `APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME` | `introscope.agent.customProcessName` |
| `APMENV_LOG4J_LOGGER_INTROSCOPEAGENT` | log4j logger spec, e.g. `"INFO, logfile"` |
| `APMENV_INTROSCOPE_AGENT_URLGROUP_FRONTEND_URL_CLAMP` | `introscope.agent.urlgroup.frontend.url.clamp` — hardcoded `50` |
| `APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_*` | DB Monitor MySQL properties |

### Container hostname (metric path)

`APMENV_INTROSCOPE_AGENT_HOSTNAME` only affects the IA (Java). The BPA module reads the OS `gethostname()`. The PHP probe uses `wily_php_agent.hostname` (set to `APMIA_PHP_AGENT_NAME` by the entrypoint). To prevent auto-generated IDs in the metric path:
- **Kubernetes:** `spec.hostname: {{ .Values.dxo2.hostName }}` in the pod template (covers IA + BPA).
- **Compose:** `hostname: ${APMIA_HOST_NAME:-bpa-demo-host}` on the `apachephp` service (covers IA + BPA).
- **PHP probe:** `wily_php_agent.hostname` is always patched to `APMIA_PHP_AGENT_NAME` regardless of deployment mode.

### APMIA_DEPLOY flag

| Value | Behaviour |
|---|---|
| `true` (default) | Start IA and BTL daemons |
| `false` | Passive: seed the volume only, `exec sleep infinity` |

### Expected paths inside `/opt/apmia`

```
bin/APMIAgent.sh
jre/                                               ← JAVA_HOME at runtime
core/config/IntroscopeAgent.profile                ← NEVER overwrite
extensions/PHPAgent/wily_php_agent.so
extensions/PHPAgent/wily_php_agent.ini
extensions/WebServerPlugin/mod_<name>.so           ← Apache BPA module
logs/
```

BTL at `/opt/btlistener/bin/BTListener.sh`; config at `/opt/btlistener/conf/custom/application.properties`.

---

## Container image contents (both images)

Both `apache-php` and `dx-o2-agents` include these troubleshooting packages (Ubuntu 22.04):

| Package | Commands |
|---|---|
| `curl` | HTTP/HTTPS checks |
| `dnsutils` | `dig`, `nslookup`, `host` |
| `iputils-ping` | `ping` |
| `less` | pager |
| `net-tools` | `netstat`, `ifconfig`, `route` |
| `procps` | `ps`, `top`, `pgrep`, `kill` |

---

## Demo use cases

Assigned per user via the admin panel. Active use case is in `$_SESSION['usecase']`; `usecase_run()` dispatches on every request.

| Use case | File | Behaviour |
|---|---|---|
| `trouble` | `usecases/trouble.php` | 5 000 sequential DB reads per request |
| `empty_basket` | `usecases/empty_basket.php` | Basket total always €0.00 |
| `locked` | `usecases/locked.php` | Blocks login; session flash shown once on login page |

**`locked` flow:** after `auth_login()` succeeds, `login.php` checks `$_SESSION['usecase'] === 'locked'`, revokes all auth session keys, and displays the error without granting access. Already-logged-in users are evicted by `usecase_locked()` on the next request (evicts keys → `session_regenerate_id(true)` → stores `$_SESSION['login_error']` → redirects to login). The login page reads and clears the flash before the already-logged-in redirect check.

Seed user: `locked` / `demo123` — id 14, Laura Locked, use case pre-assigned.

---

## Admin diagnostic pages

Gated by `auth_require_admin()`. Linked from the **Diagnostics** sidebar section visible only when admin is logged in.

| Route | File | Purpose |
|---|---|---|
| `/info` | `pages/info.php` | PHP version, SAPI, OS, memory limit, loaded extensions |
| `/db` | `pages/db.php` | Live PDO connection test, server version, uptime |
| `/dxo2` | `pages/dxo2.php` | Full DX O2 stack health check |

### `/dxo2` checks

- **PHP probe:** `extension_loaded('wily_php_agent')`; globs `$phpConfD/*-wily_php_agent.ini` (phpConfD built from `PHP_MAJOR_VERSION`/`PHP_MINOR_VERSION`); `realpath()` to resolve symlink to mods-available; displays key INI properties.
- **BPA module:** `shell_exec('apache2ctl -t -D DUMP_MODULES 2>&1')` → searches for `caplugin_module`. Falls back to `apache_get_modules()` if `shell_exec` is unavailable. Raw output shown verbatim.
- **Connectivity:** `fsockopen()` TCP probe of `APMIA_PHP_COLLECTOR_HOST:PORT` and `APMIA_BTL_HOST:PORT`.
- **Env vars:** all `APMIA_*` / `APMENV_*` in a table; credential-bearing keys redacted.
- **Log tails (three cards):** APMIA IA logs from `/opt/apmia/logs/*.log` (BTListener.log excluded); PHP probe logs from `/var/log/php-probe/*.log`; BTListener log from `/opt/apmia/logs/BTListener.log` (redirected there by the sidecar — see BTL log redirect below). No BPA module log card — the module has no documented log-file output.

When `/opt/apmia` is absent (`dxo2.enabled=false`) only the summary badges and a "not deployed" notice are shown — all detail cards are hidden. Deployment is detected via `is_dir('/opt/apmia')`.

---

## Helm chart

Chart: `helm/php-demo/` — version 0.2.0.

- ConfigMap holds `vhost.conf` mounted via `subPath`.
- `checksum/config` and `checksum/secret` annotations on the pod template force pod restart on config/secret change.
- `dxo2.emHost` is optional when using the DX O2 installer download (EM URL is pre-configured in the profile). Any non-empty string triggers `dxo2.enabled: true` in `deploy.sh`.
- `image.*.pullPolicy: Always` for custom images; `IfNotPresent` for `mariadb`.
- **Kubernetes probes** (`startupProbe`, `livenessProbe`, `readinessProbe`) all target `GET /health` — a static file (`app/src/health`) served by Apache without invoking PHP. This keeps probes independent of APMIA state: the PHP probe extension is not triggered, so the `dx-o2-agent` sidecar (PHP collector `127.0.0.1:5005`) does not need to be ready before probes pass. Access log entries for `/health` are suppressed via `SetEnvIf` in `vhost.conf`.
- **`dx-o2-agent` memory sizing:** The APMIA JVM + BTL consume ~757 MiB at idle (measured via `docker stats`). `requests.memory` is set to `792Mi` (idle baseline + buffer) and `limits.memory` to `4Gi` (headroom under APM load). Never set the limit below 512 Mi — the agent OOMKills before connecting to the backend.

---

## .config required variables

```bash
# Registry
REGISTRY  REGISTRY_USER  REGISTRY_PASSWORD

# Images
IMAGE_PREFIX  IMAGE_TAG  BUILD_PLATFORM

# MariaDB
MARIADB_ROOT_PASSWORD  MARIADB_DATABASE  MARIADB_USER  MARIADB_PASSWORD

# Kubernetes / Helm
APP_NAMESPACE  APP_HOSTNAME  TLS_CLUSTER_ISSUER  INGRESS_CLASS_NAME  KUBECONFIG
HELM_CHART_PATH          # optional; defaults to helm/php-demo

# DX O2 – lifecycle
APMIA_DEPLOY             # true (default) = run IA+BTL; false = passive volume
APMIA_EM_HOST            # non-empty → dxo2.enabled=true; value is informational only
APMIA_EM_PORT            # default 8443

# DX O2 – identity (exposed as APMENV_* to dx-o2-agent container)
APMIA_AGENT_NAME         # → APMENV_INTROSCOPE_AGENT_AGENTNAME
APMIA_APP_NAME           # → APMENV_INTROSCOPE_AGENT_APPLICATION_NAME
APMIA_HOST_NAME          # → APMENV_INTROSCOPE_AGENT_HOSTNAME + OS hostname
APMIA_PROCESS_NAME       # → APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME
APMIA_PHP_AGENT_NAME     # → wily_php_agent.agentName in PHP INI
APMIA_PHP_LOG_LEVEL      # default INFO → wily_php_agent.logLevel (probe log verbosity)
APMIA_WEB_AGENT_NAME     # → APMIA_WEB_AGENT_NAME env for BPA Apache module
APMIA_LOG_LEVEL          # default INFO → APMENV_LOG4J_LOGGER_INTROSCOPEAGENT

# DX O2 – IPC (defaults: same-pod 127.0.0.1; Compose overrides to dxo2 service name)
APMIA_PHP_COLLECTOR_HOST  APMIA_PHP_COLLECTOR_PORT   # default 127.0.0.1:5005
APMIA_BTL_HOST            APMIA_BTL_PORT             # default 127.0.0.1:8000

# DX O2 – optional
MYSQL_MONITOR            # default true – enable DB Monitor for MariaDB
APMIA_BROWSER_SNIPPET    # default "" – <script> tag; enclose in single quotes in .config
```

---

## Docker Compose notes

- `load_config()` in `compose.sh` explicitly exports all DX O2 variables with safe defaults before `docker compose`. Un-exported variables are invisible to YAML interpolation.
- The `apachephp` environment block uses **uniform list form** (`- KEY` or `- KEY=value`). Mixing mapping and list style is illegal YAML.
- `APMIA_BROWSER_SNIPPET` uses passthrough form (`- APMIA_BROWSER_SNIPPET`, no `=`) to prevent YAML parser corruption of the embedded double-quotes.
- `APMIA_PHP_COLLECTOR_HOST` and `APMIA_BTL_HOST` are hardcoded to `dxo2` (service name) in `docker-compose.yml`. In Kubernetes the same-pod default `127.0.0.1` applies.

---

## CHANGELOG

Update on every commit. Format: `YYYY-MM-DD @ HH:MM - [Type – Description]`. Prepend newest first. Include file names and the reason for each change. No secrets or credentials.

## Git practices

- Branch: `master`. Commit format: `<type>: <short description>` (feat/fix/refactor/docs/chore).
- Every commit includes `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`.
- Never commit: `.config`, `.build_number`, `src/dx-o2-agents/installers/*`, `src/apache-php/app.tar.gz`, `helm/*/values.local.yaml`, `.claude/`.

---

## Key file paths

| Purpose | Path |
|---|---|
| Front controller + routing | `app/src/index.php` |
| Session bootstrap + CSRF | `app/src/config/app.php` |
| PDO singleton | `app/src/config/database.php` |
| Layout template | `app/src/templates/layout.php` |
| Application stylesheet | `app/src/css/app.css` |
| Apache vhost config (no-cache headers, probe suppression) | `src/apache-php/config/vhost.conf` |
| Apache+PHP entrypoint (probe + BPA injection) | `src/apache-php/entrypoint.sh` |
| DX O2 entrypoint (IA + BTL + watchdog) | `src/dx-o2-agents/entrypoint.sh` |
| Admin page — DX O2 status | `app/src/pages/dxo2.php` |
| Use case — locked | `app/src/usecases/locked.php` |
| MariaDB schema + seed | `helm/php-demo/sql/schema.sql` / `seed.sql` |
| Helm values defaults | `helm/php-demo/values.yaml` |
| Config template | `.config.example` |
| DX O2 setup guide | `DX-O2-AGENT-SETUP.md` |
| Version compatibility matrix | `COMPATIBILITY.md` |
