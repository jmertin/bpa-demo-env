#!/usr/bin/env bash
# bpa-demo-agent-health-dashboard.sh - Create, check, or unbind the
# "BPA-Demo * Agent Health" dashboard in the existing "BPA-Demo" folder.
#
# Structure created:
#   Dashboard "BPA-Demo * Agent Health" in folder "BPA-Demo"
#     Row "Agent Status": 3 polystat traffic-light circles, one per
#       deployed agent (Infrastructure Agent, PHP Probe Agent, BPA
#       WebServer Agent). Each circle queries the reserved
#       "Custom Metric Agent (Virtual)" alert-status metric
#       (Alerts|BPA-Demo:<alert name>) for every alert belonging to that
#       agent's tier (via a regex on the alert name), and rolls up to the
#       WORST (max) severity among them -- green only if every alert for
#       that agent is currently OK. This reuses the alerts already
#       created by bpa-demo-management-module.sh and
#       bpa-demo-agent-alerts.sh; it does not create any new alert.
#     Row "Infrastructure Agent -- DB Monitor": DB Availability (stat),
#       Connection Refusal Rate, Buffer Pool Cache Hit Rate, Slow Query
#       Rate (graphs) -- same metrics as the infra-tier alerts.
#     Row "PHP Probe Agent -- Application": App Response Time, App Error
#       Rate, App Concurrency, DB Backend Response Time (graphs) -- same
#       metrics as the php-tier alerts.
#     Row "BPA WebServer Agent -- Browser/RUM": Page Load Time, Page Hits
#       (graphs). These will likely show 0/no-data under the traffic
#       generator alone -- it drives plain HTTP requests, not a real
#       browser executing the BA snippet's JS, so no genuine RUM timing
#       is ever produced without a human (or real browser automation)
#       visiting the app.
#
# All metric/source regex patterns were verified live against real
# metric data (`dx-do metric data`) before being wired into the
# dashboard -- see this repo's CHANGELOG for the verification transcript.
#
# dx-do's `dashboard` command group on this CLI build has NO
# dashboard-create, dashboard-delete, validate-layout, or
# dashboard-render command (a smaller surface than some dx-do
# documentation describes) -- only dashboard-import (create-or-replace,
# via preserveUid/overwrite), dashboard-search, dashboard-export,
# dashboard-update, and folder-list/folder-create exist. `create` here
# uses dashboard-import for both the initial create (fresh uid, file's
# uid left null) and later self-heal/upsert (preserveUid=true
# overwrite=true with the persisted uid injected into a temp copy of the
# template) passes. `delete` has no CLI equivalent at all -- it prints
# manual console-removal instructions instead of pretending to work.
#
# Usage:
#   dxo2-scripts/bpa-demo-agent-health-dashboard.sh create   - import the
#                                                dashboard into the
#                                                "BPA-Demo" folder
#                                                (created if missing).
#                                                Safe to re-run: upserts
#                                                in place by uid instead
#                                                of duplicating.
#   dxo2-scripts/bpa-demo-agent-health-dashboard.sh check    - print
#                                                whether it exists and a
#                                                summary of its panels.
#   dxo2-scripts/bpa-demo-agent-health-dashboard.sh delete   - print
#                                                manual console-removal
#                                                instructions (no CLI
#                                                delete command exists
#                                                for dashboards on this
#                                                dx-do build).
#   dxo2-scripts/bpa-demo-agent-health-dashboard.sh -h|--help - print
#                                                this help.
#
# Prerequisites:
#   tools/dx-do-<platform>              DX O2 CLI - download the latest
#                                        release for your platform from
#                                        https://github.com/kialambroca/dx-do-dist/releases
#                                        and place it under tools/ (chmod +x).
#                                        Override the path with the DX_DO
#                                        environment variable if it lives
#                                        somewhere else.
#   ~/.dxdo/default.dxo2.config.json    dx-do tenant credentials - see
#                                        https://github.com/kialambroca/dx-do-dist
#                                        for how to generate this file.
#   python3                             used to inject the persisted uid
#                                        into a temp copy of the template
#                                        on upsert, and to parse JSON
#                                        responses.
#
# State:
#   This script persists the dashboard uid it creates to
#   dxo2-scripts/.state/bpa-demo-agent-health-dashboard.env (git-ignored)
#   so check/delete can find it again. If that file is lost, the
#   dashboard still exists in the tenant -- find it via `dx-do dashboard
#   dashboard-search searchTerm=Agent Health` (the title "BPA-Demo *
#   Agent Health" is visible there even without the state file).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly DASHBOARD_TITLE="BPA-Demo · Agent Health"
readonly FOLDER_TITLE="BPA-Demo"
readonly TEMPLATE_FILE="${SCRIPT_DIR}/templates/bpa-demo-agent-health-dashboard.json"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-agent-health-dashboard.env"

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-agent-health-dashboard] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-agent-health-dashboard] ERROR: $*" >&2
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

## Verify the dx-do binary, tenant config, and dashboard template are
## present before doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
    [[ -f "${TEMPLATE_FILE}" ]] || \
        fatal "Dashboard template not found at ${TEMPLATE_FILE}."
    command -v python3 >/dev/null 2>&1 || \
        fatal "python3 is required (used to inject the uid on upsert and parse JSON responses)."
}

## Run a dx-do command, stripping progress noise and defensively dropping
## any line containing an Authorization header (dx-do's own error handler
## has been observed to dump one on some failed requests).
run_dx_do() {
    "${DX_DO_BIN}" "$@" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization'
}

## Run a dx-do command with output.format=json, discarding all progress
## noise (it goes to stderr) so stdout is valid, parseable JSON.
run_dx_do_json() {
    "${DX_DO_BIN}" "$@" 2>/dev/null
}

## Load DASH_UID from the state file, if it exists.
load_state() {
    DASH_UID=""
    # An `if` guard, not `[[ -f ]] && source` -- the latter is this
    # function's last statement, so under `set -e` a nonexistent state
    # file (the common first-run case) would make load_state itself
    # return 1 and silently kill the whole script when called bare.
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist DASH_UID to the state file.
save_state() {
    mkdir -p "${STATE_DIR}"
    printf 'DASH_UID=%q\n' "${DASH_UID}" > "${STATE_FILE}"
}

## Find the "BPA-Demo" folder's numeric id via folder-list. Prints the
## id, or nothing if not found.
find_folder_id() {
    run_dx_do_json dashboard folder-list output.format=json | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data:
    if row.get('title', '').strip() == '${FOLDER_TITLE}':
        print(row['id'])
        break
" 2>/dev/null || true
}

## Look up the dashboard's uid by title via dashboard-search, regardless
## of state file. Prints the uid, or nothing if not found.
find_dash_uid() {
    run_dx_do_json dashboard dashboard-search "searchTerm=Agent Health" output.format=json | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data:
    if row.get('title', '').strip() == '${DASHBOARD_TITLE}':
        print(row['uid'])
        break
" 2>/dev/null || true
}

## Create or upsert the dashboard. Safe to re-run.
cmd_create() {
    load_state

    if [[ -z "${DASH_UID}" ]]; then
        DASH_UID="$(find_dash_uid)"
    fi

    local folder_id
    folder_id="$(find_folder_id)"
    if [[ -z "${folder_id}" ]]; then
        info "Folder '${FOLDER_TITLE}' not found -- creating it."
        local folder_json
        folder_json=$("${DX_DO_BIN}" dashboard folder-create "folderTitle=${FOLDER_TITLE}" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
        echo "${folder_json}"
        folder_id="$(find_folder_id)"
        [[ -n "${folder_id}" ]] || fatal "Could not find or create folder '${FOLDER_TITLE}'."
    fi

    if [[ -n "${DASH_UID}" ]]; then
        info "Dashboard '${DASHBOARD_TITLE}' already exists (uid ${DASH_UID}) -- updating in place."
        # dashboard-import's preserveUid=true/overwrite=true upsert is
        # documented elsewhere but this dx-do build silently ignores
        # overwrite= (confirmed live: the request body always shows
        # "overwrite":false regardless), which omits the required Grafana
        # `version` field and fails with HTTP 412 "version-mismatch".
        # dashboard-update on this build also does NOT resolve a numeric
        # id from a bare uid (confirmed live: "Export dashboard does not
        # have an id!" even with dashboard.uid set) -- unlike what some
        # dx-do documentation describes for newer builds. The classic
        # export -> edit -> update workflow is what actually works here:
        # export the live dashboard to get its real numeric id +
        # meta.folderId, replace its panels/title with the freshly
        # regenerated template's, and push that back.
        local exported_file
        exported_file="$(mktemp -t bpa-demo-agent-health-dashboard-export-XXXXXX.json)"
        rm -f "${exported_file}"
        "${DX_DO_BIN}" dashboard dashboard-export "uid=${DASH_UID}" "dashboardExportFile=${exported_file}" >/dev/null 2>&1 || \
            fatal "Could not export the existing dashboard (uid ${DASH_UID}) to merge the update into."

        local rendered_file
        rendered_file="$(mktemp -t bpa-demo-agent-health-dashboard-XXXXXX.json)"
        python3 -c "
import json
with open('${exported_file}') as f:
    live = json.load(f)
with open('${TEMPLATE_FILE}') as f:
    fresh = json.load(f)
live['dashboard']['panels'] = fresh['dashboard']['panels']
live['dashboard']['title'] = fresh['dashboard']['title']
live['dashboard']['tags'] = fresh['dashboard']['tags']
with open('${rendered_file}', 'w') as f:
    json.dump(live, f)
"
        rm -f "${exported_file}"
        run_dx_do dashboard dashboard-update "dashboardExportFile=${rendered_file}"
        rm -f "${rendered_file}"
        save_state
        info "Run '${SCRIPT_NAME} check' to see its current definition."
        return 0
    fi

    info "Importing dashboard '${DASHBOARD_TITLE}' into folder '${FOLDER_TITLE}' (id ${folder_id})..."
    local import_json
    import_json=$("${DX_DO_BIN}" dashboard dashboard-import \
        "dashboardExportFile=${TEMPLATE_FILE}" \
        "folderId=${folder_id}" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${import_json}"
    DASH_UID=$(printf '%s' "${import_json}" | grep -oE "uid: *'[^']*'|uid: *\"[^\"]*\"|\"uid\": *\"[^\"]*\"" | head -1 | grep -oE "[A-Za-z0-9_-]{6,}" | tail -1)
    [[ -n "${DASH_UID}" ]] || fatal "Could not parse dashboard uid from dx-do output above."
    info "Dashboard created: uid ${DASH_UID}"

    save_state
    info "Done. State saved to ${STATE_FILE}."
}

## Print whether the dashboard exists and a summary of its panels.
cmd_check() {
    load_state

    if [[ -z "${DASH_UID}" ]]; then
        DASH_UID="$(find_dash_uid)"
    fi

    if [[ -z "${DASH_UID}" ]]; then
        info "No state file at ${STATE_FILE} and no dashboard named '${DASHBOARD_TITLE}' found via 'dx-do dashboard dashboard-search' -- '${SCRIPT_NAME} create' has not been run."
        exit 1
    fi

    info "Dashboard (uid ${DASH_UID}):"
    local export_file
    export_file="$(mktemp -t bpa-demo-agent-health-dashboard-check-XXXXXX.json)"
    rm -f "${export_file}"
    if "${DX_DO_BIN}" dashboard dashboard-export "uid=${DASH_UID}" "dashboardExportFile=${export_file}" >/dev/null 2>&1; then
        python3 -c "
import json
with open('${export_file}') as f:
    data = json.load(f)
dash = data['dashboard']
print(f\"  title: {dash.get('title')}\")
print(f\"  uid: {dash.get('uid')}\")
print(f\"  panels: {len(dash.get('panels', []))}\")
for p in dash.get('panels', []):
    print(f\"    - #{p.get('id')} {p.get('type'):8s} {p.get('title','')}\")
"
        rm -f "${export_file}"
    else
        info "  not found -- may have been deleted outside this script."
    fi
}

## Print manual console-removal instructions. There is no CLI delete
## command for dashboards on this dx-do build.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (unused; accepted
#   for symmetry with the other dxo2-scripts).
cmd_delete() {
    load_state

    if [[ -z "${DASH_UID}" ]]; then
        DASH_UID="$(find_dash_uid)"
    fi

    if [[ -z "${DASH_UID}" ]]; then
        info "No state file at ${STATE_FILE} and no dashboard named '${DASHBOARD_TITLE}' found -- nothing to delete."
        exit 1
    fi

    info "This dx-do build has no dashboard-delete command -- remove it manually:"
    info "  1. Open the DX O2 console -> Dashboards -> '${FOLDER_TITLE}' folder."
    info "  2. Open '${DASHBOARD_TITLE}' (uid ${DASH_UID})."
    info "  3. Dashboard settings -> Delete Dashboard."
    info "After deleting, remove the state file so this script forgets it:"
    info "  rm -f ${STATE_FILE}"
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
