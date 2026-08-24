#!/usr/bin/env bash
# bpa-demo-axa-app.sh - Create, check, or delete the "BPA Demo AXA"
# Application Experience Analytics (AXA) application on the DX O2 tenant,
# and keep .config.example's APMIA_BROWSER_SNIPPET template in sync with
# its BrowserAgent snippet.
#
# AXA (`dx-do axa`) is the DX O2 surface for mobile/browser Real User
# Monitoring applications -- a distinct resource type from every other
# telemetry source this project's dxo2-scripts/*.sh manage (Services,
# Universes, Management Modules/Metric Groupings/Alerts, SLI groups,
# Dashboards). An AXA "application" definition is what a BrowserAgent (BA)
# snippet is generated *for* -- the `APMIA_BROWSER_SNIPPET` variable this
# project's .config/.config.example carry (see CLAUDE.md's ".config
# required variables" section) is exactly this snippet, normally obtained
# by hand via DX O2 Settings -> Manage Mobile/Browser Web Monitoring ->
# App to Monitor -> Web App. This script does that step via the CLI
# instead, named `"BPA Demo AXA"` (not plain `"BPA Demo"`, to disambiguate
# from the many other tenant resources already using that exact name --
# the Service, both Universe types, the Management Module, the SLI
# groups -- none of which are AXA applications).
#
# The BrowserAgent snippet itself is NOT a secret in the way `.config`'s
# other values are: it is a client-side `<script>` tag meant to be
# embedded in every HTML response and is visible to any site visitor via
# view-source, so baking this project's own demo AXA application's
# snippet into the checked-in `.config.example` (rather than leaving the
# generic empty default) is safe and intentional -- unlike `.config`
# itself, which is never committed and holds real credentials.
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
#   AXA application "BPA Demo AXA" (a Web App / browser application, no
#   mobile SDK usage) -- a BrowserAgent snippet is generated for it and
#   written into .config.example's APMIA_BROWSER_SNIPPET line.
#
# Usage:
#   dxo2-scripts/bpa-demo-axa-app.sh create   - create the AXA application
#                                        if it doesn't exist (self-heals
#                                        by name), then (re-)fetch its
#                                        BrowserAgent snippet and patch it
#                                        into .config.example. Safe to
#                                        re-run -- always re-syncs the
#                                        snippet even if the application
#                                        already existed.
#   dxo2-scripts/bpa-demo-axa-app.sh check    - print whether it exists,
#                                        its current definition, and its
#                                        current snippet.
#   dxo2-scripts/bpa-demo-axa-app.sh delete   - permanently delete the AXA
#                                        application (irreversible, no
#                                        dry-run on the API side) and
#                                        reset .config.example's
#                                        APMIA_BROWSER_SNIPPET back to the
#                                        empty placeholder. Prompts for
#                                        confirmation; pass -y|--yes to
#                                        skip it.
#   dxo2-scripts/bpa-demo-axa-app.sh -h|--help - print this help.
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
#   Persists the application's key to
#   dxo2-scripts/.state/bpa-demo-axa-app.env (git-ignored) so
#   check/delete can find it again. If lost, `axa list-applications`
#   finds it by name (`"BPA Demo AXA"`) regardless.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly APP_NAME="BPA Demo AXA"
readonly CONFIG_EXAMPLE="${ROOT_DIR}/.config.example"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-axa-app.env"

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

## Patch .config.example's APMIA_BROWSER_SNIPPET line with the given
## snippet (single-quoted, since the snippet contains double-quotes --
## the same convention the live .config already documents). Pass an
## empty string to reset it to the placeholder default. Writes the
## snippet to a temp file and passes paths (not the raw value) into
## python, rather than interpolating it into inline python source --
## the snippet's `/`, `:`, and `"` characters make sed-delimiter or
## shell-string-interpolation approaches fragile.
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

    python3 - "${CONFIG_EXAMPLE}" "${snippet_file}" <<'PYEOF'
import re
import sys

config_path, snippet_path = sys.argv[1], sys.argv[2]
with open(snippet_path) as f:
    snippet = f.read()
with open(config_path) as f:
    content = f.read()

new_line = "APMIA_BROWSER_SNIPPET='" + snippet + "'"
content, n = re.subn(r'^APMIA_BROWSER_SNIPPET=.*$', new_line, content, count=1, flags=re.MULTILINE)
if n != 1:
    raise SystemExit('APMIA_BROWSER_SNIPPET= line not found in ' + config_path)

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

    info "Fetching BrowserAgent snippet and syncing it into $(basename "${CONFIG_EXAMPLE}")..."
    local snippet
    snippet="$(fetch_snippet)"
    patch_config_example "${snippet}"
    info "Updated APMIA_BROWSER_SNIPPET."

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
        info "No state file at ${STATE_FILE} and no AXA application named '${APP_NAME}' found via 'axa list-applications' -- '${SCRIPT_NAME} create' has not been run."
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

    if grep -qF "APMIA_BROWSER_SNIPPET='<script" "${CONFIG_EXAMPLE}"; then
        info "${CONFIG_EXAMPLE} is in sync (APMIA_BROWSER_SNIPPET is populated)."
    else
        info "${CONFIG_EXAMPLE}'s APMIA_BROWSER_SNIPPET is NOT populated -- run '${SCRIPT_NAME} create' to sync it."
    fi

    save_state
}

## Delete the AXA application and reset .config.example's
## APMIA_BROWSER_SNIPPET to the empty placeholder. Prompts for
## confirmation unless -y/--yes is given.
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

    info "Resetting $(basename "${CONFIG_EXAMPLE}")'s APMIA_BROWSER_SNIPPET to the empty placeholder..."
    patch_config_example ""

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
