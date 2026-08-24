#!/usr/bin/env bash
# bpa-demo-services-universe.sh - Create, check, or delete the "BPA Demo
# service universe" O2/Platform Universe (a.k.a. "Services Universe" in
# the console) on the DX O2 tenant.
#
# `dx-do service-universe` is the newer/platform universe surface --
# distinct from `dx-do apm-universe` (the "APM Universe" type; see
# bpa-demo-universe.sh, a separate resource under that other surface). The
# two universe types are not the same resource and don't share ids -- the
# tenant currently needs both, per the user: they haven't been merged into
# one concept in the product yet.
#
# Bug fixed 2026-08-24 (API-side, confirmed by the dx-do maintainer's own
# fix): this script previously used the older `o2-universe` command
# group, which had three permanent limitations documented at length in a
# prior revision of this file and in `dx-do-o2-universe-issue.md`:
#   1. `o2-universe create` accepted no scoping parameters at all -- a
#      CLI-created Universe was always left unscoped (`tas` filter
#      `{"op":"ALL"}`, `nass` `serviceFilter.values: []`), which crashed
#      the console's edit UI when opened (confirmed 2026-07-07).
#   2. No `update`/`add-view` command existed to narrow the filter after
#      creation.
#   3. No `delete` command existed at all -- deleting relied on the
#      cross-group `apm-universe delete` call working on an o2-universe's
#      id (confirmed empirically to work, but undocumented and fragile).
# `o2-universe` no longer even appears in `dx-do`'s command-group list --
# it's been replaced outright by `service-universe`, which fixes all
# three: `create`/`update` both take a `serviceNames=` (comma-separated)
# parameter that produces the correct `SERVICE`-scoped filter shape on
# both the `tas` and `nass` views (verified live via a `create ... dry-run`
# preview -- see this script's git history for the exact JSON, which
# matches the shape of a universe made through the console's wizard), and
# `delete` is a first-class command (`viewId=` + `label=` required to
# match, as a typo-proof confirmation -- same pattern as `dashboard
# folder-delete`). All three (`create`/`update`/`delete`) are dry-run by
# default, matching this project's established mutation-safety
# convention. `service-universe get`/`list`/`export` round out the CRUD
# surface with consistent `viewId=` naming throughout (the old
# `o2-universe` group used three different id param names across its
# subcommands -- `name=` for create, `universeViewId=` for export/services
# -- see git history for the pre-fix version of this comment if that
# ever needs to be understood again).
#
# Adopted the existing tenant Universe (`VIEW621`, label "BPA Demo service
# universe") as the tracked instance rather than creating a new one --
# this Universe was already correctly `SERVICE`-scoped to "BPA-Demo"
# (created 2026-07-07, apparently by hand through the console around the
# same time the `o2-universe` crash was first found and worked around;
# this script's state file had gone missing/never pointed at it, so
# `check`/`create` had no way to find it before this fix). No prior
# `create` invocation of this script ever produced a resource, since the
# old `o2-universe create` fallback was deliberately disabled -- so
# there's no orphaned unscoped Universe to clean up from this script's
# own history.
#
# Usage:
#   dxo2-scripts/bpa-demo-services-universe.sh create   - create the
#                                        Universe if it doesn't exist
#                                        (self-heals by label if the
#                                        state file is missing/stale), or
#                                        re-apply the correct
#                                        SERVICE-scoped serviceNames via
#                                        `service-universe update` if it
#                                        exists but has drifted. Safe to
#                                        re-run.
#   dxo2-scripts/bpa-demo-services-universe.sh check    - print whether it
#                                        exists and its current
#                                        definition.
#   dxo2-scripts/bpa-demo-services-universe.sh delete   - delete the
#                                        Universe. Prompts for
#                                        confirmation; pass -y|--yes to
#                                        skip it.
#   dxo2-scripts/bpa-demo-services-universe.sh -h|--help - print this help.
#
# Prerequisites:
#   tools/dx-do-<platform>              DX O2 CLI - see
#                                        bpa-demo-service.sh's header
#                                        comment for download/setup.
#                                        Override the path with the DX_DO
#                                        environment variable if it lives
#                                        somewhere else.
#   ~/.dxdo/default.dxo2.config.json    dx-do tenant credentials.
#   python3                             used to parse JSON responses and
#                                        verify the SERVICE filter values.
#
# State:
#   Persists the Universe id (VIEW###) to
#   dxo2-scripts/.state/bpa-demo-services-universe.env (git-ignored). If
#   the state file is lost, `create`/`check` recover it automatically via
#   `service-universe list` and a label match on "BPA Demo service
#   universe" -- or find it manually the same way: `dx-do service-universe
#   list output.format=json` (redirect to a file, not a pipe -- see the
#   ~64KB pipe-truncation gotcha documented elsewhere in this directory).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly UNIVERSE_LABEL="BPA Demo service universe"
readonly SERVICE_NAME="BPA-Demo"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-services-universe.env"

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-services-universe] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-services-universe] ERROR: $*" >&2
    exit 1
}

## Resolve the dx-do binary path: DX_DO env var override, else a
## platform-appropriate default under tools/.
resolve_dx_do() {
    if [[ -n "${DX_DO:-}" ]]; then
        printf '%s' "${DX_DO}"
        return
    fi
    local -r uname_s="$(uname -s)"
    local -r uname_m="$(uname -m)"
    case "${uname_s}-${uname_m}" in
        Darwin-arm64) printf '%s' "${ROOT_DIR}/tools/dx-do-macos-arm64" ;;
        *)            printf '%s' "${ROOT_DIR}/tools/dx-do-linux-x64" ;;
    esac
}

readonly DX_DO_BIN="$(resolve_dx_do)"

## Verify the dx-do binary, tenant config, and python3 are present before
## doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
    command -v python3 >/dev/null 2>&1 || \
        fatal "python3 is required (used to parse JSON responses)."
}

## Run a dx-do command, stripping progress noise and defensively dropping any
## line containing an Authorization header (dx-do's own error handler has
## been observed to dump one on some failed requests).
run_dx_do() {
    "${DX_DO_BIN}" "$@" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization'
}

## Run a dx-do command with output.format=json, discarding all progress
## noise (it goes to stderr) so stdout is valid, parseable JSON.
run_dx_do_json() {
    "${DX_DO_BIN}" "$@" 2>/dev/null
}

## Find the service-universe id matching UNIVERSE_LABEL by listing all
## service-universes and matching on label. Prints the id, or nothing if
## not found.
find_universe_id() {
    run_dx_do_json service-universe list output.format=json | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for u in data:
    if u.get('name', '').strip() == '${UNIVERSE_LABEL}':
        print(u.get('id', ''))
        break
" 2>/dev/null || true
}

## Check whether the Universe's tas-view SERVICE filter is scoped to
## SERVICE_NAME. Prints "1" if scoped correctly, "0" otherwise (including
## if the id doesn't resolve at all).
#
# @param string $1
#   The viewId to check.
filter_is_correct() {
    local -r view_id="$1"
    run_dx_do_json service-universe get "viewId=${view_id}" output.format=json | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(0)
    sys.exit(0)
for v in d.get('views', []):
    if v.get('type') == 'tas':
        f = v.get('filter', {}).get('filter', {})
        if f.get('op') == 'SERVICE' and '${SERVICE_NAME}' in (f.get('values') or []):
            print(1)
            sys.exit(0)
print(0)
" 2>/dev/null || echo 0
}

## Load the Universe id from the state file into UNIVERSE_ID, if it exists.
load_state() {
    UNIVERSE_ID=""
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist UNIVERSE_ID to the state file.
save_state() {
    mkdir -p "${STATE_DIR}"
    printf 'UNIVERSE_ID=%q\n' "${UNIVERSE_ID}" > "${STATE_FILE}"
}

## Create or self-heal the Universe. Safe to re-run.
cmd_create() {
    load_state

    if [[ -z "${UNIVERSE_ID}" ]]; then
        UNIVERSE_ID="$(find_universe_id)"
    fi

    if [[ -n "${UNIVERSE_ID}" ]]; then
        if [[ "$(filter_is_correct "${UNIVERSE_ID}")" == "1" ]]; then
            info "Universe '${UNIVERSE_LABEL}' (${UNIVERSE_ID}) already exists and is correctly scoped to '${SERVICE_NAME}' -- nothing to do."
            save_state
            info "Run '${SCRIPT_NAME} check' to see its current definition."
            return 0
        fi
        info "Universe '${UNIVERSE_LABEL}' (${UNIVERSE_ID}) exists but its SERVICE filter is missing or doesn't include '${SERVICE_NAME}' -- self-healing with 'service-universe update'."
        run_dx_do service-universe update \
            "viewId=${UNIVERSE_ID}" \
            "serviceNames=${SERVICE_NAME}" \
            dry-run=false
        save_state
        info "Done. Run '${SCRIPT_NAME} check' to verify."
        return 0
    fi

    info "Creating Universe '${UNIVERSE_LABEL}' scoped to service '${SERVICE_NAME}'..."
    local create_json
    create_json=$("${DX_DO_BIN}" service-universe create \
        "label=${UNIVERSE_LABEL}" \
        "serviceNames=${SERVICE_NAME}" \
        output.format=json \
        dry-run=false 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${create_json}"
    UNIVERSE_ID="$(find_universe_id)"
    [[ -n "${UNIVERSE_ID}" ]] || fatal "Universe was created but could not be found again via 'service-universe list' -- check the tenant manually."
    info "Universe created: ${UNIVERSE_ID}"

    save_state
    info "Done. State saved to ${STATE_FILE}."
}

## Print whether the Universe exists and its current definition.
cmd_check() {
    load_state

    if [[ -z "${UNIVERSE_ID}" ]]; then
        UNIVERSE_ID="$(find_universe_id)"
    fi

    if [[ -z "${UNIVERSE_ID}" ]]; then
        info "No state file at ${STATE_FILE} and no Universe named '${UNIVERSE_LABEL}' found via 'service-universe list' -- '${SCRIPT_NAME} create' has not been run."
        exit 1
    fi

    info "Universe (${UNIVERSE_ID}):"
    if run_dx_do service-universe get "viewId=${UNIVERSE_ID}"; then
        save_state
    else
        info "  not found -- may have been deleted outside this script."
        exit 1
    fi
}

## Delete the Universe. Prompts for confirmation unless -y/--yes is given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    load_state

    if [[ -z "${UNIVERSE_ID}" ]]; then
        UNIVERSE_ID="$(find_universe_id)"
    fi

    if [[ -z "${UNIVERSE_ID}" ]]; then
        info "No state file at ${STATE_FILE} and no Universe named '${UNIVERSE_LABEL}' found -- nothing to delete."
        exit 1
    fi

    local skip_confirm="false"
    local arg
    for arg in "$@"; do
        case "${arg}" in
            -y|--yes) skip_confirm="true" ;;
        esac
    done

    if [[ "${skip_confirm}" != "true" ]]; then
        local reply
        read -r -p "Delete Universe '${UNIVERSE_LABEL}' (${UNIVERSE_ID}) from the DX O2 tenant? [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    info "Deleting Universe (${UNIVERSE_ID})..."
    run_dx_do service-universe delete \
        "viewId=${UNIVERSE_ID}" \
        "label=${UNIVERSE_LABEL}" \
        dry-run=false || info "  already gone."

    rm -f "${STATE_FILE}"
    info "Done."
}

# == Argument parsing =========================================================
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
    usage
    exit 0
fi

check_prerequisites

case "${1}" in
    create) cmd_create ;;
    check)  cmd_check ;;
    delete) shift; cmd_delete "$@" ;;
    *)
        usage
        fatal "Unknown subcommand: '${1}'"
        ;;
esac
