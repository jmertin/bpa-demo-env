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
APMIA_AGENT_NAME / APMIA_APP_NAME / APMIA_HOST_NAME
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

## 6 — Tear down

```bash
helm uninstall php-demo -n php-demo
kubectl delete pvc -n php-demo --all
kubectl delete namespace php-demo   # optional
```

---

> Full documentation: [README.md](README.md) | DX O2 agent setup: [DX-O2-AGENT-SETUP.md](DX-O2-AGENT-SETUP.md)
