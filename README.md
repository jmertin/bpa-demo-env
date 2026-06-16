# BPA-Demo – Smart Home Device Web Shop

A full-stack PHP demo web shop selling home-assistant compatible smart devices
(Shelly, SonOff, Tuya) containerised with **nginx**, **PHP-FPM**, and **MariaDB**.

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
│   ├── php-fpm/                  # PHP-FPM container (multi-stage, ubuntu:22.04)
│   │   ├── Dockerfile            # Stage 1: extract archive; Stage 2: runtime only
│   │   ├── entrypoint.sh         # PHP probe injection, cron, then php-fpm -F -R
│   │   └── config/
│   │       ├── php-fpm.conf      # global config (no daemon, log to stderr)
│   │       └── www.conf          # pool: TCP 0.0.0.0:9000, workers as www-data
│   │
│   ├── nginx/                    # NGINX container (ubuntu:22.04)
│   │   ├── Dockerfile            # pessimistic cleanup of all distro defaults
│   │   ├── entrypoint.sh         # BPA plugin injection, cron, then nginx -g 'daemon off;'
│   │   └── config/
│   │       ├── nginx.conf        # includes /etc/nginx/modules-enabled/*.conf at top level
│   │       ├── default.conf      # listen 8080, fastcgi_pass 127.0.0.1:9000
│   │       └── default-compose.conf  # listen 8080, fastcgi_pass phpfpm:9000 (Compose)
│   │
│   └── dx-o2-agents/             # Broadcom DX O2 monitoring container (ubuntu:22.04)
│       ├── Dockerfile            # installs APMIA to /opt/apmia via silent installer
│       ├── entrypoint.sh         # validates EM host, renders profile, starts agent + BTL
│       ├── config/
│       │   └── IntroscopeAgent.profile.template
│       └── installers/           # place apmia-*.tar.gz here (git-ignored, licensed binary)
│           └── .gitkeep
│
├── build-scripts/
│   ├── package-app.sh            # tar app/src/ → src/php-fpm/app.tar.gz
│   ├── build.sh                  # calls package-app.sh, then docker build all images
│   ├── push.sh                   # docker login (--password-stdin) + push all images
│   ├── deploy.sh                 # renders values.local.yaml from .config, helm upgrade
│   └── compose.sh                # docker compose wrapper (sources .config, builds if needed)
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
            ├── deployment.yaml         # pod: nginx + php-fpm + mariadb (+ dx-o2 sidecar)
            ├── serviceaccount.yaml     # automountServiceAccountToken: false
            ├── registry-secret.yaml    # kubernetes.io/dockerconfigjson pull secret
            ├── db-init-configmap.yaml  # embeds schema.sql + seed.sql for MariaDB init
            ├── configmap.yaml          # nginx + PHP-FPM configs (mounted over image defaults)
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
│  [dx-o2-agent] Java daemon ──► Enterprise Manager       │ ← when dxo2.enabled
│                                                          │
│  [nginx]       listen 8080  ◄── external traffic         │
│      │  BPA plugin ◄── /opt/apmia (emptyDir)            │ ← when dxo2.enabled
│      │  FastCGI → 127.0.0.1:9000                        │
│  [php-fpm]     listen 9000                               │
│      │  PHP probe ◄── /opt/apmia (emptyDir)             │ ← when dxo2.enabled
│      │  PDO → 127.0.0.1:3306                            │
│  [mariadb:11]  listen 3306                               │
│      │  data → PersistentVolumeClaim (1 Gi)             │
└──────────────────────────────────────────────────────────┘
```

All containers share the same network namespace, communicating via `127.0.0.1`.

### Docker Compose (local development)

```
localhost:8080
   │
   ▼
[nginx]    listen 8080
   │  FastCGI → phpfpm:9000   (service name, not 127.0.0.1)
   ▼
[phpfpm]   listen 9000
   │  PDO → mariadb:3306
   ▼
[mariadb]  listen 3306
   │  data → named volume mariadb_data
```

Services run in separate containers and communicate via the Compose network.
There is no DX O2 agent in the Compose stack.

---

## Design decisions

| Requirement | Implementation |
|---|---|
| Base image | `ubuntu:22.04` LTS (Jammy) – glibc 2.35, PHP 8.1, NGINX 1.18; all within Broadcom DX O2 agent ceilings |
| No-recommends installs | `apt-get install --no-install-recommends` on every `RUN` layer |
| Multi-stage PHP-FPM build | Stage 1 (app-builder): `ubuntu:22.04` + `tar` only – extracts `app.tar.gz`; Stage 2 (runtime): PHP 8.1 packages + app from Stage 1; no archive tools in the final image |
| PHP version pin | PHP 8.1 from Ubuntu 22.04 repos; within DX O2 PHP Agent ceiling (≤ 8.4) |
| NGINX version pin | NGINX 1.18 from Ubuntu 22.04 repos; within BPA WebServer Plugin ceiling (≤ 1.29.x) |
| Pessimistic NGINX hardening | All distro default vhosts, `conf.d/*`, `snippets/*`, and `modules-enabled/*` removed in Dockerfile; only project-supplied configs remain |
| Signed/official sources only | Ubuntu `apt` (Ubuntu GPG), official `mariadb:11` Docker Hub image |
| DX O2 opportunistic injection | PHP probe and BPA plugin are NOT baked into app images; `dxo2-init` initContainer populates an `emptyDir`; entrypoints inject probes at startup if the volume is mounted; containers start cleanly without it |
| Security updates inside containers | `cron.d` rule in each custom image; `entrypoint.sh` starts cron before the main process |
| Registry credentials in Kubernetes | `kubernetes.io/dockerconfigjson` Secret; attached to the pod's ServiceAccount (`automountServiceAccountToken: false`); kubelet inherits pull credentials automatically |
| Secrets never in git | `.config` is gitignored; `values.local.yaml` is generated by `deploy.sh` and deleted immediately after `helm upgrade` returns |
| Config/credentials isolation | All variables in `.config` (shell format); every script sources it at runtime; no variable is embedded in any tracked file |
| PHP coding standards | Backdrop CMS: 2-space indent, K&R braces, PHPDoc on every function, single quotes, no closing `?>` in pure-PHP files |
| Shell scripting standards | OpenWaterFoundation (OWF): `#!/usr/bin/env bash`, `set -euo pipefail`, `readonly` constants, `local` function variables, `usage()` / `info()` / `fatal()` helpers, prerequisite checks, `--help` flags |
| Build versioning | `build.sh` auto-increments `.build_number` and appends `b<N>` to `IMAGE_TAG` (e.g. `1.0.0b12`) so every build produces a distinct tag that Kubernetes cannot skip due to a cached image |

---

## Prerequisites

| Tool | Minimum version | Notes |
|---|---|---|
| Docker | 24.x | With Compose plugin v2 (`docker compose`) |
| kubectl | 1.28+ | Pointed at target cluster (`KUBECONFIG` in `.config`) |
| helm | 3.12+ | Kubernetes deploy only |
| cert-manager | 1.13+ | Cluster-side; for TLS Ingress |
| NGINX Ingress Controller | any | Or Traefik, HAProxy, ALB — set `INGRESS_CLASS_NAME` |

---

## Configuration

All scripts read **exclusively** from `.config` in the project root:

```bash
cp .config.example .config
$EDITOR .config
```

`.config` is gitignored and must never be committed. The full variable set:

```bash
# Docker Registry
REGISTRY="registry.example.com"
REGISTRY_USER="admin"
REGISTRY_PASSWORD="changeme"

# Image settings — build.sh appends b<N> automatically
IMAGE_PREFIX="php-demo"
IMAGE_TAG="1.0.0"
BUILD_PLATFORM="linux/amd64"

# MariaDB credentials
MARIADB_ROOT_PASSWORD="changeme_root"
MARIADB_DATABASE="phpapp"
MARIADB_USER="phpuser"
MARIADB_PASSWORD="changeme_user"

# Kubernetes / Helm
APP_NAMESPACE="php-demo"
APP_HOSTNAME="php-demo.example.com"
TLS_CLUSTER_ISSUER="letsencrypt-prod"
INGRESS_CLASS_NAME="nginx"
KUBECONFIG="${HOME}/.kube/config"
HELM_CHART_PATH=""              # defaults to helm/php-demo when empty

# Broadcom DX O2 Agent (optional — leave APMIA_EM_HOST empty to disable)
APMIA_EM_HOST=""
APMIA_EM_PORT="5001"
APMIA_AGENT_NAME="bpa-demo-agent"
APMIA_APP_NAME="BPA-Demo"
APMIA_LOG_LEVEL="INFO"
```

---

## Kubernetes deployment (production)

### 1 — Build images

```bash
build-scripts/build.sh
```

Steps performed automatically:

1. Calls `package-app.sh` → `src/php-fpm/app.tar.gz`
2. Builds **php-fpm** (multi-stage) tagged `<REGISTRY>/<IMAGE_PREFIX>/php-fpm:<TAG>b<N>`
3. Builds **nginx** tagged `<REGISTRY>/<IMAGE_PREFIX>/nginx:<TAG>b<N>`
4. Builds **dx-o2-agents** — only when `src/dx-o2-agents/installers/apmia-*.tar.gz` is present; skipped gracefully otherwise
5. Removes the temporary archive; updates `IMAGE_TAG` in `.config` with the new `b<N>` suffix

Add `--push` to push immediately after a successful build.

### 2 — (Optional) Download the DX O2 agent installer

To enable Broadcom monitoring, download the **Broadcom Infrastructure Agent**
(`apmia-*.tar.gz`) from [Broadcom Support](https://support.broadcom.com/) and
place it in `src/dx-o2-agents/installers/`.  The directory is gitignored.
Re-run `build.sh` — Step 4 will then build the dx-o2-agents image.

### 3 — Push images to registry

```bash
build-scripts/push.sh
```

Authenticates with `REGISTRY` using `--password-stdin` (credentials never on
the command line), pushes all three images, and removes credentials from the
local Docker credential store afterwards.

Use `--skip-dxo2` if the dx-o2-agents image was not built.

### 4 — Deploy to Kubernetes

```bash
build-scripts/deploy.sh
```

Steps performed:

1. Validates all required variables and cluster reachability.
2. Creates the target namespace if absent.
3. Renders a transient `values.local.yaml` with registry credentials, DB
   passwords, ingress configuration, and DX O2 settings from `.config`.
4. Runs `helm upgrade --install php-demo helm/php-demo`.
5. Deletes `values.local.yaml` immediately so no credentials remain on disk.
6. Runs `init_users.php` via `kubectl exec` to confirm DB connectivity.

Use `--skip-init` to bypass the post-deploy DB check.

### 5 — Kubernetes resources created by Helm

| Resource | Kind | Purpose |
|---|---|---|
| `<rel>-php-demo-registry-pull` | Secret (dockerconfigjson) | Registry pull credentials |
| `<rel>-php-demo` | ServiceAccount | Carries the pull secret; no API token mounted |
| `<rel>-php-demo-db-secret` | Secret (Opaque) | MariaDB passwords |
| `<rel>-php-demo-config` | ConfigMap | nginx + PHP-FPM runtime configuration |
| `<rel>-php-demo-db-init` | ConfigMap | schema.sql + seed.sql for MariaDB initialisation |
| `<rel>-php-demo` | Deployment | Pod with nginx + php-fpm + mariadb (+ dx-o2 sidecar) |
| `<rel>-php-demo` | Service | ClusterIP on port 8080 |
| `<rel>-php-demo` | Ingress | TLS termination via cert-manager |
| `<rel>-php-demo-mariadb-data` | PersistentVolumeClaim | MariaDB data directory (1 Gi) |

### 6 — Verify

```bash
# Watch pod come up (all containers must reach Running)
kubectl get pods -n php-demo -w

# List containers and images
kubectl get pod -n php-demo -l app.kubernetes.io/name=php-demo \
  -o jsonpath='{range .items[0].spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'

# Port-forward if ingress is not yet reachable
kubectl port-forward -n php-demo svc/php-demo-php-demo 8080:8080
# then open http://localhost:8080/
```

---

## Local development with Docker Compose

Docker Compose runs the application stack locally without a registry or TLS.
NGINX routes FastCGI to the `phpfpm` service by hostname rather than
`127.0.0.1`, so the containers run independently (not in a shared network
namespace as they do in Kubernetes).

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

`compose.sh` sources `.config`, exports the required environment variables, and
calls `package-app.sh` automatically before any build.  Only `REGISTRY`,
`IMAGE_PREFIX`, `IMAGE_TAG`, and the four `MARIADB_*` variables are required
for Compose; Kubernetes/Helm variables are ignored.

The application is reachable at **http://localhost:8080/** after `up`.

---

## DX O2 agent setup

> **Full guide:** see **[DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md)** for
> complete download instructions, installer structure, build walkthrough,
> runtime injection diagrams, verification steps, and troubleshooting.

### Components

All four Broadcom monitoring components ship in a **single installer archive**
(`apmia-<version>-linux.tar.gz`) downloaded from
[Broadcom Support](https://support.broadcom.com/):

| Component | Runs in | Path after install |
|---|---|---|
| Infrastructure Agent | `dx-o2-agent` sidecar | `bin/APMIAgent` |
| Business Transaction Listener (BTL) | `dx-o2-agent` sidecar | `bin/btl` |
| PHP Probe | `php-fpm` (injected at startup) | `extensions/PHPAgent/wily_php_agent.so` |
| BPA WebServer Plugin | `nginx` (injected at startup) | `extensions/WebServerPlugin/ngx_http_ca_plugin_filter_module.so` |

### How it works

Broadcom monitoring uses an **opportunistic injection** pattern so agent binaries
are never baked into the application images:

1. `dxo2-init` (Kubernetes initContainer) copies the pre-installed APMIA tree
   from `/opt/apmia` inside the dx-o2-agents image to a shared `emptyDir` volume.
2. `dx-o2-agent` (sidecar container) runs the Infrastructure Agent daemon and
   the BTL binary, connected to the Enterprise Manager.
3. The **php-fpm** entrypoint detects `wily_php_agent.ini` in the mounted
   volume and loads the PHP probe by copying the `.so` to PHP's `extension_dir`.
4. The **nginx** entrypoint detects the BPA `.so` in the mounted volume and
   writes a `load_module` directive to `/etc/nginx/modules-enabled/bpa.conf`.

Without the DX O2 image (or with `dxo2.enabled=false`), all containers start
cleanly with no agent overhead.

### Quick-start (Kubernetes)

```bash
# 1. Download apmia-<version>-linux.tar.gz from support.broadcom.com
#    and verify its checksum, then:
cp ~/Downloads/apmia-<version>-linux.tar.gz src/dx-o2-agents/installers/

# 2. Configure EM connection in .config
APMIA_EM_HOST="em.example.internal"
APMIA_EM_PORT="5001"
APMIA_AGENT_NAME="bpa-demo-agent"
APMIA_APP_NAME="BPA-Demo"
APMIA_LOG_LEVEL="INFO"

# 3. Build — Step 4 now builds dx-o2-agents
build-scripts/build.sh

# 4. Push all images including dx-o2-agents
build-scripts/push.sh

# 5. Deploy — deploy.sh sets dxo2.enabled=true when APMIA_EM_HOST is non-empty
build-scripts/deploy.sh
```

### Manual Helm override

```bash
helm upgrade --install php-demo helm/php-demo \
  --set dxo2.enabled=true \
  --set dxo2.emHost="em.example.internal" \
  --set dxo2.emPort="5001" \
  --set image.dxo2.repository="registry.example.com/php-demo/dx-o2-agents" \
  --set image.dxo2.tag="1.0.0b1"
```

---

## Registry credentials

Pull credentials flow from `.config` to Kubernetes through the following chain:

```
.config  (REGISTRY / REGISTRY_USER / REGISTRY_PASSWORD)
   │
   ▼  build-scripts/deploy.sh → values.local.yaml (deleted after deploy)
   │
   ▼  Helm: registry-secret.yaml
   │  Secret type: kubernetes.io/dockerconfigjson
   │  Name: <release>-php-demo-registry-pull
   │
   ▼  Helm: serviceaccount.yaml
   │  ServiceAccount: <release>-php-demo
   │  imagePullSecrets: [registry-pull]
   │  automountServiceAccountToken: false
   │
   ▼  Helm: deployment.yaml
      serviceAccountName: <release>-php-demo
      → kubelet uses the pull secret for all containers automatically
```

The registry Secret and `imagePullSecrets` are only rendered when both
`imageCredentials.username` and `imageCredentials.password` are non-empty,
so the chart works against a public registry with no credential configuration.

---

## Helm chart reference

Chart: `helm/php-demo` — version **0.2.0**

### Key values

| Value | Default | Description |
|---|---|---|
| `image.phpfpm.tag` | `1.0.0` | PHP-FPM image tag |
| `image.nginx.tag` | `1.0.0` | NGINX image tag |
| `image.dxo2.tag` | `1.0.0` | DX O2 agents image tag |
| `image.mariadb.tag` | `11` | MariaDB major version pin |
| `imageCredentials.registry` | `""` | Registry hostname |
| `imageCredentials.username` | `""` | Registry login — set via `values.local.yaml` |
| `imageCredentials.password` | `""` | Registry password — set via `values.local.yaml` |
| `service.port` | `8080` | ClusterIP service port |
| `ingress.enabled` | `true` | Toggle Ingress resource creation |
| `ingress.className` | `""` | IngressClass — set via `INGRESS_CLASS_NAME` in `.config` |
| `persistence.enabled` | `true` | Use a PVC for MariaDB data |
| `persistence.size` | `1Gi` | PVC capacity |
| `mariadb.auth.rootPassword` | _(required)_ | MariaDB root password |
| `mariadb.auth.password` | _(required)_ | Application DB password |
| `dxo2.enabled` | `false` | Enable DX O2 agent sidecar and probe injection |
| `dxo2.emHost` | `""` | Enterprise Manager hostname (required when enabled) |
| `dxo2.emPort` | `5001` | EM collector port |
| `dxo2.agentName` | `bpa-demo-agent` | Logical agent name in the EM console |
| `dxo2.appName` | `BPA-Demo` | Application name for metric grouping |
| `dxo2.logLevel` | `INFO` | Agent log verbosity: DEBUG \| INFO \| WARN \| ERROR |

### Manual Helm install (without deploy.sh)

```bash
helm upgrade --install php-demo helm/php-demo \
  --namespace php-demo --create-namespace \
  --set imageCredentials.registry="registry.example.com" \
  --set imageCredentials.username="<user>" \
  --set imageCredentials.password="<password>" \
  --set mariadb.auth.rootPassword="<root-pw>" \
  --set mariadb.auth.password="<user-pw>" \
  --set image.phpfpm.repository="registry.example.com/php-demo/php-fpm" \
  --set image.nginx.repository="registry.example.com/php-demo/nginx" \
  --set ingress.hosts[0].host="php-demo.example.com" \
  --set ingress.tls[0].hosts[0]="php-demo.example.com" \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=letsencrypt-prod'
```

---

## Updating configuration without rebuilding

NGINX and PHP-FPM runtime configuration lives in
`helm/php-demo/templates/configmap.yaml` and is mounted over image defaults at
pod start.  Edit the ConfigMap and re-run `deploy.sh` — the pod restarts
automatically because the deployment template includes a `checksum/config`
annotation that changes whenever the ConfigMap content changes.

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

MariaDB reinitialises automatically from the SQL files embedded in the
`db-init` ConfigMap (`helm/php-demo/sql/schema.sql` + `seed.sql`).

---

## BPA-Demo application

### Overview

| Brand | Products | Protocols |
|---|---|---|
| Shelly | 100 | WiFi, Matter (Gen3), Bluetooth (BLU series), Z-Wave (Qubino Wave) |
| SonOff | 100 | WiFi, Zigbee, Matter |
| Tuya | 100 | WiFi, Zigbee, Matter, Bluetooth, Tuya protocol |

### Demo accounts

All accounts use the password **`demo123`** (automatically upgraded to bcrypt on
first successful login; stored as `$SETUP$...` in the DB until then).

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

Every response carries the following headers for APM and tracing:

| Header | Format | Example |
|---|---|---|
| `X-Page-ID` | `MODULE-ACTION-TARGET` | `SHOP-LIST-SHELLY` |
| `X-User-Role` | `anonymous \| user \| admin` | `user` |
| `X-Basket-Total` | EUR float | `49.80` |
| `X-Alert` | string (on errors) | `LOGIN_FAILED` |
| `X-Use-Case` | use-case name | `trouble` |

### Use-case system

Use cases are PHP files in `app/src/usecases/<name>.php`, each defining
`usecase_<name>(PDO $db, array &$ctx): void`.

| Use case | Effect |
|---|---|
| `trouble` | 5 000 sequential DB reads against 300 product IDs per request |
| `empty_basket` | Forces `basket_total()` to return `0.00` |

The admin panel assigns or removes use cases per user.

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

SQL files live in `helm/php-demo/sql/` and are embedded in the `db-init`
ConfigMap (`db-init-configmap.yaml`), mounted at
`/docker-entrypoint-initdb.d/` in the MariaDB container.  They run
automatically on first start when the data directory is empty.

---

## Security update cron job

Each custom image installs a `cron.d` rule that runs `apt-get upgrade` once
per day.  The jobs are offset to avoid simultaneous load:

```
php-fpm:  03:15 daily  (root)
nginx:    03:30 daily  (root)
```

The `entrypoint.sh` of each container starts `cron` before the main process.

> In-container upgrades complement, but do not replace, image rebuilds.  The
> recommended practice is to rebuild and redeploy images whenever upstream
> Ubuntu security notices (USNs) are published.
