# BPA-Demo – Smart Home Device Web Shop

A full-stack PHP demo web shop selling home-assistant compatible smart devices
(Shelly, SonOff, Tuya) containerised with **Apache 2.4 + mod_php** and **MariaDB**.

The application ships 300 products across three brands, a session-based shopping
basket, fake credit-card checkout with Luhn validation, an admin panel with
per-user use-case assignment, and monitoring HTTP headers on every response.
All source code follows the **Backdrop CMS PHP coding standards** (2-space
indent, K&R braces, PHPDoc on every function, single quotes).

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
│       ├── index.php             # front-controller (routes via ?page=)
│       ├── config/               # session bootstrap, PDO singleton
│       ├── lib/                  # auth, product, basket, order, usecase, validate, headers
│       ├── pages/                # shop, product, basket, checkout, order, login, admin
│       ├── templates/            # layout.php (full CSS), footer.php
│       ├── usecases/             # trouble.php, empty_basket.php
│       └── setup/                # init_users.php (CLI only, not web-accessible)
│
├── src/
│   ├── apache-php/               # Apache 2.4 + mod_php container (ubuntu:22.04, multi-stage)
│   │   ├── Dockerfile            # Stage 1: extract archive; Stage 2: Apache + PHP runtime
│   │   ├── entrypoint.sh         # PHP probe + BPA Apache module injection, cron, Apache
│   │   └── config/
│   │       └── vhost.conf        # VirtualHost listen 8080; baked in + overridden by ConfigMap
│   │
│   └── dx-o2-agents/             # Broadcom DX O2 monitoring container (ubuntu:22.04)
│       ├── Dockerfile            # extracts APMIA + BTL + BPA plugin to /opt/apmia, /opt/btlistener
│       ├── entrypoint.sh         # APMENV_* identity; starts IA + BTL; APMIA_DEPLOY passthrough
│       └── installers/           # place 3 DX O2 packages here (git-ignored)
│
├── build-scripts/
│   ├── package-app.sh            # tar app/src/ → src/apache-php/app.tar.gz
│   ├── build.sh                  # calls package-app.sh, then docker build all images
│   ├── push.sh                   # docker login (--password-stdin) + push all images
│   ├── deploy.sh                 # renders values.local.yaml from .config, helm upgrade
│   └── compose.sh                # docker compose wrapper (sources .config, exports vars)
│
└── helm/
    └── php-demo/                 # Helm chart v0.2.0
        ├── Chart.yaml
        ├── values.yaml           # all defaults – no secrets, no registry credentials
        ├── .helmignore
        ├── sql/
        │   ├── schema.sql        # 8-table MariaDB schema
        │   └── seed.sql          # 3 brands, 6 capabilities, 300 products, 13 demo users
        └── templates/
            ├── _helpers.tpl
            ├── deployment.yaml         # pod: apache-php + mariadb (+ dx-o2 sidecar + init)
            ├── serviceaccount.yaml     # automountServiceAccountToken: false
            ├── registry-secret.yaml    # kubernetes.io/dockerconfigjson pull secret
            ├── db-init-configmap.yaml  # embeds schema.sql + seed.sql for MariaDB init
            ├── configmap.yaml          # Apache VirtualHost config (mounted via subPath)
            ├── secret.yaml             # MariaDB credentials from Helm values
            ├── service.yaml            # ClusterIP on port 8080
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
The pod's `spec.hostname` is set to `dxo2.hostName` so the PHP probe and BPA
Apache module report a human-readable name instead of the auto-generated pod name.

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
| Container hostname in metric path | `spec.hostname` on the pod template ensures PHP probe and BPA Apache module report the configured name, not an auto-generated container/pod ID |
| DB Monitor | APMIA DB Monitor extension enabled via APMENV_INTROSCOPE_AGENT_DBMONITOR_MYSQL_* vars; credentials from Kubernetes Secret |
| Browser agent | PHP probe injects the DX O2 browser snippet via `wily_php_agent.enable.browseragent.snippet.autoInjection=1` when `APMIA_BROWSER_SNIPPET` is set |
| Signed/official sources only | Ubuntu `apt` (Ubuntu GPG), official `mariadb:11` Docker Hub image |
| Secrets never in git | `.config` is gitignored; `values.local.yaml` generated by `deploy.sh` and deleted immediately after `helm upgrade` returns |
| Shell scripting standards | OpenWaterFoundation (OWF): `set -euo pipefail`, `readonly` constants, `local` function variables, `usage()`/`info()`/`fatal()` helpers |
| Build versioning | `build.sh` auto-increments `.build_number`, appends `b<N>` to `IMAGE_TAG` |

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

1. Calls `package-app.sh` → `src/apache-php/app.tar.gz`
2. Builds **apache-php** (multi-stage) tagged `<REGISTRY>/<IMAGE_PREFIX>/apache-php:<TAG>b<N>`
3. Builds **dx-o2-agents** — only when the three installer archives are present in
   `src/dx-o2-agents/installers/`; skipped gracefully otherwise
4. Removes the temporary archive; updates `IMAGE_TAG` in `.config` with the new `b<N>` suffix

Add `--push` to push immediately after a successful build.

### 2 — (Optional) Download the DX O2 agent packages

Download three packages from your **DX O2 interface** (not from
support.broadcom.com).  See **[DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md)**
for full instructions.

```bash
# Place all three archives here:
src/dx-o2-agents/installers/PHP_apmia_*.tar
src/dx-o2-agents/installers/Business_Transaction_Listener.zip
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
kubectl get pods -n php-demo -w

# Port-forward if ingress is not yet reachable
kubectl port-forward -n php-demo svc/php-demo-php-demo 8080:8080
# then open http://localhost:8080/

# Check DX O2 agent activity
kubectl logs -n php-demo <pod> -c apache-php | grep -E "probe|BPA"
kubectl logs -n php-demo <pod> -c dx-o2-agent | grep -E "started|connected"
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
safe defaults, and calls `package-app.sh` automatically before any build.
The application is reachable at **http://localhost:8080/** after `up`.

---

## DX O2 agent setup

> **Full guide:** see **[DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md)** for
> complete download instructions, installer structure, build walkthrough,
> runtime injection diagrams, verification steps, and troubleshooting.

### Quick-start (Kubernetes)

```bash
# 1. Download three packages from your DX O2 interface and place in installers/
# 2. Configure agent identity in .config:
APMIA_AGENT_NAME="bpa-demo-agent"
APMIA_APP_NAME="bpa-demo"
APMIA_HOST_NAME="bpa-demo-host"
APMIA_EM_HOST="placeholder"   # non-empty triggers dxo2.enabled=true

# 3. Build (dx-o2-agents image is built when installers are present)
build-scripts/build.sh

# 4. Push all images including dx-o2-agents
build-scripts/push.sh

# 5. Deploy — dxo2.enabled=true is set automatically when APMIA_EM_HOST is non-empty
build-scripts/deploy.sh
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
| `dxo2.agentName` | `bpa-demo-agent` | Agent name in the DX O2 console (APMENV_*) |
| `dxo2.appName` | `bpa-demo` | Application name for metric grouping (APMENV_*) |
| `dxo2.hostName` | `bpa-demo-host` | Pod hostname + APMENV_INTROSCOPE_AGENT_HOSTNAME |
| `dxo2.logLevel` | `INFO` | APMENV_LOG4J_LOGGER_INTROSCOPEAGENT level |
| `dxo2.dbMonitor.enabled` | `true` | Enable APMIA DB Monitor for MariaDB |
| `dxo2.browserSnippet` | `""` | Browser agent snippet (empty = disabled) |

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
| `alice` … `jack` | user | 10 regular accounts |

### Application routes

| URL | Description |
|---|---|
| `?page=shop` | Product grid with filter bar (default landing page) |
| `?page=shop&brand=<slug>` | Filter by brand: `shelly` / `sonoff` / `tuya` |
| `?page=shop&cap=<slug>` | Filter by protocol capability |
| `?page=shop&q=<search>` | Full-text product search |
| `?page=product&slug=<slug>` | Product detail page |
| `?page=basket` | Shopping basket |
| `?page=checkout` | Billing form + Luhn-validated fake credit-card payment |
| `?page=order&id=<id>` | Order confirmation |
| `?page=order` | Order history (login required) |
| `?page=login` | Sign in |
| `?page=admin` | Admin panel (admin role required) |

### Monitoring HTTP headers

| Header | Format | Example |
|---|---|---|
| `X-Page-ID` | `MODULE-ACTION-TARGET` | `SHOP-LIST-SHELLY` |
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
