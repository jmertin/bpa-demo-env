#!/usr/bin/env bash
# bpa-demo-services-universe.sh - Create, check, or delete the "BPA Demo
# universe" O2/Platform Universe (a.k.a. "Services Universe" in the
# console) on the DX O2 tenant.
#
# `dx-do o2-universe` is the newer/platform universe surface -- distinct
# from `dx-do apm-universe` (the "APM Universe" type; see
# bpa-demo-universe.sh, which creates a universe with the SAME name under
# that other surface). The two universe types are not the same resource
# and don't share ids -- the tenant currently needs both, per the user:
# they haven't been merged into one concept in the product yet.
#
# Unlike bpa-demo-universe.sh, this script does NOT scope the created
# Universe to just the app's 4 telemetry entities -- it can't. See
# "Known limitation" below.
#
# Structure created:
#   O2 Universe "BPA Demo universe"
#     `o2-universe create name=...` accepts no other parameters -- any
#     extra ones (a filter, a service scope, ...) are silently ignored
#     ("ignoring extra args"), same landmine as `apm-universe create`'s
#     dry-run-ignoring but for different params. The Universe is created
#     with the platform's own default views, unscoped:
#       - a `tas` view: `{"filter": {"op": "ALL"}, ...}`
#       - a `nass` view: `{"filter": {"op": "ALL"}, "serviceFilter":
#         {"op": "SERVICE", "values": []}}`
#     i.e. it matches the ENTIRE tenant's topology and metric sources,
#     not just BPA-Demo's.
#
# Known limitation (see BUGS for the full writeup of the sibling
# apm-universe finding this extends): there is no `dx-do o2-universe`
# command to narrow either view's filter after creation -- the command
# group is only `create, export, list, services`; no `update`/`add-view`/
# anything else exists, and `create` itself ignores any filter-shaped
# extra params. The `nass` view's `serviceFilter.values: []` looks like
# exactly the right place to put `"BPA-Demo"` (scoping by the existing
# Service, which the sibling apm-universe investigation confirmed
# correctly covers all 4 telemetry entities -- see
# `dx-do tas query-json` with `{"op": "SERVICE", "values":
# ["BPA-Demo"]}`), but there is no CLI path to set it. Narrowing this
# Universe's scope requires manual console configuration -- edit the
# "BPA Demo universe" O2 Universe's `nass`/`tas` view filters to scope by
# Service -> "BPA-Demo" instead of leaving them at the "ALL" default.
#
# Usage:
#   dxo2-scripts/bpa-demo-services-universe.sh create   - create the
#                                        Universe. Safe to re-run: warns
#                                        instead of failing if it already
#                                        exists (by label).
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
#
# State:
#   Persists the Universe id (VIEW###) to
#   dxo2-scripts/.state/bpa-demo-services-universe.env (git-ignored).
#   `o2-universe create`'s own output never prints the created id (unlike
#   `apm-universe create`'s "(VIEWxxx)" message) -- this script recovers
#   it immediately afterward via `o2-universe list` and a label match. If
#   the state file is lost, find the id the same way: `dx-do o2-universe
#   list output.format=json` (redirect to a file, not a pipe -- see the
#   ~64KB pipe-truncation gotcha documented elsewhere in this directory)
#   and search for the label "BPA Demo universe".
#
# Gotchas discovered while writing this script (2026-07-06):
#   - `o2-universe create`'s id param is `name=` (the label, same as
#     `apm-universe create`); `export`/`services` take `universeViewId=`
#     -- a THIRD distinct id param name alongside `apm-universe`'s
#     `universeId=`/`id=` (see bpa-demo-universe.sh's header comment).
#     Don't assume any id param name carries over between the two
#     universe command groups, or even between subcommands of the same
#     group.
#   - `o2-universe` has no `delete` command at all. `apm-universe delete
#     id=<id> name=<label>` deletes an o2-universe's id just fine despite
#     being a different CLI command group -- confirmed empirically. This
#     script relies on that cross-group behavior for cmd_delete.
#   - The "Expect to wait 30 seconds before you see this service"
#     warning `create` prints is misleading -- the created Universe is
#     immediately visible via `o2-universe list`, no wait needed
#     (confirmed empirically; the warning likely refers to some other
#     downstream system's cache, not the list API this script depends on).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly UNIVERSE_NAME="BPA Demo universe"
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

## Verify the dx-do binary and tenant config are present before doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
}

## Run a dx-do command, stripping progress noise and defensively dropping any
## line containing an Authorization header (dx-do's own error handler has
## been observed to dump one on some failed requests).
run_dx_do() {
    "${DX_DO_BIN}" "$@" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization'
}

## Find the o2-universe id matching UNIVERSE_NAME by listing all
## o2-universes and matching on label. Prints the id, or nothing if not
## found. Redirects to a temp file rather than piping, to avoid the
## ~64KB pipe-truncation gotcha other dx-do list commands are known to hit.
find_universe_id() {
    local list_file
    list_file="$(mktemp -t bpa-demo-services-universe-list-XXXXXX.json)"
    "${DX_DO_BIN}" o2-universe list output.format=json >"${list_file}" 2>/dev/null || true
    python3 - "${list_file}" "${UNIVERSE_NAME}" <<'PYEOF'
import json, sys
path, name = sys.argv[1], sys.argv[2]
content = open(path).read()
depth = 0
end = None
for i, c in enumerate(content):
    if c == '[':
        depth += 1
    elif c == ']':
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end is None:
    sys.exit(0)
try:
    arr = json.loads(content[:end])
except json.JSONDecodeError:
    sys.exit(0)
for u in arr:
    if u.get('label') == name:
        print(u.get('viewId', ''))
        break
PYEOF
    rm -f "${list_file}"
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

## Create the O2 Universe. Safe to re-run.
cmd_create() {
    load_state

    if [[ -n "${UNIVERSE_ID}" ]]; then
        # Don't trust the state file alone -- verify the id still resolves
        # on the tenant before short-circuiting. Confirmed necessary: this
        # Universe was deleted out-of-band (console, or someone else)
        # while the state file still pointed at it, and 'create' silently
        # no-op'd instead of noticing and recreating it.
        if "${DX_DO_BIN}" o2-universe export universeViewId="${UNIVERSE_ID}" >/dev/null 2>&1; then
            info "Universe '${UNIVERSE_NAME}' already created (${UNIVERSE_ID}) -- nothing to do."
            info "Run '${SCRIPT_NAME} check' to see its current definition."
            info "Reminder: this Universe is unscoped (matches the whole tenant) -- see this script's header comment for why, and the manual console step needed to narrow it."
            return 0
        fi
        info "State file points at ${UNIVERSE_ID} but it no longer exists on the tenant -- recreating."
        UNIVERSE_ID=""
    fi

    info "Creating Universe '${UNIVERSE_NAME}'..."
    run_dx_do o2-universe create name="${UNIVERSE_NAME}"

    UNIVERSE_ID="$(find_universe_id)"
    [[ -n "${UNIVERSE_ID}" ]] || fatal "Created the universe but could not find its id afterward via 'o2-universe list' -- check the tenant manually for a duplicate named '${UNIVERSE_NAME}'."
    info "Universe created: ${UNIVERSE_ID}"

    save_state
    info "Done. State saved to ${STATE_FILE}."
    info "This Universe is unscoped (matches the whole tenant) -- see this script's header comment ('Known limitation') for why, and the manual console step needed to narrow it to BPA-Demo."
}

## Print whether the Universe exists and its current definition.
cmd_check() {
    load_state

    if [[ -z "${UNIVERSE_ID}" ]]; then
        info "No state file at ${STATE_FILE} -- '${SCRIPT_NAME} create' has not been run here."
        info "The Universe may still exist under a different state file/machine -- check 'dx-do o2-universe list output.format=json' (redirect to a file) for the label '${UNIVERSE_NAME}'."
        exit 1
    fi

    info "Universe (${UNIVERSE_ID}):"
    if run_dx_do o2-universe export universeViewId="${UNIVERSE_ID}"; then
        :
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
        info "No state file at ${STATE_FILE} -- nothing recorded here to delete."
        info "If '${UNIVERSE_NAME}' still exists in the tenant, remove it via 'dx-do apm-universe delete id=<id> name=\"${UNIVERSE_NAME}\"' (works across both universe types -- find <id> via 'dx-do o2-universe list output.format=json') or the console."
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
        read -r -p "Delete Universe '${UNIVERSE_NAME}' (${UNIVERSE_ID}) from the DX O2 tenant? [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    # o2-universe has no delete command -- apm-universe's delete works on
    # its id anyway (confirmed empirically; see header comment).
    info "Deleting Universe (${UNIVERSE_ID})..."
    run_dx_do apm-universe delete id="${UNIVERSE_ID}" name="${UNIVERSE_NAME}" || info "  already gone."

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
