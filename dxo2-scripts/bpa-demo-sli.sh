#!/usr/bin/env bash
# bpa-demo-sli.sh - Create, check, or unbind the "BPA-Demo Frontend Response
# Time" Service Level Indicator (SLI) for the "BPA-Demo" Service.
#
# Structure created:
#   SLI "BPA-Demo Frontend Response Time" (sliId 2767 in this tenant)
#     Raw metric: average of every Frontends|Apps|BPA-Demo|URLs|<page>
#       :Average Response Time (ms) attribute reported by the PHP probe
#       agent (SuperDomain|bpa-demo-php-probe|php-probes|
#       bpa-demo-infra-agent(/usr/sbin/apache2)), matched via a REGEX
#       specifier that deliberately excludes the nested "Called
#       Backends|...SQL..." sub-metrics -- this is page load time, not
#       blended with DB query time. Surfaces the `trouble` use case's
#       5000-sequential-DB-read slowdown regardless of which page the
#       trouble user visits.
#     Written onto the BPA-Demo service vertex as an is_sli-tagged metric
#       named "BPA-Demo Frontend Response Time", sli_type "Latency".
#     Phase 1 only: no sloDefinition (threshold/rolling-percentage/
#       error-budget) or alertDefinition yet -- see "Why no SLO yet" below.
#
# The dx-do `sli` command group has no native create/delete: a new SLI is
# made by `sli import`-ing a raw SLI export JSON file, bound to a target
# service via serviceName=. The unbind counterpart is `sli exclude-service`
# (there is no `sli delete` -- excluding a service just returns the SLI to
# the unbound-template state the tenant's other 3 pre-existing SLIs are
# already in; the SLI definition itself is not deleted from the tenant).
#
# Why no SLO yet: the tenant's two SLI examples with a full SLO/error-budget
# pipeline (sliId 813, 873) use `attributeType` numeric codes and an
# `errorbudget` threshold whose exact units/semantics are not documented and
# differ between the two examples in ways this script's author could not
# fully verify from the outside. Rather than guess and risk a
# silently-broken SLO pipeline -- the same failure mode as the
# agentExpressions bug in bpa-demo-management-module.sh -- this script
# ships the raw SLI only, verified with real matched data (52 live metrics
# at creation time), and leaves the SLO/error-budget/alert layer as a
# follow-up once its semantics are confirmed.
#
# Usage:
#   dxo2-scripts/bpa-demo-sli.sh create   - import the SLI bound to
#                                            BPA-Demo. Safe to re-run: if it
#                                            already exists but is unbound
#                                            or has zero live metrics,
#                                            self-heals via include-service.
#   dxo2-scripts/bpa-demo-sli.sh check    - print whether it exists, is
#                                            bound to BPA-Demo, and its
#                                            live metric count.
#   dxo2-scripts/bpa-demo-sli.sh delete   - unbind BPA-Demo from the SLI
#                                            (sli exclude-service). Prompts
#                                            for confirmation; pass -y|--yes
#                                            to skip it. Does not delete the
#                                            SLI definition itself.
#   dxo2-scripts/bpa-demo-sli.sh -h|--help - print this help.
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
#   This script persists the sliId it creates to
#   dxo2-scripts/.state/bpa-demo-sli.env (git-ignored) so check/delete can
#   find it again. If that file is lost, the SLI still exists in the tenant
#   -- find it via `dx-do sli list` (the name "BPA-Demo Frontend Response
#   Time" is visible there even without the state file).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SLI_NAME="BPA-Demo Frontend Response Time"
readonly SERVICE_NAME="BPA-Demo"
readonly TEMPLATE_FILE="${SCRIPT_DIR}/templates/bpa-demo-response-time-sli.json"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-sli.env"

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-sli] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-sli] ERROR: $*" >&2
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

## Verify the dx-do binary, tenant config, and SLI template are present
## before doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
    [[ -f "${TEMPLATE_FILE}" ]] || \
        fatal "SLI template not found at ${TEMPLATE_FILE}."
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

## Load the sliId from the state file into SLI_ID, if it exists.
load_state() {
    SLI_ID=""
    # An `if` guard, not `[[ -f ]] && source` -- the latter is this
    # function's last statement, so under `set -e` a nonexistent state
    # file (the common first-run case) would make load_state itself
    # return 1 and silently kill the whole script when called bare.
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist SLI_ID to the state file.
save_state() {
    mkdir -p "${STATE_DIR}"
    printf 'SLI_ID=%q\n' "${SLI_ID}" > "${STATE_FILE}"
}

## Look up the sliId for SLI_NAME via `sli list`, regardless of state file.
## Prints the id, or nothing if not found.
find_sli_id() {
    "${DX_DO_BIN}" sli list output.format=json 2>/dev/null \
        | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data:
    if row.get('sliName', '').strip() == '${SLI_NAME}':
        print(row['sliId'])
        break
" 2>/dev/null || true
}

## Create the SLI, bound to BPA-Demo. Safe to re-run.
cmd_create() {
    load_state

    if [[ -z "${SLI_ID}" ]]; then
        SLI_ID="$(find_sli_id)"
    fi

    if [[ -n "${SLI_ID}" ]]; then
        info "SLI '${SLI_NAME}' already exists (sliId ${SLI_ID}) -- checking it's bound to '${SERVICE_NAME}' and has live metrics."
        local detail_json
        detail_json=$("${DX_DO_BIN}" sli list output.format=json 2>/dev/null || true)
        local bound total
        bound=$(printf '%s' "${detail_json}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for row in data:
    if str(row.get('sliId')) == '${SLI_ID}':
        print('yes' if '${SERVICE_NAME}' in row.get('serviceNames', []) else 'no')
        print(row.get('totalMetrics', 0))
        break
" 2>/dev/null || echo "no
0")
        total=$(printf '%s' "${bound}" | tail -1)
        bound=$(printf '%s' "${bound}" | head -1)

        if [[ "${bound}" != "yes" ]]; then
            info "SLI exists but is not bound to '${SERVICE_NAME}' -- self-healing with 'sli include-service'."
            run_dx_do sli include-service sliId="${SLI_ID}" serviceName="${SERVICE_NAME}" dry-run=false
        elif [[ "${total}" -eq 0 ]]; then
            info "WARNING: SLI is bound to '${SERVICE_NAME}' but reports zero live metrics -- the underlying PHP probe frontend metrics may not be flowing. Check with '${SCRIPT_NAME} check'."
        else
            info "Bound with ${total} live metrics -- nothing to do."
        fi
        save_state
        info "Run '${SCRIPT_NAME} check' to see its current definition."
        return 0
    fi

    info "Importing SLI '${SLI_NAME}' for service '${SERVICE_NAME}'..."
    local import_json
    import_json=$("${DX_DO_BIN}" sli import \
        file="${TEMPLATE_FILE}" \
        serviceName="${SERVICE_NAME}" \
        dry-run=false 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${import_json}"
    SLI_ID=$(printf '%s' "${import_json}" | grep -o '"groupId": *[0-9]*' | head -1 | grep -o '[0-9]*$')
    [[ -n "${SLI_ID}" ]] || fatal "Could not parse SLI id (groupId) from dx-do output above."
    info "SLI created: sliId ${SLI_ID}"

    save_state
    info "Done. State saved to ${STATE_FILE}."
    info "Note: raw SLI only -- no SLO/error-budget/alert layer yet (see this script's header comment)."
}

## Print whether the SLI exists, is bound to BPA-Demo, and its live metric
## count / current definition.
cmd_check() {
    load_state

    if [[ -z "${SLI_ID}" ]]; then
        SLI_ID="$(find_sli_id)"
    fi

    if [[ -z "${SLI_ID}" ]]; then
        info "No state file at ${STATE_FILE} and no SLI named '${SLI_NAME}' found via 'dx-do sli list' -- '${SCRIPT_NAME} create' has not been run."
        exit 1
    fi

    info "SLI (sliId ${SLI_ID}):"
    run_dx_do_json sli list output.format=json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for row in data:
    if str(row.get('sliId')) == '${SLI_ID}':
        print(json.dumps(row, indent=2))
        break
else:
    print('  not found -- may have been deleted outside this script.')
"

    info "Bound services (via 'service slis'):"
    run_dx_do service slis serviceName="${SERVICE_NAME}" output.format=json || info "  none currently bound."
}

## Unbind BPA-Demo from the SLI (sli exclude-service). Does not delete the
## SLI definition itself -- there is no `sli delete` command; excluding the
## service returns it to the unbound-template state. Prompts for
## confirmation unless -y/--yes is given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    load_state

    if [[ -z "${SLI_ID}" ]]; then
        SLI_ID="$(find_sli_id)"
    fi

    if [[ -z "${SLI_ID}" ]]; then
        info "No state file at ${STATE_FILE} and no SLI named '${SLI_NAME}' found -- nothing to unbind."
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
        read -r -p "Unbind '${SERVICE_NAME}' from SLI '${SLI_NAME}' (sliId ${SLI_ID})? The SLI definition itself is not deleted. [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    info "Excluding '${SERVICE_NAME}' from SLI (sliId ${SLI_ID})..."
    run_dx_do sli exclude-service sliId="${SLI_ID}" serviceName="${SERVICE_NAME}" dry-run=false || info "  already unbound."

    rm -f "${STATE_FILE}"
    info "Done. The SLI definition itself still exists in the tenant, unbound (same state as the tenant's other pre-existing SLIs)."
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
