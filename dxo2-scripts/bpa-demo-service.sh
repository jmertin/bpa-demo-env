#!/usr/bin/env bash
# bpa-demo-service.sh - Create, check, or delete the "BPA-Demo" DX O2 Service.
#
# The Service groups every BPA-Demo-related telemetry entity under one DX O2
# console view:
#   - php-probe frontend URLs (/shop, /info, /dxo2, /basket, ...)
#   - BPA Webserver Extension business transactions (page_login,
#     SHOP-LIST-MATTER, SHOP-LIST-SHELLY, ...)
#   - the BPA WebServer Agent's own reporting identity, `Experience
#     Collector Host|DxC Agent|Logstash-APM-Plugin` -- this is where the
#     Browser Agent (BA snippet)'s page-load/page-hits timing actually
#     lands (see dxo2-scripts/.state and this script's own history: the BA
#     snippet is the source, the BPA plugin is what reports it into APM
#     under this agent identity, per-URL under `Business Segment|BPA
#     Demo|<url>:<leaf>`). A THIRD path,
#     `Custom Metric Host (Virtual)|Custom Metric Process (Virtual)|Custom
#     Business Application Agent (Virtual)`, shows the same values rolled
#     up under a Business Service view, but is NOT a real topology
#     entity -- confirmed empirically (2026-07-06) that no content-query
#     attribute (`agent EQUALS`/`MATCHES` on the full path or bare name,
#     `type EQUALS AGENT` + `name` variants) matches it; it only exists as
#     a metric-source-path label, never as an AGENT vertex. So there is no
#     separate "Browser Agent" content group to add -- group g4 below
#     already covers its data.
#   - the mysql backend database -- both the php-probe's inferred DATABASE
#     dependency and the DB Monitor extension's own richer CI
#
# Usage:
#   dxo2-scripts/bpa-demo-service.sh create        - create the Service.
#                                                     Safe to re-run: warns
#                                                     instead of failing if
#                                                     it already exists.
#   dxo2-scripts/bpa-demo-service.sh check         - print whether the
#                                                     Service exists and its
#                                                     current definition.
#   dxo2-scripts/bpa-demo-service.sh delete        - delete the Service.
#                                                     Prompts for
#                                                     confirmation; pass
#                                                     -y|--yes to skip it.
#   dxo2-scripts/bpa-demo-service.sh -h|--help     - print this help and exit.
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
#                                        dx-do's own setup documentation
#                                        (https://github.com/kialambroca/dx-do-dist)
#                                        for how to generate this file.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SERVICE_NAME="BPA-Demo"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly BPA_WEBSERVER_AGENT="Experience Collector Host|DxC Agent|Logstash-APM-Plugin"

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-service] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-service] ERROR: $*" >&2
    exit 1
}

## Resolve the dx-do binary path: DX_DO env var override, else a
## platform-appropriate default under tools/.
#
# @return string
#   Absolute path to the expected dx-do binary (may not exist yet).
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

## Create the BPA-Demo Service. Safe to re-run: if it already exists, adds
## any content groups declared above that are missing from the live
## definition (e.g. the BPA WebServer Agent group, added 2026-07-06 to a
## Service that already existed) instead of just no-op'ing.
cmd_create() {
    local detail_json
    if detail_json=$("${DX_DO_BIN}" service detail serviceName="${SERVICE_NAME}" output.format=json 2>/dev/null); then
        info "Service '${SERVICE_NAME}' already exists -- checking for missing content groups."
        if printf '%s' "${detail_json}" | grep -qF "${BPA_WEBSERVER_AGENT}"; then
            info "BPA WebServer Agent content group already present -- nothing to do."
        else
            info "Adding missing BPA WebServer Agent content group..."
            run_dx_do service add-content serviceName="${SERVICE_NAME}" \
                content.g4.agent.EQUALS="${BPA_WEBSERVER_AGENT}" \
                dry-run=false
        fi
        info "Run '${SCRIPT_NAME} check' to see its current definition."
        return 0
    fi

    info "Creating Service '${SERVICE_NAME}'..."
    run_dx_do service create name="${SERVICE_NAME}" \
        content.g1.applicationName.EQUALS="${SERVICE_NAME}" \
        content.g2.agent.EQUALS="bpa-demo-host|bpa-demo|bpa-demo-infra-agent" \
        content.g3.agent.EQUALS="bpa-demo-php-probe|php-probes|bpa-demo-infra-agent(/usr/sbin/apache2)" \
        content.g4.agent.EQUALS="${BPA_WEBSERVER_AGENT}" \
        dry-run=false
    info "Done. Allow ~30 seconds for the Service to become visible in the console."
}

## Print whether the Service exists and its current definition.
cmd_check() {
    info "Checking Service '${SERVICE_NAME}'..."
    if run_dx_do service detail serviceName="${SERVICE_NAME}"; then
        info "Service '${SERVICE_NAME}' exists."
    else
        info "Service '${SERVICE_NAME}' does not exist."
        exit 1
    fi
}

## Delete the Service. Prompts for confirmation unless -y/--yes is given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    local skip_confirm="false"
    local arg
    for arg in "$@"; do
        case "${arg}" in
            -y|--yes) skip_confirm="true" ;;
        esac
    done

    if [[ "${skip_confirm}" != "true" ]]; then
        local reply
        read -r -p "Delete Service '${SERVICE_NAME}' from the DX O2 tenant? [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    info "Deleting Service '${SERVICE_NAME}'..."
    if run_dx_do service delete-service name="${SERVICE_NAME}"; then
        info "Done."
    else
        info "Service '${SERVICE_NAME}' was not found (already deleted?)."
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
