#!/usr/bin/env bash
# package-app.sh – Package the PHP application source into a tar archive.
#
# Creates src/apache-php/app.tar.gz from app/src/.  The archive is consumed as
# the build context by the Apache + mod_php Docker multi-stage build (Stage 1).
# This script must be run before build.sh (build.sh calls it automatically).
#
# Usage:
#   build-scripts/package-app.sh [-h|--help]
#
# Options:
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
    [[ -f "${config_file}" ]] || \
        fatal ".config not found in project root. Copy .config.example to .config."
    # shellcheck source=../.config
    source "${config_file}"
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
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)  usage; exit 0 ;;
        *)          fatal "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

# ── Main ───────────────────────────────────────────────────────────────────────
check_prerequisites
load_config
create_archive
