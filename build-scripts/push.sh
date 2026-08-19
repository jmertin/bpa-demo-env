#!/usr/bin/env bash
# push.sh – Authenticate with the container registry and push built images.
#
# Images must be built first by running build.sh.
# Registry credentials are read exclusively from .config – they are never
# passed on the command line or embedded in any tracked file.
#
# Usage:
#   build-scripts/push.sh [--skip-dxo2] [-h|--help]
#
# Options:
#   --skip-dxo2  Skip pushing the dx-o2-agents image even if it exists locally.
#   -h, --help   Print this help message and exit.
#
# Prerequisites:
#   docker     Must be installed and the daemon must be running.
#   .config    Must exist in the project root (copy from .config.example).
#              REGISTRY, REGISTRY_USER, REGISTRY_PASSWORD, IMAGE_PREFIX, and
#              IMAGE_TAG must all be set.
#
# Images pushed:
#   apache-php        Apache 2.4 + mod_php 8.3 application image (replaces nginx + php-fpm)
#   dx-o2-agents      Broadcom APMIA + BTL sidecar (conditional on --skip-dxo2)
#   traffic-generator Synthetic user traffic for the demo shop
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
    echo "[push] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[push] ERROR: $*" >&2
    exit 1
}

## Verify that required tools are installed and accessible.
check_prerequisites() {
    local -r required_tools=("docker")
    local tool
    for tool in "${required_tools[@]}"; do
        command -v "${tool}" >/dev/null 2>&1 || \
            fatal "Required tool not found in PATH: ${tool}"
    done

    docker info >/dev/null 2>&1 || \
        fatal "Docker daemon is not running or not accessible."
}

## Load and validate the .config file.
load_config() {
    local -r config_file="${ROOT_DIR}/.config"
    [[ -f "${config_file}" ]] || \
        fatal ".config not found in project root. Copy .config.example to .config."
    # shellcheck source=../.config
    source "${config_file}"

    : "${REGISTRY:?REGISTRY must be set in .config}"
    : "${REGISTRY_USER:?REGISTRY_USER must be set in .config}"
    : "${REGISTRY_PASSWORD:?REGISTRY_PASSWORD must be set in .config}"
    : "${IMAGE_PREFIX:?IMAGE_PREFIX must be set in .config}"
    : "${IMAGE_TAG:?IMAGE_TAG must be set in .config}"
}

## Authenticate with the registry.
# Uses printf instead of echo to avoid the trailing newline that some registry
# daemons reject as part of the credential stream.
registry_login() {
    info "Authenticating with registry: ${REGISTRY}"
    printf '%s' "${REGISTRY_PASSWORD}" | \
        docker login "${REGISTRY}" \
            --username "${REGISTRY_USER}" \
            --password-stdin
    info "Authentication successful."
    echo ""
}

## Push a single image if it exists locally; skip with a warning if it does not.
# Arguments: image reference string.
push_image() {
    local -r image_ref="$1"

    if docker image inspect "${image_ref}" >/dev/null 2>&1; then
        info "Pushing ${image_ref} ..."
        docker push "${image_ref}"
        info "Push complete."
    else
        info "WARNING: Image not found locally – skipped: ${image_ref}"
        info "         Run build.sh first to create the image."
    fi
    echo ""
}

## Log out from the registry to avoid leaving credentials in the docker
## credential store on shared build machines.
registry_logout() {
    docker logout "${REGISTRY}" >/dev/null 2>&1 || true
    info "Logged out from ${REGISTRY}."
}

# ── Argument parsing ───────────────────────────────────────────────────────────
OPT_SKIP_DXO2=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-dxo2)  OPT_SKIP_DXO2=true ;;
        -h|--help)    usage; exit 0       ;;
        *)            fatal "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

# ── Main ───────────────────────────────────────────────────────────────────────
check_prerequisites
load_config

readonly APACHE_PHP_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/apache-php:${IMAGE_TAG}"
readonly DXO2_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/dx-o2-agents:${IMAGE_TAG}"
readonly TRAFFIC_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/traffic-generator:${IMAGE_TAG}"

echo "=== BPA-Demo image push ==="
echo "  Registry : ${REGISTRY}"
echo "  Tag      : ${IMAGE_TAG}"
echo ""

# Authenticate once for all pushes.
registry_login

# Push the application image.
push_image "${APACHE_PHP_IMAGE}"

# Push DX O2 agents image conditionally.
if [[ "${OPT_SKIP_DXO2}" == "true" ]]; then
    info "dx-o2-agents push: SKIPPED (--skip-dxo2 flag set)."
    echo ""
else
    push_image "${DXO2_IMAGE}"
fi

# Push the traffic generator image.
push_image "${TRAFFIC_IMAGE}"

# Clean up registry credentials from the local credential store.
registry_logout

echo "=== Push complete ==="
echo "  ${APACHE_PHP_IMAGE}"
if [[ "${OPT_SKIP_DXO2}" == "false" ]]; then
    echo "  ${DXO2_IMAGE}"
fi
echo "  ${TRAFFIC_IMAGE}"
