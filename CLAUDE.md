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

## Local tooling (`tools/`)

`tools/` holds local-only binaries that support demo-app automation (e.g. `dx-do`, downloaded from an external GitHub release). The entire directory is excluded via `tools/*` in `.gitignore` — nothing under it is ever committed, including its own `README.md`, which documents each binary's source/version for local reference. Do not commit files here; do not assume `tools/` is populated in a fresh clone.

---

## DX O2 tenant configuration scripts (`dxo2-scripts/`)

`dxo2-scripts/` holds scripted DX O2 tenant configuration changes (Services, inventorize rules, and similar tenant-side setup) driven by the `dx-do` CLI (`tools/dx-do-<platform>`, see above). Unlike `tools/`, this directory **is** tracked in git — the scripts themselves contain no secrets, only logic.

Every script follows the same `create`/`check`/`delete` convention so anyone running the demo can manage tenant state without an AI assistant: `create` is idempotent (checks first, warns instead of failing if the resource already exists); `check` prints existence + current definition; `delete` prompts for confirmation unless `-y`/`--yes` is passed, since it mutates shared tenant state visible to everyone with console access. See `dxo2-scripts/README.md` for the full convention and the list of scripts.

`bpa-demo-service.sh` creates the `"BPA-Demo"` DX O2 Service, grouping the php-probe's frontend URLs, the BPA Webserver Extension's business transactions (`page_login`, `SHOP-LIST-*`, etc.), the BPA WebServer Agent's own reporting identity (`agent EQUALS "Experience Collector Host|DxC Agent|Logstash-APM-Plugin"` — where the Browser Agent (BA snippet)'s page-load/page-hits timing actually lands, per-URL under `Business Segment|BPA Demo|<url>:<leaf>`), and the mysql backend database (both the php-probe's inferred `DATABASE` dependency and the DB Monitor extension's own richer CI) under one console view. Content query (4 groups, OR'd): `applicationName EQUALS "BPA-Demo"`, `agent EQUALS "bpa-demo-host|bpa-demo|bpa-demo-infra-agent"` (the Infrastructure Agent), `agent EQUALS "bpa-demo-php-probe|php-probes|bpa-demo-infra-agent(/usr/sbin/apache2)"` (the PHP probe agent), `agent EQUALS "Experience Collector Host|DxC Agent|Logstash-APM-Plugin"` (the BPA WebServer Agent) — the first three exist because the DB Monitor extension's CI doesn't carry `applicationName` (it comes from a host-scoped inventorize rule, not an app-scoped one). There is deliberately **no** separate content group for a distinct "Browser Agent" entity: a `Custom Business Application Agent (Virtual)|By Business Service|BPA Demo` path shows the identical values rolled up under the Business Service view, but it is not a real topology entity — confirmed empirically (2026-07-06) that no content-query attribute (`agent EQUALS`/`MATCHES` on the full path or bare name, `type EQUALS AGENT` + `name` variants) matches it; it only exists as a metric-source-path label. `create` self-heals: if the Service already exists, it diffs the live content query against the groups declared in the script and adds anything missing via `service add-content`, rather than no-op'ing outright.

`bpa-demo-management-module.sh` creates a classic APM Management Module `"BPA-Demo"` containing one Metric Grouping (`attributeNamePattern` matching `Frontends|Apps|BPA-Demo|URLs|*:Average Response Time (ms)` — every tracked frontend URL) and one Alert (`GREATER_THAN`, warning `100ms`, error `250ms`) that catches the `trouble` use case (`usecases/trouble.php` — 5 000 sequential DB reads/request). Thresholds are measured, not guessed: real traffic showed ~6–7ms for normal requests and ~350–690ms for the `trouble` user, both comfortably clear of the chosen thresholds. `empty_basket` (basket total always €0.00) and `locked` (blocks login) have **no currently-observable APM signal**: neither returns an HTTP error status (confirmed by reading `login.php`/`usecases/locked.php` — no `http_response_code()`/error-status `header()` calls anywhere), and BPA's payload metrics only expose request/response **size in bytes**, not extracted field values, so there is nothing to threshold-alert on for either today. Catching `empty_basket` would need the response header `X-Basket-Total` (already emitted by `checkout.php` — see `page_id.php`'s `set_monitoring_headers()`) exposed as a captured BPA attribute; this was being configured tenant-side as of the last check but did not yet appear on live checkout transactions even after a `dxo2` container restart (BTL re-fetches its capture-rule cache on startup) and repeated fresh traffic — revisit once that's confirmed working, then extend this script's Metric Grouping/Alert set to match. Classic-APM resources (`managementmodule`/`metricgrouping`/`alert` in `dx-do`) don't share `service create`'s dry-run-by-default safety net — `managementmodule create` in particular executes immediately — so double-check parameters before creating. **Bug fixed 2026-07-06:** the Metric Grouping originally inherited the MM's `agentExpressions` (`bpa-demo.*`, no `SuperDomain|` prefix) via the default `useManagementModuleAgentExpression=true`. The 4-segment MM `agentExpressions`/`sourceNamePattern` regime is implicitly start-anchored against the **full** `SuperDomain|<host>|<process>|<agent>` path (see `reference-agent-expressions` in `.claude/skills/`), so a pattern missing that prefix matches zero agents — silently: the create succeeds, the console shows the alert, but it never has data. Fixed by giving the Metric Grouping its own explicit `sourceNamePattern='SuperDomain\|.*bpa-demo.*'` with `useManagementModuleAgentExpression=false` instead of inheriting. `create` now also self-heals: if the Metric Grouping already exists, it checks `metricgrouping list-metrics` for at least one live match and re-applies the fix if it finds none, instead of treating "exists" as "working."

`bpa-demo-agent-alerts.sh` creates 12 Metric Groupings + Alerts across three telemetry sources, all attached to the same `"BPA-Demo"` Management Module: five for the Infrastructure Agent's DB Monitor extension (availability, connection refusals, connection pool pressure, buffer pool cache hit rate, slow query rate), five for the PHP probe agent (app response time, error rate, concurrency, DB backend response time, DB backend query volume), and two for the browser/RUM pipeline reported via the BPA WebServer Agent (page load time, page hits per interval — same `Logstash-APM-Plugin` identity as `bpa-demo-service.sh`'s fourth content group, which never appears in `dx-done agent list`/`query-by-regex` output despite being real and queryable via `metric data`). Every Metric Grouping here uses an explicit `sourceNamePattern` + `useManagementModuleAgentExpression=false` from the start (the pattern that fixed `bpa-demo-management-module.sh`'s bug above), so none of them share that failure mode. Depends on `bpa-demo-management-module.sh create` having been run first (reads its state file for the parent MM id). Thresholds are measured from live metric windows, not guessed — see the script's header comment for the readings behind each one.

`bpa-demo-universe.sh` creates the `"BPA Demo universe"` APM Universe (`dx-do apm-universe` — the default/regular surface, `viewId`s look like `VIEW###`; distinct from the legacy `o2-universe`). A Universe has no content-query membership mechanism over the CLI — it's populated with explicit metric-source agent paths via `apm-universe add-metric-source`, one call per source, which accumulate into a single `EXACT`-type specifier server-side. Scoped to 3 sources covering all 4 of the app's named telemetry identities: the Infrastructure Agent, the PHP probe agent, and the BPA WebServer Agent (`Logstash-APM-Plugin` — covers both "BPA agent" and "Browser agent," per the same finding documented above under `bpa-demo-agent-alerts.sh`). `create` self-heals by adding any of the 3 sources missing from an existing Universe. Note: `apm-universe create` does not honor `dry-run` — it's silently ignored and the Universe is created for real immediately, and each subcommand uses a different id parameter name (`create` takes `name=` for the *label*, `detail`/`add-metric-source` take `universeId=`, `delete` takes both `id=` and `name=`) — see the script's header comment for this and other landmines found while writing it.

`bpa-demo-services-universe.sh` manages the separate `"BPA Demo"` **O2/Platform Universe** (`dx-do o2-universe` — a.k.a. "Services Universe" in the console; the tenant needs both universe types until the product merges them). **Confirmed console bug (2026-07-07):** `o2-universe create` accepts no scoping parameters at all — a CLI-created Universe is always left unscoped (`tas` view filter `{"op": "ALL"}`, `nass` view `serviceFilter.values: []`), and opening that Universe in the console's edit UI crashes. Confirmed by diffing the crashing Universe (`VIEW617`, created via this script's original `o2-universe create` call) against one the user created manually through the console's own wizard (`VIEW618`, label `"BPA Demo"`, scoped to the `"BPA-Demo"` Service up front) — the only structural difference is the unscoped vs. `SERVICE`-shaped filter; see `dxo2-scripts/dx-do-o2-universe-issue.md` for the full writeup (this extends an earlier 404-on-open finding against the same root cause). `VIEW617` was deleted (`apm-universe delete` — `o2-universe` has no `delete` command of its own, but the cross-group call works). The script now points at `VIEW618` and **deliberately does not fall back to `o2-universe create`** when its state file is missing — since that call is confirmed to always produce a console-breaking Universe, `create` instead fails with instructions for manual console creation (pick a Service scope in the wizard, which avoids the bug entirely).

**Landmine — the two agentExpressions/sourceNamePattern segment regimes.** `dx-done metric data`'s `agentExpression.<key>=` and `dx-done agent query-by-regex`'s `regex=` match the **3-segment bare path** (`<host>|<process>|<agent>`, `SuperDomain|` stripped). `managementmodule create`'s `agentExpressions.<key>=` and `metricgrouping create/update`'s `sourceNamePattern=` match the **4-segment full path** (`SuperDomain|<host>|<process>|<agent>`) and require the `SuperDomain|` prefix (or a leading `.*\|`) to match anything under the implicit start-anchor. Mixing the two up is silent — no error, just zero live-matched metrics forever. Always verify a newly created/updated Metric Grouping with `dx-do metricgrouping list-metrics metricGroupingId=<id> managementModuleId=<mm-id>` before trusting it; "the create succeeded" is not evidence it matches anything.

`bpa-demo-sli.sh` creates the tenant's first SLI (Service Level Indicator) for BPA-Demo: `"BPA-Demo Frontend Response Time"` (`sliId 2767`), bound to the `"BPA-Demo"` Service. SLIs are a different resource type from the Alerts above — instead of a threshold on a raw agent metric, an SLI's value is computed and *written onto the Service's own topology vertex* (`sourceName: OI|SA|SERVICES|ALL`, `attributeName: {serviceVertex.attr.id}:<metric_name>`, tagged `is_sli: true`); `service metrics serviceName=<x>` confirmed BPA-Demo's vertex exposed nothing but the built-in `service_risk`/`service_health` composites before this. `dx-do`'s `sli` command group has no native create/delete — a new SLI is made by exporting an existing SLI as JSON (`sli export`) and re-importing it bound to a target service (`sli import file=... serviceName=...`); the unbind counterpart is `sli exclude-service` (there is no `sli delete` — excluding a service just returns the SLI to the unbound-template state the tenant's 3 pre-existing example SLIs were already found in via `sli list`). The tenant's richest example (`sliId 873`, `"CEmperf DB Errors"`) chains raw metric → SLO threshold comparator → rolling-percentage → rolling error-budget → an alert on the budget — a proper error-budget SLO — but its `attributeType` numeric codes and `errorbudget` threshold units aren't documented and differ between the tenant's own two SLO-bearing examples in ways that couldn't be fully verified from the outside. Rather than risk a silently-broken SLO pipeline (the same failure mode as the agentExpressions bug above), `bpa-demo-sli.sh` ships the **raw SLI only** for now: average of every `Frontends\|Apps\|BPA-Demo\|URLs\|<page>:Average Response Time (ms)` metric from the PHP probe agent, matched via a `REGEX` specifier (`^Frontends\|Apps\|BPA-Demo\|URLs\|[^|]+:Average Response Time \(ms\)$`) that deliberately excludes the nested `Called Backends\|...SQL...` sub-metrics, and an `EXACT` `sourceNameSpecifier` on the real probe agent path (`SuperDomain|bpa-demo-php-probe|php-probes|bpa-demo-infra-agent(/usr/sbin/apache2)`, confirmed via `metricgrouping list-metrics`). Verified working, not just created: `sli list` and `service slis serviceName=BPA-Demo` both confirm `enabled: true`, `totalMetrics: 52`, `sli_compliant: true` at creation time. One real landmine hit while building the import payload: the raw export's `groupId` (a real numeric id like `1191` on the template SLI reused as a base) must be replaced with a placeholder number (`0`, not `null`) — `null` fails schema validation (`expected number, received null`), and leaving the *original* SLI's real id in place risks the importer treating it as an update to that existing SLI instead of creating a new one. The SLO/error-budget/alert layer is a follow-up once its semantics are confirmed, not a rejected idea. The import payload's `createdBy`/`created_by` fields are not hardcoded to whichever tenant user happened to write this script — the tracked template (`dxo2-scripts/templates/bpa-demo-response-time-sli.json`) carries a `__DXO2_TENANT_USER_EMAIL__` placeholder, and `cmd_create` renders it into a temp file (`sed`, cleaned up with `rm -f` after the import call) with the real value substituted from `DXO2_TENANT_USER_EMAIL` in `.config` — so a different tenant user running this script gets their own login attributed, not a stale one that may not exist in their tenant.

---

## Traffic generator (`traffic-generator/`)

`traffic-generator/` is a standalone container that continuously generates synthetic user traffic against the app, so the DX O2 agents have real, varied data to report without a human clicking through the demo. Built with the rest of the stack (`build-scripts/build.sh`) and run as the `traffic` service in `docker-compose.yml`.

`generator.py` uses only the Python standard library (`urllib`, `http.cookiejar`) — no third-party dependencies, no `pip install`, no dependency layer. This was a deliberate fallback, not a stylistic choice: PyPI (`files.pythonhosted.org`) was unreachable from the build environment used to write this component (network policy, not a cert issue — confirmed via a 403 even after fixing an initial TLS interception error). `requests` would have been the more common choice otherwise; if PyPI access is available in your build environment, that constraint no longer applies.

Every full pass shuffles and cycles through **all** demo users (see "Demo use cases" above), not a random subset — this guarantees `trouble`/`empty_basket`/`locked` all fire regularly rather than only by chance. Per user: login, a random number of random actions (browse the shop with occasional filters, view a product, add to basket, view the basket, or complete a checkout — weighted so basket/checkout activity is common without crowding out plain browsing), then logout. The `admin` account also occasionally visits the admin diagnostic pages. A failed login (the `locked` use case returns `403`, not a redirect) is a normal, tolerated outcome, not an error — logged and the generator moves on to the next user.

Two urllib gotchas hit while writing this, both now handled in `_do_request()`:
- `HTTPRedirectHandler.redirect_request` returning `None` (to deliberately *not* follow a 3xx, so the caller can inspect `Location` itself — e.g. to tell a successful login apart from a re-rendered form) does **not** suppress the exception the way the stdlib docs suggest — `urlopen` still raises `HTTPError` for the 3xx via the default error handler. Must be caught and converted into a normal response object.
- The app's own `403`/`404` responses raise the same way. `HTTPError` is itself a valid response-like object (`.code`, `.headers`, `.read()`), so the catch block reads through it rather than re-requesting.

`TRAFFIC_ENABLED=false` keeps the container up but idle — same pattern as `APMIA_DEPLOY` in `dx-o2-agents/entrypoint.sh`. Pacing (`TRAFFIC_MIN/MAX_ACTION_DELAY_SECS`, `TRAFFIC_MIN/MAX_SESSION_DELAY_SECS`) and `TRAFFIC_LOG_LEVEL` are configurable via `.config`; `TARGET_URL` is hardcoded to the Compose service name (`http://apachephp:8080`) in `docker-compose.yml`, not read from `.config`, matching the same hardcoded-service-name convention used for `APMIA_PHP_COLLECTOR_HOST`/`APMIA_BTL_HOST`.

Verified end to end against the real stack (not just a syntax check): built via `compose.sh build`, ran via `compose.sh up -d`, confirmed real traffic in Apache's own access log (correct status codes per action: `403` for the blocked `locked` login, `302` for successful logins/redirects, `200` for pages) and confirmed the `trouble` use case's 5000-sequential-DB-read slowdown is visible in the generator's own action timing.

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

# DX O2 tenant configuration scripts (dxo2-scripts/)
DXO2_TENANT_USER_EMAIL   # login email of the tenant user running dxo2-scripts/*.sh;
                         # required by bpa-demo-sli.sh (SLI createdBy/created_by attribution)
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
- Never commit: `.config`, `.build_number`, `src/dx-o2-agents/installers/*`, `src/apache-php/app.tar.gz`, `helm/*/values.local.yaml`, `.claude/`, `tools/*`.

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
