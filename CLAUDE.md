# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

BPA-Demo is a PHP 8.3 + Apache 2.4 + MariaDB web shop (300 smart-home products, three brands) used as a Broadcom DX O2 APM demonstration target. Deployed via Helm/Kubernetes or Docker Compose with an optional APMIA monitoring sidecar.

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
build-scripts/package-helm-bundle.sh  # bundle helm/ + deploy.sh for a separate deploy host (images already pushed)
```

There is no test suite and no linter. Verify changes by running the app locally with `compose.sh up -d`.

All scripts source `.config` from the project root (copy from `.config.example`; never commit `.config`).

---

## PHP application architecture

### Front controller

`app/src/index.php` is the single entry point for all requests. It:
1. Bootstraps session and CSRF via `config/app.php`.
2. Opens the PDO singleton via `config/database.php`.
3. Resolves `?page=<slug>` against a static `$routes` array. There is no clean-URL rewriting — `vhost.conf` has no `RewriteRule` at all (removed 2026-08-19 along with the per-page wrapper files, per the same user-requested revert); every page is reached as `index.php?page=<slug>` (e.g. `/index.php?page=shop`), and bare `/`/`/index.php` default internally to `page=shop`. All internal links, form actions, and redirects across `templates/layout.php` and every `pages/*.php` file were updated to the `index.php?page=...` form to match.
4. Emits `X-Page-ID: page_<slug>` as a baseline header (e.g. `page_dxo2`) so every response carries a human-readable page identifier. Pages that call `set_monitoring_headers()` override this with a richer value.

**`X-Page-ID` cardinality rule:** the BPA WebServer Extension groups business transactions by the full `X-Page-ID` value, so `target` in `set_page_id()`/`set_monitoring_headers()` calls must be a fixed string or a small bounded set (e.g. a brand slug), **never** a numeric row ID or other high-cardinality value — that creates one distinct metric path per request instead of one shared path per logical page. **Bug fixed 2026-07-08:** `pages/order.php`'s confirmation view passed the numeric order ID as `target` (`ORDER-CONFIRM-186`, `ORDER-CONFIRM-187`, ...), so BPA accumulated one metric path per checkout ever completed. Fixed to a fixed `'SUCCESS'` target (`ORDER-CONFIRM-SUCCESS` for every order), mirroring the sibling not-found case's existing fixed `'NOTFOUND'` target on the same page. Verified live: two separate checkouts (order ids 225, 226) both produced the identical header.
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
| PHP OPcache | Disabled | `/etc/php/8.3/apache2/conf.d/99-disable-opcache.ini` (`opcache.enable=0`) — written by Dockerfile |
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

**`wily_php_agent.so` is a per-PHP-minor-version binary, not a single portable build.** `src/dx-o2-agents/Dockerfile` extracts it from `probe/lib/php<ver>/` inside the `PHP_apmia_*.tar` archive (`probe/lib/` for non-ZTS builds — matches Ubuntu's non-threaded mod_php; `probe/lib-zts/` ships in parallel for threaded SAPIs and is unused here). Confirmed by inspecting the real downloaded archive: it ships prebuilt `.so` files for PHP 8.0 through 8.4, each compiled against that PHP version's own Zend Module API — loading the wrong one doesn't degrade gracefully, it fails outright (`PHP Warning: PHP Startup: wily_php_agent: Unable to initialize module... Module compiled with module API=<X>, PHP compiled with module API=<Y>, These options need to match`), and the probe silently reports as "not loaded" everywhere (`?page=dxo2`, `get_loaded_extensions()`) with no other error. The Dockerfile's `probe/lib/php<ver>/` selection must always exactly match `apache-php/entrypoint.sh`'s own `PHP_VERSION` — verify with `docker exec <apache-php container> sha256sum <extension_dir>/wily_php_agent.so` against `docker run --rm --entrypoint sha256sum <dx-o2-agents image> /opt/apmia/extensions/PHPAgent/wily_php_agent.so`; a mismatch (or the `?page=dxo2` "Extension loaded: ✗ no" badge) means either the wrong `php<ver>` directory was selected or the `apmia_data` volume is stale (see "Docker Compose notes" above — this exact combination is what broke live verification of the 2026-08-19 PHP 8.1→8.3 upgrade before the volume was recreated).

`apache-php/entrypoint.sh`:
- Copies `wily_php_agent.so` into PHP's `extension_dir`.
- Copies `wily_php_agent.ini` to `/etc/php/8.3/mods-available/`; symlinks as `99-wily_php_agent.ini` into `/etc/php/8.3/apache2/conf.d/`.
- Patches `collectorHost`, `collectorPort`, `application.name`, `agentName`, `hostname` via `sed -i`. `agentName` and `hostname` are both set to `APMIA_PHP_AGENT_NAME` (default `bpa-demo-php-probe`) — `hostname` overrides OS `gethostname()` so the PHP probe appears with a recognisable name in the metric path instead of an auto-generated pod ID.
- Sets `logdir="/var/log/php-probe"`, `disableLogging=0`, `logLevel=<N>` (numeric). `APMIA_PHP_LOG_LEVEL` accepts a name (TRACE/DEBUG/INFO/WARN/WARNING/ERROR/FATAL) or a number (0–5); the entrypoint maps the name to its numeric equivalent before writing the INI because `wily_php_agent.logLevel` only accepts `0=trace,1=debug,2=info,3=warning,4=error,5=fatal`. The log directory is created in the Dockerfile and owned by `www-data` so the Apache process can write logs without privilege escalation.
- Writes browser-agent INI properties when `APMIA_BROWSER_SNIPPET` is set (enclose in single quotes in `.config` because the value contains double-quotes). Three properties are set: `response.decoration=1` (master switch — activates the browser agent module; required by the PHP probe before `autoInjection` is honoured), `snippet.autoInjection=1`, and `browseragent.autoInjection.snippetString='...'`. When `APMIA_BROWSER_SNIPPET` is empty all three are disabled/removed. Also sets `wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength=30000` unconditionally — `<head>` is at byte 33 and `</head>`/`<body>` at byte ~239/247 (CSS is a separate static file), well within the probe's 100–30000 valid range. **Frontend start and SCRIPT_NAME — known probe limitation, workaround reverted 2026-08-19:** the PHP probe has two independent gates for BA injection. (1) It hooks PHP opcodes: if the very first opcode of a script is an include (op 61/62/136), the probe enters include-tracking mode and never emits `Frontend start` — BA injection is skipped entirely. (2) It extracts the last segment of `SCRIPT_NAME` (not `REQUEST_URI`) to name the BA cookie; it treats `index.php` and bare `/` as null segments and skips injection for those. A plain front-controller pattern (all requests through `index.php`, which is what this app uses) fails both gates — see `bug_php_probe.md` for the full diagnosis and the vendor-facing write-up of what a probe-side fix would look like. A previous fix (per-page wrapper files at the document root, each running a non-include opcode before `require`-ing `index.php`, plus a `vhost.conf` rewrite to route through them and an external 302 redirect of bare `/` to `/shop`) worked around both gates, but was an application-level workaround for a probe-side limitation, not a fix to the underlying cause. At the user's request that workaround was fully reverted on 2026-08-19: the wrapper files are deleted, and `vhost.conf`'s `RewriteRule`/root-redirect were removed entirely (not just repointed) — every page is now reached as `index.php?page=<slug>` with no clean-URL rewriting at all, and every internal link/form/redirect in the app was updated to match (see "Front controller" above). **Browser-agent auto-injection does not currently work as a result** — this is the original, unfixed probe behavior, restored intentionally. **Open question, not investigated:** whether the PHP probe's separate, non-BA "Frontends|Apps|<app>|URLs|<url>" response-time/error-rate metrics (the ones `dxo2-scripts/` alerts and SLIs are built on) are gated by the same "Frontend start" mechanism as BA injection, or are independent base APM instrumentation unaffected by it. `bug_php_probe.md`'s diagnosis is scoped entirely to BA injection and never claims the general per-URL metrics were also broken, but all of this project's `nass query`-verified evidence for those metrics was gathered *while the wrapper-file workaround was active* (SCRIPT_NAME was never `/index.php` during that verification), so it's untested territory now. If those metrics silently stop reporting per-URL data after this revert, this is the first place to look. Everything else in this "PHP probe injection" section (INI property patching, log level mapping, etc.) is unaffected and still applies.

**Bug fixed 2026-07-09, found on the user's live Traefik/k8s deploy (not caught by local Compose or `kubectl port-forward` testing):** that root-redirect rule originally substituted a bare relative path (`RewriteRule ^$ /shop [R=302,L]`). For an `[R]` (external) redirect with a relative substitution, Apache itself has to build the absolute `Location` header via `ap_construct_url()` — and Apache has no idea a reverse proxy is terminating TLS in front of it, since it only ever serves plain HTTP on `:8080`. It defaulted to scheme `http` and appended its own listen port (`8080`, non-default for `http`), so a browser hitting `https://bpa-demo.shdw.fr/` behind Traefik got redirected to `http://bpa-demo.shdw.fr:8080/shop` — wrong scheme, and a port the Ingress/Service never expose externally. Compose/local testing never exercised this because there's no TLS-terminating proxy in front of Apache there, so the (coincidentally correct-looking) `http://host:8080/shop` redirect always matched the request's real host:port. Fixed by building the redirect as a fully-qualified URL from `%{HTTP_HOST}` (the original client-facing Host header, already portless for a default port) and a scheme detected from `X-Forwarded-Proto` (Traefik's default header for TLS-terminated requests) or a directly-terminated `HTTPS` connection — two `RewriteRule`s (https-branch guarded by `RewriteCond`, http-branch as the fallthrough) instead of one relative substitution. Verified against the actual `apache-php` image: `apache2ctl configtest` passes, and `curl` with `X-Forwarded-Proto: https` set produces `Location: https://<host>/shop` while the same request without it (matching Compose's no-proxy setup) still produces the original `http://<host>:<port>/shop` behavior unchanged.

**Bug fixed and confirmed live 2026-07-15 — `UnknownAgent` in the PHP probe's metric path:** per Broadcom's [PHP agent naming docs](https://techdocs.broadcom.com/us/en/ca-enterprise-software/it-operations-management/dx-apm-agents/SaaS/php-agent/monitor-php-applications-with-ca-digital-experience-insights/php-agent-naming-ca-digital-experience-insights.html), the PHP probe's metric path takes the form `host|php-probes|<AgentName>(<program>)`, where `<AgentName>` is the `{collector}` variable — "Name of Infrastructure Agent," resolved from the IA's own `introscope.agent.agentName` at the moment the PHP probe first registers. Confirmed live via `nass query` (2026-07-10): the Kubernetes deployment's PHP probe reports under `SuperDomain|bpa-demo-k8s|php-probes|UnknownAgent(/usr/sbin/apache2)` — a generic fallback, not `bpa-demo-k8s` — while Docker Compose's own PHP probe correctly resolved to `bpa-demo-docker(/usr/sbin/apache2)` once its identity was fixed (see "Deployment identity" above). **Two timing-based fix attempts, both shipped then disproved:** (1) a wait loop polling `APMIA_PHP_COLLECTOR_HOST:APMIA_PHP_COLLECTOR_PORT` via `/dev/tcp` before starting Apache, on the theory that the PHP probe's first registration could race ahead of the IA's own identity resolution — deployed and retested live, `UnknownAgent` still occurred; (2) after reading a real `IntroscopeAgent.log` pulled off a live pod and finding the port/probe connection happens at ~23-24s after IA startup while the actual EM WSS handshake doesn't succeed until ~104s (after a first attempt fails with a `NullPointerException` in the WebSocket handshake), replaced the port wait with a wait on `IntroscopeAgent.log` itself for the EM-connection-success line — written and locally verified against the real log, but never deployed, because a better fix surfaced before that redeploy happened. **Real fix:** Broadcom's own Kubernetes-cluster-mode documentation identifies this as a known interaction between the IA's remote-agent auto-naming (which assigns the probe's `AgentName` segment based on whichever of the IA's own identities has resolved *at the moment the probe registers* — not a fixed point in time, so no wait deadline can be sized correctly against it) and cluster-style deployments. The fix is to disable auto-naming and force the probe's identity statically instead of ever letting it race: `APMENV_INTROSCOPE_AGENT_AGENTAUTONAMINGENABLED=false` plus `APMENV_INTROSCOPE_REMOTEAGENT_PROBE_AGENT_NAME=<deployment identity>` on the `dx-o2-agent` container (both wired in `helm/php-demo/templates/statefulset.yaml` and `docker-compose.yml`'s `dxo2` service, reusing the existing `dxo2.agentName`/`APMIA_AGENT_NAME` value — no new `.config` variable needed). Both timing-based workarounds were removed from `src/apache-php/entrypoint.sh` as dead weight once this made them unnecessary. Deliberately did **not** also set `APMENV_INTROSCOPE_REMOTEAGENT_PROBE_PROCESS_NAME` — Broadcom's doc pairs it with `_AGENT_NAME` as a matched set (it renames the literal `php-probes` process segment, the 3rd path segment, to the same value), but that literal is hardcoded across nearly every `dxo2-scripts/` script and template (`bpa-demo-service.sh`, `bpa-demo-agent-alerts.sh`, `bpa-demo-sli.sh`, the SLI/dashboard JSON templates) as the distinguishing token for "this is the PHP probe agent" — renaming it would break all of them for no benefit, since the observed bug is only ever in the `AgentName` segment, never in `php-probes` itself. **Confirmed live on both deployments** after rebuild/redeploy: Kubernetes now reports `SuperDomain|bpa-demo-k8s|php-probes|bpa-demo-k8s:Agent Type: php` and Docker Compose `SuperDomain|bpa-demo-docker|php-probes|bpa-demo-docker:Agent Type: php` — `UnknownAgent` is gone from both, `AgentName` now correctly matches each deployment's own identity.

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

### Deployment identity (`DEPLOYMENT_NAME` / `DEPLOYMENT_POSTFIX`)

**Bug found live 2026-07-10:** the Docker Compose deployment and the Helm/Kubernetes deployment defaulted to identical DX O2 agent identity strings (`APMIA_AGENT_NAME`, `APMIA_APP_NAME`, `APMIA_HOST_NAME`, `APMIA_PROCESS_NAME`, `APMIA_PHP_AGENT_NAME`, `APMIA_WEB_AGENT_NAME` all shared the same hardcoded `bpa-demo*` defaults across both `build-scripts/compose.sh` and `build-scripts/deploy.sh`). Running both against the same tenant made DX O2 disambiguate the second connection by appending a `%1` suffix to its identity — confirmed via `nass query`: `bpa-demo-infra-agent` (Kubernetes, DB Monitor hostname `127.0.0.1`, same-pod access) vs `bpa-demo-infra-agent%1` (Compose, DB Monitor hostname `mariadb`, separate-container access — whichever connected *second* got suffixed). This silently broke every dashboard/alert/metric-grouping query written against the plain (unsuffixed) name, since neither currently-reporting identity matched it exactly.

Fixed by introducing two new `.config` variables that combine as `"${DEPLOYMENT_NAME}-${DEPLOYMENT_POSTFIX}"` into the shared default for all six APMIA identity variables above:
- `DEPLOYMENT_NAME` — the logical application name, default `bpa-demo`.
- `DEPLOYMENT_POSTFIX` — left empty in `.config.example`; `compose.sh` defaults it to `docker`, `deploy.sh` defaults it to `k8s`, so the two deployment mechanisms never collide out of the box. Override explicitly for a third distinct value (e.g. two separate Kubernetes clusters).

`build-scripts/compose.sh`'s and `build-scripts/deploy.sh`'s `load_config()`/`generate_values()` each compute `deployment_id="${DEPLOYMENT_NAME}-${DEPLOYMENT_POSTFIX}"` and use it as the fallback (`${APMIA_AGENT_NAME:-${deployment_id}}`, etc.) for all six identity vars — any one can still be set explicitly in `.config` to override just that agent while the rest fall back to the shared `deployment_id`. `helm/php-demo/values.yaml`'s own standalone chart defaults (for a bare `helm install` without `deploy.sh`) were updated to `bpa-demo-k8s` to match. `docker-compose.yml`'s inline `${VAR:-default}` fallback literals (only reachable if `docker compose` is invoked directly, bypassing `compose.sh`'s own exports) were updated to `bpa-demo-docker` for consistency.

Deliberately does **not** touch the DB Monitor's `profileName` (`bpadb`) — confirmed via `nass query` that the profile name never appears in the actual reported metric *source* path at all (it's purely an internal APMIA-extension config key, invisible in the console); DB Monitor metrics report under the same Infrastructure Agent identity (`APMIA_HOST_NAME`/`APMIA_AGENT_NAME`/`APMIA_APP_NAME`) that this mechanism already covers. Also does not touch the DB Monitor's connection `hostname` property (`127.0.0.1` in Kubernetes vs `mariadb` in Compose) or the app's `MARIADB_HOST` — those are real connectivity requirements dictated by each deployment's container topology, not identity labels.

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
- **Compose:** `hostname: ${APMIA_HOST_NAME:-bpa-demo-docker}` on the `apachephp` service (covers IA + BPA).
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

`bpa-demo-service.sh` creates the `"BPA-Demo"` DX O2 Service, grouping the php-probe's frontend URLs, the BPA Webserver Extension's business transactions (`page_login`, `SHOP-LIST-*`, etc.), the BPA WebServer Agent's own reporting identity (`agent EQUALS "Experience Collector Host|DxC Agent|Logstash-APM-Plugin"` — where the Browser Agent (BA snippet)'s page-load/page-hits timing actually lands, per-URL under `Business Segment|BPA Demo|<url>:<leaf>`), and the mysql backend database (both the php-probe's inferred `DATABASE` dependency and the DB Monitor extension's own richer CI) under one console view. Content query (4 groups, OR'd): `applicationName EQUALS "BPA-Demo"`, `agent EQUALS "bpa-demo-host|bpa-demo|bpa-demo-infra-agent"` (the Infrastructure Agent), `agent EQUALS "bpa-demo-php-probe|php-probes|bpa-demo-infra-agent(/usr/sbin/apache2)"` (the PHP probe agent), `agent EQUALS "Experience Collector Host|DxC Agent|Logstash-APM-Plugin"` (the BPA WebServer Agent) — the first three exist because the DB Monitor extension's CI doesn't carry `applicationName` (it comes from a host-scoped inventorize rule, not an app-scoped one). There is deliberately **no** separate content group for a distinct "Browser Agent" entity: a `Custom Business Application Agent (Virtual)|By Business Service|BPA Demo` path shows the identical values rolled up under the Business Service view, but it is not a real topology entity — confirmed empirically (2026-07-06) that no content-query attribute (`agent EQUALS`/`MATCHES` on the full path or bare name, `type EQUALS AGENT` + `name` variants) matches it; it only exists as a metric-source-path label. **Bug fixed 2026-07-10:** three of the four groups used an exact-match `EQUALS` on identity literals (`bpa-demo-host`/`bpa-demo-infra-agent`/`bpa-demo-php-probe`/`BPA-Demo`) that went dead the same day when `DEPLOYMENT_NAME`/`DEPLOYMENT_POSTFIX` changed the real identities to `bpa-demo-k8s`/`bpa-demo-docker` (see "Deployment identity" above) — and `create`'s self-heal only ever checked for the fourth (DxC) group, so re-running it after the identity change fixed nothing. Fixed by switching the three affected groups from `EQUALS` to `MATCHES` with a wildcarded `bpa-demo-.*` segment (confirmed via a `service add-content ... dry-run=true` probe that `MATCHES` is a real, working regex operator on this API — its preview correctly matched both new agent identities before anything was committed), and by switching `create`'s self-heal from `service add-content` (checks for and appends one specific group) to `service set-content` (a full replace of all four groups, always bringing the live query back in sync with the script — idempotent when already correct). Content query is now (4 groups, OR'd): `applicationName MATCHES "^bpa-demo-.*$"`, `agent MATCHES "^bpa-demo-.*\|bpa-demo-.*\|bpa-demo-.*$"` (Infrastructure Agent), `agent MATCHES "^bpa-demo-.*\|php-probes\|bpa-demo-.*\(/usr/sbin/apache2\)$"` (PHP probe agent), `agent EQUALS "Experience Collector Host|DxC Agent|Logstash-APM-Plugin"` (BPA WebServer Agent, unchanged). Verified live via `service detail`: all four groups present with the expected operator/pattern.

`bpa-demo-management-module.sh` creates a classic APM Management Module `"BPA-Demo"` containing one Metric Grouping (`attributeNamePattern` matching `Frontends|Apps|BPA-Demo|URLs|*:Average Response Time (ms)` — every tracked frontend URL) and one Alert (`GREATER_THAN`, warning `100ms`, error `250ms`) that catches the `trouble` use case (`usecases/trouble.php` — 5 000 sequential DB reads/request). Thresholds are measured, not guessed: real traffic showed ~6–7ms for normal requests and ~350–690ms for the `trouble` user, both comfortably clear of the chosen thresholds. `empty_basket` (basket total always €0.00) and `locked` (blocks login) have **no currently-observable APM signal**: neither returns an HTTP error status (confirmed by reading `login.php`/`usecases/locked.php` — no `http_response_code()`/error-status `header()` calls anywhere), and BPA's payload metrics only expose request/response **size in bytes**, not extracted field values, so there is nothing to threshold-alert on for either today. Catching `empty_basket` would need the response header `X-Basket-Total` (already emitted by `checkout.php` — see `page_id.php`'s `set_monitoring_headers()`) exposed as a captured BPA attribute; this was being configured tenant-side as of the last check but did not yet appear on live checkout transactions even after a `dxo2` container restart (BTL re-fetches its capture-rule cache on startup) and repeated fresh traffic — revisit once that's confirmed working, then extend this script's Metric Grouping/Alert set to match. Classic-APM resources (`managementmodule`/`metricgrouping`/`alert` in `dx-do`) don't share `service create`'s dry-run-by-default safety net — `managementmodule create` in particular executes immediately — so double-check parameters before creating. **Bug fixed 2026-07-06:** the Metric Grouping originally inherited the MM's `agentExpressions` (`bpa-demo.*`, no `SuperDomain|` prefix) via the default `useManagementModuleAgentExpression=true`. The 4-segment MM `agentExpressions`/`sourceNamePattern` regime is implicitly start-anchored against the **full** `SuperDomain|<host>|<process>|<agent>` path (see `reference-agent-expressions` in `.claude/skills/`), so a pattern missing that prefix matches zero agents — silently: the create succeeds, the console shows the alert, but it never has data. Fixed by giving the Metric Grouping its own explicit `sourceNamePattern='SuperDomain\|.*bpa-demo.*'` with `useManagementModuleAgentExpression=false` instead of inheriting. `create` now also self-heals: if the Metric Grouping already exists, it checks `metricgrouping list-metrics` for at least one live match and re-applies the fix if it finds none, instead of treating "exists" as "working." **Bug fixed 2026-07-10:** `ATTRIBUTE_NAME_PATTERN` hardcoded the literal application name `BPA-Demo` (`Frontends|Apps|BPA-Demo|URLs|...`); adding `DEPLOYMENT_NAME`/`DEPLOYMENT_POSTFIX` to `.config` made `APMIA_APP_NAME` — which becomes exactly this attribute-path segment via the PHP probe's `wily_php_agent.application.name` — default to the deployment id (`bpa-demo-k8s`/`bpa-demo-docker`) instead of a fixed `BPA-Demo`, so the Metric Grouping dropped to zero live matches. Fixed by wildcarding that segment (`Frontends\|Apps\|bpa-demo-[^|]*\|URLs\|...`); the self-heal path was also missing `attributeNamePattern` from its `metricgrouping update` call (only `sourceNamePattern` was being re-applied) — fixed to re-apply both. Re-verified live: 108 matches after the fix.

`bpa-demo-agent-alerts.sh` creates 12 Metric Groupings + Alerts across three telemetry sources, all attached to the same `"BPA-Demo"` Management Module: five for the Infrastructure Agent's DB Monitor extension (availability, connection refusals, connection pool pressure, buffer pool cache hit rate, slow query rate), five for the PHP probe agent (app response time, error rate, concurrency, DB backend response time, DB backend query volume), and two for the browser/RUM pipeline reported via the BPA WebServer Agent (page load time, page hits per interval — same `Logstash-APM-Plugin` identity as `bpa-demo-service.sh`'s fourth content group, which never appears in `dx-done agent list`/`query-by-regex` output despite being real and queryable via `metric data`). Every Metric Grouping here uses an explicit `sourceNamePattern` + `useManagementModuleAgentExpression=false` from the start (the pattern that fixed `bpa-demo-management-module.sh`'s bug above), so none of them share that failure mode. Depends on `bpa-demo-management-module.sh create` having been run first (reads its state file for the parent MM id). Thresholds are measured from live metric windows, not guessed — see the script's header comment for the readings behind each one. **Bug fixed 2026-07-10:** the same deployment-identity change above broke 10 of these 12 (everything except the two browser/RUM ones): the infra/php `AGENT_SOURCE_PATTERN` entries hardcoded the pre-fix identity literals (`bpa-demo-host`/`bpa-demo-infra-agent`/`bpa-demo-php-probe`, now dead), and 7 of the 10 `ALERT_ATTR_PATTERN` entries hardcoded either `mariadb` (the DB-hostname literal, never true for Kubernetes' `127.0.0.1`-based paths, same bug the dashboard had) or `BPA-Demo` (the app-name literal, per the entry above). Wildcarded every hardcoded segment. This script's `create` previously had **no self-heal at all** — an already-recorded alert key was unconditionally skipped, so re-running `create` after fixing the patterns did nothing. Added a `heal_one()` step that checks each metric grouping's live-match count via `metricgrouping list-metrics` and re-applies both patterns via `metricgrouping update` if it finds zero. Re-verified live: all 10 previously-broken groupings show 1-2 live matches after the fix; the two browser ones were unaffected throughout (10 matches each, confirmed before touching anything).

**Situations (AIOps alarm correlation) never form from these alerts — investigated 2026-07-09, see `BUGS` for the full writeup.** `dx-do situation` has no create command; Situations are auto-correlated by DX O2's AIOps engine from firing alarms, not a defined resource. Confirmed the alerts above fire correctly for real (triggered the `trouble` use case live, then a genuine cross-tier fault by stopping the `mariadb` container for ~2 minutes) — both a same-tier alarm cluster and a real two-tier cluster (Infrastructure Agent CI + PHP probe agent CI breaching within ~90s of each other) were confirmed firing, but `situation query` returned `[]` across ~25 minutes of combined polling either way. No fix identified from the CLI alone; needs the console's own Situations view checked directly or confirmation from Broadcom on what enables correlation for a tenant this size.

`bpa-demo-universe.sh` creates the `"BPA Demo universe"` APM Universe (`dx-do apm-universe` — the default/regular surface, `viewId`s look like `VIEW###`; distinct from the legacy `o2-universe`). A Universe has no content-query membership mechanism over the CLI — it's populated with explicit metric-source agent paths via `apm-universe add-metric-source`, one call per source, which accumulate into a single `EXACT`-type specifier server-side. Scoped to 3 sources covering all 4 of the app's named telemetry identities: the Infrastructure Agent, the PHP probe agent, and the BPA WebServer Agent (`Logstash-APM-Plugin` — covers both "BPA agent" and "Browser agent," per the same finding documented above under `bpa-demo-agent-alerts.sh`). `create` self-heals by adding any of the 3 sources missing from an existing Universe. Note: `apm-universe create` does not honor `dry-run` — it's silently ignored and the Universe is created for real immediately, and each subcommand uses a different id parameter name (`create` takes `name=` for the *label*, `detail`/`add-metric-source` take `universeId=`, `delete` takes both `id=` and `name=`) — see the script's header comment for this and other landmines found while writing it.

`bpa-demo-services-universe.sh` manages the separate `"BPA Demo"` **O2/Platform Universe** (`dx-do o2-universe` — a.k.a. "Services Universe" in the console; the tenant needs both universe types until the product merges them). **Confirmed console bug (2026-07-07):** `o2-universe create` accepts no scoping parameters at all — a CLI-created Universe is always left unscoped (`tas` view filter `{"op": "ALL"}`, `nass` view `serviceFilter.values: []`), and opening that Universe in the console's edit UI crashes. Confirmed by diffing the crashing Universe (`VIEW617`, created via this script's original `o2-universe create` call) against one the user created manually through the console's own wizard (`VIEW618`, label `"BPA Demo"`, scoped to the `"BPA-Demo"` Service up front) — the only structural difference is the unscoped vs. `SERVICE`-shaped filter; see `dxo2-scripts/dx-do-o2-universe-issue.md` for the full writeup (this extends an earlier 404-on-open finding against the same root cause). `VIEW617` was deleted (`apm-universe delete` — `o2-universe` has no `delete` command of its own, but the cross-group call works). The script now points at `VIEW618` and **deliberately does not fall back to `o2-universe create`** when its state file is missing — since that call is confirmed to always produce a console-breaking Universe, `create` instead fails with instructions for manual console creation (pick a Service scope in the wizard, which avoids the bug entirely).

**Landmine — the two agentExpressions/sourceNamePattern segment regimes.** `dx-done metric data`'s `agentExpression.<key>=` and `dx-done agent query-by-regex`'s `regex=` match the **3-segment bare path** (`<host>|<process>|<agent>`, `SuperDomain|` stripped). `managementmodule create`'s `agentExpressions.<key>=` and `metricgrouping create/update`'s `sourceNamePattern=` match the **4-segment full path** (`SuperDomain|<host>|<process>|<agent>`) and require the `SuperDomain|` prefix (or a leading `.*\|`) to match anything under the implicit start-anchor. Mixing the two up is silent — no error, just zero live-matched metrics forever. Always verify a newly created/updated Metric Grouping with `dx-do metricgrouping list-metrics metricGroupingId=<id> managementModuleId=<mm-id>` before trusting it; "the create succeeded" is not evidence it matches anything.

`bpa-demo-sli.sh` creates the tenant's first SLI (Service Level Indicator) for BPA-Demo: `"BPA-Demo Frontend Response Time"` (`sliId 2767`), bound to the `"BPA-Demo"` Service. SLIs are a different resource type from the Alerts above — instead of a threshold on a raw agent metric, an SLI's value is computed and *written onto the Service's own topology vertex* (`sourceName: OI|SA|SERVICES|ALL`, `attributeName: {serviceVertex.attr.id}:<metric_name>`, tagged `is_sli: true`); `service metrics serviceName=<x>` confirmed BPA-Demo's vertex exposed nothing but the built-in `service_risk`/`service_health` composites before this. `dx-do`'s `sli` command group has no native create/delete — a new SLI is made by exporting an existing SLI as JSON (`sli export`) and re-importing it bound to a target service (`sli import file=... serviceName=...`); the unbind counterpart is `sli exclude-service` (there is no `sli delete` — excluding a service just returns the SLI to the unbound-template state the tenant's 3 pre-existing example SLIs were already found in via `sli list`). The tenant's richest example (`sliId 873`, `"CEmperf DB Errors"`) chains raw metric → SLO threshold comparator → rolling-percentage → rolling error-budget → an alert on the budget — a proper error-budget SLO — but its `attributeType` numeric codes and `errorbudget` threshold units aren't documented and differ between the tenant's own two SLO-bearing examples in ways that couldn't be fully verified from the outside. Rather than risk a silently-broken SLO pipeline (the same failure mode as the agentExpressions bug above), `bpa-demo-sli.sh` ships the **raw SLI only** for now: average of every `Frontends\|Apps\|BPA-Demo\|URLs\|<page>:Average Response Time (ms)` metric from the PHP probe agent, matched via a `REGEX` specifier (`^Frontends\|Apps\|BPA-Demo\|URLs\|[^|]+:Average Response Time \(ms\)$`) that deliberately excludes the nested `Called Backends\|...SQL...` sub-metrics, and an `EXACT` `sourceNameSpecifier` on the real probe agent path (`SuperDomain|bpa-demo-php-probe|php-probes|bpa-demo-infra-agent(/usr/sbin/apache2)`, confirmed via `metricgrouping list-metrics`). Verified working, not just created: `sli list` and `service slis serviceName=BPA-Demo` both confirm `enabled: true`, `totalMetrics: 52`, `sli_compliant: true` at creation time. One real landmine hit while building the import payload: the raw export's `groupId` (a real numeric id like `1191` on the template SLI reused as a base) must be replaced with a placeholder number (`0`, not `null`) — `null` fails schema validation (`expected number, received null`), and leaving the *original* SLI's real id in place risks the importer treating it as an update to that existing SLI instead of creating a new one. The SLO/error-budget/alert layer is a follow-up once its semantics are confirmed, not a rejected idea. The import payload's `createdBy`/`created_by` fields are not hardcoded to whichever tenant user happened to write this script — the tracked template (`dxo2-scripts/templates/bpa-demo-response-time-sli.json`) carries a `__DXO2_TENANT_USER_EMAIL__` placeholder, and `cmd_create` renders it into a temp file (`sed`, cleaned up with `rm -f` after the import call) with the real value substituted from `DXO2_TENANT_USER_EMAIL` in `.config` — so a different tenant user running this script gets their own login attributed, not a stale one that may not exist in their tenant. **Bug found 2026-07-10, confirmed unfixable via this CLI:** the deployment-identity change broke both specifiers — the `EXACT` `sourceNameSpecifier` hardcoded the now-dead `bpa-demo-php-probe`/`bpa-demo-infra-agent` literals, and the `attributeNameSpecifier` hardcoded the `BPA-Demo` app-name literal (per the entries above) — dropping the live SLI to `totalMetrics: 0`. The template is fixed (both specifiers are now wildcarded `REGEX`), but **there is no way to push that fix to the existing SLI via this CLI**: `sli` has only `exclude-service`/`export`/`import`/`include-service`/`list` — no `update`. `sli import` refuses outright on a name collision (confirmed live, even with `dry-run=false` and undocumented `overwrite=true`/`force=true`, both silently ignored), contradicting this script's original assumption that importing with the real `groupId` would update in place. Excluding the service first doesn't free the name either — it persists across unbind, the same state the tenant's 3 pre-existing example SLIs are already in. Fixing the live SLI requires a manual console edit of its filter using the corrected patterns now in the template — this is the one resource of the three broken by the identity change that could not be self-healed by script. The console's filter editor takes structured Source/Metric conditions (`contains`/`starts_with`/`ends_with`), not raw regex — see `DX-O2_MANUAL_CONFIGURATION.md` for the exact steps taken, the resulting specifier, and an open item (the two-step "filter then refine" approach appears to replace rather than AND the two conditions in the persisted specifier, leaving the metric-type restriction missing).

**2026-07-10: two more SLIs added** — `"BPA-Demo Frontend Error Rate"` (`sliId 2768`, `Frontends\|Apps\|bpa-demo-[^|]+:Errors Per Interval$` on the PHP probe agent, `sli_type: "Errors"` — a real value confirmed from the tenant's own pre-existing `"CEmperf DB Errors"` example, `sliId 873`) and `"BPA-Demo Client-Side Page Load Time"` (`sliId 2769`, `Business Segment\|BPA Demo\|[^|]+:Average Page Load Time \(ms\)$` on the Browser Agent's `Experience Collector Host|DxC Agent|Logstash-APM-Plugin` identity — real End-User/Digital Experience data, not the classic APM path, though it surfaces through the same NASS metric catalog). Both templates (`dxo2-scripts/templates/bpa-demo-error-rate-sli.json`, `bpa-demo-page-load-time-sli.json`) were verified via `nass query` against real data *before* import this time (learned from the response-time SLI's over-matching mistake) — error rate matches exactly one live source (`bpa-demo-docker`, app-level aggregate, no nested backends possible since `Errors Per Interval` has no per-SQL-statement variant), page load matches multiple real per-page entries with no over-matching. Imported as one-off `sli import` calls (no name collision, since these are new names) rather than building out a full self-healing script yet — the user explicitly plans to fine-tune both in the console, so a script would just go stale immediately, the same trap `bpa-demo-sli.sh`'s own template fell into. **Landmine confirmed while checking these: `sli list`'s `totalMetrics` field is not a match-count for the specifier** — `sliId 2768` showed `totalMetrics: 78` despite matching exactly one real source via `nass query`; it appears to count aggregated time-series intervals computed so far (roughly consistent with `sliId 2767` also showing `78` after running a similar length of time), not "how many sources matched." `sliId 2769` correctly showed `totalMetrics: 0`, consistent with no real browser traffic yet (traffic generator is plain HTTP only) — so the field isn't meaningless, just not a proxy for filter correctness. Verify specifier scope with `nass query`, not `totalMetrics`.

**2026-07-10: SLO layer, modeled on 2767's now-confirmed-working structure.** Re-exporting `sliId 2767` showed the user had since added a real, working `sloDefinition` via the console: `comparator` (raw value `LE 200`ms, 5-min window) → `percentage` (rolling 1-day % passing) → `errorbudget` (`GE 98`% rolling 1-day) — resolving this project's earlier "`attributeType` codes and `errorbudget` units aren't documented" uncertainty (see `bpa-demo-sli.sh`'s "Why no SLO yet" header) with a real confirmed example (`attributeType: 258`/`4097`/`2` for threshold/percentage/error-budget respectively) instead of a guess. Added the identical 3-function structure to both new templates, with thresholds pulled from this project's own already-measured alert baselines rather than guessed: Error Rate `LE 2` (matches `bpa-demo-agent-alerts.sh`'s `ALERT_WARNING[php-error-rate]`), Page Load Time `LE 300`ms (matches `ALERT_WARNING[browser-page-load]`), both `GE 98`% error budget. Confirmed via `sli import ... dry-run=true` that this can't be pushed to the live 2768/2769 either — same collision refusal, since both now exist; the SLO layer needs the console's own SLO editor. See `DX-O2_MANUAL_CONFIGURATION.md` for the exact values.

`bpa-demo-agent-health-dashboard.sh` creates `"BPA-Demo · Agent Health"` (a dashboard's title can't equal its containing folder's title, hence the `· Agent Health` suffix) in the pre-existing `"BPA-Demo"` dashboard folder — discovered a folder and a dashboard (`"BPA-Demo PHP Probe · Overview"`) already there from earlier work, neither created by any tracked script; left both untouched and added this as a complementary, agent-scoped overview rather than editing what already existed. Three sections: an "Agent Status" row of 3 `grafana-polystat-panel` traffic-light circles (Infrastructure Agent, PHP Probe Agent, BPA WebServer Agent), then each agent's basic metrics (Infra: DB Availability/Connection Refusals/Cache Hit Rate/Slow Query Rate; PHP: App Response Time/Error Rate/Concurrency/DB Backend Response Time; Browser: Page Load Time/Page Hits). Each traffic light queries the reserved `Custom Metric Agent (Virtual)` alert-status metric (`Alerts|BPA-Demo:<alert name>`, published by the EM for every alert on an active Management Module — confirmed via `metric data`, values are a discrete 0=no-data/1=ok/2=warning/3=critical severity scale) with a regex matching every alert belonging to that agent's tier, rolled up to the *worst* severity among them via a polystat composite (`globalOperatorName: "max"`) — green only if every alert for that agent is currently OK. Reuses the alerts `bpa-demo-management-module.sh`/`bpa-demo-agent-alerts.sh` already created; no new alert. Verified live before wiring anything in: every alert-status regex and every metric-graph pattern was checked against real `dx-do metric data` output first, including confirming the lights show a genuine mix of severities (not trivially all-green) — at verification time the PHP Probe Agent light was legitimately red from a leftover elevated error-rate alert from earlier fault-injection testing (see the Situations entry above), not a dashboard bug.

**Bug fixed 2026-07-09: every panel rendered empty despite that verification.** Root cause: `metric data`'s `agentExpression` regime strips the `SuperDomain|` prefix before matching (the 3-segment bare-path regime used throughout the earlier alert/SLI work in this project), but the dashboard's own NASS query engine (`basicFilters[].sourceNameSpecifier[].pattern`, the same mechanism `dx-do nass query` exposes directly) does a literal REGEX match against the **full** `metric.source` string, which always starts with `SuperDomain|`. Every `sourceNameSpecifier` pattern in the dashboard template was written in the bare 3-segment form (correctly verified against `metric data`, which normalizes it away) and therefore matched zero rows against the dashboard's actual query surface — a different landmine instance of the same "3-segment vs 4-segment path regime" confusion documented under `reference-agent-expressions` and the `bpa-demo-management-module.sh` agentExpressions bug above, just hitting a third API surface (NASS dashboard queries) this time. Found by probing the raw `dx-do nass query` API directly with `FROM_METADATA` + `KEEP` (the empirical-discovery move from `reference-datastore-entities`/`dx-done-nas`): the bare-path pattern returned zero rows, the identical pattern with `SuperDomain\|` prepended returned the real metric. Fixed by prepending `SuperDomain\|` to all 13 `sourceNameSpecifier` patterns in the template (3 polystat + 10 metric-graph targets); re-verified every one of the 18 panels' query patterns individually against the raw `nass query` API before redeploying, not just the handful spot-checked the first time. **Lesson: `dx-do metric data` is not a valid stand-in for verifying a dashboard's own NASS query shape** — its agentExpression convenience layer silently normalizes away exactly the prefix the raw dashboard query needs; verify dashboard `sourceNameSpecifier` patterns with `dx-do nass query` (or `dashboard-render`, unavailable on this build) instead.

**2026-07-10: identity collision, a "Deployment" selector, and a same-day app-name gap — see `dxo2-scripts/README.md`'s Dashboards section for the full narrative** (this file already covers the DEPLOYMENT_NAME/DEPLOYMENT_POSTFIX root cause and the PHP probe `UnknownAgent` race elsewhere). Summary: added a Grafana `custom` variable (`deployment`: `docker`/`k8s`, defaults to "All") interpolated via `${deployment:regex}` into the DB-Monitor/PHP-Probe panels' `sourceNameSpecifier`; found and fixed two bugs shipping it (the self-heal script dropped `templating` on push; the "All" option needed to be a literal `options[0]` entry, not just `current.value`). While fixing the Management Module/Alerts/SLI for the same identity change (see `bpa-demo-management-module.sh`/`bpa-demo-agent-alerts.sh`/`bpa-demo-sli.sh` entries above), found this dashboard's own PHP-tier panels (App Response Time/Error Rate/Concurrency) still hardcoded the dead `BPA-Demo` app-name literal in their `attributeNameSpecifier` — the earlier `${deployment:regex}` fix only touched the source side, not the attribute side. Fixed by applying the same `${deployment:regex}` variable to the attribute pattern's app-name segment, keeping both sides scoped to whichever deployment is selected.

**2026-07-09: split "Browser/RUM" into the two genuinely distinct sources it was conflating, added panel descriptions, added a network-time comparison.** The original 3-section build treated the Browser Agent and the BPA WebServer Plugin as one thing because both publish under the same `Logstash-APM-Plugin` agent identity (see the earlier telemetry-sources finding above) — but they're opposite ends of the same request: the **Browser Agent** is client-side (`Business Segment|BPA Demo|<url>:...`, timing as measured inside a real visitor's browser, including network + render), and the **BPA WebServer Plugin** (`mod_caplugin`) is server-side (`Business Segment|[BPA Demo]<ip>:<port>|<X-Page-ID>:...`, timing as measured inside our own Apache process for the same requests — the `[BPA Demo]<ip>:<port>` segment identifies which Apache instance reported it; stale entries from before the static-IP fix remain harmlessly in the catalog since the patterns wildcard the IP). Split into their own sections; added a new BPA WebServer Plugin section (Response Time, Backend Server Time, Responses/Errors Per Interval, wildcarded across business transactions and IPs). Every data panel now carries a `description` (Grafana's "i" hover icon) naming its real source, to make this distinction visible in the console, not just in docs. Also added the Browser Agent's real per-resource `Average Time To First Byte (ms)` metric — confirmed via `nass query` to have genuine non-zero historical data (from earlier manual browser testing), unlike the page-level Page Load Time/Page Hits metrics which sit at 0 under the traffic generator's plain-HTTP-only traffic. For the requested "network time" panel, considered a true computed difference (`Response Time − Backend Server Time`) via a Grafana `calculateField` transform, but this build's lack of `dashboard-render` means the AIOps NASS datasource's output field names couldn't be visually confirmed — shipping an unverifiable transform risked silently doing nothing. Shipped the verified alternative: both metrics as two lines on one graph, so the gap (≈ network transit + plugin overhead) is visible by eye; the transform is a reasonable follow-up once it can be checked in the console's own panel editor.

**This dx-do build's `dashboard` command group is missing `dashboard-create`, `dashboard-delete`, `validate-layout`, and `dashboard-render` entirely** (a smaller surface than some dx-do documentation describes for newer builds) — `create` uses `dashboard-import` for the fresh case and the classic export→edit→`dashboard-update` workflow to self-heal/upsert (the documented `dashboard-import ... preserveUid=true overwrite=true` upsert doesn't work here: `overwrite=` is silently ignored, so the request always carries `"overwrite":false` and fails with HTTP 412 `version-mismatch`; `dashboard-update` also doesn't resolve a numeric id from a bare `uid` on this build, contrary to some documentation — it needs the real numeric `id` from a fresh `dashboard-export`). `delete` prints manual console-removal instructions instead of pretending a CLI command exists. No `dashboard-render` means no PNG self-check was possible; verification relied on `dashboard-export`/`check` (panel count/types/titles) plus the live `metric data` checks above.

---

## Traffic generator (`traffic-generator/`)

`traffic-generator/` is a standalone container that continuously generates synthetic user traffic against the app, so the DX O2 agents have real, varied data to report without a human clicking through the demo. Built with the rest of the stack (`build-scripts/build.sh`) and run as the `traffic` service in `docker-compose.yml`.

`generator.py` uses only the Python standard library (`urllib`, `http.cookiejar`) — no third-party dependencies, no `pip install`, no dependency layer. This was a deliberate fallback, not a stylistic choice: PyPI (`files.pythonhosted.org`) was unreachable from the build environment used to write this component (network policy, not a cert issue — confirmed via a 403 even after fixing an initial TLS interception error). `requests` would have been the more common choice otherwise; if PyPI access is available in your build environment, that constraint no longer applies.

Every full cycle guarantees exactly one authenticated session per demo user (see "Demo use cases" above) — this guarantees `trouble`/`empty_basket`/`locked` all fire regularly rather than only by chance. Per user: login, a random number of random actions (browse the shop with occasional filters, view a product, add to basket, view the basket, or complete a checkout — weighted so basket/checkout activity is common without crowding out plain browsing), then logout. The `admin` account also occasionally visits the admin diagnostic pages. A failed login (the `locked` use case returns `403`, not a redirect) is a normal, tolerated outcome, not an error — logged and the generator moves on to the next session.

Two urllib gotchas hit while writing this, both now handled in `_do_request()`:
- `HTTPRedirectHandler.redirect_request` returning `None` (to deliberately *not* follow a 3xx, so the caller can inspect `Location` itself — e.g. to tell a successful login apart from a re-rendered form) does **not** suppress the exception the way the stdlib docs suggest — `urlopen` still raises `HTTPError` for the 3xx via the default error handler. Must be caught and converted into a normal response object.
- The app's own `403`/`404` responses raise the same way. `HTTPError` is itself a valid response-like object (`.code`, `.headers`, `.read()`), so the catch block reads through it rather than re-requesting.

`TRAFFIC_ENABLED=false` keeps the container up but idle — same pattern as `APMIA_DEPLOY` in `dx-o2-agents/entrypoint.sh`. Pacing (`TRAFFIC_MIN/MAX_ACTION_DELAY_SECS`, `TRAFFIC_MIN/MAX_SESSION_DELAY_SECS`) and `TRAFFIC_LOG_LEVEL` are configurable via `.config`; `TARGET_URL` is hardcoded to the Compose service name (`http://apachephp:8080`) in `docker-compose.yml`, not read from `.config`, matching the same hardcoded-service-name convention used for `APMIA_PHP_COLLECTOR_HOST`/`APMIA_BTL_HOST`.

Verified end to end against the real stack (not just a syntax check): built via `compose.sh build`, ran via `compose.sh up -d`, confirmed real traffic in Apache's own access log (correct status codes per action: `403` for the blocked `locked` login, `302` for successful logins/redirects, `200` for pages) and confirmed the `trouble` use case's 5000-sequential-DB-read slowdown is visible in the generator's own action timing.

**2026-07-08: anonymous traffic, concurrency, and pacing shaping added.** User reported response-time averages in DX O2 looking suspiciously flat, since the original generator ran exactly one session at a time, strictly sequentially — zero real request overlap, so there was never any genuine server-side contention to produce natural variance. Three changes, all in `generator.py`:
- **`TRAFFIC_ANONYMOUS_RATIO` (default `0.8`):** each cycle now builds a shuffled mix of exactly one authenticated session per demo user plus enough anonymous guest sessions (`run_guest_session()`, no login at all) to reach this ratio of the cycle's total — 14 users → 56 guest sessions → 70 total at the default 80/20 split. Guest sessions run the identical weighted action set, including checkout: `checkout.php`'s `order_create()` already accepts a null user id (guest checkout), so no app changes were needed. The one-authenticated-session-per-user guarantee above is unaffected — `trouble`/`empty_basket`/`locked` still fire every cycle regardless of this ratio.
- **`TRAFFIC_CONCURRENT_SESSIONS` (default `3`):** a small pool of worker threads (stdlib `threading` + `queue.Queue`, no new dependencies) now pulls from the cycle's shuffled session list and runs sessions in parallel instead of one at a time. This is the mechanism that actually produces response-time variance — genuinely overlapping requests create real contention (Apache workers, MariaDB connections), unlike client-side pacing changes alone. Verified live: Apache's own access log showed multiple distinct requests landing within the same second, and the generator's own logs showed one session's `logged in` / `session complete` pair straddling two other sessions' full start-to-finish lifecycle.
- **`TRAFFIC_SLOWDOWN_PROBABILITY`/`_MIN_SECS`/`_MAX_SECS` (defaults `0.12`/`3`/`12`):** `sleep_with_shaping()` layers an extra randomized delay on top of the normal per-action pacing this fraction of the time, widening the pacing distribution beyond a narrow uniform range and increasing the odds of concurrent workers' requests landing close together. This affects request *pacing/overlap*, not server-side compute time directly — the concurrency mechanism above is what's actually responsible for genuine response-time variance; this just makes that overlap happen more unevenly, more realistically. Verified the branch actually fires via a temporary `TRAFFIC_SLOWDOWN_PROBABILITY=0.9`/`LOG_LEVEL=DEBUG` run.

---

## Container image contents (both images)

Both `apache-php` and `dx-o2-agents` include these troubleshooting packages (Ubuntu 24.04):

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
| `/index.php?page=info` | `pages/info.php` | PHP version, SAPI, OS, memory limit, loaded extensions |
| `/index.php?page=db` | `pages/db.php` | Live PDO connection test, server version, uptime |
| `/index.php?page=dxo2` | `pages/dxo2.php` | Full DX O2 stack health check |

### `/index.php?page=dxo2` checks

- **PHP probe:** `extension_loaded('wily_php_agent')`; globs `$phpConfD/*-wily_php_agent.ini` (phpConfD built from `PHP_MAJOR_VERSION`/`PHP_MINOR_VERSION`); `realpath()` to resolve symlink to mods-available; displays key INI properties.
- **BPA module:** `shell_exec('apache2ctl -t -D DUMP_MODULES 2>&1')` → searches for `caplugin_module`. Falls back to `apache_get_modules()` if `shell_exec` is unavailable. Raw output shown verbatim.
- **Connectivity:** `fsockopen()` TCP probe of `APMIA_PHP_COLLECTOR_HOST:PORT` and `APMIA_BTL_HOST:PORT`.
- **Env vars:** all `APMIA_*` / `APMENV_*` in a table; credential-bearing keys redacted.
- **Log tails (three cards):** APMIA IA logs from `/opt/apmia/logs/*.log` (BTListener.log excluded); PHP probe logs from `/var/log/php-probe/*.log`; BTListener log from `/opt/apmia/logs/BTListener.log` (redirected there by the sidecar — see BTL log redirect below). No BPA module log card — the module has no documented log-file output.

When `/opt/apmia` is absent (`dxo2.enabled=false`) only the summary badges and a "not deployed" notice are shown — all detail cards are hidden. Deployment is detected via `is_dir('/opt/apmia')`.

---

## Helm chart

Chart: `helm/php-demo/` — version 0.2.0.

- ConfigMap holds `vhost.conf` mounted via `subPath`, sourced from `helm/php-demo/files/vhost.conf` — a symlink to `src/apache-php/config/vhost.conf`, the same file Docker Compose mounts directly and the Dockerfile bakes in. **Bug fixed 2026-07-09:** the ConfigMap template previously carried its own hand-copied literal block instead of reading the real file, and it had silently drifted out of sync — missing the no-cache headers, the health-check log suppression, and (found while investigating a report that the browser-agent per-page-wrapper fix "wasn't reflected in the Ingress/Traefik config" on a Kubernetes deployment — it was never an Ingress/Traefik issue at all, since the Ingress here is a plain host + `path: /` prefix rule with no rewrite annotations, so it passes every path through to Apache unchanged) the per-page-wrapper `RewriteRule` the browser agent injection depends on. Kubernetes deployments had been running without all three fixes since whenever the ConfigMap was first written; Docker Compose was never affected, since it mounts `src/apache-php/config/vhost.conf` directly with no duplicate copy to drift. Fixed by having `configmap.yaml` read the file via `{{ .Files.Get "files/vhost.conf" }}` instead of embedding a literal copy — confirmed via `helm lint`/`helm template` that Helm follows the symlink and includes the real file's current content (it prints an explicit `found symbolic link in path... Contents of linked file included and used` info line). Verified safe for this project's deployment model: `helm upgrade --install php-demo "${chart_dir}"` in `deploy.sh` runs directly against the local chart directory, not a packaged `.tgz`, so the symlink is never separated from its target.
- **`build-scripts/package-helm-bundle.sh`** produces a self-contained tarball (`helm/php-demo/` + `build-scripts/deploy.sh` + `.config.example` + a generated `README.txt`) for deploying via Helm from a separate host that doesn't have the full repo — e.g. a bastion host that pushed the images but isn't where `helm upgrade` runs, or vice versa. Stages into a temp dir with `cp -rL` (dereferences every symlink, not just `vhost.conf` specifically) before tarring, so the bundle is a fully self-contained tree with no dangling links to anything outside it — a plain `cp -r helm/` from the source repo would leave `files/vhost.conf` dangling, since its symlink target lives three levels above `helm/` (see the ConfigMap entry above); this is exactly the failure mode the nuc1 partial-copy incident hit doing this by hand. Asserts the copied `vhost.conf` is a real, non-empty file (not a symlink) before packaging, so a future regression fails loudly instead of shipping a broken bundle. Verified end to end: extracted the produced tarball standalone (no other repo files present) and confirmed `helm lint` passes clean with no symlink-related warnings, and that `deploy.sh`'s own `SCRIPT_DIR`-relative path resolution finds the chart correctly from the bundle's preserved sibling layout.
- `checksum/config` and `checksum/secret` annotations on the pod template force pod restart on config/secret change.
- `dxo2.emHost` is optional when using the DX O2 installer download (EM URL is pre-configured in the profile). Any non-empty string triggers `dxo2.enabled: true` in `deploy.sh`.
- `image.*.pullPolicy: Always` for custom images; `IfNotPresent` for `mariadb`.
- **Kubernetes probes** (`startupProbe`, `livenessProbe`, `readinessProbe`) all target `GET /health` — a static file (`app/src/health`) served by Apache without invoking PHP. This keeps probes independent of APMIA state: the PHP probe extension is not triggered, so the `dx-o2-agent` sidecar (PHP collector `127.0.0.1:5005`) does not need to be ready before probes pass. Access log entries for `/health` are suppressed via `SetEnvIf` in `vhost.conf`.
- **`dx-o2-agent` memory sizing:** The APMIA JVM + BTL consume ~757 MiB at idle (measured via `docker stats`). `requests.memory` is set to `792Mi` (idle baseline + buffer) and `limits.memory` to `4Gi` (headroom under APM load). Never set the limit below 512 Mi — the agent OOMKills before connecting to the backend.
- **Workload kind: StatefulSet, not Deployment** (`templates/statefulset.yaml`). Root cause: DX O2 was observed treating the app as a new/duplicate host each redeploy. The pod's `spec.hostname` was already pinned (fixed value from `dxo2.hostName`, not derived from the k8s pod name) before this change, but the k8s pod *name* itself still changed on every rollout under a Deployment (random ReplicaSet-hash suffix). StatefulSet gives a stable, predictable pod name (`<release>-0`) plus, via `spec.serviceName` pointing at a dedicated headless Service (`templates/service-headless.yaml`, `clusterIP: None`), a stable per-pod DNS name that survives pod recreation. **This does not pin the pod's IP address** — Kubernetes assigns that fresh from the cluster's CNI on every pod (re)creation regardless of workload kind; only `hostNetwork: true` (not used here — would drop network-policy isolation for this pod) or a CNI-specific static-IP annotation (not portable across clusters) can do that. `replicaCount` stays at `1`; no `volumeClaimTemplates` were introduced since the existing named MariaDB PVC (`pvc.yaml`) is referenced directly in `volumes:`, same as it was under the Deployment — that pattern doesn't require StatefulSet's per-ordinal PVC auto-provisioning at `replicaCount: 1`. First `helm upgrade` after this change deletes the old Deployment object and creates the new StatefulSet in its place (different `kind` = different resource identity to Kubernetes) — a one-time full pod recreation, same as any other redeploy.
- **Traffic generator: separate Deployment, anti-affined to a different node** (`templates/traffic-deployment.yaml`, gated by `trafficGenerator.enabled`, default `false` in `values.yaml` — `deploy.sh` always sets it `true` in the generated `values.local.yaml`, matching how `compose.sh` always includes the standalone `traffic` service). Deliberately a plain Deployment (`replicaCount` from `trafficGenerator.replicaCount`, default `1`), not a StatefulSet — it has no persistent identity or storage needs, unlike the main app. Reuses the existing ServiceAccount (`{{ include "php-demo.fullname" . }}`) for registry-pull access; no new RBAC. `TARGET_URL` is the in-cluster Service DNS name (`http://{{ include "php-demo.fullname" . }}:{{ .Values.service.port }}` — resolves within the same namespace without the fully-qualified `.svc.cluster.local` form). Container env vars map `trafficGenerator.env.*` Helm values onto the plain (unprefixed) names `generator.py` actually reads (`MIN_ACTION_DELAY_SECS`, `LOG_LEVEL`, etc.) plus the `TRAFFIC_`-prefixed ones it does (`TRAFFIC_ANONYMOUS_RATIO`, `TRAFFIC_CONCURRENT_SESSIONS`, `TRAFFIC_SLOWDOWN_*`) — same split `docker-compose.yml`'s `traffic:` service already uses; see the *Traffic generator* section above for the definitive env var list.
  - **Not in the same pod as the app** — its own Deployment, container, and pod identity, entirely separate from the app's StatefulSet.
  - **Different node than the app, via `podAntiAffinity`** (`trafficGenerator.antiAffinity`): targets the main app pod's `app.kubernetes.io/component: app` label (added to the StatefulSet's pod template specifically for this — see below) with `topologyKey: kubernetes.io/hostname`. `antiAffinity.required` (default `true`) selects `requiredDuringSchedulingIgnoredDuringExecution` (hard constraint — the traffic-generator pod stays `Pending` rather than ever landing on the app's node); set to `false` for `preferredDuringSchedulingIgnoredDuringExecution` (soft/best-effort) on single-node clusters (kind, minikube, a demo VM), where a hard constraint would make the pod permanently unschedulable.
  - **Label-selector landmine — caught the Deployment/anti-affinity case, missed the Service case, verified live.** Kubernetes `matchLabels` is subset/superset matching, not exact-equality — a selector on just `app.kubernetes.io/name` + `app.kubernetes.io/instance` (the chart's common `php-demo.labels`/`selectorLabels` helpers) also matches any *other* workload sharing those two labels. Applied the fix (an explicit `app.kubernetes.io/component` label: `app` on the StatefulSet's pod template, `traffic-generator` on the new Deployment's pods and its own `spec.selector.matchLabels`) to the traffic-generator Deployment's own selector and its anti-affinity `labelSelector` — but initially missed that **`templates/service.yaml` and `templates/service-headless.yaml` have the exact same selector, unfixed**. **Bug fixed 2026-07-09, found live:** first production deploy on a real 2-node k3s cluster returned intermittent `502 Bad Gateway` from Traefik. `kubectl get endpoints php-demo-php-demo` showed **two** endpoints — the real app pod *and* the traffic-generator pod — because the main ClusterIP Service's selector matched both (same landmine, third occurrence: Deployment selector, anti-affinity selector, and now Service selector are three independent `matchLabels` blocks that all needed the same fix, not one). Requests round-robin between them at the kube-proxy/Service level; roughly half landed on the traffic-generator pod, which listens on nothing at port 8080 (it's an outbound-only Python script), so `connection refused` surfaced through Traefik as 502. Fixed by adding `app.kubernetes.io/component: app` to both Services' selectors. **Lesson: when adding a distinguishing label to solve one selector's subset-matching problem, grep the whole chart for every other `{{ include "php-demo.selectorLabels" . }}` use and ask whether each one also needs the new label** — it's not a one-shot fix scoped to whichever manifest prompted the change.
  - `image.trafficGenerator.{repository,tag,pullPolicy}` mirrors the `apachephp`/`dxo2` image blocks; `deploy.sh` derives `repository`/`tag` from `.config`'s `REGISTRY`/`IMAGE_PREFIX`/`IMAGE_TAG` the same way it does for the other two images.

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

# DX O2 – deployment identity (see "Deployment identity" section below)
DEPLOYMENT_NAME          # default "bpa-demo" – logical application name
DEPLOYMENT_POSTFIX       # default "docker" (compose.sh) / "k8s" (deploy.sh) –
                         # combines as "<name>-<postfix>" into the shared
                         # default for every APMIA_* identity var below

# DX O2 – identity (exposed as APMENV_* to dx-o2-agent container)
# Each defaults to "${DEPLOYMENT_NAME}-${DEPLOYMENT_POSTFIX}" when left
# empty; set any one explicitly to override just that agent.
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
- **Static per-service IPs** on a dedicated `bpa-demo` bridge network (`172.28.0.0/24`; `dxo2`=`.10`, `mariadb`=`.11`, `apachephp`=`.12`, `traffic`=`.13`). Without a user-defined network, Compose places every service on the project's auto-created default bridge, whose subnet Docker picks fresh at network-creation time — this can shift across a `compose.sh down` + `up` cycle (new network = new IPAM choice), and DX O2 was observed treating this as a distinct host each time. Pinning both the network's subnet and each service's `ipv4_address` makes every address deterministic regardless of Docker's IPAM. Verified: IPs identical before and after a full `down`/`up` cycle; service-name DNS resolution (`mariadb`, `dxo2`) and app health both confirmed working unchanged.
- **`apmia_data` named volume only ever seeds once — rebuilding `dx-o2-agents` alone is not enough to pick up new contents.** Docker's named-volume behaviour: when a volume is mounted read-write over a directory that has content baked into the image (`/opt/apmia` here), Docker copies the image's content into the volume only the *first* time that volume is created — every subsequent container start (including `compose.sh up -d` after rebuilding the `dx-o2-agents` image) reuses whatever is already in the volume and ignores the new image's `/opt/apmia` entirely. Caught live during the 2026-08-19 PHP 8.1→8.3 upgrade: rebuilding `dx-o2-agents` with a corrected `wily_php_agent.so` selection (see "PHP probe injection" below) produced a verified-correct image, but the running `apachephp` container kept injecting the *old* `.so` from the stale `apmia_data` volume — confirmed via `sha256sum` mismatch between the volume's copy and the freshly built image's copy. Any change to `dx-o2-agents`' baked-in `/opt/apmia` contents (probe binaries, BTL, BPA module, profile) requires `compose.sh down -v` (or `docker volume rm <project>_apmia_data`) before the next `up`, not just a rebuild — a plain rebuild + restart silently keeps serving the old volume contents with no error of any kind.

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
| DX O2 manual (console-only) configuration steps | `DX-O2_MANUAL_CONFIGURATION.md` |
| Version compatibility matrix | `COMPATIBILITY.md` |
