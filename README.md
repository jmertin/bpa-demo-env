# BPA-Demo – Smart Home Device Web Shop

A full-stack PHP demo web shop selling home-assistant compatible smart devices
(Shelly, SonOff, Tuya) containerised with **Apache 2.4 + mod_php** and **MariaDB**.

The application itself is a vehicle: BPA-Demo exists to demonstrate the
**full end-to-end monitoring capabilities of Broadcom DX O2 APM** — from a
raw HTTP request, through the PHP runtime and the database, out to a real
visitor's browser — under one console view, with realistic (and
occasionally deliberately broken) traffic to observe.

The application ships 300 products across three brands, a session-based shopping
basket, fake credit-card checkout with Luhn validation, an admin panel with
per-user use-case assignment, and monitoring HTTP headers on every response.
All source code follows the **Backdrop CMS PHP coding standards** (2-space
indent, K&R braces, PHPDoc on every function, single quotes).

### DX O2 agents demonstrated

| Agent / component | What it monitors | Where it runs |
|---|---|---|
| **Infrastructure Agent (IA)** | Host + process‑level agent; hosts the extensions below and reports the app's core identity to the DX O2 tenant | `dx-o2-agent` sidecar container |
| **PHP Probe** (`wily_php_agent`) | In‑process PHP instrumentation — frontend URL response time, error rate, concurrency, and per‑SQL‑statement backend calls to MariaDB | Injected into the `apache-php` container's PHP runtime |
| **DB Monitor extension** | MySQL/MariaDB‑specific server metrics (availability, connection pool, buffer pool cache hit rate, slow queries) | Runs inside the Infrastructure Agent, connects to the `mariadb` container |
| **Business Transaction Listener (BTL)** | Receives payload data forwarded by the BPA WebServer Plugin | `dx-o2-agent` sidecar container |
| **BPA WebServer Plugin** (`mod_caplugin`) | Apache‑level Business Payload Analyzer — per‑business‑transaction server‑side timing, independent of the PHP probe | Apache module injected into the `apache-php` container |
| **Browser Agent (BA snippet)** | Real‑user monitoring (RUM) in an actual visitor's browser — page load time, resource timing, time‑to‑first‑byte | JavaScript snippet auto‑injected into every HTML response by the PHP probe |

### What deploys automatically vs. what needs manual setup

**Automatic** — a single `build-scripts/deploy.sh` (Kubernetes) or
`build-scripts/compose.sh up -d` (local) run handles all of this, driven
entirely by `.config`:
- Building the app and pulling/copying the DX O2 agent installer archives
  into the `dx-o2-agents` image.
- Starting the Infrastructure Agent + BTL as a sidecar, with an identity
  (`DEPLOYMENT_NAME`/`DEPLOYMENT_POSTFIX`) that keeps it distinct from any
  other deployment reporting to the same tenant.
- Injecting the PHP Probe and the BPA WebServer Plugin into the `apache-php`
  container at startup (opportunistic — the app starts cleanly with neither
  if the agent volume is absent).
- Configuring the DB Monitor extension against the deployed MariaDB
  instance, including creating its monitoring login if it doesn't exist yet.
- Injecting the Browser Agent snippet into every HTML response, once a
  snippet value is supplied (see below).

**Manual, one-time, outside this repo's automation:**
- **Downloading the four DX O2 agent installer archives** from your DX O2
  tenant's own interface (not from support.broadcom.com — see
  [DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md)) and placing them in
  `src/dx-o2-agents/installers/`. This is a licensed, tenant-specific
  download that can't be scripted or committed to git.
- **Copying the Browser Agent snippet** from your tenant's own console
  (DX O2 Settings → Manage Mobile/Browser Web Monitoring → App to Monitor →
  Web App) into `.config`'s `APMIA_BROWSER_SNIPPET`.
- **Tenant-side console configuration** (Service, Management Module,
  Alerts, Universes, SLIs, Dashboard) — mostly scripted via `dxo2-scripts/`
  (see step 6 of [QUICKSTART.md](QUICKSTART.md)), but a few specific pieces
  have no CLI path at all and must be done by hand in the console — see
  [DX-O2_MANUAL_CONFIGURATION.md](DX-O2_MANUAL_CONFIGURATION.md) for
  exactly which ones and why.

---

## Project structure

```
.
├── .gitignore                    # excludes .config, .build_number, generated artefacts
├── .config.example               # template – copy to .config and fill in values
├── CHANGELOG                     # change history by phase
├── COMPATIBILITY.md              # DX O2 agent / OS / runtime version matrix
├── docker-compose.yml            # local development stack (no TLS, no registry)
│
├── app/
│   └── src/                      # PHP application source
│       ├── health                # static file – K8s liveness/readiness/startup probe target (no PHP)
│       ├── index.php             # front-controller (all routing; never called directly by Apache)
│       ├── shop.php              # per-page wrapper → index.php (non-include anchor for PHP probe Frontend start)
│       ├── basket.php            # (same pattern – all 11 wrapper files are identical in structure)
│       ├── product.php checkout.php order.php login.php logout.php admin.php info.php db.php dxo2.php
│       ├── config/               # session bootstrap, PDO singleton
│       ├── lib/                  # auth, product, basket, order, usecase, validate, headers
│       ├── pages/                # shop, product, basket, checkout, order, login, admin
│       ├── css/                  # app.css (application stylesheet – served as /css/app.css)
│       ├── templates/            # layout.php (links app.css), footer.php
│       ├── usecases/             # trouble.php, empty_basket.php, locked.php
│       └── setup/                # init_users.php (CLI only, not web-accessible)
│
├── src/
│   ├── apache-php/               # Apache 2.4 + mod_php container (ubuntu:22.04, multi-stage)
│   │   ├── Dockerfile            # Stage 1: extract archive; Stage 2: runtime + OPcache disabled
│   │   ├── entrypoint.sh         # PHP probe + BPA Apache module injection, cron, Apache
│   │   └── config/
│   │       └── vhost.conf        # VirtualHost :8080; no-cache headers; baked in + ConfigMap override
│   │
│   └── dx-o2-agents/             # Broadcom DX O2 monitoring container (ubuntu:22.04)
│       ├── Dockerfile            # extracts APMIA + BTL + BPA plugin to /opt/apmia, /opt/btlistener
│       ├── entrypoint.sh         # APMENV_* identity; starts IA + BTL; APMIA_DEPLOY passthrough
│       └── installers/           # place 3 DX O2 packages here (git-ignored)
│
├── build-scripts/
│   ├── package-app.sh            # tar app/src/ → app.tar.gz; bumps .build_number + IMAGE_TAG
│   ├── build.sh                  # docker build all images using IMAGE_TAG as-is (no bump)
│   ├── push.sh                   # docker login (--password-stdin) + push all images
│   ├── deploy.sh                 # renders values.local.yaml from .config, helm upgrade
│   ├── compose.sh                # docker compose wrapper (sources .config, exports vars)
│   └── package-helm-bundle.sh    # bundle helm/ + deploy.sh for a separate deploy host (images already pushed)
│
├── traffic-generator/            # synthetic user traffic for the demo shop (stdlib-only Python)
│   ├── Dockerfile
│   ├── generator.py               # cycles through all demo users; random shop actions
│   └── README.md
│
├── tools/                        # local-only binaries for demo automation (git-ignored, see tools/README.md)
│
├── dxo2-scripts/                 # scripted DX O2 tenant config (Service + alerts) via the dx-do CLI
│   ├── bpa-demo-service.sh       # "BPA-Demo" Service: create|check|delete
│   ├── bpa-demo-management-module.sh  # "BPA-Demo" MM + trouble-use-case alert
│   ├── bpa-demo-agent-alerts.sh  # 12 more alerts: DB Monitor, PHP probe, browser/RUM
│   └── .state/                   # resource ids created in the tenant (git-ignored)
│
└── helm/
    └── php-demo/                 # Helm chart v0.2.0
        ├── Chart.yaml
        ├── values.yaml           # all defaults – no secrets, no registry credentials
        ├── .helmignore
        ├── files/
        │   └── vhost.conf        # symlink -> src/apache-php/config/vhost.conf (single source of truth)
        ├── sql/
        │   ├── schema.sql        # 8-table MariaDB schema
        │   └── seed.sql          # 3 brands, 6 capabilities, 300 products, 13 demo users
        └── templates/
            ├── _helpers.tpl
            ├── statefulset.yaml        # pod: apache-php + mariadb (+ dx-o2 sidecar + init)
            ├── traffic-deployment.yaml # separate Deployment, node-anti-affined away from the app pod
            ├── serviceaccount.yaml     # automountServiceAccountToken: false
            ├── registry-secret.yaml    # kubernetes.io/dockerconfigjson pull secret
            ├── db-init-configmap.yaml  # embeds schema.sql + seed.sql for MariaDB init
            ├── configmap.yaml          # {{ .Files.Get "files/vhost.conf" }} (mounted via subPath)
            ├── secret.yaml             # MariaDB credentials from Helm values
            ├── service.yaml            # ClusterIP on port 8080 -- Ingress routes here
            ├── service-headless.yaml   # clusterIP: None -- stable per-pod DNS for the StatefulSet
            ├── ingress.yaml            # TLS ingress with cert-manager annotation
            ├── pvc.yaml                # 1 Gi PersistentVolumeClaim for MariaDB data
            └── NOTES.txt
```

---

## Architecture

### Kubernetes (production)

```
Internet
   │
   ▼
Ingress (TLS – cert-manager)
   │  port 443
   ▼
Service (ClusterIP :8080)
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│  Pod: php-demo                                           │
│                                                          │
│  initContainer: dxo2-init  ──► emptyDir /opt/apmia      │ ← when dxo2.enabled
│                                                          │
│  [dx-o2-agent] Java IA + BTL ──► DX O2 backend (WSS)    │ ← when dxo2.enabled
│                                                          │
│  [apache-php]  Apache 2.4 + mod_php                      │
│      listen 8080 ◄── external traffic                    │
│      PHP probe ◄── /opt/apmia (emptyDir)                 │ ← when dxo2.enabled
│      BPA Apache module ◄── /opt/apmia (emptyDir)         │ ← when dxo2.enabled
│      PDO → 127.0.0.1:3306                                │
│                                                          │
│  [mariadb:11]  listen 3306                               │
│      data → PersistentVolumeClaim (1 Gi)                 │
└──────────────────────────────────────────────────────────┘
```

All containers share the same network namespace, communicating via `127.0.0.1`.
The pod's `spec.hostname` is set to `dxo2.hostName` so the IA and BPA Apache
module report a human-readable name. The PHP probe uses `wily_php_agent.hostname`
(patched to `APMIA_PHP_AGENT_NAME` by the entrypoint) for its own metric path.

The pod is managed by a **StatefulSet**, not a Deployment, so its name is
always `<release>-0` rather than a random ReplicaSet-hash suffix that
changes on every rollout. A headless Service (`service-headless.yaml`)
gives it a stable, resolvable DNS name across pod recreation
(`<pod>.<headless-svc>.<namespace>.svc.cluster.local`). This does **not**
pin the pod's IP address -- Kubernetes assigns that fresh from the
cluster's CNI on every pod (re)creation regardless of workload kind; only
`hostNetwork: true` (not used here) or a CNI-specific static-IP annotation
can do that.

The traffic generator runs as a **separate Deployment** (`trafficGenerator.enabled`,
gated off by default in `values.yaml`; `deploy.sh` always turns it on), not
inside the StatefulSet's pod. It is scheduled onto a **different node** than
the app pod via `podAntiAffinity` matching the app pod's
`app.kubernetes.io/component: app` label (`topologyKey: kubernetes.io/hostname`).
`trafficGenerator.antiAffinity.required` defaults to `true` (hard constraint,
`requiredDuringSchedulingIgnoredDuringExecution`) — set it to `false` on a
single-node cluster (kind/minikube/demo VM), where a hard constraint would
leave the pod permanently `Pending`.

### Docker Compose (local development)

```
localhost:8080
   │
   ▼
[apachephp]   Apache 2.4 + mod_php, listen 8080
   │  PHP probe → dxo2:5005  (Compose service name, not 127.0.0.1)
   │  BPA plugin → dxo2:8000
   │  PDO → mariadb:3306
   │
[dxo2]        IA + BTL daemon; seeds apmia_data volume
   │
[mariadb]     listen 3306, named volume mariadb_data
```

Services run in separate containers and communicate via the Compose network.

---

## Design decisions

| Requirement | Implementation |
|---|---|
| Base image | `ubuntu:22.04` LTS (Jammy) – glibc 2.35, PHP 8.1, Apache 2.4; all within Broadcom DX O2 agent ceilings |
| Single web container | Apache 2.4 + mod_php replaces the former nginx + php-fpm pair; eliminates FastCGI intermediary and cross-container vhost config differences |
| No-recommends installs | `apt-get install --no-install-recommends` on every `RUN` layer |
| Multi-stage Apache build | Stage 1 (app-builder): extracts `app.tar.gz`; Stage 2 (runtime): Apache + PHP packages; no archive tools in the final image |
| PHP version pin | PHP 8.1 (libapache2-mod-php8.1); within DX O2 PHP Agent ceiling (≤ 8.4) |
| DX O2 opportunistic injection | PHP probe and BPA module NOT baked into app image; `dxo2-init` initContainer populates an `emptyDir`; entrypoint injects at startup if the volume is present; starts cleanly without it |
| APMENV_* identity | Agent identity set via native APMIA Docker env var mechanism; `IntroscopeAgent.profile` (tenant JWT + EM URL) is never modified |
| Container hostname in metric path | `spec.hostname` on the pod template sets the OS hostname used by the IA and BPA Apache module. The PHP probe additionally has `wily_php_agent.hostname` patched to `APMIA_PHP_AGENT_NAME` by the entrypoint, so it always reports a fixed name regardless of pod hostname |
| DB Monitor | APMIA DB Monitor extension enabled via APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_* vars; credentials from Kubernetes Secret. The entrypoint verifies the login exists in MariaDB before the IA starts, creating it (and re-applying SELECT/PROCESS/REPLICATION CLIENT grants every start) if missing — a pre-existing login from MariaDB's own bootstrapping only has grants on its own database. `version=5_6x` selects the extension's information_schema-based query set, since MariaDB doesn't implement the default MySQL 5.7+ performance_schema tables the extension otherwise queries |
| Browser agent | PHP probe injects the DX O2 browser snippet when `APMIA_BROWSER_SNIPPET` is set. Three INI properties are written: `response.decoration=1` (master switch), `snippet.autoInjection=1`, and `snippetString`. `maxSearchingLength=30000` always set. **Two probe gates must both pass:** (1) the very first PHP opcode of the entry script must be non-include; (2) `SCRIPT_NAME` must not be `index.php` or bare `/`. A front-controller pattern (all requests through `index.php`) silently fails both. Fix: per-page wrapper files (`shop.php`, `basket.php`, etc.) each run `$_GET['page'] ??= basename(__FILE__, '.php')` (non-include opcode) before `require __DIR__ . '/index.php'` — this triggers `Frontend start: /shop.php`; `vhost.conf` routes `/shop` → `shop.php?page=shop` so `SCRIPT_NAME=/shop.php` passes Gate 2 and `REQUEST_URI=/shop` names the cookie |
| Stylesheet delivery | All CSS is served as a separate static file (`/css/app.css`); no inline `<style>` block in HTML — keeps HTML responses small and ensures `</head>` appears at byte ~239 |
| Caching disabled | All caching is intentionally off: PHP OPcache disabled via Dockerfile ini drop-in; `mod_cache` never loaded; `vhost.conf` sends `Cache-Control: no-store` + `Pragma: no-cache` + epoch `Expires` on every response, strips ETags and `Last-Modified` — every page load hits PHP and the DB fresh for accurate APM telemetry |
| Kubernetes probes | All three probes (`startupProbe`, `livenessProbe`, `readinessProbe`) target `GET /health` — a static file served without PHP, so the APMIA PHP probe extension is never triggered; probes succeed independently of the `dx-o2-agent` sidecar startup timing |
| Signed/official sources only | Ubuntu `apt` (Ubuntu GPG), official `mariadb:11` Docker Hub image |
| Secrets never in git | `.config` is gitignored; `values.local.yaml` generated by `deploy.sh` and deleted immediately after `helm upgrade` returns |
| Shell scripting standards | OpenWaterFoundation (OWF): `set -euo pipefail`, `readonly` constants, `local` function variables, `usage()`/`info()`/`fatal()` helpers |
| Build versioning | `package-app.sh` owns the build counter: increments `.build_number` and updates `IMAGE_TAG` in `.config` to `b<N>`; `build.sh` and `compose.sh` use the tag as-is |

---

## Prerequisites

| Tool | Minimum version | Notes |
|---|---|---|
| Docker | 24.x | With Compose plugin v2 (`docker compose`) |
| kubectl | 1.28+ | Pointed at target cluster (`KUBECONFIG` in `.config`) |
| helm | 3.12+ | Kubernetes deploy only |
| cert-manager | 1.13+ | Cluster-side; for TLS Ingress |
| Ingress Controller | any | nginx, Traefik, HAProxy, ALB — set `INGRESS_CLASS_NAME` |

---

## Configuration

All scripts read **exclusively** from `.config` in the project root:

```bash
cp .config.example .config
$EDITOR .config
```

`.config` is gitignored and must never be committed.  See `.config.example` for
the full variable set with documentation.

---

## Kubernetes deployment

### 1 — Build images

```bash
build-scripts/build.sh
```

Steps performed automatically:

1. Calls `package-app.sh --no-bump` → `src/apache-php/app.tar.gz` (no version bump)
2. Builds **apache-php** (multi-stage) tagged `<REGISTRY>/<IMAGE_PREFIX>/apache-php:<IMAGE_TAG>`
3. Builds **dx-o2-agents** — only when `PHP_apmia*.tar` is present in
   `src/dx-o2-agents/installers/`; skipped gracefully otherwise. (The build
   itself also requires `Business_Transaction_Listener.zip`; the other two
   installer archives are optional — see DX-O2-AGENT-SETUP.md §2.2.)
4. Removes the temporary archive

> **Note:** `IMAGE_TAG` is not modified by `build.sh`. Run `package-app.sh` first to
> increment the build counter and set the new tag before building.

Add `--push` to push immediately after a successful build.

### 2 — (Optional) Download the DX O2 agent packages

Download four packages from your **DX O2 interface** (not from
support.broadcom.com): two from **Agents → Infrastructure Agent → Linux**,
two more together from **Settings → Web Payload Capture Rules (Webserver) →
Download** (top right). See
**[DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md)** for full instructions.

```bash
# Required -- the build fails without these two:
src/dx-o2-agents/installers/PHP_apmia_*.tar
src/dx-o2-agents/installers/Business_Transaction_Listener.zip

# Optional -- skipped gracefully if absent (no DB Monitor / no BPA plugin):
src/dx-o2-agents/installers/Infrastructure_Agent_apmia_*.tar
src/dx-o2-agents/installers/Business_Payload_Analyzer_WebServer_Plugins.zip
```

### 3 — Push images to registry

```bash
build-scripts/push.sh
```

Authenticates with `REGISTRY` using `--password-stdin`.  Use `--skip-dxo2` if
the dx-o2-agents image was not built.

### 4 — Deploy to Kubernetes

```bash
build-scripts/deploy.sh
```

Steps:
1. Validates all required variables and cluster reachability.
2. Creates the target namespace if absent.
3. Renders a transient `values.local.yaml` from `.config`.
4. Runs `helm upgrade --install php-demo helm/php-demo`.
5. Deletes `values.local.yaml` immediately.
6. Runs `init_users.php` via `kubectl exec` to confirm DB connectivity.

Use `--skip-init` to bypass the post-deploy DB check.

### 5 — Verify

```bash
# Watch pod come up
kubectl get pods -n <APP_NAMESPACE> -w

# Confirm the health endpoint responds (static, bypasses APMIA)
kubectl port-forward -n <APP_NAMESPACE> svc/php-demo-php-demo 8080:8080 &
curl -s http://localhost:8080/health    # should print: OK

# Check DX O2 agent activity
kubectl logs -n <APP_NAMESPACE> <pod> -c apache-php | grep -E "probe|BPA"
kubectl logs -n <APP_NAMESPACE> <pod> -c dx-o2-agent | grep -E "started|connected"
```

---

## Local development with Docker Compose

```bash
# Start (builds images locally if absent)
build-scripts/compose.sh up -d

# Tail logs
build-scripts/compose.sh logs -f

# Rebuild after source changes
build-scripts/compose.sh build && build-scripts/compose.sh up -d

# Stop and remove containers (keeps DB data)
build-scripts/compose.sh down

# Stop and wipe the MariaDB volume (full reset)
build-scripts/compose.sh down -v
```

`compose.sh` sources `.config`, exports **all** required DX O2 variables with
safe defaults, and calls `package-app.sh --no-bump` automatically before any
build (the build counter is not modified). The application is reachable at
**http://localhost:8080/** after `up`.

### Synthetic traffic

The `traffic` service (see `traffic-generator/README.md`) starts automatically
with the rest of the stack and continuously generates realistic shop traffic,
cycling through every demo user (including `trouble`/`empty_basket`/`locked`)
so their use cases fire regularly without manual clicking. Set
`TRAFFIC_ENABLED="false"` in `.config` to keep the container up but idle, or
tune its pacing via the `TRAFFIC_*` variables (see `.config.example`).

```bash
# Watch it in action
build-scripts/compose.sh logs -f traffic
```

---

## Accessing the application

### Docker Compose

After `build-scripts/compose.sh up -d` the application is immediately reachable at:

```
http://localhost:8080/
```

No further setup is needed.  The shop is public — browsing and adding items to the
basket works without logging in.

### Kubernetes

After `build-scripts/deploy.sh` the application is served via TLS Ingress at the
hostname set in `.config`:

```bash
# The URL is:
https://<APP_HOSTNAME>/
```

To confirm the Ingress address and TLS status:

```bash
kubectl get ingress -n <APP_NAMESPACE>
```

**If the Ingress is not yet reachable** (cert-manager still issuing, DNS not
propagated, or no external load balancer assigned), use a port-forward:

```bash
kubectl port-forward -n <APP_NAMESPACE> svc/php-demo-php-demo 8080:8080
# then open: http://localhost:8080/
```

Replace `<APP_NAMESPACE>` with the value of `APP_NAMESPACE` from your `.config`
(default: `dxo2-bpa-demo`).

### Logging in

Click **Sign in** in the top-right corner, or navigate directly to `/login`.
All demo accounts use the password **`demo123`**.

| Username | Role | Notes |
|---|---|---|
| `admin` | admin | Admin panel + all three diagnostic pages |
| `alice` … `jack` | user | Regular shoppers |
| `trouble` | user | APM load simulation — 5 000 DB reads per request |
| `empty` | user | Basket total always shown as €0.00 |
| `locked` | user | Login blocked — demonstrates the locked use case |

### Admin panel

Log in as `admin`, then click **Admin Panel** in the left sidebar.  From there you
can view all users and assign or remove use cases.

A **Diagnostics** section also appears in the sidebar, giving access to three
pages that inspect the runtime from inside the container:

| Page | URL | Shows |
|---|---|---|
| DX O2 Status | `/dxo2` | PHP probe, BPA module, browser agent, TCP connectivity, APMIA env vars, APMIA IA / PHP probe / BTListener log tails |
| PHP Info | `/info` | PHP version, SAPI, OS, memory limit, loaded extensions |
| Database | `/db` | Live MariaDB connection result, server version, uptime |

These pages are available even when DX O2 is not deployed — all probes will report
"not loaded", which is the expected state for a vanilla deployment.

---

## DX O2 agent setup

> **Full guide:** see **[DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md)** for
> complete download instructions, installer structure, build walkthrough,
> runtime injection diagrams, verification steps, and troubleshooting.

### Quick-start (Kubernetes)

```bash
# 1. Download four packages from your DX O2 interface and place in installers/
# 2. Configure agent identity in .config -- leave the six APMIA_* identity
#    vars empty to use the DEPLOYMENT_NAME-DEPLOYMENT_POSTFIX default
#    (e.g. "bpa-demo-k8s"), which keeps this deployment's agents distinct
#    from a Compose deployment reporting to the same tenant (default
#    "bpa-demo-docker" there) -- see .config.example and CLAUDE.md's
#    "Deployment identity" section:
DEPLOYMENT_NAME="bpa-demo"
DEPLOYMENT_POSTFIX="k8s"
APMIA_EM_HOST="placeholder"   # non-empty triggers dxo2.enabled=true

# 3. Build (dx-o2-agents image is built when installers are present)
build-scripts/build.sh

# 4. Push all images including dx-o2-agents
build-scripts/push.sh

# 5. Deploy — dxo2.enabled=true is set automatically when APMIA_EM_HOST is non-empty
build-scripts/deploy.sh

# 6. (Optional) Console-side Service + alerts, once traffic has flowed —
#    see dxo2-scripts/README.md
dxo2-scripts/bpa-demo-service.sh create
dxo2-scripts/bpa-demo-management-module.sh create
dxo2-scripts/bpa-demo-agent-alerts.sh create
```

---

## Helm chart reference

Chart: `helm/php-demo` — version **0.2.0**

### Key values

| Value | Default | Description |
|---|---|---|
| `image.apachephp.tag` | `1.0.0` | Apache+PHP image tag |
| `image.dxo2.tag` | `1.0.0` | DX O2 agents image tag |
| `image.mariadb.tag` | `11` | MariaDB major version pin |
| `service.port` | `8080` | ClusterIP service port |
| `persistence.size` | `1Gi` | PVC capacity for MariaDB data |
| `dxo2.enabled` | `false` | Enable DX O2 agent sidecar and probe injection |
| `dxo2.deploy` | `"true"` | `"false"` = passive volume only (seed without starting IA) |
| `dxo2.agentName` | `bpa-demo-k8s` | Agent name in the DX O2 console (APMENV_*) — `deploy.sh` overrides from `.config`'s `DEPLOYMENT_NAME`-`DEPLOYMENT_POSTFIX` |
| `dxo2.appName` | `bpa-demo-k8s` | Application name for metric grouping (APMENV_*) — same override |
| `dxo2.hostName` | `bpa-demo-k8s` | Pod hostname + APMENV_INTROSCOPE_AGENT_HOSTNAME — same override |
| `dxo2.logLevel` | `INFO` | APMENV_LOG4J_LOGGER_INTROSCOPEAGENT level |
| `dxo2.dbMonitor.enabled` | `true` | Enable APMIA DB Monitor for MariaDB |
| `dxo2.dbMonitor.schemaVersion` | `5_6x` | Selects the extension's information_schema-based query set (MariaDB doesn't implement the default MySQL 5.7+ performance_schema tables); not a MySQL version match |
| `dxo2.browserSnippet` | `''` | Browser agent snippet — use YAML single quotes (snippet contains HTML double-quotes); empty = disabled |
| `dxo2.resources.requests.memory` | `792Mi` | Scheduler reservation — sized to observed IA+BTL idle baseline (~757 MiB) |
| `dxo2.resources.limits.memory` | `4Gi` | Hard ceiling — APMIA JVM grows under APM load; 512 Mi causes OOMKilled |
| `trafficGenerator.enabled` | `false` | Deploy the traffic-generator Deployment (`deploy.sh` always sets this `true`) |
| `trafficGenerator.antiAffinity.required` | `true` | Hard node anti-affinity vs. the app pod; set `false` on single-node clusters |
| `trafficGenerator.env.*` | see `values.yaml` | Mirrors the `TRAFFIC_*` `.config`/Compose variables — see *Traffic generator* section above |

### Kubernetes probes

All three probes for the `apache-php` container target `GET /health`, a static
file (`app/src/health`) served by Apache without invoking PHP or the APMIA
extension.  This means the `dx-o2-agent` sidecar does not need to be fully
started before probes succeed.

| Probe | Path | Initial delay | Period | Notes |
|---|---|---|---|---|
| `startupProbe` | `/health` | 5 s | 5 s | Up to 150 s startup window (30 failures) |
| `livenessProbe` | `/health` | 15 s | 20 s | Restarts container if Apache is down |
| `readinessProbe` | `/health` | 5 s | 10 s | Gates traffic until Apache is accepting requests |

Probe requests to `/health` are excluded from the Apache access log via
`SetEnvIf` to reduce noise.

---

## BPA-Demo application

### Overview

| Brand | Products | Protocols |
|---|---|---|
| Shelly | 100 | WiFi, Matter (Gen3), Bluetooth (BLU series), Z-Wave (Qubino Wave) |
| SonOff | 100 | WiFi, Zigbee, Matter |
| Tuya | 100 | WiFi, Zigbee, Matter, Bluetooth, Tuya protocol |

### Demo accounts

All accounts use the password **`demo123`**.

| Username | Role | Behaviour |
|---|---|---|
| `admin` | admin | Full access to the admin panel |
| `trouble` | user | **Use case: trouble** — 5 000 sequential DB reads per request |
| `empty` | user | **Use case: empty_basket** — basket total always shown as €0.00 |
| `locked` | user | **Use case: locked** — login blocked; error message shown on the login page |
| `alice` … `jack` | user | 10 regular accounts |

### Application routes

| URL | Description |
|---|---|
| `/shop` | Product grid with filter bar (default landing page) |
| `/shop?brand=<slug>` | Filter by brand: `shelly` / `sonoff` / `tuya` |
| `/shop?cap=<slug>` | Filter by protocol capability |
| `/shop?q=<search>` | Full-text product search |
| `/product?slug=<slug>` | Product detail page |
| `/basket` | Shopping basket |
| `/checkout` | Billing form + Luhn-validated fake credit-card payment |
| `/order?id=<id>` | Order confirmation |
| `/order` | Order history (login required) |
| `/login` | Sign in |
| `/admin` | Admin panel (admin role required) |
| `/info` | PHP runtime diagnostics — **admin only** |
| `/db` | MariaDB connection test — **admin only** |
| `/dxo2` | DX O2 agent status and log tails — **admin only** |

### Admin diagnostic pages

Three diagnostic pages are accessible only to users with the **admin** role.
They appear as a **Diagnostics** section in the left sidebar when an admin is
logged in, and are useful for verifying the runtime environment and DX O2 agent
stack from inside the running container without needing shell access.

**PHP runtime info** (`?page=info`)

Displays the PHP version, SAPI, OS, architecture, memory limit, max execution
time, and all loaded extensions (including `wily_php_agent` when the DX O2 PHP
probe is active).

Access:
1. Log in as `admin` (password: `demo123`).
2. Navigate to `http://<host>:8080/?page=info`

**MariaDB connection test** (`?page=db`)

Attempts a live PDO connection to MariaDB using the environment variables
(`MARIADB_HOST`, `MARIADB_PORT`, `MARIADB_DATABASE`, `MARIADB_USER`,
`MARIADB_PASSWORD`) and displays the server version, uptime, and connection
parameters, or a formatted error message on failure.

Access:
1. Log in as `admin` (password: `demo123`).
2. Navigate to `http://<host>:8080/?page=db`

**DX O2 agent status** (`?page=dxo2`)

Comprehensive health check for the DX O2 monitoring stack.  Checks:

- **PHP probe** — whether `wily_php_agent` extension is loaded, the INI
  file path, and key properties: `agentName`, `hostname`, `collectorHost/Port`,
  `logdir`, `response.decoration`, `snippet.autoInjection`, `maxSearchingLength`, and snippet presence.
- **BPA Apache module** — whether `/etc/apache2/conf-enabled/bpa.conf`
  exists, the parsed `LoadModule` directive, and whether the module is
  present in `apache_get_modules()`.  The raw conf is shown verbatim.
- **Browser agent** — INI flags and whether `snippetString` is configured.
- **APMIA connectivity** — live TCP probe of the PHP collector port
  (`APMIA_PHP_COLLECTOR_HOST:PORT`) and BTL port (`APMIA_BTL_HOST:PORT`).
- **Environment variables** — all `APMIA_*` and `APMENV_*` container
  variables in a table; credential-bearing keys are redacted.
- **Log tails** — last 40 lines of every `*.log` file found in
  `/opt/apmia/logs/`, displayed in scrollable terminal blocks.

Access:
1. Log in as `admin` (password: `demo123`).
2. Navigate to `http://<host>:8080/?page=dxo2`

> **Note:** when `dxo2.enabled=false` (the default), the apmia volume is
> absent.  The page loads cleanly but reports all probes as not-loaded and
> no log files.  This is the expected state when running without DX O2.

From Kubernetes you can reach all diagnostic pages via port-forward:
```bash
kubectl port-forward -n <APP_NAMESPACE> svc/php-demo-php-demo 8080:8080
# then open:
#   http://localhost:8080/?page=info
#   http://localhost:8080/?page=db
#   http://localhost:8080/?page=dxo2
```

### Monitoring HTTP headers

| Header | Format | Example |
|---|---|---|
| `X-Page-ID` | `page_<slug>` (baseline, every page) | `page_dxo2` |
| `X-Page-ID` | `MODULE-ACTION-TARGET` (overridden by shop/auth/order pages) | `SHOP-LIST-SHELLY` |
| `X-User-Role` | `anonymous \| user \| admin` | `user` |
| `X-Basket-Total` | EUR float | `49.80` |
| `X-Alert` | string (on errors) | `LOGIN_FAILED` |
| `X-Use-Case` | use-case name | `trouble` |

### Database schema

```
brands               → id, name, slug, color, description
capabilities         → id, name, slug, color
products             → id, brand_id, name, slug, description, price, stock
product_capabilities → product_id, capability_id
users                → id, username, password_hash, email, role, full_name, created_at
user_usecases        → user_id, usecase_name, assigned_by, assigned_at
orders               → id, user_id, session_id, status, subtotal, total,
                       billing_name, billing_email, cc_last4, created_at
order_items          → id, order_id, product_id, product_name, quantity, unit_price
```

SQL files live in `helm/php-demo/sql/` and are mounted at
`/docker-entrypoint-initdb.d/` in the MariaDB container.

---

## Removing the deployment

```bash
helm uninstall php-demo --namespace php-demo

# Optionally remove persistent data and the namespace
kubectl delete pvc -n php-demo --all
kubectl delete namespace php-demo
```

### Resetting the database

```bash
helm uninstall php-demo -n php-demo
kubectl delete pvc -n php-demo --all
build-scripts/deploy.sh
```
