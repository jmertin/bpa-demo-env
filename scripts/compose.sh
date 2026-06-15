#!/usr/bin/env bash
# Wrapper around docker compose that sources .config and ensures local images
# are built before commands that need them.
#
# Usage:
#   ./scripts/compose.sh build       – package app + build images locally
#   ./scripts/compose.sh up -d       – start stack (builds if images missing)
#   ./scripts/compose.sh logs -f     – tail logs
#   ./scripts/compose.sh down        – stop and remove containers
#   ./scripts/compose.sh down -v     – also delete the mariadb data volume
#   ./scripts/compose.sh ps          – show running services
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

# ── Load configuration ─────────────────────────────────────────────────────────
if [[ ! -f "${ROOT_DIR}/.config" ]]; then
    echo "ERROR: ${ROOT_DIR}/.config not found." >&2
    echo "       Copy .config.example to .config and fill in real values." >&2
    exit 1
fi

# shellcheck source=../.config
source "${ROOT_DIR}/.config"

export REGISTRY IMAGE_PREFIX IMAGE_TAG
export MARIADB_ROOT_PASSWORD MARIADB_DATABASE MARIADB_USER MARIADB_PASSWORD

# Derive the local image names (same tags that build.sh produces).
PHP_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/php-fpm:${IMAGE_TAG}"
NGX_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/nginx:${IMAGE_TAG}"

SUBCMD="${1:-}"

# ── Short-circuit for commands that never touch images ─────────────────────────
case "${SUBCMD}" in
    down|logs|ps|top|config|version|--help|-h|"")
        cd "${ROOT_DIR}"
        exec docker compose "$@"
        ;;
esac

# ── Detect whether local images exist ─────────────────────────────────────────
images_present() {
    docker image inspect "${PHP_IMAGE}" >/dev/null 2>&1 &&
    docker image inspect "${NGX_IMAGE}" >/dev/null 2>&1
}

# ── Build local images when explicitly requested or when images are absent ─────
if [[ "${SUBCMD}" == "build" ]] || ! images_present; then
    echo "── Packaging application source ──"
    "${SCRIPT_DIR}/package-app.sh"
    echo ""

    # When the user explicitly called 'build', let the exec below handle it
    # so any extra flags (e.g. --no-cache) are forwarded correctly.
    # Otherwise build here so the subsequent 'up' finds the images.
    if [[ "${SUBCMD}" != "build" ]]; then
        echo "── Building images locally (images not found in local Docker) ──"
        cd "${ROOT_DIR}"
        docker compose build
        echo ""
    fi
fi

cd "${ROOT_DIR}"
exec docker compose "$@"
