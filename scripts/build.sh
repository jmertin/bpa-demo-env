#!/usr/bin/env bash
# Build all custom Docker images.
# Reads all configuration from .config in the project root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

# shellcheck source=../.config
source "${ROOT_DIR}/.config"

PHP_FPM_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/php-fpm:${IMAGE_TAG}"
NGINX_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/nginx:${IMAGE_TAG}"

echo "=== Build configuration ==="
echo "  Registry  : ${REGISTRY}"
echo "  Tag       : ${IMAGE_TAG}"
echo "  Platform  : ${BUILD_PLATFORM}"
echo ""

# ── Step 1: package application archive ─────────────────────────────────────
echo "── Packaging application ──"
"${SCRIPT_DIR}/package-app.sh"
echo ""

# ── Step 2: build php-fpm image ─────────────────────────────────────────────
echo "── Building php-fpm image: ${PHP_FPM_IMAGE} ──"
docker build \
    --platform "${BUILD_PLATFORM}" \
    --pull \
    --no-cache \
    -t "${PHP_FPM_IMAGE}" \
    "${ROOT_DIR}/docker/php-fpm/"
echo ""

# ── Step 3: build nginx image ────────────────────────────────────────────────
echo "── Building nginx image: ${NGINX_IMAGE} ──"
docker build \
    --platform "${BUILD_PLATFORM}" \
    --pull \
    --no-cache \
    -t "${NGINX_IMAGE}" \
    "${ROOT_DIR}/docker/nginx/"
echo ""

# ── Cleanup intermediate artifacts ──────────────────────────────────────────
rm -f "${ROOT_DIR}/docker/php-fpm/app.tar.gz"

echo "=== All images built successfully ==="
echo "  ${PHP_FPM_IMAGE}"
echo "  ${NGINX_IMAGE}"
