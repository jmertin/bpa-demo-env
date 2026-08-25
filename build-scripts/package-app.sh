#!/usr/bin/env bash
# package-app.sh – Package the PHP application source into a tar archive.
#
# Creates src/apache-php/app.tar.gz from app/src/.  The archive is consumed as
# the build context by the Apache + mod_php Docker multi-stage build (Stage 1).
# This script must be run before build.sh (build.sh calls it automatically).
#
# When called standalone (without --no-bump) the build counter in
# .build_number is incremented and IMAGE_TAG in .config is updated to the new
# b<N> tag so that compose.sh and deploy.sh pick up the new version immediately.
# build.sh passes --no-bump when it calls this script internally because it
# manages the counter lifecycle itself (compute then commit only on success).
#
# Usage:
#   build-scripts/package-app.sh [--no-bump] [-h|--help]
#
# Options:
#   --no-bump   Skip build-counter increment (used by build.sh internally).
#   -h, --help  Print this help message and exit.
#
# Prerequisites:
#   tar        Must be installed and in PATH.
#   app/src/   Must exist in the project root.
#   .config    Must exist in the project root (copy from .config.example).
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
info() {
    echo "[package-app] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[package-app] ERROR: $*" >&2
    exit 1
}

## Verify that required tools are installed and accessible.
check_prerequisites() {
    local -r required_tools=("tar")
    local tool
    for tool in "${required_tools[@]}"; do
        command -v "${tool}" >/dev/null 2>&1 || \
            fatal "Required tool not found in PATH: ${tool}"
    done
}

## Load and validate the .config file.
load_config() {
    local -r config_file="${ROOT_DIR}/.config"
    local -r config_example="${ROOT_DIR}/.config.example"
    [[ -f "${config_file}" ]] || \
        fatal ".config not found in project root. Copy .config.example to .config."

    # Load .config.example first so a not-yet-updated .config still gets
    # sensible defaults for any variable a newer .config.example added that
    # .config doesn't know about yet -- .config is sourced second, so its
    # real values override these defaults wherever it actually sets them.
    if [[ -f "${config_example}" ]]; then
        # shellcheck source=../.config.example
        source "${config_example}"
    fi
    # shellcheck source=../.config
    source "${config_file}"
    : "${IMAGE_TAG:?IMAGE_TAG must be set in .config}"
}

## Compute the next build tag in memory; sets globals FULL_TAG and BUILD_NUM.
# Mirrors the same function in build.sh.  No file is written here.
compute_build_tag() {
    local build_num
    build_num=$(( $(cat "${BUILD_FILE}" 2>/dev/null || echo 0) + 1 ))
    local base_tag="${IMAGE_TAG%%b*}"
    FULL_TAG="${base_tag}b${build_num}"
    BUILD_NUM="${build_num}"
}

## Persist the build counter and updated IMAGE_TAG to disk.
# Mirrors the same function in build.sh.
commit_build_tag() {
    printf '%s\n' "${BUILD_NUM}" > "${BUILD_FILE}"
    sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=\"${FULL_TAG}\"|" "${ROOT_DIR}/.config"
    # shellcheck source=../.config
    source "${ROOT_DIR}/.config"
    info "Build tag committed: ${FULL_TAG} (build #${BUILD_NUM})"
}

## Create the application archive.
create_archive() {
    local -r app_src="${ROOT_DIR}/app/src"
    local -r archive="${ROOT_DIR}/src/apache-php/app.tar.gz"

    [[ -d "${app_src}" ]] || \
        fatal "Application source directory not found: ${app_src}"

    info "Source  : ${app_src}"
    info "Archive : ${archive}"

    tar -czf "${archive}" -C "${app_src}" .

    local size
    size=$(du -sh "${archive}" | cut -f1)
    info "Done – archive size: ${size}"
}

# ── Argument parsing ───────────────────────────────────────────────────────────
OPT_NO_BUMP=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-bump)  OPT_NO_BUMP=true ;;
        -h|--help)  usage; exit 0 ;;
        *)          fatal "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

# ── Main ───────────────────────────────────────────────────────────────────────
check_prerequisites
load_config
create_archive

if [[ "${OPT_NO_BUMP}" == "false" ]]; then
    compute_build_tag
    commit_build_tag
fi
