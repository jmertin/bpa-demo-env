#!/usr/bin/env bash
# download-dx-do.sh - Download the dx-do CLI referenced by this project's
# dxo2-scripts/ into tools/ (git-ignored, see tools/README.md).
#
# dx-do (https://github.com/kialambroca/dx-do-dist) is the CLI every script
# in dxo2-scripts/ uses to drive DX O2 tenant configuration. It is never
# committed to this repo; each contributor fetches their own local copy.
# This script pins the exact version tools/README.md documents as verified
# working against this project (see DX_DO_VERSION below) rather than always
# grabbing "latest" -- a newer release may not have been checked yet. Bump
# DX_DO_VERSION here (and re-verify, per tools/README.md's own process)
# when you deliberately want to move to a newer release.
#
# Detects the local platform the same way every dxo2-scripts/*.sh script's
# own resolve_dx_do() does (Darwin-arm64 -> dx-do-macos-arm64; everything
# else -> dx-do-linux-x64), downloads the matching asset plus the release's
# SHA256SUMS file, verifies the checksum, and installs it to
# tools/dx-do-<platform> with the executable bit set. An existing binary
# for the same platform is kept alongside as a .bak (mirrors tools/
# README.md's own documented upgrade convention) rather than silently
# overwritten with no way back.
#
# Usage:
#   build-scripts/download-dx-do.sh [-v|--version <X.Y.Z>] [-h|--help]
#
# Options:
#   -v, --version <X.Y.Z>  Download a specific dx-do release instead of the
#                          version pinned below. Not verified against this
#                          project -- use at your own risk.
#   -h, --help             Print this help message and exit.
#
# Prerequisites:
#   curl   Must be installed and able to reach github.com.
#
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly TOOLS_DIR="${ROOT_DIR}/tools"

# The version tools/README.md documents as downloaded and verified working
# against this project's dxo2-scripts/. Update both together.
readonly DX_DO_VERSION_DEFAULT="7.2.1"
readonly DX_DO_REPO="kialambroca/dx-do-dist"

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[download-dx-do] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[download-dx-do] ERROR: $*" >&2
    exit 1
}

## Verify that required tools are installed.
check_prerequisites() {
    command -v curl >/dev/null 2>&1 || fatal "curl is required but not found in PATH."
}

## Print the tools/ asset name for the local platform.
resolve_asset_name() {
    local -r uname_s="$(uname -s)"
    local -r uname_m="$(uname -m)"
    case "${uname_s}-${uname_m}" in
        Darwin-arm64) printf '%s' "dx-do-macos-arm64" ;;
        *)            printf '%s' "dx-do-linux-x64" ;;
    esac
}

## Download the binary and SHA256SUMS asset for the given version, verify
## the checksum, and install the binary into tools/.
# Arguments: version (e.g. "7.2.1"), asset name (e.g. "dx-do-linux-x64").
download_and_verify() {
    local -r version="$1"
    local -r asset_name="$2"
    local -r release_base="https://github.com/${DX_DO_REPO}/releases/download/release/${version}"
    local -r dest="${TOOLS_DIR}/${asset_name}"

    mkdir -p "${TOOLS_DIR}"

    local -r tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp_dir}'" EXIT

    info "Downloading ${asset_name} (dx-do v${version})..."
    curl -fSL --progress-bar -o "${tmp_dir}/${asset_name}" "${release_base}/${asset_name}" || \
        fatal "Download failed: ${release_base}/${asset_name} -- check the version exists for this platform."

    info "Downloading SHA256SUMS to verify..."
    curl -fSL -o "${tmp_dir}/SHA256SUMS" "${release_base}/SHA256SUMS" || \
        fatal "Could not download SHA256SUMS from ${release_base}/SHA256SUMS."

    local -r expected_sum="$(grep -E " \*?${asset_name}\$" "${tmp_dir}/SHA256SUMS" | awk '{print $1}')"
    [[ -n "${expected_sum}" ]] || \
        fatal "No checksum entry for ${asset_name} found in SHA256SUMS."

    local -r actual_sum="$(sha256sum "${tmp_dir}/${asset_name}" | awk '{print $1}')"
    [[ "${expected_sum}" == "${actual_sum}" ]] || \
        fatal "SHA256 mismatch for ${asset_name}: expected ${expected_sum}, got ${actual_sum}."
    info "Checksum verified."

    if [[ -f "${dest}" ]]; then
        info "Existing ${asset_name} found -- keeping it as ${asset_name}.bak."
        mv -f "${dest}" "${dest}.bak"
    fi

    mv "${tmp_dir}/${asset_name}" "${dest}"
    chmod 0755 "${dest}"
    info "Installed ${dest}"
}

# ── Argument parsing ───────────────────────────────────────────────────────────
version="${DX_DO_VERSION_DEFAULT}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            [[ -n "${2:-}" ]] || fatal "-v|--version requires an argument."
            version="$2"
            shift 2
            ;;
        *)
            usage
            fatal "Unknown argument: '$1'"
            ;;
    esac
done

# ── Main ───────────────────────────────────────────────────────────────────────
check_prerequisites

asset_name="$(resolve_asset_name)"
info "Platform detected: $(uname -s)-$(uname -m) -> ${asset_name}"
download_and_verify "${version}" "${asset_name}"

info "Done. Run '${asset_name} --version' to confirm, then see dxo2-scripts/README.md for next steps."
