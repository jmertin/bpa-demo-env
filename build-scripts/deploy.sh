#!/usr/bin/env bash
# Deploy (or upgrade) the Helm release to Kubernetes.
# Generates a local values override file from .config – this file is never
# committed to git.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
HELM_CHART="${ROOT_DIR}/helm/php-demo"
LOCAL_VALUES="${HELM_CHART}/values.local.yaml"

# shellcheck source=../.config
source "${ROOT_DIR}/.config"

export KUBECONFIG

echo "=== Generating local Helm values override ==="
cat > "${LOCAL_VALUES}" <<EOF
# Auto-generated from .config by deploy.sh – do NOT commit.
image:
  phpfpm:
    repository: ${REGISTRY}/${IMAGE_PREFIX}/php-fpm
    tag: "${IMAGE_TAG}"
  nginx:
    repository: ${REGISTRY}/${IMAGE_PREFIX}/nginx
    tag: "${IMAGE_TAG}"

ingress:
  className: "${INGRESS_CLASS_NAME}"
  hosts:
    - host: ${APP_HOSTNAME}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: php-demo-tls
      hosts:
        - ${APP_HOSTNAME}
  annotations:
    cert-manager.io/cluster-issuer: "${TLS_CLUSTER_ISSUER}"

mariadb:
  auth:
    rootPassword: "${MARIADB_ROOT_PASSWORD}"
    database: "${MARIADB_DATABASE}"
    username: "${MARIADB_USER}"
    password: "${MARIADB_PASSWORD}"

imageCredentials:
  registry: "${REGISTRY}"
  username: "${REGISTRY_USER}"
  password: "${REGISTRY_PASSWORD}"
EOF

echo "=== Deploying Helm release 'php-demo' to namespace '${APP_NAMESPACE}' ==="
kubectl get namespace "${APP_NAMESPACE}" &>/dev/null || \
    kubectl create namespace "${APP_NAMESPACE}"

helm upgrade --install php-demo "${HELM_CHART}" \
    --namespace "${APP_NAMESPACE}" \
    --values "${HELM_CHART}/values.yaml" \
    --values "${LOCAL_VALUES}" \
    --wait \
    --timeout 5m

# Remove sensitive override file after deployment
rm -f "${LOCAL_VALUES}"

echo ""
echo "=== Deployment complete ==="
helm status php-demo --namespace "${APP_NAMESPACE}"

# ── Optional: run DB init check via kubectl exec ──────────────────────────────
# Wait for the php-fpm container to be ready, then run the setup check script.
echo ""
echo "=== Running DB init check (setup/init_users.php) ==="
POD=$(kubectl get pods -n "${APP_NAMESPACE}" \
    -l app.kubernetes.io/name=php-demo \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -n "${POD}" ]; then
    kubectl exec -n "${APP_NAMESPACE}" "${POD}" -c php-fpm -- \
        php /var/www/html/setup/init_users.php || true
else
    echo "  (pod not found – skipping init check)"
fi
