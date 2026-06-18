#!/usr/bin/env bash
# build.sh – Build all Docker images for the BPA-Demo application stack.
#
# Reads all configuration from .config in the project root.
# Auto-increments a local build counter (.build_number) and appends it to
# IMAGE_TAG as b<N> (e.g. 1.0.0 → 1.0.0b4) so every build produces a
# distinct tag that Kubernetes cannot skip due to a cached image.
#
# Usage:
#   build-scripts/build.sh [--push] [-h|--help]
#
# Options:
#   --push    Push images to the registry immediately after a successful build.
#   -h, --help  Print this help message and exit.
#
# Prerequisites:
#   docker     Must be installed and the daemon must be running.
#   .config    Must exist in the project root (copy from .config.example).
#
# DX O2 agents image:
#   Built only when src/dx-o2-agents/installers/PHP_apmia*.tar is present.
#   Download all three packages from your DX O2 interface (not from
#   support.broadcom.com) and place them in that directory.  See
#   DX-O2-AGENT-SETUP.md for download instructions.
#
# Application image:
#   src/apache-php/ – Apache 2.4 + mod_php 8.1 in a single container, replacing
#   the former nginx + php-fpm two-image setup.
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly BUILD_FILE="${ROOT_DIR}/.build_number"

# ── Functions ──────────────────────────────────────────────────────────────────

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
# Arguments: message string
info() {
    echo "[build] $*"
}

## Print a fatal error message to stderr and exit with status 1.
# Arguments: message string
fatal() {
    echo "[build] ERROR: $*" >&2
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

    # Verify docker daemon is reachable.
    docker info >/dev/null 2>&1 || \
        fatal "Docker daemon is not running or not accessible."
}

## Load and validate the .config file.
load_config() {
    local -r config_file="${ROOT_DIR}/.config"
    [[ -f "${config_file}" ]] || \
        fatal ".config not found in project root. Copy .config.example to .config and fill in values."
    # shellcheck source=../.config
    source "${config_file}"

    # Validate variables that this script cannot function without.
    : "${REGISTRY:?REGISTRY must be set in .config}"
    : "${IMAGE_PREFIX:?IMAGE_PREFIX must be set in .config}"
    : "${IMAGE_TAG:?IMAGE_TAG must be set in .config}"
    : "${BUILD_PLATFORM:?BUILD_PLATFORM must be set in .config}"
}

## Compute the next build tag without touching any file yet.
# Sets globals FULL_TAG and BUILD_NUM.  Call commit_build_tag() only after
# every image that should be built has been built successfully.
compute_build_tag() {
    local build_num
    build_num=$(( $(cat "${BUILD_FILE}" 2>/dev/null || echo 0) + 1 ))

    # Strip any existing b<N> suffix so the base version is always clean,
    # regardless of whether .config currently holds "1.0.0" or "1.0.0b3".
    local base_tag="${IMAGE_TAG%%b*}"
    FULL_TAG="${base_tag}b${build_num}"
    BUILD_NUM="${build_num}"
}

## Persist the build counter and new tag after all images have been built.
# Writes BUILD_NUM to .build_number and FULL_TAG back to .config so that
# push.sh and deploy.sh automatically use the new tag.
commit_build_tag() {
    printf '%s\n' "${BUILD_NUM}" > "${BUILD_FILE}"
    sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=\"${FULL_TAG}\"|" "${ROOT_DIR}/.config"
    # shellcheck source=../.config
    source "${ROOT_DIR}/.config"
    info "Build tag committed: ${FULL_TAG} (build #${BUILD_NUM})"
}

## Build a single Docker image and print status.
# Arguments: human-readable label, image reference, build-context directory.
build_image() {
    local -r label="$1"
    local -r image_ref="$2"
    local -r context="$3"

    info "Building ${label}: ${image_ref}"
    docker build \
        --platform "${BUILD_PLATFORM}" \
        --pull \
        --no-cache \
        -t "${image_ref}" \
        "${context}"
    info "${label} built successfully."
    echo ""
}

## Package the PHP application archive (calls package-app.sh).
package_app() {
    info "Packaging application source archive..."
    "${SCRIPT_DIR}/package-app.sh"
    echo ""
}

## Clean up transient build artefacts.
cleanup() {
    rm -f "${ROOT_DIR}/src/apache-php/app.tar.gz"
}

# ── Argument parsing ───────────────────────────────────────────────────────────
OPT_PUSH=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --push)       OPT_PUSH=true   ;;
        -h|--help)    usage; exit 0   ;;
        *)            fatal "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

# ── Main ───────────────────────────────────────────────────────────────────────
check_prerequisites
load_config
compute_build_tag   # computes FULL_TAG / BUILD_NUM; does NOT write any file yet

readonly APACHE_PHP_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/apache-php:${FULL_TAG}"
readonly DXO2_IMAGE="${REGISTRY}/${IMAGE_PREFIX}/dx-o2-agents:${FULL_TAG}"

echo "=== BPA-Demo image build ==="
echo "  Registry  : ${REGISTRY}"
echo "  Prefix    : ${IMAGE_PREFIX}"
echo "  Tag       : ${FULL_TAG}  (build #${BUILD_NUM})"
echo "  Platform  : ${BUILD_PLATFORM}"
echo ""

# Step 1 – package PHP application
package_app

# Step 2 – build Apache + mod_php image (multi-stage, replaces nginx + php-fpm)
build_image "apache-php" "${APACHE_PHP_IMAGE}" "${ROOT_DIR}/src/apache-php/"

# Step 3 – build DX O2 agents image (conditional on installer presence)
DXO2_INSTALLER_COUNT=$(find "${ROOT_DIR}/src/dx-o2-agents/installers" \
    -name 'PHP_apmia*.tar' 2>/dev/null | wc -l | tr -d ' ')
DXO2_BUILT=false

if [[ "${DXO2_INSTALLER_COUNT}" -gt 0 ]]; then
    build_image "dx-o2-agents" "${DXO2_IMAGE}" "${ROOT_DIR}/src/dx-o2-agents/"
    DXO2_BUILT=true
else
    info "dx-o2-agents: SKIPPED – PHP_apmia*.tar not found in installers/."
    info "  Download all three DX O2 agent packages from your DX O2 interface"
    info "  and place them in src/dx-o2-agents/installers/."
    info "  See DX-O2-AGENT-SETUP.md for instructions."
    echo ""
fi

# Step 4 – remove intermediate artefact
cleanup

# Step 5 – commit build counter and tag now that all images built successfully.
# This is intentionally the last write operation: if any build step above
# failed (set -euo pipefail), this line is never reached and .config retains
# the previous tag so the next run reuses the same build number.
commit_build_tag

# ── Build summary ──────────────────────────────────────────────────────────────
echo "=== Build summary ==="
echo "  [OK]  ${APACHE_PHP_IMAGE}"
if [[ "${DXO2_BUILT}" == "true" ]]; then
    echo "  [OK]  ${DXO2_IMAGE}"
else
    echo "  [--]  ${DXO2_IMAGE}  (skipped – installer absent)"
fi
echo ""

# Step 6 – optional push
if [[ "${OPT_PUSH}" == "true" ]]; then
    info "Push requested – invoking push.sh..."
    "${SCRIPT_DIR}/push.sh"
fi
