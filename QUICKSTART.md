# BPA-Demo — Quick Deployment Guide

---

## Prerequisites

| Tool | Notes |
|---|---|
| Docker 24+ (with Compose plugin) | `docker compose version` |
| `kubectl` 1.28+ | Pointed at the target cluster |
| `helm` 3.12+ | Kubernetes deploy only |
| cert-manager + Ingress controller | Cluster-side, for TLS |

---

## 1 — Configuration

```bash
cp .config.example .config
$EDITOR .config          # fill in all required variables
```

Minimum required variables:

```bash
REGISTRY / REGISTRY_USER / REGISTRY_PASSWORD
IMAGE_PREFIX / IMAGE_TAG
MARIADB_ROOT_PASSWORD / MARIADB_DATABASE / MARIADB_USER / MARIADB_PASSWORD
APP_NAMESPACE / APP_HOSTNAME / TLS_CLUSTER_ISSUER / INGRESS_CLASS_NAME / KUBECONFIG
```

Add these for DX O2 monitoring (optional):

```bash
DEPLOYMENT_NAME / DEPLOYMENT_POSTFIX   # e.g. "bpa-demo" / "k8s" -> "bpa-demo-k8s";
                                        # keeps this deployment's agents distinct
                                        # from a Compose deployment on the same tenant
APMIA_EM_HOST="placeholder"   # any non-empty value enables the agent sidecar
```

---

## 2 — Build

```bash
# Bump build counter + package app source (run once per new release)
build-scripts/package-app.sh

# Build all Docker images
build-scripts/build.sh
```

**Kubernetes only** — push images to the registry:

```bash
build-scripts/push.sh
```

> If the DX O2 agent packages are absent from `src/dx-o2-agents/installers/`,
> the `dx-o2-agents` image is skipped. Use `push.sh --skip-dxo2` in that case.

> **Local Docker Compose:** skip `push.sh` entirely. `compose.sh` builds images
> directly into the local Docker store and runs them from there — no registry
> needed.

---

## 3 — Kubernetes deploy

```bash
build-scripts/deploy.sh
```

This generates a transient `values.local.yaml` from `.config`, runs
`helm upgrade --install`, then deletes the file immediately.

Verify:

```bash
kubectl get pods -n php-demo -w
curl -sk https://<APP_HOSTNAME>/health   # expected: OK
```

---

## 4 — Local dev (Docker Compose)

```bash
build-scripts/compose.sh up -d     # start stack
build-scripts/compose.sh logs -f   # tail logs
build-scripts/compose.sh down -v   # stop + wipe DB volume
```

App available at **http://localhost:8080/**.

The `traffic` service starts automatically alongside the app and generates
synthetic shopper traffic (login/browse/basket/checkout) across all demo
accounts, including the `trouble`/`empty`/`locked` use-case users. Set
`TRAFFIC_ENABLED="false"` in `.config` to disable it. See
[traffic-generator/README.md](traffic-generator/README.md).

---

## 5 — Default accounts

Password for all accounts: **`demo123`**

| Username | Role | Notes |
|---|---|---|
| `admin` | admin | Admin panel + diagnostics (`?page=dxo2`, `?page=info`, `?page=db`) |
| `alice` … `jack` | user | Regular shoppers |
| `trouble` | user | 5 000 DB reads per request (APM load demo) |
| `empty` | user | Basket total always €0.00 |
| `locked` | user | Login blocked |

---

## 6 — DX O2 tenant configuration (optional)

Once the app is deployed with DX O2 monitoring enabled (`APMIA_EM_HOST` set)
and has taken some traffic — the `traffic` Compose service (see step 4) or
its standalone container (`traffic-generator/`) can generate this
automatically — set up the full console-side view (Service, Management
Module, Alerts, Universes, SLI, Dashboard) with the scripts in
`dxo2-scripts/` — no AI assistant required, just the `dx-do` CLI (see
`dxo2-scripts/README.md` for setup). Run them in this order:

```bash
dxo2-scripts/bpa-demo-service.sh create                  # "BPA-Demo" Service
dxo2-scripts/bpa-demo-management-module.sh create        # MM + trouble-use-case alert
dxo2-scripts/bpa-demo-agent-alerts.sh create              # 12 more alerts (DB, PHP, browser/RUM)
dxo2-scripts/bpa-demo-universe.sh create                  # APM Universe (topology/metric scope)
dxo2-scripts/bpa-demo-services-universe.sh create         # O2/Platform ("Services") Universe
dxo2-scripts/bpa-demo-sli.sh create                       # "BPA-Demo Frontend Response Time" SLI
dxo2-scripts/bpa-demo-agent-health-dashboard.sh create    # "BPA-Demo · Agent Health" Dashboard
```

Every script supports `create` (safe to re-run — self-heals a
previously-broken definition instead of just no-op'ing), `check`, and
`delete`. `bpa-demo-agent-alerts.sh` depends on
`bpa-demo-management-module.sh` having been run first;
`bpa-demo-agent-health-dashboard.sh` reuses the alerts both of those create.

**One exception:** `bpa-demo-services-universe.sh create` cannot create its
Universe from nothing — `o2-universe create` always produces an unscoped
Universe that crashes the console's own edit UI. The *first* one must be
created by hand in the console (New Universe, scope both views to the
`"BPA-Demo"` Service); after that, `create` finds and self-heals it like
the rest. See the script's own header comment and
[DX-O2_MANUAL_CONFIGURATION.md](DX-O2_MANUAL_CONFIGURATION.md) for the
exact steps.

A handful of other tenant-side settings similarly have no CLI path at all
(mainly around SLI filter/SLO tuning) and must be configured by hand in the
console too — see
[DX-O2_MANUAL_CONFIGURATION.md](DX-O2_MANUAL_CONFIGURATION.md) for exactly
which ones, the values to use, and why they can't be scripted.

---

## 7 — Tear down

```bash
helm uninstall php-demo -n php-demo
kubectl delete pvc -n php-demo --all
kubectl delete namespace php-demo   # optional
```

---

> Full documentation: [README.md](README.md) | DX O2 agent setup: [DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md) | DX O2 tenant config scripts: [dxo2-scripts/README.md](dxo2-scripts/README.md)
