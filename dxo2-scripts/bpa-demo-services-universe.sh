#!/usr/bin/env bash
# bpa-demo-services-universe.sh - Create, check, or delete the "BPA Demo"
# O2/Platform Universe (a.k.a. "Services Universe" in the console) on the
# DX O2 tenant.
#
# `dx-do o2-universe` is the newer/platform universe surface -- distinct
# from `dx-do apm-universe` (the "APM Universe" type; see
# bpa-demo-universe.sh, a separate resource under that other surface). The
# two universe types are not the same resource and don't share ids -- the
# tenant currently needs both, per the user: they haven't been merged into
# one concept in the product yet.
#
# Confirmed console bug (2026-07-07): a Universe created via
# `o2-universe create name=...` (see "Known limitation" below) is left
# unscoped -- its `tas` view filter is the bare `{"op": "ALL"}`, with none
# of the fields (`input`, `values`, `includeServiceHierarchy`,
# `excludeSubServices`) a `SERVICE`-scoped filter carries. The console's
# edit UI crashes when opening a Universe in this state (confirmed by the
# user against the first CLI-created Universe, viewId VIEW617, since
# deleted) -- almost certainly because the edit form assumes every filter
# object carries the `SERVICE`-filter fields regardless of `op` type, and
# doesn't guard against them being absent. A Universe created through the
# console's own wizard (which always has you pick a Service scope up
# front) never produces this bare-`ALL` shape, so it doesn't hit this.
# Per the developer working the fix: the console's data model changed to
# require the `SERVICE`-scoped shape, but the change was never enforced
# at the API level -- `o2-universe create` still silently accepts/produces
# the old unscoped shape. Once that's fixed API-side, revisit whether
# `create` can safely call `o2-universe create` again -- see
# dx-do-o2-universe-issue.md's 2026-07-07 (2) update for what to check.
#
# Consequence: this script's `create` cannot produce a Universe that's
# both (a) scoped to the app the way the sibling bpa-demo-universe.sh
# manages, and (b) safe to edit afterward in the console -- there's no
# `dx-do o2-universe` command to narrow the filter post-creation (see
# "Known limitation"), and creating it unscoped hits the crash above.
# Until Broadcom fixes the crash or adds a way to set the filter at
# creation, **the working instance is a manually-created Universe** (the
# user created one via the console, labeled "BPA Demo", scoped to the
# existing "BPA-Demo" Service, viewId VIEW618) -- this script's state file
# points at that one. `create`'s self-heal check (verifies the id still
# resolves via `o2-universe export`) works the same regardless of how the
# Universe was originally created, so check/delete both work normally
# against it; only a fresh `create` from scratch would hit the crash-prone
# unscoped shape again.
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
# ["BPA-Demo"]}`), but there is no CLI path to set it, and even if there
# were, an unscoped Universe crashes the console's editor before it could
# be narrowed (see above) -- manual console creation is the only reliable
# path today.
#
# Usage:
#   dxo2-scripts/bpa-demo-services-universe.sh create   - verify the
#                                        Universe recorded in this script's
#                                        state file still exists. Safe to
#                                        re-run: no-ops if it does. Fails
#                                        with instructions for manual
#                                        console creation if the state file
#                                        is missing/stale -- see "Confirmed
#                                        console bug" above for why this
#                                        script won't create one itself.
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
readonly UNIVERSE_NAME="BPA Demo"
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
            return 0
        fi
        info "State file points at ${UNIVERSE_ID} but it no longer exists on the tenant."
        UNIVERSE_ID=""
    fi

    # Deliberately does NOT fall back to 'o2-universe create name=...' here.
    # That call only accepts a name and always produces an unscoped Universe
    # (tas view filter op=ALL, nass view serviceFilter.values=[]) that
    # crashes the console's edit UI when opened -- confirmed 2026-07-07, see
    # this script's header comment. There is currently no CLI path to
    # create a Service-scoped, edit-safe Universe from scratch.
    fatal "No existing Universe found for '${UNIVERSE_NAME}' and this script cannot safely create one -- 'o2-universe create' always produces an unscoped Universe that crashes the console's edit UI (see this script's header comment). Create it manually via the console instead: New Universe, label '${UNIVERSE_NAME}', scope both the tas and nass views to Service -> 'BPA-Demo'. Then note its viewId (VIEW###, via 'dx-do o2-universe list output.format=json' redirected to a file) and put it in ${STATE_FILE} as UNIVERSE_ID=<id>."
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
