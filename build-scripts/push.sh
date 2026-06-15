#!/usr/bin/env bash
# Push built images to the configured registry.
# Images must be built first via build.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

# shellcheck source=../.config
source "${ROOT_DIR}/.config"

PHP_FPM_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/php-fpm:${IMAGE_TAG}"
NGINX_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/nginx:${IMAGE_TAG}"

echo "=== Authenticating with registry: ${REGISTRY} ==="
# printf '%s' avoids the trailing newline that echo appends, which some
# registry daemons reject when reading credentials from stdin.
printf '%s' "${REGISTRY_PASSWORD}" | \
    docker login "${REGISTRY}" \
        --username "${REGISTRY_USER}" \
        --password-stdin

echo ""
echo "── Pushing ${PHP_FPM_IMAGE} ──"
docker push "${PHP_FPM_IMAGE}"

echo ""
echo "── Pushing ${NGINX_IMAGE} ──"
docker push "${NGINX_IMAGE}"

echo ""
echo "=== All images pushed successfully ==="
