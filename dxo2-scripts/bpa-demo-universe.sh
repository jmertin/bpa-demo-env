#!/usr/bin/env bash
# bpa-demo-universe.sh - Create, check, or delete the "BPA Demo universe"
# APM Universe (a.k.a. classic APM "View") on the DX O2 tenant.
#
# `dx-do apm-universe` is the default/regular APM Universe surface (the
# `viewId` field it returns looks like `VIEW###`) -- distinct from
# `o2-universe`, the legacy OI v2 surface, which this script does not use.
#
# A Universe scopes a slice of the tenant's topology/metric data for
# dashboards and views. Unlike a Service (a content QUERY that matches
# entities dynamically), a Universe is populated with an explicit list of
# metric-source agent paths via `apm-universe add-metric-source` -- there is
# no query-based membership mechanism exposed over the CLI.
#
# Structure created:
#   Universe "BPA Demo universe"
#     3 metric sources (EXACT agent paths), covering all 4 of the app's
#     known telemetry-producing identities:
#       1. Infrastructure Agent (MySQL/MariaDB DB Monitor extension)
#            SuperDomain|bpa-demo-host|bpa-demo|bpa-demo-infra-agent
#       2. PHP probe agent (frontend URLs + DB backend calls)
#            SuperDomain|bpa-demo-php-probe|php-probes|bpa-demo-infra-agent(/usr/sbin/apache2)
#       3. BPA WebServer Agent -- covers BOTH the "BPA agent" and the
#          "Browser agent" the app reports. Per this session's own
#          investigation (see CLAUDE.md's dxo2-scripts section and
#          dxo2-scripts/README.md's Alerts section): the Browser Agent (BA
#          snippet)'s page-load/page-hits timing is not a fourth,
#          independently-addressable topology entity -- it's reported
#          into APM by the BPA Webserver Extension under this single
#          agent identity. A separate "Custom Business Application Agent
#          (Virtual)" path shows the same values again as a rollup, but is
#          not a real entity (confirmed empirically: no content-query
#          attribute matches it, and it cannot be added as a metric
#          source either -- `add-metric-source` operates on real NASS
#          agent paths, and this one isn't one).
#            SuperDomain|Experience Collector Host|DxC Agent|Logstash-APM-Plugin
#
# All three source paths were already confirmed live/real earlier in this
# project's history (via `dx-done agent list`/`metric data` for the first
# two; via direct `metricgrouping`/`service` dry-run+live testing for the
# third, since it never appears in `agent list`). This script does not
# re-verify them -- it trusts that prior verification.
#
# The companion "BPA-Demo" Service (dxo2-scripts/bpa-demo-service.sh) is a
# separate resource covering the same telemetry via a content QUERY
# (`agent EQUALS`/`applicationName EQUALS`) rather than an explicit source
# list; this script does not create or touch it.
#
# Usage:
#   dxo2-scripts/bpa-demo-universe.sh create   - create the Universe and add
#                                        all 3 metric sources. Safe to
#                                        re-run: if the Universe already
#                                        exists, adds any missing metric
#                                        source instead of no-op'ing.
#   dxo2-scripts/bpa-demo-universe.sh check    - print whether it exists and
#                                        its current definition.
#   dxo2-scripts/bpa-demo-universe.sh delete   - delete the Universe.
#                                        Prompts for confirmation; pass
#                                        -y|--yes to skip it.
#   dxo2-scripts/bpa-demo-universe.sh -h|--help - print this help.
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
#   dxo2-scripts/.state/bpa-demo-universe.env (git-ignored) so check/delete
#   can find it again -- `apm-universe` has no "get by name" command, only
#   `list` (dumps every universe in the tenant as JSON) and `detail`/
#   `add-metric-source`/`delete` (which all take the id). If the state file
#   is lost, find the id via `dx-do apm-universe list output.format=json`
#   (redirect to a file, not a pipe -- large tenants can exceed the ~64KB
#   pipe-truncation limit other dx-do list commands are known to hit) and
#   search for the "BPA Demo universe" label.
#
# Gotchas discovered while writing this script (2026-07-06):
#   - `apm-universe create` does NOT honor `dry-run` -- it's silently
#     ignored ("ignoring extra args") and the universe is created for
#     real immediately, same as `managementmodule create`/`alert create`'s
#     lack of a dry-run safety net documented elsewhere in this directory.
#   - `create`'s id param is `name=`; every other subcommand
#     (`detail`/`add-metric-source`) takes `universeId=`; `delete` takes
#     both `id=` and `name=` (guard against deleting the wrong one, same
#     pattern as `alert delete`/`metricgrouping delete`). Three different
#     param names for the same id across four subcommands -- don't assume
#     one name works everywhere.
#   - `metricSourceType` must be `EXACT` or `REGEX` (enum-validated).
#     Multiple `EXACT` sources added via separate `add-metric-source` calls
#     accumulate into ONE specifier's `names` array server-side, not one
#     specifier per call -- confirmed via `apm-universe export`.
#   - `export`'s `exportFile=` param is silently ignored; it always prints
#     the full JSON to stdout regardless.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly UNIVERSE_NAME="BPA Demo universe"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-universe.env"

# The 3 real agent paths covering all 4 named telemetry-producing
# identities (BPA WebServer Agent covers both "BPA agent" and "Browser
# agent" -- see header comment).
readonly METRIC_SOURCES=(
    'SuperDomain|bpa-demo-host|bpa-demo|bpa-demo-infra-agent'
    'SuperDomain|bpa-demo-php-probe|php-probes|bpa-demo-infra-agent(/usr/sbin/apache2)'
    'SuperDomain|Experience Collector Host|DxC Agent|Logstash-APM-Plugin'
)

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-universe] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-universe] ERROR: $*" >&2
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

## Create the Universe and add all 3 metric sources. Safe to re-run: adds
## any missing source instead of no-op'ing if the Universe already exists.
cmd_create() {
    load_state

    # Don't trust the state file alone -- verify the id still resolves on
    # the tenant before treating it as "already created." Confirmed
    # necessary on the sibling bpa-demo-services-universe.sh: a Universe
    # deleted out-of-band (console, or someone else) while the state file
    # still pointed at it made 'create' silently no-op instead of
    # noticing and recreating it.
    if [[ -n "${UNIVERSE_ID}" ]] && ! "${DX_DO_BIN}" apm-universe detail universeId="${UNIVERSE_ID}" >/dev/null 2>&1; then
        info "State file points at ${UNIVERSE_ID} but it no longer exists on the tenant -- recreating."
        UNIVERSE_ID=""
    fi

    if [[ -z "${UNIVERSE_ID}" ]]; then
        info "Creating Universe '${UNIVERSE_NAME}'..."
        local create_output
        create_output=$(run_dx_do apm-universe create name="${UNIVERSE_NAME}")
        echo "${create_output}"
        UNIVERSE_ID=$(printf '%s' "${create_output}" | grep -o '(VIEW[0-9]*)' | head -1 | tr -d '()')
        [[ -n "${UNIVERSE_ID}" ]] || fatal "Could not parse Universe id from dx-do output above."
        info "Universe created: ${UNIVERSE_ID}"
        save_state
    else
        info "Universe '${UNIVERSE_NAME}' already created (${UNIVERSE_ID}) -- checking metric sources."
    fi

    local export_json
    export_json=$(run_dx_do apm-universe export universeId="${UNIVERSE_ID}")

    local source
    for source in "${METRIC_SOURCES[@]}"; do
        if printf '%s' "${export_json}" | grep -qF "${source}"; then
            info "Metric source already present: ${source}"
            continue
        fi
        info "Adding missing metric source: ${source}"
        run_dx_do apm-universe add-metric-source \
            universeId="${UNIVERSE_ID}" \
            metricSourceType=EXACT \
            metricSource="${source}"
    done

    info "Done. State saved to ${STATE_FILE}."
}

## Print whether the Universe exists and its current definition.
cmd_check() {
    load_state

    if [[ -z "${UNIVERSE_ID}" ]]; then
        info "No state file at ${STATE_FILE} -- '${SCRIPT_NAME} create' has not been run here."
        info "The Universe may still exist under a different state file/machine -- check 'dx-do apm-universe list output.format=json' (redirect to a file) for the label '${UNIVERSE_NAME}'."
        exit 1
    fi

    info "Universe (${UNIVERSE_ID}):"
    if run_dx_do apm-universe detail universeId="${UNIVERSE_ID}"; then
        :
    else
        info "  not found -- may have been deleted outside this script."
        exit 1
    fi

    info "Full definition:"
    run_dx_do apm-universe export universeId="${UNIVERSE_ID}"
}

## Delete the Universe. Prompts for confirmation unless -y/--yes is given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    load_state

    if [[ -z "${UNIVERSE_ID}" ]]; then
        info "No state file at ${STATE_FILE} -- nothing recorded here to delete."
        info "If '${UNIVERSE_NAME}' still exists in the tenant, remove it via 'dx-do apm-universe delete id=<id> name=\"${UNIVERSE_NAME}\"' (find <id> via 'dx-do apm-universe list output.format=json') or the console."
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
