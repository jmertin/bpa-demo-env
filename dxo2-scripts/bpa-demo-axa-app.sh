#!/usr/bin/env bash
# bpa-demo-axa-app.sh - Create, check, or delete the per-platform "BPA Demo
# AXA" Application Experience Analytics (AXA) application on the DX O2
# tenant, and keep .config.example's matching APMIA_BROWSER_SNIPPET_*
# template in sync with its BrowserAgent snippet.
#
# AXA (`dx-do axa`) is the DX O2 surface for mobile/browser Real User
# Monitoring applications -- a distinct resource type from every other
# telemetry source this project's dxo2-scripts/*.sh manage (Services,
# Universes, Management Modules/Metric Groupings/Alerts, SLI groups,
# Dashboards). An AXA "application" definition is what a BrowserAgent (BA)
# snippet is generated *for*.
#
# Bug fixed 2026-08-26, reported by the user: this script originally
# created exactly ONE AXA application shared by both deployments, and
# .config/.config.example carried exactly ONE APMIA_BROWSER_SNIPPET
# variable read by both compose.sh (Docker) and deploy.sh (Kubernetes) --
# meaning every real browser session, regardless of which deployment it
# hit, reported into DX O2 under the identical AXA application with no way
# to tell them apart. Split into two independent AXA applications, one per
# platform, each with its own snippet and its own .config variable:
#
#   docker -> AXA application "BPA Demo AXA"        -> APMIA_BROWSER_SNIPPET_DOCKER
#   k8s    -> AXA application "BPA Demo AXA K8s"     -> APMIA_BROWSER_SNIPPET_K8S
#
# The "docker" name intentionally keeps the original, pre-split name
# ("BPA Demo AXA", not "BPA Demo AXA Docker") rather than being renamed to
# match the new convention -- `axa` has no rename/update-application
# command (confirmed via `dx-do help axa`), so the already-existing
# application from before this split couldn't be renamed even if a
# "Docker"-suffixed name were preferred; only a brand new one could be
# created with the new naming, which is what happened for "k8s".
#
# compose.sh now exports APMIA_BROWSER_SNIPPET from
# APMIA_BROWSER_SNIPPET_DOCKER only; deploy.sh's generate_values() now
# reads APMIA_BROWSER_SNIPPET_K8S only -- see those scripts' own comments.
# The container-facing environment variable name (APMIA_BROWSER_SNIPPET,
# read by the PHP probe's entrypoint patching) is unchanged on both
# platforms; only which .config variable feeds it differs.
#
# `secure=false` is passed to `axa create-application` -- that flag
# encrypts transient data at rest on devices and over the wire, which
# matters for the mobile SDKs AXA also supports but has no meaningful
# effect on a browser-only RUM snippet like this project's; kept simple
# for a demo app.
#
# `axa create-application` has no dry-run and rejects duplicate names
# outright (confirmed via `dx-do help describe group=axa
# command=create-application` -- no `dry-run` arg exists, unlike
# `service-universe create`/`sli create-group` elsewhere in this
# project), so `create` here always checks `axa list-applications` for
# an existing entry by name first, rather than calling create and
# handling the rejection.
#
# `axa get-application-snippet` ignores `output.format=json` entirely
# (confirmed live -- prints "ignoring extra args" and always returns
# pretty-printed, multi-line HTML with leading whitespace on each
# attribute line) and its noise-stripped raw output is what
# `fetch_snippet()` captures and collapses to the single-line form this
# project's `.config`/`.config.example` already use elsewhere.
#
# Structure created:
#   One AXA application per platform (a Web App / browser application, no
#   mobile SDK usage) -- a BrowserAgent snippet is generated for it and
#   written into .config.example's matching APMIA_BROWSER_SNIPPET_* line.
#
# Usage:
#   dxo2-scripts/bpa-demo-axa-app.sh <docker|k8s> create   - create that
#                                        platform's AXA application if it
#                                        doesn't exist (self-heals by
#                                        name), then (re-)fetch its
#                                        BrowserAgent snippet and patch it
#                                        into .config.example. Safe to
#                                        re-run -- always re-syncs the
#                                        snippet even if the application
#                                        already existed.
#   dxo2-scripts/bpa-demo-axa-app.sh <docker|k8s> check    - print whether
#                                        it exists, its current
#                                        definition, and its current
#                                        snippet.
#   dxo2-scripts/bpa-demo-axa-app.sh <docker|k8s> delete   - permanently
#                                        delete that platform's AXA
#                                        application (irreversible, no
#                                        dry-run on the API side) and
#                                        reset its .config.example
#                                        APMIA_BROWSER_SNIPPET_* line back
#                                        to the empty placeholder. Prompts
#                                        for confirmation; pass -y|--yes
#                                        to skip it.
#   dxo2-scripts/bpa-demo-axa-app.sh -h|--help - print this help.
#
# The <docker|k8s> platform argument is required and must come first --
# the script exits with an error if it's missing or not exactly one of
# those two values, before doing anything else (including reading .config
# or contacting the tenant).
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
#   python3                             used to parse JSON responses and
#                                        to patch .config.example without
#                                        relying on shell-quoting-fragile
#                                        sed/string interpolation (the
#                                        snippet contains many `/`, `:`,
#                                        and `"` characters).
#
# State:
#   Persists each platform's application key to
#   dxo2-scripts/.state/bpa-demo-axa-app-<docker|k8s>.env (git-ignored) so
#   check/delete can find it again. If lost, `axa list-applications` finds
#   it by name ("BPA Demo AXA" / "BPA Demo AXA K8s") regardless.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly CONFIG_EXAMPLE="${ROOT_DIR}/.config.example"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-axa-app] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-axa-app] ERROR: $*" >&2
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

## Verify the dx-do binary, tenant config, python3, and .config.example
## are present before doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
    [[ -f "${CONFIG_EXAMPLE}" ]] || \
        fatal ".config.example not found at ${CONFIG_EXAMPLE}."
    command -v python3 >/dev/null 2>&1 || \
        fatal "python3 is required (used to parse JSON responses and patch .config.example)."
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

## Find the AXA application's key matching APP_NAME by listing all AXA
## applications. Prints the key, or nothing if not found.
find_app_key() {
    run_dx_do_json axa list-applications output.format=json | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in data:
    if a.get('appId') == '${APP_NAME}':
        print(a.get('appKey', ''))
        break
" 2>/dev/null || true
}

## Fetch the BrowserAgent snippet for APP_NAME, collapsed to the single-
## line form this project's .config/.config.example already use, and
## print it to stdout. Fatals if a well-formed snippet wasn't returned.
fetch_snippet() {
    local snippet
    snippet=$("${DX_DO_BIN}" axa get-application-snippet "applicationName=${APP_NAME}" 2>&1 \
        | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e '^✔' -e '^✖' -e '^⚠' -e '^★' -e '^●' -e 'Authorization' -e '^$' \
        | python3 -c "import sys; print(' '.join(sys.stdin.read().split()))")
    case "${snippet}" in
        '<script'*'</script>') ;;
        *) fatal "Could not fetch a well-formed BrowserAgent snippet for '${APP_NAME}' -- got: ${snippet}" ;;
    esac
    printf '%s' "${snippet}"
}

## Patch .config.example's CONFIG_VAR line with the given snippet (single-
## quoted, since the snippet contains double-quotes -- the same
## convention the live .config already documents). Pass an empty string
## to reset it to the placeholder default. Writes the snippet to a temp
## file and passes paths (not the raw value) into python, rather than
## interpolating it into inline python source -- the snippet's `/`, `:`,
## and `"` characters make sed-delimiter or shell-string-interpolation
## approaches fragile.
#
# @param string $1
#   The snippet to write in (empty string resets to the placeholder).
patch_config_example() {
    local -r snippet="$1"
    if [[ "${snippet}" == *"'"* ]]; then
        fatal "The fetched snippet contains a single quote, which would break .config.example's shell quoting -- not patching. Update it manually."
    fi

    local snippet_file
    snippet_file="$(mktemp -t bpa-demo-axa-app-snippet-XXXXXX)"
    printf '%s' "${snippet}" > "${snippet_file}"

    python3 - "${CONFIG_EXAMPLE}" "${snippet_file}" "${CONFIG_VAR}" <<'PYEOF'
import re
import sys

config_path, snippet_path, var_name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(snippet_path) as f:
    snippet = f.read()
with open(config_path) as f:
    content = f.read()

new_line = var_name + "='" + snippet + "'"
pattern = r'^' + re.escape(var_name) + r'=.*$'
content, n = re.subn(pattern, new_line, content, count=1, flags=re.MULTILINE)
if n != 1:
    raise SystemExit(var_name + '= line not found in ' + config_path)

with open(config_path, 'w') as f:
    f.write(content)
PYEOF

    rm -f "${snippet_file}"
}

## Load APP_KEY from the state file, if it exists.
load_state() {
    APP_KEY=""
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist APP_KEY to the state file.
save_state() {
    mkdir -p "${STATE_DIR}"
    printf 'APP_KEY=%q\n' "${APP_KEY}" > "${STATE_FILE}"
}

## Create the AXA application if missing, then (re-)sync its snippet
## into .config.example. Safe to re-run.
cmd_create() {
    load_state

    if [[ -z "${APP_KEY}" ]]; then
        APP_KEY="$(find_app_key)"
    fi

    if [[ -n "${APP_KEY}" ]]; then
        info "AXA application '${APP_NAME}' already exists (key ${APP_KEY})."
    else
        info "Creating AXA application '${APP_NAME}'..."
        run_dx_do axa create-application "applicationName=${APP_NAME}" secure=false
        APP_KEY="$(find_app_key)"
        [[ -n "${APP_KEY}" ]] || fatal "Application was created but could not be found again via 'axa list-applications' -- check the tenant manually."
        info "Application created: ${APP_KEY}"
    fi

    info "Fetching BrowserAgent snippet and syncing it into $(basename "${CONFIG_EXAMPLE}")'s ${CONFIG_VAR}..."
    local snippet
    snippet="$(fetch_snippet)"
    patch_config_example "${snippet}"
    info "Updated ${CONFIG_VAR}."

    save_state
    info "Done. State saved to ${STATE_FILE}."
}

## Print whether the AXA application exists, its current definition, and
## its current snippet.
cmd_check() {
    load_state

    if [[ -z "${APP_KEY}" ]]; then
        APP_KEY="$(find_app_key)"
    fi

    if [[ -z "${APP_KEY}" ]]; then
        info "No state file at ${STATE_FILE} and no AXA application named '${APP_NAME}' found via 'axa list-applications' -- '${SCRIPT_NAME} ${PLATFORM} create' has not been run."
        exit 1
    fi

    info "AXA application '${APP_NAME}' (key ${APP_KEY}):"
    run_dx_do_json axa list-applications output.format=json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data:
    if a.get('appKey') == '${APP_KEY}':
        print(json.dumps(a, indent=2))
        break
"

    echo
    info "Current BrowserAgent snippet:"
    fetch_snippet
    echo

    if grep -qF "${CONFIG_VAR}='<script" "${CONFIG_EXAMPLE}"; then
        info "${CONFIG_EXAMPLE} is in sync (${CONFIG_VAR} is populated)."
    else
        info "${CONFIG_EXAMPLE}'s ${CONFIG_VAR} is NOT populated -- run '${SCRIPT_NAME} ${PLATFORM} create' to sync it."
    fi

    save_state
}

## Delete the AXA application and reset .config.example's CONFIG_VAR to
## the empty placeholder. Prompts for confirmation unless -y/--yes is
## given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    load_state

    if [[ -z "${APP_KEY}" ]]; then
        APP_KEY="$(find_app_key)"
    fi

    if [[ -z "${APP_KEY}" ]]; then
        info "No state file at ${STATE_FILE} and no AXA application named '${APP_NAME}' found -- nothing to delete."
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
        read -r -p "Delete AXA application '${APP_NAME}' (key ${APP_KEY})? This is irreversible -- 'axa delete-application' has no dry-run. [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    info "Deleting AXA application (key ${APP_KEY})..."
    run_dx_do axa delete-application "applicationName=${APP_NAME}" "applicationKey=${APP_KEY}"

    info "Resetting $(basename "${CONFIG_EXAMPLE}")'s ${CONFIG_VAR} to the empty placeholder..."
    patch_config_example ""

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
        readonly APP_NAME="BPA Demo AXA"
        readonly CONFIG_VAR="APMIA_BROWSER_SNIPPET_DOCKER"
        ;;
    k8s)
        readonly APP_NAME="BPA Demo AXA K8s"
        readonly CONFIG_VAR="APMIA_BROWSER_SNIPPET_K8S"
        ;;
esac
readonly STATE_FILE="${STATE_DIR}/bpa-demo-axa-app-${PLATFORM}.env"

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
