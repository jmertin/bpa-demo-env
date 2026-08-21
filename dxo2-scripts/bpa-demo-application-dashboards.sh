#!/usr/bin/env bash
# bpa-demo-application-dashboards.sh - Create, check, or unbind the three
# "BPA-Demo" application dashboards in the existing "BPA-Demo" folder.
#
# Source material: exported by hand from the DX O2 console (Dashboards ->
# JSON Model -> Export) into jm-dashboards/bpa/ and handed over for
# templating -- these are pre-existing, tenant-provided BPA application
# dashboards, not ones authored from scratch for this project like
# bpa-demo-agent-health-dashboard.sh's dashboard is. Templated here as
# dxo2-scripts/templates/bpa-demo-{application-overview,
# application-drilldown,transaction-details-drilldown}-dashboard.json:
# id/uid/version stripped (fresh import mints its own), title prefixed
# "BPA-Demo · " to match this folder's existing dashboard and to fix a
# double-space typo in the original "Transaction Details  Drilldown"
# title, tags set to ["bpa-demo", "BPA"] (keeps the dashboards' own
# built-in "BPA" cross-link dropdown -- see links[1] in each template --
# working, while also matching this project's tagging convention), and a
# human-readable `description` (Grafana's "i" hover icon) added to every
# data panel that lacked one.
#
# Structure created (3 dashboards):
#   "BPA-Demo · Application Overview" -- fleet-wide view for one
#     selected Application: Success Rate (piechart), Average Response
#     Time heatmap, Response Count (graph), and three "Performance
#     Overview" tables (dashboard time range / fixed last-24h / fixed
#     last-7d) breaking response time percentiles, size, volume, and
#     server-error count out per Business Transaction.
#   "BPA-Demo · Application Drilldown" -- same Application scoped
#     further to one selected Business Transaction: Server Errors
#     (graph), ART by Server IP (heatmap -- spot one slow backend
#     instance), Unique Client IPs / Forwarded Client IPs (stat --
#     visitor diversity, the latter for behind-a-proxy deployments), and
#     two Performance Overview tables (BT-level, then URL-level detail).
#   "BPA-Demo · Transaction Details Drilldown" -- individual-request
#     level: Transaction Details (grouped by time/client IP/server IP),
#     a Total Filtered Transactions counter, a raw-captured-document
#     table (intentionally unaggregated -- narrow the filters first), and
#     a Filtered Transaction List keyed by transaction_id for picking one
#     request to inspect. Templating vars: application, bt_name,
#     httpStatus, resTime (minimum response time threshold), and an
#     ad-hoc Filters variable.
#
# All three query the AIOps_BPAMetadata Grafana datasource against the
# BPA WebServer Extension's raw captured-transaction Elasticsearch index
# (ao_aum_captured_data_2*) -- one document per HTTP request/response
# mod_caplugin actually captured, fields like app_alias, bt_name,
# res_status, server_time, res_size/req_size,
# req_metadata_client_ip/server_ip, req_header_x_forwarded_for,
# reqUrl.keyword, transaction_id. This is a genuinely different,
# per-request-level telemetry surface from the NASS/metric-catalog
# aggregates (Frontends|Apps|...:Average Response Time (ms), etc.) that
# every other dxo2-scripts/*.sh in this project queries via
# sourceNameSpecifier/attributeNameSpecifier patterns -- there is no
# metric-catalog equivalent of "list me the individual slow requests,"
# which is exactly what these three dashboards are for. The datasource
# name is referenced as a plain string ("AIOps_BPAMetadata", not a
# templated ${DS_...} input), so it must already exist as a configured
# Grafana datasource on the target tenant -- true here since these
# dashboards were exported directly from this same tenant.
#
# dx-do's `dashboard` command group on this CLI build has NO
# dashboard-create, dashboard-delete, validate-layout, or
# dashboard-render command -- same limitation documented in
# bpa-demo-agent-health-dashboard.sh. `create` uses dashboard-import for
# the fresh case (uid left null in the template, so a fresh uid is
# minted) and the classic export -> edit -> dashboard-update workflow to
# self-heal/upsert in place by uid (dashboard-import's documented
# preserveUid=true overwrite=true doesn't work on this build -- see that
# script's header comment for the full landmine writeup, identical here).
# `delete` has no CLI equivalent -- it prints manual console-removal
# instructions instead of pretending to work.
#
# Usage:
#   dxo2-scripts/bpa-demo-application-dashboards.sh create   - import all
#                                                three dashboards into the
#                                                "BPA-Demo" folder
#                                                (created if missing).
#                                                Safe to re-run: upserts
#                                                each in place by uid
#                                                instead of duplicating.
#   dxo2-scripts/bpa-demo-application-dashboards.sh check    - print
#                                                whether each exists and a
#                                                summary of its panels.
#   dxo2-scripts/bpa-demo-application-dashboards.sh delete   - print
#                                                manual console-removal
#                                                instructions for each
#                                                (no CLI delete command
#                                                exists for dashboards on
#                                                this dx-do build).
#   dxo2-scripts/bpa-demo-application-dashboards.sh -h|--help - print
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
#                                        into a temp copy of each template
#                                        on upsert, and to parse JSON
#                                        responses.
#
# State:
#   This script persists the uid each dashboard is created with to
#   dxo2-scripts/.state/bpa-demo-application-dashboards.env (git-ignored)
#   so check/delete can find them again. If that file is lost, the
#   dashboards still exist in the tenant -- find them via `dx-do
#   dashboard dashboard-search searchTerm=BPA-Demo` (each title is
#   visible there even without the state file).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly FOLDER_TITLE="BPA-Demo"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-application-dashboards.env"

readonly DASH_KEYS=(overview drilldown transaction-details)
declare -A DASH_TITLE=(
    [overview]="BPA-Demo · Application Overview"
    [drilldown]="BPA-Demo · Application Drilldown"
    [transaction-details]="BPA-Demo · Transaction Details Drilldown"
)
declare -A DASH_SEARCH_TERM=(
    [overview]="Application Overview"
    [drilldown]="Application Drilldown"
    [transaction-details]="Transaction Details Drilldown"
)
declare -A DASH_TEMPLATE=(
    [overview]="${SCRIPT_DIR}/templates/bpa-demo-application-overview-dashboard.json"
    [drilldown]="${SCRIPT_DIR}/templates/bpa-demo-application-drilldown-dashboard.json"
    [transaction-details]="${SCRIPT_DIR}/templates/bpa-demo-transaction-details-drilldown-dashboard.json"
)

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-application-dashboards] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-application-dashboards] ERROR: $*" >&2
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

## Verify the dx-do binary, tenant config, and all three dashboard
## templates are present before doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
    local key
    for key in "${DASH_KEYS[@]}"; do
        [[ -f "${DASH_TEMPLATE[${key}]}" ]] || \
            fatal "Dashboard template not found at ${DASH_TEMPLATE[${key}]}."
    done
    command -v python3 >/dev/null 2>&1 || \
        fatal "python3 is required (used to inject the uid on upsert and parse JSON responses)."
}

## Run a dx-do command, stripping progress noise and defensively dropping
## any line containing an Authorization header.
run_dx_do() {
    "${DX_DO_BIN}" "$@" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization'
}

## Run a dx-do command with output.format=json, discarding all progress
## noise (it goes to stderr) so stdout is valid, parseable JSON.
run_dx_do_json() {
    "${DX_DO_BIN}" "$@" 2>/dev/null
}

## Load DASH_UID_<key> variables from the state file, if it exists.
load_state() {
    local key
    for key in "${DASH_KEYS[@]}"; do
        declare -g "DASH_UID_${key//-/_}="
    done
    # An `if` guard, not `[[ -f ]] && source` -- see
    # bpa-demo-agent-health-dashboard.sh's identical comment for why.
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist all DASH_UID_<key> variables to the state file.
save_state() {
    mkdir -p "${STATE_DIR}"
    local key varname
    {
        for key in "${DASH_KEYS[@]}"; do
            varname="DASH_UID_${key//-/_}"
            printf '%s=%q\n' "${varname}" "${!varname}"
        done
    } > "${STATE_FILE}"
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

## Look up a dashboard's uid by title via dashboard-search, regardless of
## state file.
#
# @param string $1
#   The dashboard key (index into DASH_TITLE/DASH_SEARCH_TERM).
#
# @return string
#   Prints the uid, or nothing if not found.
find_dash_uid() {
    local -r key="$1"
    local -r title="${DASH_TITLE[${key}]}"
    run_dx_do_json dashboard dashboard-search "searchTerm=${DASH_SEARCH_TERM[${key}]}" output.format=json | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data:
    if row.get('title', '').strip() == '${title}':
        print(row['uid'])
        break
" 2>/dev/null || true
}

## Create or upsert one dashboard by key. Safe to re-run.
#
# @param string $1
#   The dashboard key.
# @param string $2
#   The BPA-Demo folder's numeric id.
create_one() {
    local -r key="$1"
    local -r folder_id="$2"
    local -r title="${DASH_TITLE[${key}]}"
    local -r template="${DASH_TEMPLATE[${key}]}"
    local -r varname="DASH_UID_${key//-/_}"
    local dash_uid="${!varname}"

    if [[ -z "${dash_uid}" ]]; then
        dash_uid="$(find_dash_uid "${key}")"
    fi

    if [[ -n "${dash_uid}" ]]; then
        info "'${title}' already exists (uid ${dash_uid}) -- updating in place."
        # Same export -> edit -> update workaround as
        # bpa-demo-agent-health-dashboard.sh: dashboard-import's
        # preserveUid=true/overwrite=true upsert is silently broken on
        # this dx-do build (overwrite= is ignored, so the request is
        # missing the `version` field Grafana requires and 412s), and
        # dashboard-update does not resolve a numeric id from a bare uid.
        local exported_file
        exported_file="$(mktemp -t bpa-demo-application-dashboards-export-XXXXXX.json)"
        rm -f "${exported_file}"
        "${DX_DO_BIN}" dashboard dashboard-export "uid=${dash_uid}" "dashboardExportFile=${exported_file}" >/dev/null 2>&1 || \
            fatal "Could not export the existing dashboard '${title}' (uid ${dash_uid}) to merge the update into."

        local rendered_file
        rendered_file="$(mktemp -t bpa-demo-application-dashboards-XXXXXX.json)"
        python3 -c "
import json
with open('${exported_file}') as f:
    live = json.load(f)
with open('${template}') as f:
    fresh = json.load(f)
live['dashboard']['panels'] = fresh['dashboard']['panels']
live['dashboard']['title'] = fresh['dashboard']['title']
live['dashboard']['tags'] = fresh['dashboard']['tags']
live['dashboard']['templating'] = fresh['dashboard'].get('templating', {'list': []})
live['dashboard']['links'] = fresh['dashboard'].get('links', [])
with open('${rendered_file}', 'w') as f:
    json.dump(live, f)
"
        rm -f "${exported_file}"
        run_dx_do dashboard dashboard-update "dashboardExportFile=${rendered_file}"
        rm -f "${rendered_file}"
        declare -g "${varname}=${dash_uid}"
        return 0
    fi

    info "Importing '${title}' into folder '${FOLDER_TITLE}' (id ${folder_id})..."
    local import_json
    import_json=$("${DX_DO_BIN}" dashboard dashboard-import \
        "dashboardExportFile=${template}" \
        "folderId=${folder_id}" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${import_json}"
    dash_uid=$(printf '%s' "${import_json}" | grep -oE "uid: *'[^']*'|uid: *\"[^\"]*\"|\"uid\": *\"[^\"]*\"" | head -1 | grep -oE "[A-Za-z0-9_-]{6,}" | tail -1)
    [[ -n "${dash_uid}" ]] || fatal "Could not parse dashboard uid from dx-do output above for '${title}'."
    info "'${title}' created: uid ${dash_uid}"
    declare -g "${varname}=${dash_uid}"
}

## Create or upsert all three dashboards. Safe to re-run.
cmd_create() {
    load_state

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

    local key
    for key in "${DASH_KEYS[@]}"; do
        create_one "${key}" "${folder_id}"
    done

    save_state
    info "Done. State saved to ${STATE_FILE}."
}

## Print whether each dashboard exists and a summary of its panels.
cmd_check() {
    load_state

    local key varname dash_uid title export_file
    for key in "${DASH_KEYS[@]}"; do
        varname="DASH_UID_${key//-/_}"
        dash_uid="${!varname}"
        title="${DASH_TITLE[${key}]}"

        if [[ -z "${dash_uid}" ]]; then
            dash_uid="$(find_dash_uid "${key}")"
        fi

        if [[ -z "${dash_uid}" ]]; then
            info "'${title}': not found -- 'create' has not been run for this one."
            continue
        fi

        info "'${title}' (uid ${dash_uid}):"
        export_file="$(mktemp -t bpa-demo-application-dashboards-check-XXXXXX.json)"
        rm -f "${export_file}"
        if "${DX_DO_BIN}" dashboard dashboard-export "uid=${dash_uid}" "dashboardExportFile=${export_file}" >/dev/null 2>&1; then
            python3 -c "
import json
with open('${export_file}') as f:
    data = json.load(f)
dash = data['dashboard']
print(f\"  panels: {len(dash.get('panels', []))}\")
for p in dash.get('panels', []):
    print(f\"    - #{p.get('id')} {p.get('type'):22s} {p.get('title') or ''}\")
"
            rm -f "${export_file}"
        else
            info "  not found via export -- may have been deleted outside this script."
        fi
    done
}

## Print manual console-removal instructions for each dashboard. There is
## no CLI delete command for dashboards on this dx-do build.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (unused; accepted
#   for symmetry with the other dxo2-scripts).
cmd_delete() {
    load_state

    local key varname dash_uid title any_found=0
    for key in "${DASH_KEYS[@]}"; do
        varname="DASH_UID_${key//-/_}"
        dash_uid="${!varname}"
        title="${DASH_TITLE[${key}]}"

        if [[ -z "${dash_uid}" ]]; then
            dash_uid="$(find_dash_uid "${key}")"
        fi

        if [[ -z "${dash_uid}" ]]; then
            info "'${title}': not found -- nothing to delete."
            continue
        fi

        any_found=1
        info "This dx-do build has no dashboard-delete command -- remove '${title}' manually:"
        info "  1. Open the DX O2 console -> Dashboards -> '${FOLDER_TITLE}' folder."
        info "  2. Open '${title}' (uid ${dash_uid})."
        info "  3. Dashboard settings -> Delete Dashboard."
    done

    if [[ "${any_found}" -eq 1 ]]; then
        info "After deleting, remove the state file so this script forgets them:"
        info "  rm -f ${STATE_FILE}"
    fi
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
