#!/usr/bin/env bash
# compose.sh – Wrapper around `docker compose` for local development.
#
# Sources .config, exports the variables that docker-compose.yml references,
# and ensures local images are present before commands that require them.
#
# Usage:
#   build-scripts/compose.sh build              – package app + build images locally
#   build-scripts/compose.sh up [-d]            – start the stack (builds if images absent)
#   build-scripts/compose.sh logs [-f]          – tail container logs
#   build-scripts/compose.sh down               – stop and remove containers
#   build-scripts/compose.sh down -v            – also delete the MariaDB data volume
#   build-scripts/compose.sh ps                 – show running services
#   build-scripts/compose.sh <any docker compose subcommand>
#   build-scripts/compose.sh -h | --help        – print this help and exit
#
# Prerequisites:
#   docker     Must be installed with the compose plugin (docker compose).
#   .config    Must exist in the project root (copy from .config.example).
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ── Functions ──────────────────────────────────────────────────────────────────

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[compose] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[compose] ERROR: $*" >&2
    exit 1
}

## Verify required tools are present.
check_prerequisites() {
    command -v docker >/dev/null 2>&1 || \
        fatal "docker not found in PATH."
    docker compose version >/dev/null 2>&1 || \
        fatal "docker compose plugin is not installed (requires Docker 20.10+)."
}

## Load .config and export variables consumed by docker-compose.yml.
load_config() {
    local -r config_file="${ROOT_DIR}/.config"
    [[ -f "${config_file}" ]] || \
        fatal ".config not found in project root. Copy .config.example to .config."
    # shellcheck source=../.config
    source "${config_file}"

    : "${REGISTRY:?REGISTRY must be set in .config}"
    : "${IMAGE_PREFIX:?IMAGE_PREFIX must be set in .config}"
    : "${IMAGE_TAG:?IMAGE_TAG must be set in .config}"
    : "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set in .config}"
    : "${MARIADB_DATABASE:?MARIADB_DATABASE must be set in .config}"
    : "${MARIADB_USER:?MARIADB_USER must be set in .config}"
    : "${MARIADB_PASSWORD:?MARIADB_PASSWORD must be set in .config}"

    export REGISTRY IMAGE_PREFIX IMAGE_TAG
    export MARIADB_ROOT_PASSWORD MARIADB_DATABASE MARIADB_USER MARIADB_PASSWORD

    # DX O2 variables are optional; export with safe defaults so docker-compose.yml
    # can reference them without triggering unbound-variable errors.
    export APMIA_EM_HOST="${APMIA_EM_HOST:-}"
    export APMIA_EM_PORT="${APMIA_EM_PORT:-8443}"
    export APMIA_DEPLOY="${APMIA_DEPLOY:-true}"
    export APMIA_AGENT_NAME="${APMIA_AGENT_NAME:-bpa-demo-agent}"
    export APMIA_APP_NAME="${APMIA_APP_NAME:-bpa-demo}"
    export APMIA_HOST_NAME="${APMIA_HOST_NAME:-bpa-demo-host}"
    export APMIA_PROCESS_NAME="${APMIA_PROCESS_NAME:-bpa-demo}"
    export APMIA_PHP_AGENT_NAME="${APMIA_PHP_AGENT_NAME:-bpa-demo-php-probe}"
    export APMIA_WEB_AGENT_NAME="${APMIA_WEB_AGENT_NAME:-bpa-demo-web-plugin}"
    export APMIA_LOG_LEVEL="${APMIA_LOG_LEVEL:-INFO}"
    export APMIA_PHP_COLLECTOR_HOST="${APMIA_PHP_COLLECTOR_HOST:-127.0.0.1}"
    export APMIA_PHP_COLLECTOR_PORT="${APMIA_PHP_COLLECTOR_PORT:-5005}"
    export APMIA_BTL_HOST="${APMIA_BTL_HOST:-127.0.0.1}"
    export APMIA_BTL_PORT="${APMIA_BTL_PORT:-8000}"
    export MYSQL_MONITOR="${MYSQL_MONITOR:-true}"
    # APMIA_BROWSER_SNIPPET may contain double-quotes and other characters that
    # are unsafe to interpolate directly into YAML.  Export it here so that
    # docker-compose.yml can use the list/passthrough form (- APMIA_BROWSER_SNIPPET)
    # which passes the value straight to the container without YAML parsing.
    export APMIA_BROWSER_SNIPPET="${APMIA_BROWSER_SNIPPET:-}"
}

## Return 0 (true) when both application images exist in the local Docker store.
images_present() {
    local php_image="${REGISTRY}/${IMAGE_PREFIX}/apache-php:${IMAGE_TAG}"
    local dxo2_image="${REGISTRY}/${IMAGE_PREFIX}/dx-o2-agents:${IMAGE_TAG}"
    docker image inspect "${php_image}" >/dev/null 2>&1 && \
    docker image inspect "${dxo2_image}" >/dev/null 2>&1
}

## Package and build images locally (calls the build-scripts chain).
# --no-bump is passed to package-app.sh because compose.sh never owns the
# build counter; only standalone package-app.sh invocations bump the number.
build_images() {
    info "Packaging application source..."
    "${SCRIPT_DIR}/package-app.sh" --no-bump
    echo ""

    info "Building images locally..."
    cd "${ROOT_DIR}"
    docker compose build
    echo ""
}

# ── Argument parsing ───────────────────────────────────────────────────────────
# Handle --help / -h before loading config so it works without .config present.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# ── Main ───────────────────────────────────────────────────────────────────────
check_prerequisites
load_config

SUBCMD="${1:-}"

# Short-circuit for commands that never touch images – pass through directly.
case "${SUBCMD}" in
    down|logs|ps|top|config|version|"")
        cd "${ROOT_DIR}"
        exec docker compose "$@"
        ;;
esac

# Explicit build request – let docker compose handle it (forwards extra flags).
if [[ "${SUBCMD}" == "build" ]]; then
    info "Packaging application source before build..."
    "${SCRIPT_DIR}/package-app.sh" --no-bump
    echo ""
    cd "${ROOT_DIR}"
    exec docker compose "$@"
fi

# Any other subcommand (e.g. 'up', 'run'): ensure images exist first.
if ! images_present; then
    info "Local images not found – building before '${SUBCMD}'..."
    build_images
fi

cd "${ROOT_DIR}"
exec docker compose "$@"
