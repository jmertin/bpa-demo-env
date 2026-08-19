# Broadcom DX O2 Agent Setup Guide

This guide covers every step required to obtain, build, and verify the
Broadcom DX O2 monitoring components used in BPA-Demo.

| Component | Installer package | Runtime location |
|---|---|---|
| PHP Agent (Infrastructure Agent core + PHP Probe + JRE) | `PHP_apmia_*.tar` | `/opt/apmia/` in `dx-o2-agents` image (base install) |
| PHP Probe | `PHP_apmia_*.tar` (bundled) | `/opt/apmia/extensions/PHPAgent/` |
| Infrastructure Agent + MySQL Monitor extension | `Infrastructure_Agent_apmia_*.tar` | Only the bundled `mysql-*.tar.gz` is used, staged at `/opt/apmia/extensions/deploy/` |
| Business Transaction Listener (BTL) | `Business_Transaction_Listener.zip` | `/opt/btlistener/` in `dx-o2-agents` image |
| BPA WebServer Plugin (Apache) | `Business_Payload_Analyzer_WebServer_Plugins.zip` | `/opt/apmia/extensions/WebServerPlugin/mod_*.so` |

Four packages, from two different console locations, all downloaded from the
**DX O2 interface** (not from support.broadcom.com):

- **PHP Agent** and **Infrastructure Agent + MySQL Monitor extension** are two
  separate file selections on the same **Agents → Infrastructure Agent →
  Linux** page — despite both being full APMIA installer trees, only the
  first (`PHP_apmia_*.tar`) is used as this image's base install (it's the
  one bundling the PHP probe); the second (`Infrastructure_Agent_apmia_*.tar`)
  is used only to extract its `mysql-*.tar.gz` DB Monitor extension.
- **BTL** and the **BPA WebServer Plugin** are downloaded together from
  **Settings → Web Payload Capture Rules (Webserver) → Download** (the button
  in the top-right corner) — not from an "Agents" page.

Every DX O2 download includes a pre-configured `IntroscopeAgent.profile` with
your tenant's EM URL and JWT credential already embedded — the agent connects
to your DX O2 backend automatically without any manual EM configuration.

---

## 1. Compatibility matrix

| Runtime | Project version | APMIA requirement | Status |
|---|---|---|---|
| PHP | 8.3 (ubuntu:24.04) | PHP Probe ≤ 8.4 | ✓ within ceiling |
| Apache | 2.4.x (ubuntu:24.04) | BPA Apache module (mod_*.so) | ✓ supported |
| glibc | 2.39 (ubuntu:24.04 Noble) | Infrastructure Agent ≥ 2.17 | ✓ satisfied |
| JRE | Bundled in `PHP_apmia*.tar` | BTL requires JRE 11+ | ✓ bundled JRE used |
| OS architecture | linux/amd64 | x86_64 Linux | ✓ matches `BUILD_PLATFORM` |

If targeting `linux/arm64` (Apple Silicon, AWS Graviton), download the
`aarch64` variant and update `BUILD_PLATFORM=linux/arm64` in `.config`.

---

## 2. Obtaining the packages

### 2.1 Navigate to the DX O2 download areas

Two different console locations are involved:

1. Log in to your **DX O2 interface** (the SaaS portal, e.g.
   `https://dx.dxi-eu1.saas.broadcom.com/` for the EU1 region).
2. **Agents → Infrastructure Agent → Linux** — offers (at least) two separate
   file selections: the **PHP Agent** variant (`PHP_apmia_*.tar`, used as this
   image's base install) and a second, plain **Infrastructure Agent** variant
   (`Infrastructure_Agent_apmia_*.tar`, used here only for its bundled MySQL
   Monitor extension). Download both.
3. **Settings → Web Payload Capture Rules (Webserver) → Download** (the
   button in the top-right corner) — downloads the Business Transaction
   Listener and BPA WebServer Plugin together.

### 2.2 Download the four packages

| Package | DX O2 navigation | File name pattern |
|---|---|---|
| PHP Agent (base install + PHP Probe) | Agents → Infrastructure Agent → Linux | `PHP_apmia_<date>_v<n>.tar` |
| Infrastructure Agent (for its MySQL Monitor extension) | Agents → Infrastructure Agent → Linux (second file) | `Infrastructure_Agent_apmia_<date>_v<n>.tar` |
| Business Transaction Listener | Settings → Web Payload Capture Rules (Webserver) → Download | `Business_Transaction_Listener.zip` |
| BPA WebServer Plugin | Settings → Web Payload Capture Rules (Webserver) → Download | `Business_Payload_Analyzer_WebServer_Plugins.zip` |

Of these four, `PHP_apmia_*.tar` and `Business_Transaction_Listener.zip` are
**required** — the Dockerfile build fails without either. The other two are
**optional**: `Business_Payload_Analyzer_WebServer_Plugins.zip` is skipped
gracefully (BPA instrumentation just won't be available), and
`Infrastructure_Agent_apmia_*.tar` is skipped gracefully (no DB Monitor
metrics until it's added and the image rebuilt — see §7.4).

> **Why from the DX O2 interface and not support.broadcom.com?**
> Packages downloaded from the DX O2 interface include a pre-configured
> `IntroscopeAgent.profile` with your tenant's WSS EM URL and JWT credential
> already baked in.  The agent connects without any manual EM host configuration.
> Packages from the Broadcom Support Portal use a different archive layout, do
> not include a pre-configured profile, and will cause the build to fail.

### 2.3 Verify the downloads

```bash
# Should list many files ending in .jar, .sh, .so, etc.
tar -tf PHP_apmia_*.tar | head -20

# Must show: apmia/core/config/IntroscopeAgent.profile
tar -tf PHP_apmia_*.tar | grep IntroscopeAgent.profile

# Must show: apmia/extensions/deploy/mysql-*.tar.gz
tar -tf Infrastructure_Agent_apmia_*.tar | grep 'extensions/deploy/mysql'

unzip -l Business_Transaction_Listener.zip | tail -5
unzip -l Business_Payload_Analyzer_WebServer_Plugins.zip | tail -5
```

---

## 3. Placing the packages

```bash
# From the project root
cp ~/Downloads/PHP_apmia_*.tar \
   src/dx-o2-agents/installers/
cp ~/Downloads/Infrastructure_Agent_apmia_*.tar \
   src/dx-o2-agents/installers/
cp ~/Downloads/Business_Transaction_Listener.zip \
   src/dx-o2-agents/installers/
cp ~/Downloads/Business_Payload_Analyzer_WebServer_Plugins.zip \
   src/dx-o2-agents/installers/

# Verify placement
ls -lh src/dx-o2-agents/installers/
# should show exactly four files (Infrastructure_Agent_apmia*.tar and
# Business_Payload_Analyzer_WebServer_Plugins.zip are optional -- see §2.2 --
# but both are recommended for full DB Monitor + BPA coverage)
```

The `installers/` directory is gitignored — the archives are never committed.
Only one copy of each archive may be present at a time.  Remove older versions
before adding new ones.

---

## 4. What the Dockerfile extracts

`build.sh` builds the `dx-o2-agents` image.  The Dockerfile extracts all
present archives in sequence — `PHP_apmia*.tar` and
`Business_Transaction_Listener.zip` are required (the build fails without
either); `Infrastructure_Agent_apmia*.tar` and
`Business_Payload_Analyzer_WebServer_Plugins.zip` are optional and skipped
gracefully if absent.

### 4.1 `/opt/apmia/` (from `PHP_apmia*.tar`)

```
/opt/apmia/
├── bin/APMIAgent.sh               ← IA start script (Java Service Wrapper)
├── APMIACtrl.sh                   ← Agent control script
├── jre/                           ← Bundled JRE (set as JAVA_HOME at runtime)
├── core/config/
│   └── IntroscopeAgent.profile    ← Pre-configured: tenant EM URL (WSS) + JWT
│                                     NEVER overwrite — identity set via APMENV_*
├── extensions/PHPAgent/
│   ├── wily_php_agent.so          ← PHP 8.3 probe extension (normalised by Dockerfile)
│   └── wily_php_agent.ini         ← PHP INI snippet (normalised by Dockerfile)
├── extensions/WebServerPlugin/
│   ├── mod_<name>.so              ← Apache BPA module (from BPA zip, if present)
│   └── ngx_http_ca_plugin_filter_module_<ver>.so  ← nginx variants (also extracted)
└── logs/                          ← Runtime log directory
```

> The `apache-php` entrypoint searches for `mod_*.so` for the Apache module and
> uses the filename to derive the `LoadModule` module name:
> `mod_<name>.so → <name>_module`.

### 4.2 `/opt/btlistener/` (from `Business_Transaction_Listener.zip`)

```
/opt/btlistener/
├── bin/BTListener.sh              ← BTL start script
└── conf/custom/
    └── application.properties    ← Pre-configured: DXC URL, tenantId, port 8000
```

### 4.3 PHP Probe normalisation step

The `PHP_apmia*.tar` archive places probe files at `probe/lib/php83/`.
The Dockerfile copies them to `extensions/PHPAgent/` so the `apache-php`
entrypoint always finds them at the same path regardless of APMIA release generation.

### 4.4 MySQL Monitor extension (from `Infrastructure_Agent_apmia*.tar`, optional)

The Dockerfile does **not** extract this archive's full tree — only its
bundled `apmia/extensions/deploy/mysql-*.tar.gz` is pulled out and staged at
`/opt/apmia/extensions/deploy/mysql-*.tar.gz`, layered on top of the
`PHP_apmia`-based install above. The APMIA auto-deploys anything in
`extensions/deploy/` at container startup. See §7.4 for full configuration
(credentials, schema version, the automatic MariaDB monitor-user setup).

---

## 5. Building the dx-o2-agents image

```bash
build-scripts/build.sh
```

`build.sh` detects the `PHP_apmia*.tar` archive to decide whether to attempt
the `dx-o2-agents` image at all. Within the Dockerfile itself, `PHP_apmia*.tar`
and `Business_Transaction_Listener.zip` are hard requirements — the build
fails with a clear banner identifying which is missing.
`Infrastructure_Agent_apmia*.tar` and
`Business_Payload_Analyzer_WebServer_Plugins.zip` are optional: their build
steps print a warning and continue (`exit 0`) when absent, so a build with
only the two required archives still succeeds — just without DB Monitor
metrics or BPA instrumentation until the optional archives are added.

---

## 6. Runtime injection — how each component is loaded

### 6.1 Infrastructure Agent + BTL (`dx-o2-agent` sidecar)

`src/dx-o2-agents/entrypoint.sh` runs inside the sidecar:

```
1. Sets JAVA_HOME to the bundled JRE (/opt/apmia/jre/).
2. Promotes APMIA_* fallback vars to APMENV_* if not already set:
     APMENV_INTROSCOPE_AGENT_AGENTNAME
     APMENV_INTROSCOPE_AGENT_APPLICATION_NAME
     APMENV_INTROSCOPE_AGENT_HOSTNAME
     APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME
3. Checks APMIA_DEPLOY:
     false → exec sleep infinity (passive volume mode; IA not started)
     true  → continue
4. Verifies pre-configured profile exists at
   /opt/apmia/core/config/IntroscopeAgent.profile
   (fatal error if missing — wrong installer format).
5. Starts APMIAgent.sh in 'console' mode (foreground).
6. Starts BTListener.sh in the background (if the script is present).
7. Sets SIGTERM/SIGINT trap → graceful shutdown of both processes.
8. wait $AGENT_PID — keeps the container alive for the pod's lifetime.
```

> The `IntroscopeAgent.profile` is NEVER patched.  All identity configuration
> is applied by the APMIA agent itself when it reads the `APMENV_*` vars.

### 6.2 PHP Probe (`apache-php` container startup)

`src/apache-php/entrypoint.sh` runs at startup.  The emptyDir volume at
`/opt/apmia` (populated by `dxo2-init`) is the source:

```
Check: /opt/apmia/extensions/PHPAgent/wily_php_agent.ini exists?
  YES →
    Copy wily_php_agent.so  →  $(php8.3 -r 'echo ini_get("extension_dir");')/
    Copy wily_php_agent.ini →  /etc/php/8.3/mods-available/wily_php_agent.ini
    Symlink                 →  /etc/php/8.3/apache2/conf.d/99-wily_php_agent.ini
    Patch wily_php_agent.ini:
      wily_php_agent.collectorHost    = ${APMIA_PHP_COLLECTOR_HOST}  (default: 127.0.0.1)
      wily_php_agent.collectorPort    = ${APMIA_PHP_COLLECTOR_PORT}  (default: 5005)
      wily_php_agent.application.name = ${APMIA_APP_NAME}
      wily_php_agent.logdir           = /var/log/php-probe
      wily_php_agent.logLevel         = <0-5>  (mapped from APMIA_PHP_LOG_LEVEL; default INFO→2)
      wily_php_agent.agentName        = ${APMIA_PHP_AGENT_NAME}  (default: bpa-demo-php-probe)
      wily_php_agent.hostname         = ${APMIA_PHP_AGENT_NAME}  (overrides OS gethostname())
    Browser agent (if APMIA_BROWSER_SNIPPET is set):
      wily_php_agent.enable.browseragent.response.decoration      = 1   ← master switch
      wily_php_agent.enable.browseragent.snippet.autoInjection    = 1
      wily_php_agent.browseragent.autoInjection.snippetString     = '<value>'
    Browser agent (if APMIA_BROWSER_SNIPPET is empty):
      wily_php_agent.enable.browseragent.response.decoration      = 0
      wily_php_agent.enable.browseragent.snippet.autoInjection    = 0
      remove wily_php_agent.browseragent.autoInjection.snippetString
    Always:
      remove wily_php_agent.browseragent.autoInjection.enabled (legacy property)
      wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength = 30000
    → PHP probe active.
  NO →
    Log "DX O2 agent volume not mounted" and continue without probe.
```

**IPC note:** PHP probe → IA collector uses port 5005.  In Kubernetes (same pod)
this is `127.0.0.1`.  In Compose the host is the `dxo2` service name.

### 6.3 BPA WebServer Plugin (`apache-php` container startup)

```
Check: any mod_*.so in /opt/apmia/extensions/WebServerPlugin/?
  YES →
    Derive module name: mod_<name>.so → <name>_module
    Write /etc/apache2/conf-available/bpa.conf:
      LoadModule <name>_module <path>
      SetEnv APMIA_WEB_AGENT_NAME <APMIA_WEB_AGENT_NAME>
      TcpClientHostAndPort <APMIA_BTL_HOST>:<APMIA_BTL_PORT>
      TcpClientWaitTimeForReconnectInSecs 30
    Symlink → /etc/apache2/conf-enabled/bpa.conf
    Run: apache2ctl configtest
      PASS → BPA module active.
      FAIL → remove bpa.conf; start Apache without BPA instrumentation.
  NO →
    Remove stale /etc/apache2/conf-enabled/bpa.conf (if any).
    Log "No BPA Apache module found" and continue.
```

### 6.4 Kubernetes init-container flow (complete sequence)

```
Pod startup
  │
  ├─ initContainer: dxo2-init
  │    Image: dx-o2-agents
  │    Command: cp -a /opt/apmia/. /apmia-share/
  │    VolumeMount: apmia-share → /apmia-share  (readWrite)
  │    → Exits 0; emptyDir now contains full agent tree.
  │
  ├─ initContainer: mariadb-lock-cleanup  (removes stale DB lock files)
  │
  └─ Containers start (in parallel after all initContainers exit 0):
       │
       ├─ dx-o2-agent sidecar
       │    JAVA_HOME=/opt/apmia/jre
       │    APMENV_* identity vars from Helm values
       │    Runs: APMIAgent.sh console → connects to pre-configured EM (WSS)
       │    Runs: BTListener.sh → listens on 127.0.0.1:8000
       │    Tails: IntroscopeAgent.log → stdout  (kubectl logs / compose logs)
       │    Tails: BTListener.log    → stdout  (kubectl logs / compose logs)
       │    Named ports: php-collector:5005, btl:8000
       │
       ├─ apache-php
       │    VolumeMount: apmia-share → /opt/apmia  (readOnly)
       │    Entrypoint: PHP probe → INI patching → Apache starts
       │    Entrypoint: BPA Apache module → LoadModule → apache2ctl configtest
       │    hostname = dxo2.hostName (set at pod spec level)
       │    Probes: startupProbe / livenessProbe / readinessProbe → GET /health
       │            /health is a static file – PHP is NOT invoked, so the
       │            APMIA PHP probe extension never fires during health checks.
       │            Probes succeed independently of dx-o2-agent startup timing.
       │
       └─ mariadb  (no agent involvement)
```

---

## 7. Configuring the deployment

### 7.1 DX O2 interface download (pre-configured — minimal setup)

When using packages downloaded from the DX O2 interface, the EM URL and
credential are already embedded in `IntroscopeAgent.profile`.  Configure
only identity fields in `.config`:

```bash
# Deployment identity – combines as "<name>-<postfix>" into the shared
# default for every APMIA agent below (Infrastructure Agent, PHP probe, BPA
# WebServer plugin), so a Kubernetes deployment never collides on identity
# with a Docker Compose deployment reporting to the same DX O2 tenant.
# Leave DEPLOYMENT_POSTFIX empty to accept deploy.sh's own default ("k8s");
# compose.sh defaults to "docker" instead. See CLAUDE.md's "Deployment
# identity" section for the full explanation (this was found live: running
# both deployments with identical hardcoded identities caused DX O2 to
# silently suffix the second connection with "%1" and break every
# dashboard/alert query written against the plain name).
DEPLOYMENT_NAME="bpa-demo"
DEPLOYMENT_POSTFIX=""

# Agent identity – displayed in the DX O2 console (APMENV_* vars). Leave
# empty (as below) to use the DEPLOYMENT_NAME-DEPLOYMENT_POSTFIX default
# above (e.g. "bpa-demo-k8s"); set any one explicitly to override just that
# agent's identity.
APMIA_AGENT_NAME=""
APMIA_APP_NAME=""
APMIA_HOST_NAME=""
APMIA_PROCESS_NAME=""
APMIA_PHP_AGENT_NAME=""
APMIA_WEB_AGENT_NAME=""
APMIA_LOG_LEVEL="INFO"

# Set to any non-empty value to trigger dxo2.enabled=true in deploy.sh.
# The EM connection itself comes from the pre-configured profile.
APMIA_EM_HOST="placeholder"
```

### 7.2 APMENV_* mapping

`deploy.sh` sets these environment variables on the `dx-o2-agent` sidecar.
The APMIA agent reads them at startup and overrides the profile without patching:

| .config variable | APMENV_* variable on the container |
|---|---|
| `APMIA_AGENT_NAME` | `APMENV_INTROSCOPE_AGENT_AGENTNAME` |
| `APMIA_APP_NAME` | `APMENV_INTROSCOPE_AGENT_APPLICATION_NAME` |
| `APMIA_HOST_NAME` | `APMENV_INTROSCOPE_AGENT_HOSTNAME` |
| `APMIA_PROCESS_NAME` | `APMENV_INTROSCOPE_AGENT_CUSTOMPROCESSNAME` |
| `APMIA_LOG_LEVEL` | `APMENV_LOG4J_LOGGER_INTROSCOPEAGENT` (e.g. `"INFO, logfile"`) |

### 7.3 Same-pod IPC addresses

All containers in the BPA-Demo pod share `127.0.0.1` (Kubernetes pod network):

| Variable | Default | Purpose |
|---|---|---|
| `APMIA_PHP_COLLECTOR_HOST` | `127.0.0.1` | PHP probe → IA PHP collector |
| `APMIA_PHP_COLLECTOR_PORT` | `5005` | IA PHP collector port |
| `APMIA_BTL_HOST` | `127.0.0.1` | BPA Apache module → BTL |
| `APMIA_BTL_PORT` | `8000` | BTL listener port |

In Docker Compose the hosts are hardcoded to the `dxo2` service name in
`docker-compose.yml` (not read from `.config`).

### 7.4 DB Monitor (MariaDB)

The APMIA DB Monitor extension for MySQL/MariaDB ships in a **separate,
optional archive** (`Infrastructure_Agent_apmia_*.tar`) that must be
downloaded and placed alongside the other installer archives before building.
Without it, the image builds fine but has no DB Monitor metrics.

**Step 1 — Download the Infrastructure archive:**

```
DX O2 interface -> Agents -> Infrastructure Agent -> Linux
File: Infrastructure_Agent_apmia_<date>_v<n>.tar
Place in: src/dx-o2-agents/installers/
```

This is a different file selection on the same page as `PHP_apmia_*.tar` (see
§2.1) — despite both being full APMIA installer trees, only its bundled
`mysql-*.tar.gz` extension is actually used (see §4.4); `PHP_apmia_*.tar`
remains the base install either way.

**Step 2 — Rebuild the `dx-o2-agents` image:**

```bash
build-scripts/build.sh
```

The Dockerfile extracts `apmia/extensions/deploy/mysql-*.tar.gz` from the
Infrastructure archive and stages it in `/opt/apmia/extensions/deploy/`.  The
APMIA auto-deploys this extension (extracts it into `extensions/mysql-*/`) at
container startup.

**Step 3 — Configure credentials in `.config`:**

```bash
MYSQL_MONITOR="true"                  # true (default) = enable; false = disable
MARIADB_USER="phpuser"                # used for DB Monitor connection
MARIADB_PASSWORD="..."                # used for DB Monitor connection
MARIADB_ROOT_PASSWORD="..."           # used by the entrypoint to verify/create the login below
```

`docker-compose.yml` passes these as
`APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_PROFILES_BPADB_USERNAME/PASSWORD`.
The `dx-o2-agents` entrypoint (`_db_monitor_setup`) patches `bundle.properties`
inside the staged extension archive at container startup, so the APMIA always
connects with the current `.config` credentials.

In Kubernetes, credentials (including `MARIADB_ROOT_PASSWORD`) are injected via
`secretKeyRef` from the mariadb Secret — they are never in plain-text values
files.

**The entrypoint also handles two MariaDB-specific gotchas automatically —
no further configuration is needed, but it's useful to know what's happening:**

1. **Login verification/creation (`_ensure_monitor_user`).** The extension
   authenticates as `MARIADB_USER`; if that login doesn't exist in MariaDB,
   connections fail silently and no metrics are gathered. Before patching
   `bundle.properties`, the entrypoint connects to MariaDB as root (waits up
   to 60s for the server), checks `mysql.user`, and runs `CREATE USER IF NOT
   EXISTS` plus `GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.*` —
   **every start**, whether the login is new or pre-existing. This matters
   because `MARIADB_USER` is commonly the same account MariaDB's own
   bootstrapping already created, scoped only to its own database; without
   the grant the extension fails with `SELECT command denied ... for table
   performance_schema.global_variables`.
2. **Schema version (`version=5_6x`).** Even with correct grants, the
   extension's default query set targets MySQL 5.7+ and queries
   `performance_schema.global_variables`/`global_status`, tables MariaDB
   does not implement (`ERROR 1146: Table 'performance_schema.global_variables'
   doesn't exist`). `docker-compose.yml` and the Helm chart
   (`dxo2.dbMonitor.schemaVersion`, default `5_6x`) both set
   `APMENV_..._VERSION=5_6x`, which selects the extension's alternate
   `information_schema`-based query set. Despite the "5_6x" (MySQL 5.6.x)
   name, this is the correct setting for MariaDB, not a version match.

**Verify DB Monitor is active:**

```bash
# Look for the extension in the deployed extensions directory
docker exec <dxo2-container> ls /opt/apmia/extensions/ | grep mysql

# Check entrypoint log for the DB Monitor lines
docker compose logs dxo2 | grep 'DB Monitor'
# expected:
#   [entrypoint] DB Monitor: login 'phpuser' has monitoring grants (SELECT, PROCESS, REPLICATION CLIENT).
#   [entrypoint] DB Monitor: enabled (profile=bpadb, host=mariadb:3306, ...)

# Confirm no DBMonitor errors are being logged
docker compose logs dxo2 | grep -c '\[ERROR\] \[IntroscopeAgent.DBMonitor\]'
# expected: 0

# After a few minutes, metrics should appear in DX O2 under:
# MySQL Databases | mariadb | phpapp | ...
```

If `MYSQL_MONITOR=false`, the entrypoint removes the extension from `deploy/`
and deletes the deployed directory so the APMIA never loads it.

### 7.5 Browser agent auto-injection

Set `APMIA_BROWSER_SNIPPET` in `.config` to the `<script>` tag from your DX O2
tenant (DX O2 Settings → Manage Mobile/Browser Web Monitoring → App to Monitor → Web App).  Enclose it in single quotes
because the value contains double-quotes:

```bash
APMIA_BROWSER_SNIPPET='<script type="text/javascript" id="ca_eum_ba" src="..."></script>'
```

The `apache-php` entrypoint writes to `wily_php_agent.ini`:

```ini
wily_php_agent.enable.browseragent.response.decoration=1
wily_php_agent.enable.browseragent.snippet.autoInjection=1
wily_php_agent.browseragent.autoInjection.snippetString='<script ...>'
wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength=30000
```

`response.decoration=1` is the master switch that activates the browser agent
module inside the PHP probe.  It mirrors `-enableBrowserAgentSupport` in the
official installer.  Without it, `snippet.autoInjection=1` is silently ignored
by the probe even if the snippet string is correctly configured.

Leave `APMIA_BROWSER_SNIPPET` empty to disable.  The entrypoint sets
`response.decoration=0`, `autoInjection=0`, and removes any pre-configured
snippet so installer defaults cannot override your `.config` setting.

**`maxSearchingLength` — why 30000:**
The probe scans the beginning of each HTTP response looking for a `<head>` or
`<body>` tag to inject the browser-agent `<script>` after.  All application CSS
is served as a separate static file (`/css/app.css`) so the `<head>` block
contains only meta tags — `</head>` appears at byte **239** and `<body>` at
byte **247** in every response.  30 000 bytes is the probe's documented maximum
(valid range 100–30 000) and gives ~125× headroom over the actual scan
requirement.  The property name is
`wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength`
(note `.autoInjection.` between `.browseragent.` and `.snippet.`).

**Why BA injection doesn't work against a plain front-controller — not currently worked around.**
The PHP probe has two independent gates that must both pass before it injects:

*Gate 1 — Frontend start detection:* the probe hooks PHP's opcode executor.
When the very first opcode of the entry script is a non-include opcode, it
emits `Frontend start: /shop.php` and proceeds to injection.  When the first
opcode is an include (op 61/62/136 — `require`/`include`), the probe enters
include-tracking mode and never establishes `Frontend start` — BA injection is
silently skipped for that entire request.  BPA-Demo's `index.php` opens with
several `require_once` calls, so this gate always fails.

*Gate 2 — SCRIPT_NAME segment:* the probe reads `SCRIPT_NAME` (not
`REQUEST_URI`) and treats `index.php` and bare `/` as null segments, skipping
injection.  Changing `REQUEST_URI` via mod_rewrite is not sufficient; `SCRIPT_NAME`
must also change — and every request in this app resolves to `SCRIPT_NAME=/index.php`.

A per-page-wrapper-file workaround (routing Apache requests to `app/src/shop.php`,
`basket.php`, etc. instead of directly to `index.php`, each running one non-include
opcode before `require`-ing `index.php`) previously satisfied both gates. It was
reverted at the user's request on 2026-08-19 — see `bug_php_probe.md` for the
full diagnosis, `CLAUDE.md`'s "PHP probe injection" section for what changed,
and the "Recommended Probe Changes (Vendor)" section of `bug_php_probe.md` for
the vendor-facing fix request this bug should really be resolved by.

**Browser-agent auto-injection does not currently function in this app** as a
result — this is the original, unmodified probe behavior against a standard
front-controller pattern, not a regression.

---

## 8. Verifying agent activity

### 8.1 Check container logs

The `dx-o2-agent` entrypoint tails `IntroscopeAgent.log` and
`BTListener.log` to stdout, so both appear in `kubectl logs` and
`docker compose logs` without needing shell access to the container.

```bash
# dx-o2-agent sidecar — entrypoint startup, IA log, and BTL log
kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent

# Filter to entrypoint messages only (excludes IA / BTL log content)
kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent | grep '^\[entrypoint\]'

# Follow live (streams IA + BTL log lines as they are written)
kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent -f

# Docker Compose equivalent
docker compose logs -f dxo2

# apache-php — verify PHP probe and BPA Apache module injection
kubectl logs -n <APP_NAMESPACE> <pod> -c apache-php | grep -E "\[entrypoint\]"
```

Expected `apache-php` log output:

```
[entrypoint] Injecting DX O2 PHP probe from /opt/apmia/extensions/PHPAgent
[entrypoint]   Copied wily_php_agent.so → /usr/lib/php/20210902/
[entrypoint]   Probe INI installed at /etc/php/8.3/apache2/conf.d/99-wily_php_agent.ini
[entrypoint]   PHP probe IPC: 127.0.0.1:5005
[entrypoint]   PHP probe agent : bpa-demo-php-probe
[entrypoint]   PHP probe host  : bpa-demo-php-probe
[entrypoint]   Browser agent : disabled (APMIA_BROWSER_SNIPPET not set)
[entrypoint] DX O2 PHP probe active – APM instrumentation enabled.
[entrypoint] Injecting BPA WebServer Plugin (Apache): mod_<name>.so
[entrypoint]   Module name : <name>_module
[entrypoint]   BPA → BTL   : 127.0.0.1:8000
[entrypoint] BPA WebServer Plugin active – BPA instrumentation enabled.
```

### 8.2 Check the PHP extension is loaded

```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  php8.3 -r 'var_dump(extension_loaded("wily_php_agent"));'
# expected: bool(true)

kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  php8.3 -m | grep wily
# expected: wily_php_agent
```

### 8.3 Check the Apache BPA module is loaded

```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  cat /etc/apache2/conf-enabled/bpa.conf
# expected: LoadModule <name>_module /opt/apmia/extensions/WebServerPlugin/mod_<name>.so

kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  apache2ctl -M 2>/dev/null | grep -i ca_
# expected: <name>_module (shared)
```

### 8.4 Inspect the wily_php_agent.ini at runtime

```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  cat /etc/php/8.3/mods-available/wily_php_agent.ini
```

Verify:
- `wily_php_agent.collectorHost` and `collectorPort` are correct.
- `wily_php_agent.agentName` matches `APMIA_PHP_AGENT_NAME`.
- `wily_php_agent.hostname` matches `APMIA_PHP_AGENT_NAME`.
- `wily_php_agent.enable.browseragent.autoInjection.snippet.maxSearchingLength` is `30000`.
- `wily_php_agent.enable.browseragent.response.decoration` is `1` or `0` as configured.
- `wily_php_agent.enable.browseragent.snippet.autoInjection` is `1` or `0`
  as configured (must match `response.decoration`).

### 8.5 Verify no-cache HTTP headers

All responses must carry `Cache-Control: no-store` so APM sees genuine latency
on every request:

```bash
# From inside the cluster (port-forward or via the Ingress URL)
curl -sI http://localhost:8080/ | grep -iE "cache-control|pragma|expires|etag|last-modified"
# expected:
#   Cache-Control: no-store, no-cache, must-revalidate, max-age=0
#   Pragma: no-cache
#   Expires: Thu, 01 Jan 1970 00:00:00 GMT
# ETag and Last-Modified must be absent.
```

Verify OPcache is disabled (PHP serves from source, not bytecode cache):

```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  php8.3 -r 'echo ini_get("opcache.enable"), "\n";'
# expected: 0
```

### 8.6 Confirm agent connects to DX O2

```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c dx-o2-agent -- \
  tail -30 /opt/apmia/logs/IntroscopeAgent.log
```

Look for lines containing `Connected to` or `Successfully connected` rather than
`Connection refused` or `UnknownHostException`.  The pre-configured profile uses
WSS; ensure your cluster can reach the tenant EM endpoint.

---

## 9. Common problems and fixes

### Wrong installer format (support.broadcom.com download)

**Symptom:** Build fails with `IntroscopeAgent.profile not found` or the
extracted archive has a different directory layout.

**Fix:** Download the packages from your DX O2 interface (see §2), not
support.broadcom.com.  Verify:
```bash
tar -tf PHP_apmia_*.tar | grep IntroscopeAgent.profile
# must show: apmia/core/config/IntroscopeAgent.profile
```
If the path is `apmia/config/IntroscopeAgent.profile` (no `core/` subdirectory),
the archive is from the support portal — it will not work.

### Probe files not found after container start

**Symptom:** `apache-php` logs `"DX O2 agent volume not mounted"`.

**Fix:**
```bash
kubectl describe pod -n <APP_NAMESPACE> <pod> | grep -A5 "dxo2-init"
kubectl logs -n <APP_NAMESPACE> <pod> -c dxo2-init
# should end with: "Done – N entries in /apmia-share"
```

### Apache fails to start with unknown module

**Symptom:** `apache-php` crashes: `Invalid command 'LoadModule'` or
`Syntax error on line ...`.

**Cause:** The derived module name or the `.so` path is wrong.

**Fix:** Check the entrypoint log for the derived module name:
```
[entrypoint] Injecting BPA WebServer Plugin (Apache): mod_<name>.so
[entrypoint]   Module name : <name>_module
```
Then validate manually:
```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- apache2ctl configtest
```

### dx-o2-agent OOMKilled (exit code 137)

**Symptom:** Pod restarts; `kubectl describe pod` shows `OOMKilled` and
exit code 137 on the `dx-o2-agent` container.

**Cause:** The APMIA Infrastructure Agent is a Java process.  Its JVM
heap plus the BTL threads consume ~757 MiB at idle (measured via
`docker stats`).  Any memory limit below that threshold — including the
former default of 512 Mi — will OOMKill the container before it can
connect to the backend.

**Fix:** The current defaults in `values.yaml` are:
```yaml
dxo2:
  resources:
    requests:
      memory: "792Mi"   # ≈ observed idle baseline + small buffer
    limits:
      memory: "4Gi"     # headroom for APM load (transaction correlation, DB monitor)
```
If OOMKilled persists under heavy APM load, increase `limits.memory`
further.  Do not lower `requests.memory` below the observed idle
baseline or the scheduler will place the pod on nodes without sufficient
real capacity.

To observe live memory usage:
```bash
# Docker Compose
docker stats --no-stream

# Kubernetes
kubectl top pod -n <APP_NAMESPACE> --containers
```

### Liveness / readiness probes return HTTP 500 after enabling APMIA

**Symptom:** Pod restarts or stays in `0/1 Running`; probe logs show HTTP 500.

**Cause:** Probes target `GET /` which invokes `index.php`; the APMIA PHP
probe extension then tries to open a TCP connection to the IA collector at
`127.0.0.1:5005`.  If the `dx-o2-agent` sidecar has not finished starting,
the port is not yet listening and the extension fails the request.

**Fix:** All probes target `GET /health` — a static file served by Apache
without invoking PHP.  The APMIA extension is never triggered during health
checks, so probes succeed regardless of sidecar state.

Verify the health endpoint is reachable and returns `OK`:
```bash
kubectl port-forward -n <APP_NAMESPACE> svc/php-demo-php-demo 8080:8080 &
curl -s http://localhost:8080/health    # expected: OK
```

### PHP probe loads but DX O2 shows no data

**Cause:** The IA sidecar (`dx-o2-agent`) is not connected to the backend.

**Fix:**
```bash
kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent | grep -i "error\|refused\|exception"
```
Ensure the cluster can reach the WSS endpoint in the pre-configured profile.
Check for firewall or proxy restrictions on outbound WSS (port 443).

### Container hostname still shows in metric path

**Symptom:** DX O2 metric path shows a random container ID instead of the
configured agent name or hostname.

There are two separate mechanisms — one for the PHP probe, one for the IA and BPA module.

**PHP probe (`wily_php_agent.hostname`):**
The entrypoint always sets `wily_php_agent.hostname` to `APMIA_PHP_AGENT_NAME`
(default `${DEPLOYMENT_NAME}-${DEPLOYMENT_POSTFIX}`, e.g. `bpa-demo-k8s`). If
the PHP probe still shows a random ID, verify the patched INI:
```bash
kubectl exec -n <APP_NAMESPACE> <pod> -c apache-php -- \
  grep hostname /etc/php/8.3/mods-available/wily_php_agent.ini
# expected: wily_php_agent.hostname="bpa-demo-k8s" (or your configured value)
```

**IA + BPA module (`spec.hostname` / OS hostname):**
`APMENV_INTROSCOPE_AGENT_HOSTNAME` only affects the IA.  The BPA module reads
the OS `gethostname()`.  Confirm the pod-level hostname is set:
```bash
kubectl get pod -n <APP_NAMESPACE> <pod> -o jsonpath='{.spec.hostname}'
# expected: bpa-demo-k8s (or your configured value)
```
If empty, verify `dxo2.hostName` is set in `values.yaml` and that
`deploy.sh` was run after updating `.config`.

### Browser agent configured correctly but snippet never appears in responses

**Symptom:** `response.decoration=1`, `autoInjection=1`, and `snippetString`
are all set in the INI, probe log shows no error, but no `<script id="ca_eum_ba">`
appears in any page response.  Debug log shows:
```
Looking for include operation, current op = 61
...
BA Correlation  last seg of url : (null) and request_info.no_headers : 0
```

**Cause:** The PHP probe has two independent injection gates, both silently skipped
by a front-controller pattern (all requests through `index.php`):

- *Gate 1 — Frontend start:* The very first opcode of the entry script must be
  non-include.  `index.php` opens with `require_once` (opcode 61), so the probe
  enters include-tracking mode and never emits `Frontend start`.  No `Frontend
  start` = no BA injection, regardless of INI configuration.

- *Gate 2 — SCRIPT_NAME segment:* The probe reads `SCRIPT_NAME` (not `REQUEST_URI`)
  and treats `index.php` and bare `/` as null segments, skipping injection.
  mod_rewrite that maps `/shop` → `index.php?page=shop` changes `REQUEST_URI`
  but leaves `SCRIPT_NAME=/index.php` — Gate 2 still fails.

**Status: not currently worked around (reverted 2026-08-19).** BPA-Demo previously
used per-page wrapper files at the document root — each wrapper (`shop.php`,
`basket.php`, etc.) ran one non-include statement before `require __DIR__ . '/index.php'`:

```php
<?php
$_GET['page'] ??= basename(__FILE__, '.php'); // triggers Frontend start
require __DIR__ . '/index.php';
```

with `vhost.conf` mapping `/shop` → `shop.php?page=shop` (not `index.php?page=shop`)
so `SCRIPT_NAME=/shop.php` and both gates passed. This workaround was removed at
the user's request — see `bug_php_probe.md` and `CLAUDE.md`'s "PHP probe injection"
section. Browser-agent auto-injection currently does not occur anywhere in the app;
this is expected, not a bug to chase. To reapply the workaround, recreate the
wrapper files and the `vhost.conf` rewrite target from `bug_php_probe.md`'s
"Fix — Per-Page Wrapper Files" section.

Enable DEBUG logging (`APMIA_PHP_LOG_LEVEL=DEBUG` in `.config`, rebuild) to
see the per-request gate decisions described above in
`/var/log/php-probe/wily_php_agent_<pid>.log`.

### PHP probe reports under `UnknownAgent` instead of its real identity

**Symptom:** the PHP probe's metric path shows
`SuperDomain|<host>|php-probes|UnknownAgent(/usr/sbin/apache2)` instead of
`SuperDomain|<host>|php-probes|<host>(/usr/sbin/apache2)`. Per
[Broadcom's PHP agent naming docs](https://techdocs.broadcom.com/us/en/ca-enterprise-software/it-operations-management/dx-apm-agents/SaaS/php-agent/monitor-php-applications-with-ca-digital-experience-insights/php-agent-naming-ca-digital-experience-insights.html),
that agent-name segment is the `{collector}` variable — "Name of
Infrastructure Agent," resolved from `introscope.agent.agentName` at the
moment the PHP probe first registers with the IA's PHP-collector socket.

**Cause:** the PHP probe's first registration attempt raced ahead of the
`dx-o2-agent` sidecar actually being up. In Kubernetes, `apache-php` and
`dx-o2-agent` are separate containers in the same pod with no guaranteed
start order, and the sidecar's JVM cold-start + WSS handshake to the SaaS
EM (especially under a tight `dxo2.resources.limits.cpu`) can outlast
Apache's own startup — the PHP probe falls back to the generic
`UnknownAgent` placeholder and it persists for the life of that Apache
process. Docker Compose's lighter, unconstrained startup profile is far
less likely to lose this race.

**Fix:** `apache-php/entrypoint.sh` now waits for
`APMIA_PHP_COLLECTOR_HOST:APMIA_PHP_COLLECTOR_PORT` to accept connections
(up to 60s, warns and starts anyway on timeout) before starting Apache, so
the probe's first registration attempt never happens before the
Infrastructure Agent is ready. Requires rebuilding and redeploying the
`apache-php` image — this is baked into the entrypoint script, not
runtime-configurable via `.config`/Helm values.

### Browser agent snippet appears in INI when not configured

**Cause:** The DX O2 installer shipped `wily_php_agent.ini` with
`autoInjection` pre-enabled, and the container image was not rebuilt.

**Fix:** Rebuild the `apache-php` image and redeploy.  The entrypoint always
reads `APMIA_BROWSER_SNIPPET` at startup and sets `autoInjection=0` when
it is empty, overriding any pre-configured INI values.

---

## 10. Complete end-to-end build checklist

```
[ ] 1. Log in to DX O2 interface (e.g. https://dx.dxi-eu1.saas.broadcom.com/)
[ ] 2. Download PHP_apmia_*.tar             (Agents -> Infrastructure Agent -> Linux)
[ ] 3. Download Infrastructure_Agent_apmia_*.tar  (same page -- needed for DB Monitor)
[ ] 4. Download Business_Transaction_Listener.zip           (Settings -> Web
       Payload Capture Rules (Webserver) -> Download, top right)
[ ] 5. Download Business_Payload_Analyzer_WebServer_Plugins.zip  (same
       download as step 4 -- both come from that one button)
[ ] 6. Place all four archives in src/dx-o2-agents/installers/
[ ] 7. Verify archive layouts:
       tar -tf src/dx-o2-agents/installers/PHP_apmia*.tar | grep IntroscopeAgent.profile
       # must show: apmia/core/config/IntroscopeAgent.profile
       tar -tf src/dx-o2-agents/installers/Infrastructure_Agent_apmia*.tar | grep 'extensions/deploy/mysql'
       # must show: apmia/extensions/deploy/mysql-*.tar.gz
[ ] 8. Set DEPLOYMENT_NAME/DEPLOYMENT_POSTFIX in .config (or leave
       DEPLOYMENT_POSTFIX empty to accept deploy.sh's "k8s" default) --
       gives this deployment's agents a distinguishable identity from a
       Docker Compose deployment on the same tenant. Individual
       APMIA_AGENT_NAME/APP_NAME/HOST_NAME/etc. vars can still override one
       agent's identity if needed.
       Also set MARIADB_ROOT_PASSWORD if not already set -- required for the
       DB Monitor login verification/creation step (checklist item 17).
[ ] 9. Set APMIA_EM_HOST to a non-empty value in .config (enables dxo2.enabled)
[ ] 10. (Optional) Set APMIA_BROWSER_SNIPPET in .config if browser agent is needed
[ ] 11. Run: build-scripts/build.sh
        Confirm: "[build] dx-o2-agents built successfully."
        Confirm: "[Dockerfile] MySQL monitor extension staged at /opt/apmia/extensions/deploy/mysql-*.tar.gz."
[ ] 12. Run: build-scripts/push.sh
[ ] 13. Run: build-scripts/deploy.sh
        deploy.sh sets dxo2.enabled: true automatically when APMIA_EM_HOST is set
[ ] 14. Verify: kubectl get pods -n <APP_NAMESPACE> -w
        Wait for 3/3 containers Running (or 4/4 with dxo2 enabled)
[ ] 15. Check: kubectl logs -n <APP_NAMESPACE> <pod> -c apache-php | grep "probe active"
        expected: "DX O2 PHP probe active -- APM instrumentation enabled."
[ ] 16. Check: kubectl logs -n <APP_NAMESPACE> <pod> -c apache-php | grep "BPA WebServer"
        expected: "BPA WebServer Plugin active -- BPA instrumentation enabled."
[ ] 17. Check: kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent | grep "DB Monitor"
        expected:
          "[entrypoint] DB Monitor: login 'phpuser' has monitoring grants (SELECT, PROCESS, REPLICATION CLIENT)."
          "[entrypoint] DB Monitor: enabled (profile=bpadb, host=mariadb:3306, ...)"
        Also confirm no DBMonitor errors:
          kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent | grep -c '\[ERROR\] \[IntroscopeAgent.DBMonitor\]'
          expected: 0
[ ] 18. Check: kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent | grep "Infrastructure Agent"
        expected: "Infrastructure Agent started (PID ...)"
[ ] 19. Verify in DX O2 console: agent tree shows configured agent name under configured app
```
