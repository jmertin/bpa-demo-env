#!/usr/bin/env bash
# bpa-demo-management-module.sh - Create, check, or delete the per-platform
# "BPA-Demo" APM Management Module and its alert(s) that catch demo
# use-case symptoms.
#
# Structure created (one platform at a time):
#   Management Module "BPA-Demo" (docker) / "BPA-Demo K8s" (k8s)
#     agentExpressions: SuperDomain\|.*bpa-demo-<platform>.*  (matches both
#       the Infrastructure Agent and the PHP probe agent for that platform
#       only -- see "Bug fixed 2026-08-26" below)
#     Metric Grouping "BPA-Demo Frontend Response Time"
#       attributeNamePattern: Frontends|Apps|bpa-demo-<platform>|URLs|.*:
#       Average Response Time (ms)  (matches every tracked frontend URL
#       for that platform's own app-name identity)
#       sourceNamePattern: SuperDomain\|.*bpa-demo-<platform>.*, with
#       useManagementModuleAgentExpression=false -- the MG carries its own
#       explicit copy of the MM's agent scope rather than inheriting it.
#       See "Bug fixed 2026-07-06" below for why.
#       Alert "Trouble User - High Response Time"
#         GREATER_THAN, warning=100ms, error=250ms
#         Catches the `trouble` use case (usecases/trouble.php - 5000
#         sequential DB reads per request). Thresholds are set from real
#         measurements, not guessed: normal page loads are ~6-7ms on this
#         stack; the trouble use case measured ~350-690ms -- both
#         comfortably clear of these thresholds with margin.
#
# Bug fixed 2026-07-06: this script originally set AGENT_EXPRESSION to the
# bare 'bpa-demo.*' and relied on the Metric Grouping inheriting it
# (useManagementModuleAgentExpression defaults to true). The 4-segment MM
# agentExpressions regime is implicitly start-anchored against the FULL
# path (`SuperDomain|<host>|<process>|<agent>`), so a pattern without a
# leading `SuperDomain\|` (or `.*\|`) never matches anything -- the create
# call succeeds, the console shows the alert, but `metricgrouping
# list-metrics` (and therefore the alert itself) silently returns zero
# matched series forever. Confirmed empirically: recreating the identical
# grouping with an explicit `sourceNamePattern='SuperDomain\|.*bpa-demo.*'`
# and `useManagementModuleAgentExpression=false` immediately returns 30+
# live matches. Fixed by giving the Metric Grouping its own explicit,
# correctly-anchored sourceNamePattern instead of inheriting the MM's
# (also corrected, for consistency, even though nothing currently depends
# on the MM-level value now that the MG no longer inherits it).
#
# Bug fixed 2026-07-10: the Metric Grouping's attributeNamePattern hardcoded
# the literal application name "BPA-Demo" (Frontends|Apps|BPA-Demo|URLs|...).
# Adding DEPLOYMENT_NAME/DEPLOYMENT_POSTFIX to .config (see CLAUDE.md's
# "Deployment identity" section) made APMIA_APP_NAME -- which becomes this
# exact attribute-path segment via the PHP probe's wily_php_agent.application.name
# INI property -- default to the deployment id ("bpa-demo-k8s"/"bpa-demo-docker")
# instead of a fixed "BPA-Demo", so the literal segment stopped matching
# anything (confirmed live via `nass query`: the real attribute prefix is now
# Frontends|Apps|bpa-demo-k8s|... and Frontends|Apps|bpa-demo-docker|...).
# Fixed (at the time) by wildcarding that segment to bpa-demo-[^|]* so the
# grouping matched any deployment's app name in one shared MM -- since
# superseded by the 2026-08-26 split below, which un-wildcards it again
# into two platform-specific literals instead.
#
# Bug fixed 2026-08-26, reported by the user: the wildcarded
# `bpa-demo-[^|]*`/`.*bpa-demo.*` segments matched BOTH the Docker and
# Kubernetes deployment's identities in one shared Management Module --
# a `trouble`-use-case spike on either deployment fired the identical
# alert with no way to tell which deployment caused it. Split into two
# independent Management Modules, one per platform, each with a literal
# (not wildcarded) identity segment:
#
#   docker -> Management Module "BPA-Demo"        -- unchanged name,
#                                                      repointed
#   k8s    -> Management Module "BPA-Demo K8s"    -- new
#
# Only `trouble` has a real, currently-observable APM signal. `empty_basket`
# (basket total always 0) and `locked` (blocks login) do not currently
# produce any performance or error-rate anomaly -- see CLAUDE.md's "Demo
# use cases" section and this script's own commit history for why. Add
# more Metric Groupings + Alerts to this same Management Module as more
# use-case signals become available (e.g. once BPA is configured to expose
# RESP_HEADER_X_BASKET_TOTAL as an attribute).
#
# Usage:
#   dxo2-scripts/bpa-demo-management-module.sh <docker|k8s> create   -
#                                                create that platform's
#                                                module, metric grouping,
#                                                and alert. Safe to
#                                                re-run: warns instead of
#                                                failing if already
#                                                created.
#   dxo2-scripts/bpa-demo-management-module.sh <docker|k8s> check    -
#                                                print whether that
#                                                platform's resources
#                                                exist and their current
#                                                definition.
#   dxo2-scripts/bpa-demo-management-module.sh <docker|k8s> delete   -
#                                                delete that platform's
#                                                alert, metric grouping,
#                                                and management module.
#                                                Prompts for
#                                                confirmation; pass
#                                                -y|--yes to skip it.
#   dxo2-scripts/bpa-demo-management-module.sh -h|--help - print this help.
#
# The <docker|k8s> platform argument is required and must come first -- the
# script exits with an error if it's missing or not exactly one of those
# two values, before doing anything else.
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
#
# State:
#   dx-do's classic-APM ids (mm-<n>, mg-<n>, simplealert-<n>) are not
#   reliably re-discoverable by name from the CLI alone (managementmodule
#   list's table output wraps across multiple lines per row and has no
#   raw-JSON mode). This script persists the ids it creates to
#   dxo2-scripts/.state/bpa-demo-management-module-<docker|k8s>.env
#   (git-ignored) so check/delete can find them again. If that file is
#   lost, the resources still exist in the tenant -- find and remove them
#   via the console, or via `dx-do managementmodule list` (the module's
#   own name, "BPA-Demo"/"BPA-Demo K8s", is visible there even without
#   the state file).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly METRIC_GROUPING_NAME="BPA-Demo Frontend Response Time"
readonly ALERT_NAME="Trouble User - High Response Time"
readonly WARNING_THRESHOLD_MS="100"
readonly ERROR_THRESHOLD_MS="250"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-management-module] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-management-module] ERROR: $*" >&2
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

## Load ids from the state file into MM_ID/MG_ID/ALERT_ID, if it exists.
load_state() {
    MM_ID=""
    MG_ID=""
    ALERT_ID=""
    # An `if` guard, not `[[ -f ]] && source` -- the latter is this
    # function's last statement, so under `set -e` a nonexistent state
    # file (the common first-run case) would make load_state itself
    # return 1 and silently kill the whole script when called bare.
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist MM_ID/MG_ID/ALERT_ID to the state file.
save_state() {
    mkdir -p "${STATE_DIR}"
    {
        printf 'MM_ID=%q\n' "${MM_ID}"
        printf 'MG_ID=%q\n' "${MG_ID}"
        printf 'ALERT_ID=%q\n' "${ALERT_ID}"
    } > "${STATE_FILE}"
}

## Create the management module, metric grouping, and alert. Safe to re-run.
cmd_create() {
    load_state

    if [[ -n "${MM_ID}" ]] && "${DX_DO_BIN}" managementmodule list 2>/dev/null | grep -q "${MM_ID}"; then
        info "Management Module '${MODULE_NAME}' already created (${MM_ID}) -- checking the metric grouping's pattern is the current platform-specific one and actually matches something."
        # Check the pattern itself, not just "any live matches" -- a resource
        # migrated from a pre-split shared/wildcarded pattern (see "Bug fixed
        # 2026-08-26" in this script's header) can still have live matches
        # under the OLD wildcarded pattern (it matched both platforms), which
        # would otherwise make a match-count-only check falsely report
        # healthy without ever picking up the new platform-specific literal.
        local current_pattern
        current_pattern=$("${DX_DO_BIN}" metricgrouping detail metricGroupingId="${MG_ID}" managementModuleId="${MM_ID}" output.format=json 2>/dev/null \
            | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('specifier', {}).get('attributeNameSpecifier', {}).get('pattern', ''))
except Exception:
    pass
" 2>/dev/null || true)
        local match_count="0"
        if [[ "${current_pattern}" == "${ATTRIBUTE_NAME_PATTERN}" ]]; then
            local metrics_json
            metrics_json=$("${DX_DO_BIN}" metricgrouping list-metrics metricGroupingId="${MG_ID}" managementModuleId="${MM_ID}" output.format=json 2>/dev/null || true)
            # Count data rows only, not the ["metric.source","metric.path"]
            # header row -- every real row's first element is a
            # "SuperDomain|..." agent path, which the header line never
            # contains.
            match_count=$(printf '%s' "${metrics_json}" | grep -c '"SuperDomain|' || true)
        fi
        if [[ "${match_count}" -gt 0 ]]; then
            info "Metric Grouping (${MG_ID}) already has the current pattern and live matches -- nothing to do."
        else
            info "Metric Grouping (${MG_ID}) has a stale pattern or ZERO live matches -- self-healing with the current sourceNamePattern/attributeNamePattern."
            run_dx_do metricgrouping update \
                metricGroupingId="${MG_ID}" \
                managementModuleId="${MM_ID}" \
                attributeNamePattern="${ATTRIBUTE_NAME_PATTERN}" \
                sourceNamePattern="${AGENT_EXPRESSION}" \
                useManagementModuleAgentExpression=false \
                dry-run=false
        fi
        info "Run '${SCRIPT_NAME} ${PLATFORM} check' to see its current definition."
        return 0
    fi

    info "Creating Management Module '${MODULE_NAME}'..."
    local mm_json
    mm_json=$("${DX_DO_BIN}" managementmodule create \
        managementModuleName="${MODULE_NAME}" \
        "agentExpressions.g1=${AGENT_EXPRESSION}" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${mm_json}"
    MM_ID=$(printf '%s' "${mm_json}" | grep -o '"id": *"[^"]*"' | head -1 | sed 's/.*"\(mm-[0-9]*\)".*/\1/')
    [[ -n "${MM_ID}" ]] || fatal "Could not parse Management Module id from dx-do output above."
    info "Management Module created: ${MM_ID}"

    info "Creating Metric Grouping '${METRIC_GROUPING_NAME}'..."
    local mg_json
    mg_json=$("${DX_DO_BIN}" metricgrouping create \
        name="${METRIC_GROUPING_NAME}" \
        managementModuleId="${MM_ID}" \
        attributeNamePattern="${ATTRIBUTE_NAME_PATTERN}" \
        sourceNamePattern="${AGENT_EXPRESSION}" \
        useManagementModuleAgentExpression=false \
        active=true \
        dry-run=false 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${mg_json}"
    MG_ID=$(printf '%s' "${mg_json}" | grep -o '"id": *"[^"]*"' | head -1 | sed 's/.*"\(mg-[0-9]*\)".*/\1/')
    [[ -n "${MG_ID}" ]] || fatal "Could not parse Metric Grouping id from dx-do output above."
    info "Metric Grouping created: ${MG_ID}"

    info "Creating Alert '${ALERT_NAME}'..."
    local alert_json
    alert_json=$("${DX_DO_BIN}" alert create \
        name="${ALERT_NAME}" \
        managementModuleId="${MM_ID}" \
        metricGroupingId="${MG_ID}" \
        compareOperator="GREATER_THAN" \
        warningThreshold="${WARNING_THRESHOLD_MS}" \
        errorThreshold="${ERROR_THRESHOLD_MS}" \
        active=true \
        dry-run=false 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${alert_json}"
    ALERT_ID=$(printf '%s' "${alert_json}" | grep -o '"id": *"[^"]*"' | head -1 | sed 's/.*"\(simplealert-[0-9]*\)".*/\1/')
    [[ -n "${ALERT_ID}" ]] || fatal "Could not parse Alert id from dx-do output above."
    info "Alert created: ${ALERT_ID}"

    save_state
    info "Done. State saved to ${STATE_FILE}."
    info "Alert evaluates every 60s -- allow at least that long after triggering the trouble use case before checking for a raised alarm."
}

## Print whether the module/grouping/alert exist and their current definitions.
cmd_check() {
    load_state

    if [[ -z "${MM_ID}" ]]; then
        info "No state file at ${STATE_FILE} -- '${SCRIPT_NAME} ${PLATFORM} create' has not been run here."
        info "The resources may still exist under a different state file/machine -- check 'dx-do managementmodule list' for '${MODULE_NAME}'."
        exit 1
    fi

    info "Management Module (${MM_ID}):"
    run_dx_do managementmodule list | grep -A3 "${MM_ID}" || info "  not found -- may have been deleted outside this script."

    info "Metric Grouping (${MG_ID}):"
    if run_dx_do metricgrouping detail metricGroupingId="${MG_ID}" managementModuleId="${MM_ID}"; then
        :
    else
        info "  not found -- may have been deleted outside this script."
    fi

    info "Alert (${ALERT_ID}):"
    if run_dx_do alert detail alertId="${ALERT_ID}" managementModuleId="${MM_ID}"; then
        :
    else
        info "  not found -- may have been deleted outside this script."
    fi
}

## Delete the alert, metric grouping, and management module. Prompts for
## confirmation unless -y/--yes is given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    load_state

    if [[ -z "${MM_ID}" ]]; then
        info "No state file at ${STATE_FILE} -- nothing recorded here to delete."
        info "If '${MODULE_NAME}' still exists in the tenant, remove it via 'dx-do managementmodule delete managementModuleId=<id>' (find <id> via 'dx-do managementmodule list') or the console."
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
        read -r -p "Delete Management Module '${MODULE_NAME}' (${MM_ID}) and its metric grouping + alert from the DX O2 tenant? [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    info "Deleting Alert (${ALERT_ID})..."
    run_dx_do alert delete alertId="${ALERT_ID}" managementModuleId="${MM_ID}" || info "  already gone."

    info "Deleting Metric Grouping (${MG_ID})..."
    run_dx_do metricgrouping delete metricGroupingId="${MG_ID}" managementModuleId="${MM_ID}" dry-run=false || info "  already gone."

    info "Deleting Management Module (${MM_ID})..."
    run_dx_do managementmodule delete managementModuleId="${MM_ID}" || info "  already gone."

    rm -f "${STATE_FILE}"
    info "Done."
}

# == Platform argument ========================================================
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ -z "${1:-}" ]]; then
    usage
    fatal "Missing required <docker|k8s> argument. Usage: ${SCRIPT_NAME} <docker|k8s> <create|check|delete>"
fi

case "${1}" in
    docker) readonly PLATFORM="docker" ;;
    k8s)    readonly PLATFORM="k8s" ;;
    *)
        usage
        fatal "Invalid first argument '${1}' -- must be 'docker' or 'k8s'."
        ;;
esac
shift

case "${PLATFORM}" in
    docker)
        readonly IDENTITY="bpa-demo-docker"
        readonly MODULE_NAME="BPA-Demo"
        ;;
    k8s)
        readonly IDENTITY="bpa-demo-k8s"
        readonly MODULE_NAME="BPA-Demo K8s"
        ;;
esac
readonly ATTRIBUTE_NAME_PATTERN="Frontends\\|Apps\\|${IDENTITY}\\|URLs\\|.*:Average Response Time \\(ms\\)"
readonly AGENT_EXPRESSION="SuperDomain\\|.*${IDENTITY}.*"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-management-module-${PLATFORM}.env"

# == Subcommand argument =======================================================
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
