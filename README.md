# BPA-Demo – Smart Home Device Web Shop on Kubernetes

A full-stack PHP demo web shop selling home-assistant compatible devices
(Shelly, SonOff, Tuya) deployed as a single Kubernetes pod containing three
containers: **nginx**, **PHP-FPM**, and **MariaDB**.  All custom images are
built on Ubuntu 26.04 LTS minimal.

The application ships 150 products across three brands, a session-based
shopping basket, fake credit-card checkout, an admin panel with per-user
use-case assignment, and monitoring HTTP headers on every response.

---

## Project structure

```
.
├── .gitignore                    # excludes .config and all generated artifacts
├── .config.example               # template – copy to .config and fill in values
├── README.md                     # this file
│
├── app/
│   └── src/                      # PHP application source code
│       ├── index.php             # BPA-Demo front-controller (routes via ?page=)
│       ├── config/               # app bootstrap, PDO singleton
│       ├── lib/                  # validators, auth, product, basket, order, usecase, headers
│       ├── pages/                # shop, product, basket, checkout, order, login, admin
│       ├── templates/            # layout.php (full CSS), footer.php
│       ├── usecases/             # trouble.php, empty_basket.php
│       └── setup/                # init_users.php (CLI only, blocked by nginx)
│
├── docker/
│   ├── php-fpm/                  # Ubuntu 26.04 + PHP-FPM image
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh         # starts cron daemon then php-fpm -F -R
│   │   └── config/
│   │       ├── php-fpm.conf      # global config (no daemon, log to stderr)
│   │       ├── www.conf          # pool: TCP 0.0.0.0:9000, workers as www-data
│   │       └── security-updates  # cron.d rule – daily apt upgrade at 03:15
│   │
│   └── nginx/                    # Ubuntu 26.04 + nginx image
│       ├── Dockerfile
│       ├── entrypoint.sh         # starts cron daemon then nginx -g 'daemon off;'
│       └── config/
│           ├── nginx.conf        # main config, temp dirs in /tmp
│           ├── default.conf      # listen 8080, fastcgi_pass 127.0.0.1:9000
│           └── security-updates  # cron.d rule – daily apt upgrade at 03:30
│
├── scripts/
│   ├── package-app.sh            # tar.gz app/src → docker/php-fpm/app.tar.gz
│   ├── build.sh                  # calls package-app.sh, then docker build both images
│   ├── push.sh                   # docker login (via printf pipe) + push both images
│   └── deploy.sh                 # renders values.local.yaml from .config, helm upgrade --install
│
└── helm/
    └── php-demo/
        ├── Chart.yaml
        ├── values.yaml           # all defaults – no secrets, no registry credentials
        ├── .helmignore           # excludes values.local.yaml
        ├── sql/
        │   ├── schema.sql        # 8-table MariaDB schema
        │   └── seed.sql          # 3 brands, 6 caps, 150 products, 13 demo users
        └── templates/
            ├── _helpers.tpl
            ├── deployment.yaml         # single pod with 3 containers
            ├── serviceaccount.yaml     # ServiceAccount with imagePullSecrets attached
            ├── registry-secret.yaml    # kubernetes.io/dockerconfigjson pull secret
            ├── db-init-configmap.yaml  # embeds schema.sql + seed.sql for MariaDB init
            ├── service.yaml            # ClusterIP on port 8080
            ├── ingress.yaml            # TLS ingress with cert-manager annotation
            ├── configmap.yaml          # nginx + PHP-FPM configs (mounted over image defaults)
            ├── secret.yaml             # MariaDB credentials from Helm values
            ├── pvc.yaml                # 1 Gi PersistentVolumeClaim for MariaDB data
            └── NOTES.txt
```

---

## Architecture

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
┌─────────────────────────────────────────────────────┐
│  Pod: php-demo                                      │
│                                                     │
│  [nginx]       listen 8080   ◄── external traffic   │
│      │  FastCGI → 127.0.0.1:9000                   │
│  [php-fpm]     listen 9000                          │
│      │  PDO/MySQLi → 127.0.0.1:3306                │
│  [mariadb:11]  listen 3306                          │
│      │  data → PersistentVolumeClaim                │
└─────────────────────────────────────────────────────┘
```

All three containers share the same network namespace within the pod, so they
communicate via `127.0.0.1` without any inter-pod routing.

---

## Design decisions

| Requirement | Implementation |
|---|---|
| Non-privileged ports | nginx 8080 · PHP-FPM 9000 · MariaDB 3306 (all ≥ 1024) |
| Ubuntu 26.04 LTS minimal base | `FROM ubuntu:26.04` with `--no-install-recommends` on every `apt-get` |
| PHP from Ubuntu repos only | `php-fpm` + `php-mysql` packages; PHP version auto-discovered at build time via symlinks |
| MariaDB major version locked | Official `mariadb:11` image tag |
| Security updates inside containers | `cron.d` rule in each custom image; cron daemon started by entrypoint before the main service |
| Application as tar archive | `package-app.sh` creates `app.tar.gz`; Dockerfile COPYs and extracts it into `/var/www/html` |
| Registry credentials in Kubernetes | `kubernetes.io/dockerconfigjson` Secret managed by Helm; attached to the pod's dedicated ServiceAccount so the kubelet inherits pull credentials automatically |
| Secrets never in git | `.config` is gitignored; `values.local.yaml` is generated at deploy time and deleted immediately after |
| Minimal image footprint | Only runtime packages installed; no build tools or dev headers left in the final image |
| Signed/official sources only | Ubuntu apt (signed with Ubuntu GPG key) + official `mariadb` Docker Hub image |
| Kubernetes TLS | Ingress annotated with `cert-manager.io/cluster-issuer`; TLS secret managed by cert-manager |
| Config/credentials isolation | All variables centralised in `.config`; every script sources it at runtime |

---

## Prerequisites

| Tool | Minimum version |
|---|---|
| Docker | 24.x |
| kubectl | 1.28+ |
| helm | 3.12+ |
| cert-manager (cluster) | 1.13+ |
| nginx Ingress controller | any |

---

## Quick start

### 1 — Configure

```bash
cp .config.example .config
$EDITOR .config
```

Fill in every variable.  The file is shell-sourced by all scripts and must
never be committed to git (it is already listed in `.gitignore`):

```bash
# Docker Registry
REGISTRY="registry.example.com"
REGISTRY_USER="admin"
REGISTRY_PASSWORD="changeme"

# Image settings
IMAGE_PREFIX="php-demo"
IMAGE_TAG="1.0.0"
BUILD_PLATFORM="linux/amd64"

# MariaDB credentials
MARIADB_ROOT_PASSWORD="changeme_root"
MARIADB_DATABASE="phpapp"
MARIADB_USER="phpuser"
MARIADB_PASSWORD="changeme_user"

# Kubernetes / Helm deployment
APP_NAMESPACE="php-demo"
APP_HOSTNAME="php-demo.example.com"
TLS_CLUSTER_ISSUER="letsencrypt-prod"
INGRESS_CLASS_NAME="nginx"          # e.g. nginx, traefik, haproxy, alb
KUBECONFIG="${HOME}/.kube/config"
```

### 2 — Build images

```bash
./scripts/build.sh
```

Steps performed:

1. Calls `package-app.sh` to produce `docker/php-fpm/app.tar.gz` from `app/src/`.
2. Builds the **php-fpm** image (`docker/php-fpm/Dockerfile`) with `--no-cache --pull`.
3. Builds the **nginx** image (`docker/nginx/Dockerfile`) with `--no-cache --pull`.
4. Removes the temporary archive.

Both images are tagged `<REGISTRY>/<IMAGE_PREFIX>/php-fpm:<IMAGE_TAG>` and
`…/nginx:<IMAGE_TAG>`.

### 3 — Push images to registry

```bash
./scripts/push.sh
```

Authenticates with the registry and pushes both images.  The password is piped
via `printf '%s'` (not `echo`) to avoid the trailing newline that some registry
daemons reject when reading credentials from stdin.

### 4 — Deploy to Kubernetes

```bash
./scripts/deploy.sh
```

Steps performed:

1. Creates the target namespace if it does not already exist.
2. Renders `values.local.yaml` with all sensitive and environment-specific
   values sourced from `.config` — including registry credentials, MariaDB
   passwords, hostname, and TLS issuer.
3. Runs `helm upgrade --install php-demo helm/php-demo` with both
   `values.yaml` (checked-in defaults) and `values.local.yaml` (overrides).
4. Deletes `values.local.yaml` immediately after the Helm call returns so no
   credentials remain on disk.

Helm creates or updates the following Kubernetes resources:

| Resource | Kind | Purpose |
|---|---|---|
| `php-demo-registry-pull` | Secret (dockerconfigjson) | Registry pull credentials |
| `php-demo` | ServiceAccount | Carries the pull secret; mounts no API token |
| `php-demo-db-secret` | Secret (Opaque) | MariaDB passwords |
| `php-demo-config` | ConfigMap | nginx and PHP-FPM runtime configuration |
| `php-demo` | Deployment | Single pod with nginx + php-fpm + mariadb |
| `php-demo` | Service | ClusterIP on port 8080 |
| `php-demo` | Ingress | TLS termination via cert-manager |
| `php-demo-mariadb-data` | PersistentVolumeClaim | MariaDB data directory |

### 5 — Verify the deployment

```bash
# Watch pod come up (all 3/3 containers must reach Running)
kubectl get pods -n php-demo -w

# List containers and their images
kubectl get pod -n php-demo -l app.kubernetes.io/name=php-demo \
  -o jsonpath='{range .items[0].spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'

# Port-forward if the ingress is not yet reachable
kubectl port-forward -n php-demo svc/php-demo 8080:8080
# then open http://localhost:8080/
```

The demo application exposes three pages:

| Path | Description |
|---|---|
| `/` | Home – pod layout summary |
| `/db` | Live MariaDB connection test (server version, uptime) |
| `/info` | PHP runtime details (version, loaded extensions) |

---

## Application deployment detail

The application source lives in `app/src/`.  Before an image build it is
packaged into a tar archive by `package-app.sh`:

```bash
./scripts/package-app.sh
# → docker/php-fpm/app.tar.gz
```

The PHP-FPM Dockerfile then deploys it during image creation:

```dockerfile
COPY app.tar.gz /tmp/app.tar.gz
RUN  mkdir -p /var/www/html && \
     tar -xzf /tmp/app.tar.gz -C /var/www/html && \
     chown -R www-data:www-data /var/www/html && \
     rm /tmp/app.tar.gz
```

To ship a new version of the application: update the files under `app/src/`,
bump `IMAGE_TAG` in `.config`, then re-run `build.sh` → `push.sh` → `deploy.sh`.

---

## Security update cron job

Each custom image (`php-fpm`, `nginx`) installs a `cron.d` rule that runs a
full security upgrade once per day.  The two jobs are offset by 15 minutes to
avoid simultaneous load:

```cron
# php-fpm: 03:15 daily
15 3 * * * root apt-get update -qq && apt-get upgrade -y -q --with-new-pkgs && apt-get clean -qq

# nginx: 03:30 daily
30 3 * * * root apt-get update -qq && apt-get upgrade -y -q --with-new-pkgs && apt-get clean -qq
```

The `entrypoint.sh` of each container calls `service cron start` before
launching the main process so the cron daemon is always available.

> **Note:** In-container package upgrades complement, but do not replace, image
> rebuilds.  The recommended production practice is to rebuild and redeploy
> images whenever upstream Ubuntu security notices are published.

---

## Registry credentials

Pull credentials flow from `.config` to Kubernetes through the following chain:

```
.config  (REGISTRY / REGISTRY_USER / REGISTRY_PASSWORD)
   │
   ▼  scripts/deploy.sh → values.local.yaml (deleted after deploy)
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
      → kubelet uses the pull secret for all three containers automatically
```

Key points:

- The registry Secret and the `imagePullSecrets` reference on the ServiceAccount
  are only rendered when `imageCredentials.username` **and**
  `imageCredentials.password` are both non-empty.  The chart therefore works
  against a public registry without any credential configuration.
- `automountServiceAccountToken: false` on the ServiceAccount prevents
  Kubernetes from mounting a cluster API token into the pod, which is not
  needed and reduces the attack surface.
- The `values.local.yaml` file that carries the plaintext password is deleted
  immediately after `helm upgrade` returns; it is also listed in `.helmignore`
  and `.gitignore` so it can never be accidentally committed or packaged.

---

## Helm chart reference

### Key values (`helm/php-demo/values.yaml`)

| Value | Default | Description |
|---|---|---|
| `image.phpfpm.tag` | `1.0.0` | php-fpm image tag |
| `image.nginx.tag` | `1.0.0` | nginx image tag |
| `image.mariadb.tag` | `11` | MariaDB major version pin |
| `imageCredentials.registry` | `""` | Registry hostname, e.g. `registry.example.com` |
| `imageCredentials.username` | `""` | Registry login – set via `values.local.yaml` |
| `imageCredentials.password` | `""` | Registry password – set via `values.local.yaml` |
| `service.port` | `8080` | ClusterIP service port |
| `ingress.enabled` | `true` | Toggle Ingress resource creation |
| `ingress.className` | `""` | IngressClass name – set via `INGRESS_CLASS_NAME` in `.config` |
| `persistence.enabled` | `true` | Use a PVC for MariaDB data |
| `persistence.size` | `1Gi` | PVC capacity |
| `mariadb.auth.database` | `phpapp` | Database name |
| `mariadb.auth.username` | `phpuser` | Application DB user |
| `mariadb.auth.rootPassword` | _(required)_ | MariaDB root password |
| `mariadb.auth.password` | _(required)_ | Application DB password |

All sensitive values are supplied at deploy time via `values.local.yaml`
(generated by `deploy.sh`) or via `--set`.  They are never stored in the
checked-in `values.yaml`.

### Manual Helm install (without deploy.sh)

```bash
helm upgrade --install php-demo helm/php-demo \
  --namespace php-demo --create-namespace \
  --set imageCredentials.registry="registry.example.com" \
  --set imageCredentials.username="<registry-user>" \
  --set imageCredentials.password="<registry-password>" \
  --set mariadb.auth.rootPassword="<root-pw>" \
  --set mariadb.auth.password="<user-pw>" \
  --set image.phpfpm.repository="registry.example.com/php-demo/php-fpm" \
  --set image.nginx.repository="registry.example.com/php-demo/nginx" \
  --set ingress.hosts[0].host="php-demo.example.com" \
  --set ingress.tls[0].hosts[0]="php-demo.example.com" \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=letsencrypt-prod'
```

---

## Updating configuration without rebuilding images

The nginx and PHP-FPM runtime configurations are stored in a Kubernetes
ConfigMap (`templates/configmap.yaml`) and mounted over the image-baked defaults
at pod start.  To change nginx or PHP-FPM settings without a new image build,
edit `helm/php-demo/templates/configmap.yaml` and re-run `deploy.sh` (or
`helm upgrade`).  Kubernetes will roll the pod to pick up the new ConfigMap.

---

## Removing the deployment

```bash
helm uninstall php-demo --namespace bpa-demo

# Optionally remove persistent data and the namespace
kubectl delete pvc -n bpa-demo --all
kubectl delete namespace bpa-demo
```

## Resetting the database

`helm upgrade` preserves the MariaDB PVC across releases to protect existing
data.  To wipe the database and reseed from scratch (e.g. after schema changes):

```bash
helm uninstall php-demo -n bpa-demo
kubectl delete pvc php-demo-php-demo-mariadb-data -n bpa-demo
./scripts/deploy.sh
```

MariaDB will reinitialise automatically from the SQL files embedded in the
`db-init` ConfigMap (`helm/php-demo/sql/schema.sql` + `seed.sql`).

---

## BPA-Demo application

### Overview

The application is a web shop for home-assistant compatible smart devices.

| Brand  | Products | Protocols |
|--------|----------|-----------|
| Shelly | 50       | WiFi, Matter (Gen3), Bluetooth (BLU series), Z-Wave (Qubino Wave) |
| SonOff | 50       | WiFi, Zigbee, Matter |
| Tuya   | 50       | WiFi, Zigbee, Matter, Bluetooth, Tuya protocol |

### Demo accounts

All accounts use the password **`demo123`** (upgraded to bcrypt on first login).

| Username | Role  | Behaviour |
|----------|-------|-----------|
| `admin`  | admin | Full access to the admin panel |
| `trouble`| user  | **Use case: trouble** — 5000 sequential DB reads per request |
| `empty`  | user  | **Use case: empty_basket** — basket total always shown as €0.00 |
| `alice` … `jack` | user | Regular accounts (10 users) |

### Application routes

| URL | Description |
|-----|-------------|
| `?page=shop` | Product grid with filter bar (default) |
| `?page=shop&brand=<slug>` | Filter by brand (shelly / sonoff / tuya) |
| `?page=shop&cap=<slug>` | Filter by protocol |
| `?page=shop&q=<search>` | Full-text search |
| `?page=product&slug=<slug>` | Product detail |
| `?page=basket` | Shopping basket |
| `?page=checkout` | Billing + fake credit-card payment |
| `?page=order&id=<id>` | Order confirmation |
| `?page=order` | Order history (login required) |
| `?page=login` | Sign in |
| `?page=admin` | Admin panel (admin role required) |

### Monitoring HTTP headers

Every response carries the following headers for APM / tracing:

| Header | Format | Example |
|--------|--------|---------|
| `X-Page-ID` | `MODULE-ACTION-TARGET` | `SHOP-LIST-SHELLY` |
| `X-User-Role` | `anonymous \| user \| admin` | `user` |
| `X-Basket-Total` | EUR float | `49.80` |
| `X-Alert` | string (on errors) | `LOGIN_FAILED` |
| `X-Use-Case` | use-case name | `trouble` |

### Use-case system

Use cases are PHP files in `app/src/usecases/<name>.php`.  Each file defines a
function `usecase_<name>(PDO $db, array &$ctx): void`.

| Use case | File | Effect |
|----------|------|--------|
| `trouble` | `usecases/trouble.php` | 5000 sequential DB reads (degrades response time) |
| `empty_basket` | `usecases/empty_basket.php` | Forces `basket_total()` to return 0.00 |

The admin panel allows assigning or removing a use case for any user.

### Database schema

Eight tables:

```
brands            → id, name, slug, color, description
capabilities      → id, name, slug, color
products          → id, brand_id, name, slug, description, price, stock
product_capabilities → product_id, capability_id
users             → id, username, password_hash, email, role, full_name, created_at
user_usecases     → user_id, usecase_name, assigned_by, assigned_at
orders            → id, user_id, session_id, status, subtotal, total,
                    billing_name, billing_email, cc_last4, created_at
order_items       → id, order_id, product_id, product_name, quantity, unit_price
```

The SQL files live in `helm/php-demo/sql/` and are embedded in a Kubernetes
ConfigMap (`db-init-configmap.yaml`) mounted at
`/docker-entrypoint-initdb.d/` in the MariaDB container.  They run
automatically on the first start when the data directory is empty.

### Application structure

```
app/src/
├── index.php               Front-controller (routes via ?page=)
├── config/
│   ├── app.php             Session bootstrap, CSRF helpers
│   └── database.php        PDO singleton (reads env vars)
├── lib/
│   ├── validate.php        Input validators (string, int, email, price, CC, …)
│   ├── page_id.php         Monitoring header helpers
│   ├── auth.php            Login, logout, role guards, $SETUP$ upgrade
│   ├── product.php         Catalogue queries with filter/pagination
│   ├── basket.php          Session basket with use-case override
│   ├── order.php           Order creation and retrieval
│   └── usecase.php         Use-case loader and admin helpers
├── pages/
│   ├── shop.php            Product listing + filters
│   ├── product.php         Product detail
│   ├── basket.php          Basket management (POST–Redirect–GET)
│   ├── checkout.php        Billing form + Luhn-validated CC payment
│   ├── order.php           Confirmation and history
│   ├── login.php / logout.php
│   └── admin.php           Stats, user list, use-case assignment
├── templates/
│   ├── layout.php          Full HTML shell with embedded CSS
│   └── footer.php          Closing tags and footer bar
├── usecases/
│   ├── trouble.php         5000 sequential reads
│   └── empty_basket.php    Forced zero total
└── setup/
    └── init_users.php      CLI DB connectivity check (not web-accessible)
```
