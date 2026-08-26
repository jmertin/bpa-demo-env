#!/usr/bin/env bash
# bpa-demo-service.sh - Create, check, or delete the per-platform "BPA-Demo"
# DX O2 Service.
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
# Bug fixed 2026-07-10: three of the four content groups used an exact-match
# `agent`/`applicationName EQUALS` on the pre-DEPLOYMENT_NAME/
# DEPLOYMENT_POSTFIX identity literals (bpa-demo-host/bpa-demo-infra-agent/
# bpa-demo-php-probe/BPA-Demo -- see CLAUDE.md's "Deployment identity"
# section), all now dead. `create`'s self-heal only ever checked for the
# fourth (BPA WebServer Agent) group, so re-running it after the identity
# change did nothing for the other three. Fixed both the identity mismatch
# and the self-heal gap:
#   - Switched all three from `EQUALS` (exact match on one literal) to
#     `MATCHES` (regex) with a wildcarded `bpa-demo-.*` segment, so the
#     Service covers any deployment's real identity, present or future,
#     instead of one specific literal that a future identity change could
#     break again. Confirmed `MATCHES` is a real, working operator on this
#     API via a `service add-content ... dry-run=true` probe before
#     committing anything -- its preview correctly matched both
#     bpa-demo-k8s and bpa-demo-docker's live agent vertices.
#   - `create` now uses `service set-content` (a full replace of all four
#     groups) instead of `service add-content` (checks for and adds only
#     one specific group) for its self-heal path, so re-running it always
#     brings the live content query back in sync with the four groups
#     declared in this script, rather than leaving stale groups from an
#     earlier identity scheme sitting alongside new ones forever.
#   - Live content query confirmed via `service detail` immediately after
#     applying: all four groups present, `MATCHES`-based ones showing the
#     corrected regex, DxC group unchanged.
#
# Bug fixed 2026-08-21: PHP_PROBE_AGENT_PATTERN required a trailing
# `(/usr/sbin/apache2)` on the agent segment -- dead since the 2026-07-15
# UnknownAgent fix disabled the IA's remote-agent auto-naming (the thing
# that was appending the running process's path to the identity in the
# first place). Confirmed via `nass query-metadata` that the live source
# is the bare `SuperDomain|bpa-demo-docker|php-probes|bpa-demo-docker`,
# with no `(/usr/sbin/apache2)` variant anywhere in the catalog. Same root
# cause as the identically-dated fix in bpa-demo-agent-alerts.sh -- see
# that script's header for the full writeup. Fixed by making the suffix
# optional rather than deleting it, so the pattern still matches if
# auto-naming is ever re-enabled. `create`'s `set-content` self-heal picks
# this up automatically on the next run.
#
# Bug fixed 2026-08-26, reported by the user: the wildcarded `bpa-demo-.*`
# segment in three of the four content groups matched BOTH the Docker and
# Kubernetes deployment's identities in one Service -- there was no way to
# tell which deployment a given piece of telemetry came from once it
# landed in the console. Split into two independent Services, one per
# platform, each with a literal (not wildcarded) identity pattern:
#
#   docker -> Service "BPA-Demo"        -- unchanged name, repointed to a
#                                           docker-only literal pattern
#   k8s    -> Service "BPA-Demo K8s"    -- new
#
# Each pattern still tolerates an optional `%N` disambiguation suffix
# (`bpa-demo-docker(%\d+)?`) in case DX O2 ever needs to disambiguate a
# same-identity reconnection -- see CLAUDE.md's "Deployment identity"
# section for why that can happen and the same `(%\d+)?` convention already
# used in bpa-demo-application-dashboards.sh's templates. The fourth group
# (BPA WebServer Agent / Browser Agent, `Logstash-APM-Plugin`) has no
# per-platform identity today (see bpa-demo-axa-app.sh's header for the
# newly-split AXA applications this may eventually enable distinguishing)
# and stays the same fixed literal on both platform's Services.
#
# Usage:
#   dxo2-scripts/bpa-demo-service.sh <docker|k8s> create   - create that
#                                        platform's Service, or if it
#                                        already exists, set its content
#                                        query to the current four groups
#                                        (idempotent, self-heals any stale
#                                        group left over from a prior
#                                        identity scheme).
#   dxo2-scripts/bpa-demo-service.sh <docker|k8s> check    - print whether
#                                        that platform's Service exists
#                                        and its current definition.
#   dxo2-scripts/bpa-demo-service.sh <docker|k8s> delete   - delete that
#                                        platform's Service. Prompts for
#                                        confirmation; pass -y|--yes to
#                                        skip it.
#   dxo2-scripts/bpa-demo-service.sh -h|--help     - print this help and exit.
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
#                                        dx-do's own setup documentation
#                                        (https://github.com/kialambroca/dx-do-dist)
#                                        for how to generate this file.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
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

## Create the platform's Service, or bring an existing one's content query up
## to date. Safe to re-run: uses `service set-content` (a full replace, not
## an incremental add) so the four groups declared above always match
## exactly what's live -- no stale groups left behind from a prior identity
## scheme (see "Bug fixed 2026-07-10" in this script's header).
cmd_create() {
    if "${DX_DO_BIN}" service detail serviceName="${SERVICE_NAME}" output.format=json >/dev/null 2>&1; then
        info "Service '${SERVICE_NAME}' already exists -- setting its content query to the current four groups (idempotent if already correct)."
    else
        info "Creating Service '${SERVICE_NAME}'..."
        run_dx_do service create name="${SERVICE_NAME}" \
            content.g1.applicationName.MATCHES="${APP_NAME_PATTERN}" \
            content.g2.agent.MATCHES="${INFRA_AGENT_PATTERN}" \
            content.g3.agent.MATCHES="${PHP_PROBE_AGENT_PATTERN}" \
            content.g4.agent.EQUALS="${BPA_WEBSERVER_AGENT}" \
            dry-run=false
        info "Done. Allow ~30 seconds for the Service to become visible in the console."
        return 0
    fi

    run_dx_do service set-content serviceName="${SERVICE_NAME}" \
        content.g1.applicationName.MATCHES="${APP_NAME_PATTERN}" \
        content.g2.agent.MATCHES="${INFRA_AGENT_PATTERN}" \
        content.g3.agent.MATCHES="${PHP_PROBE_AGENT_PATTERN}" \
        content.g4.agent.EQUALS="${BPA_WEBSERVER_AGENT}" \
        dry-run=false
    info "Done. Allow ~30 seconds for the change to become visible in the console."
    info "Run '${SCRIPT_NAME} ${PLATFORM} check' to see its current definition."
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
        readonly SERVICE_NAME="BPA-Demo"
        ;;
    k8s)
        readonly IDENTITY="bpa-demo-k8s"
        readonly SERVICE_NAME="BPA-Demo K8s"
        ;;
esac
readonly APP_NAME_PATTERN="^${IDENTITY}(%\\d+)?\$"
readonly INFRA_AGENT_PATTERN="^${IDENTITY}(%\\d+)?\\|${IDENTITY}(%\\d+)?\\|${IDENTITY}(%\\d+)?\$"
readonly PHP_PROBE_AGENT_PATTERN="^${IDENTITY}(%\\d+)?\\|php-probes\\|${IDENTITY}(%\\d+)?(\\(/usr/sbin/apache2\\))?\$"

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
