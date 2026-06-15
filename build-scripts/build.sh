#!/usr/bin/env bash
# Build all custom Docker images.
# Reads all configuration from .config in the project root.
# Auto-increments a local build counter (.build_number) and appends it to
# IMAGE_TAG as b<N> (e.g. 1.0.0b4) so every build produces a distinct tag
# that Kubernetes cannot skip due to a cached image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

# shellcheck source=../.config
source "${ROOT_DIR}/.config"

# ── Build number ───────────────────────────────────────────────────────────────
BUILD_FILE="${ROOT_DIR}/.build_number"
BUILD_NUM=$(( $(cat "${BUILD_FILE}" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "${BUILD_NUM}" > "${BUILD_FILE}"

# Strip any existing b<N> suffix from IMAGE_TAG so the base version is clean
# whether .config currently holds "1.0.0" or "1.0.0b3".
BASE_TAG="${IMAGE_TAG%%b*}"
FULL_TAG="${BASE_TAG}b${BUILD_NUM}"

# Write the new full tag back into .config so push.sh and deploy.sh pick it
# up automatically without any extra arguments.
sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=\"${FULL_TAG}\"|" "${ROOT_DIR}/.config"

# Re-source to get the updated IMAGE_TAG into this shell's environment.
source "${ROOT_DIR}/.config"

PHP_FPM_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/php-fpm:${IMAGE_TAG}"
NGINX_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/nginx:${IMAGE_TAG}"
DXO2_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/dx-o2-agents:${IMAGE_TAG}"

echo "=== Build configuration ==="
echo "  Registry  : ${REGISTRY}"
echo "  Tag       : ${IMAGE_TAG}  (build ${BUILD_NUM})"
echo "  Platform  : ${BUILD_PLATFORM}"
echo ""

# ── Step 1: package application archive ───────────────────────────────────────
echo "── Packaging application ──"
"${SCRIPT_DIR}/package-app.sh"
echo ""

# ── Step 2: build php-fpm image (multi-stage) ────────────────────────────────
echo "── Building php-fpm image: ${PHP_FPM_IMAGE} ──"
docker build \
    --platform "${BUILD_PLATFORM}" \
    --pull \
    --no-cache \
    -t "${PHP_FPM_IMAGE}" \
    "${ROOT_DIR}/src/php-fpm/"
echo ""

# ── Step 3: build nginx image ─────────────────────────────────────────────────
echo "── Building nginx image: ${NGINX_IMAGE} ──"
docker build \
    --platform "${BUILD_PLATFORM}" \
    --pull \
    --no-cache \
    -t "${NGINX_IMAGE}" \
    "${ROOT_DIR}/src/nginx/"
echo ""

# ── Step 4: build DX O2 agents image (conditional) ───────────────────────────
# The dx-o2-agents image requires the Broadcom Infrastructure Agent installer
# in src/dx-o2-agents/installers/.  Skip gracefully when the directory is
# empty (i.e. the installer has not been downloaded yet).
DXO2_INSTALLER_COUNT=$(find "${ROOT_DIR}/src/dx-o2-agents/installers" \
    -name 'apmia-*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')

if [[ "${DXO2_INSTALLER_COUNT}" -gt 0 ]]; then
    echo "── Building DX O2 agents image: ${DXO2_IMAGE} ──"
    docker build \
        --platform "${BUILD_PLATFORM}" \
        --pull \
        --no-cache \
        -t "${DXO2_IMAGE}" \
        "${ROOT_DIR}/src/dx-o2-agents/"
    echo ""
    DXO2_BUILT=true
else
    echo "── DX O2 agents image: SKIPPED (no installer in src/dx-o2-agents/installers/) ──"
    echo "   Download apmia-<version>.tar.gz from https://support.broadcom.com/ to build."
    echo ""
    DXO2_BUILT=false
fi

# ── Cleanup intermediate artifacts ────────────────────────────────────────────
rm -f "${ROOT_DIR}/src/php-fpm/app.tar.gz"

echo "=== Build summary ==="
echo "  ${PHP_FPM_IMAGE}"
echo "  ${NGINX_IMAGE}"
if [[ "${DXO2_BUILT}" == "true" ]]; then
    echo "  ${DXO2_IMAGE}"
else
    echo "  ${DXO2_IMAGE}  [NOT BUILT – installer missing]"
fi
