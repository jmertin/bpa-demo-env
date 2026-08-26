#!/usr/bin/env bash
# bpa-demo-sli.sh - Create, check, or delete the three BPA-Demo SLI groups
# under dx-do v7.2.1's SLI-group model (see `dx-do help slis`).
#
# Structure created (3 independent SLI groups, each with 1 SLI + 1 SLO +
# 1 alert on the SLO's rolling percentage, all bound to the "BPA-Demo"
# Service):
#
#   "BPA-Demo Frontend Response Time" (sliGroupId 2958 in this tenant --
#   see "Bug fixed 2026-08-21" below re: the id renumbering)
#     SLI:   average of every Frontends|Apps|bpa-demo-*|URLs|<page>
#            :Average Response Time (ms) reported by the PHP probe agent,
#            5-min aggregation, sli_type Latency.
#     SLO:   objective LE 200ms per interval, target 98% over a rolling
#            1-day window.
#     Alert: caution below 98%, danger below 90% of the rolling SLO
#            percentage.
#
#   "BPA-Demo Frontend Error Rate" (sliGroupId 2959)
#     SLI:   average of every Frontends|Apps|bpa-demo-*|URLs|<page>
#            :Errors Per Interval, 5-min aggregation, sli_type Errors.
#     SLO:   objective LE 2 per interval, target 98% rolling 1-day.
#     Alert: same caution/danger thresholds as above.
#
#   "BPA-Demo Client-Side Page Load Time" (sliGroupId 2960)
#     SLI:   average of every Business Segment|BPA Demo|<page>:Average
#            Page Load Time (ms) reported by the Browser Agent (via the
#            BPA WebServer Agent's Logstash-APM-Plugin identity), 5-min
#            aggregation, sli_type Latency.
#     SLO:   objective LE 300ms per interval, target 98% rolling 1-day.
#     Alert: same caution/danger thresholds as above.
#     Currently registers sliStatusCode 5 ("no metrics matching") -- not
#     a bug. Browser-agent auto-injection is currently reverted (see
#     CLAUDE.md's "PHP probe injection" section and bug_php_probe.md), so
#     there is no live client-side page-load data at all right now. This
#     lights up on its own once/if real browser traffic resumes.
#
# Background -- why this script was rewritten from scratch (2026-08-21):
# the tenant's entire SLI subsystem was found to have been reset -- the
# previous sliId 2767/2768/2769 (created via the old `sli export`/`import`
# raw-JSON CLI surface) no longer exist: `sli list-groups` returned zero
# groups tenant-wide, and `sli export` on both a known project id and the
# tenant's own unrelated pre-existing example returned an identical
# null/invalid response. See CLAUDE.md's dxo2-scripts section and
# TOBEDONE.md's SLI/SLO section for the full investigation. The `dx-do`
# CLI was updated to v7.2.1 in the same session (see CLAUDE.md), which
# exposes a structurally different, genuinely more capable `sli` command
# surface: `create-group`/`add-sli`/`add-slo`/`add-alert` are real,
# idempotent-preview (dry-run by default) write commands with structured
# `groupFilter.<field>.<condition>`/`sliFilter.<field>.<condition>` filters
# -- no more "no update, name-collision refusal" limitation that made the
# old SLI 2767's filter and all three SLIs' SLO/alert layers permanently
# stuck needing manual console edits.
#
# Landmine found live while building this (2026-08-21): the `regex`
# filter condition on this API is silently broken by a trailing `$`
# anchor -- a pattern like `foo$` matches ZERO metrics with no error,
# while the identical pattern without the trailing `$` matches correctly.
# Confirmed via `sli filter-test`: matching stops naturally once the
# pattern's literal content is satisfied (the match is effectively
# start-anchored/prefix-style, not `^...$`), so omitting the trailing `$`
# entirely is both necessary and sufficient -- do NOT port `$`-anchored
# patterns from `metricgrouping`/`sli`(old)/`service` regexes elsewhere in
# this project without stripping the trailing `$` first.
#
# Landmine found live while picking the Error Rate SLI's metric: the
# app-level aggregate `Frontends|Apps|bpa-demo-docker:Errors Per Interval`
# (no `|URLs|` segment) exists in the raw NASS catalog (confirmed via
# `nass query-metadata`) but is NOT visible in `sli filter-test`'s
# service-scoped view for "BPA-Demo" -- only the per-URL variants are.
# Whatever computes "which metrics belong to this service" for the SLI
# subsystem specifically is narrower than the metric's own
# `internal::serviceNames` tag that `nass query` honors. Used the
# per-URL pattern instead (same shape as the Response Time SLI), which is
# visible and reliable.
#
# Bug fixed 2026-08-26, reported by the user: the response-time and
# error-rate groups' SOURCE_PATTERN/ATTRIBUTE_PATTERN wildcarded the
# deployment identity (`bpa-demo-[^|]+`), so one shared SLI group's SLO/
# error-budget/alert blended both the Docker and Kubernetes deployment's
# response times and error rates together. Split into two independent
# sets of 3 SLI groups (the page-load one has no per-platform identity
# today and stays shared, same as elsewhere in this project), one set
# per platform, bound to that platform's own Service
# (bpa-demo-service.sh's `<docker|k8s>` split):
#
#   docker -> bound to Service "BPA-Demo",     group names unchanged
#             (e.g. "BPA-Demo Frontend Response Time")
#   k8s    -> bound to Service "BPA-Demo K8s", group names suffixed
#             " K8s" (e.g. "BPA-Demo Frontend Response Time K8s") --
#             sli group names must be unique per tenant, so the docker
#             set (repointed, unchanged) and the new k8s set can't share
#             identical names.
#
# Bug fixed 2026-08-21 (doc-only, found during an unrelated docs audit):
# every doc that recorded this rebuild's sliGroupIds (this header, CLAUDE.md,
# TOBEDONE.md, the CHANGELOG entry) said 2955/2956/2957, but the live
# tenant's `.state/bpa-demo-sli.env` and `sli list-groups` both show
# 2958/2959/2960 -- the three groups actually live today. The state
# file's mtime is a few minutes after the commit that documented
# 2955-2957, so the groups were evidently deleted and recreated
# (whether via a manual `delete` + `create` re-run or something else)
# after that commit was made, and nothing re-verified the docs against
# the new ids afterward. Corrected the header above, CLAUDE.md, and
# TOBEDONE.md to the current ids; left the CHANGELOG's original
# 13:27 entry untouched since it's a historical record of what was true
# at that timestamp, not a live reference. `create`/`check`/`delete`
# were never affected by this -- they always read the real id from
# `.state/bpa-demo-sli.env`, never a hardcoded literal.
#
# Usage:
#   dxo2-scripts/bpa-demo-sli.sh <docker|k8s> create   - create that
#                                            platform's 3 SLI groups (with
#                                            their SLO and alert). Safe to
#                                            re-run: for an already-created
#                                            group, re-applies the group
#                                            filter (idempotent) and adds
#                                            the SLO/alert only if missing.
#   dxo2-scripts/bpa-demo-sli.sh <docker|k8s> check    - print each
#                                            group's live status (`sli
#                                            status` + `sli export`
#                                            summary).
#   dxo2-scripts/bpa-demo-sli.sh <docker|k8s> delete   - permanently
#                                            delete that platform's 3 SLI
#                                            groups (their SLIs, SLOs, and
#                                            alerts). Prompts for
#                                            confirmation; pass -y|--yes to
#                                            skip it.
#   dxo2-scripts/bpa-demo-sli.sh -h|--help - print this help.
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
#   python3                             used to parse `sli list-groups`/
#                                        `sli export` JSON output.
#
# State:
#   Persists each platform's SLI group ids to
#   dxo2-scripts/.state/bpa-demo-sli-<docker|k8s>.env (git-ignored) so
#   check/delete can find them again. If lost, `sli list-groups
#   filter=BPA-Demo` finds them by name regardless.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"

readonly AGGREGATION_INTERVAL=5
readonly SLO_TARGET=98
readonly SLO_WINDOW_DAYS=1
readonly ALERT_CAUTION_THRESHOLD=98
readonly ALERT_DANGER_THRESHOLD=90

readonly SLI_KEYS=(response-time error-rate page-load)

# Templates with __NAME_SUFFIX__ (empty for docker, " K8s" for k8s) /
# __APP_ID__ (deployment identity) placeholders, resolved into the real
# per-platform arrays further down once the platform argument is parsed.
# page-load has no per-platform identity today (see this script's header)
# and carries no __APP_ID__ placeholder.
declare -A SLI_GROUP_NAME_TEMPLATE=(
    [response-time]="BPA-Demo Frontend Response Time__NAME_SUFFIX__"
    [error-rate]="BPA-Demo Frontend Error Rate__NAME_SUFFIX__"
    [page-load]="BPA-Demo Client-Side Page Load Time__NAME_SUFFIX__"
)

declare -rA SLI_TYPE=(
    [response-time]=Latency
    [error-rate]=Errors
    [page-load]=Latency
)

declare -rA SLI_DESCRIPTION=(
    [response-time]="Average PHP-probe response time across all tracked frontend URLs"
    [error-rate]="Average PHP-probe errors per interval across all tracked frontend URLs"
    [page-load]="Average real-user (Browser Agent) page load time across tracked pages"
)

declare -rA SOURCE_CONDITION=(
    [response-time]=regex
    [error-rate]=regex
    [page-load]=equals
)

# No trailing $ -- see the "Landmine" header comment above.
declare -A SOURCE_PATTERN_TEMPLATE=(
    [response-time]='SuperDomain\|__APP_ID__\|php-probes\|__APP_ID__(%\d+)?(\(/usr/sbin/apache2\))?'
    [error-rate]='SuperDomain\|__APP_ID__\|php-probes\|__APP_ID__(%\d+)?(\(/usr/sbin/apache2\))?'
    [page-load]='SuperDomain|Experience Collector Host|DxC Agent|Logstash-APM-Plugin'
)

declare -A ATTRIBUTE_PATTERN_TEMPLATE=(
    [response-time]='Frontends\|Apps\|__APP_ID__\|URLs\|[^|]+:Average Response Time \(ms\)'
    [error-rate]='Frontends\|Apps\|__APP_ID__\|URLs\|[^|]+:Errors Per Interval'
    [page-load]='Business Segment\|BPA Demo\|[^|]+:Average Page Load Time \(ms\)'
)

declare -rA SLO_OBJECTIVE_VALUE=(
    [response-time]=200
    [error-rate]=2
    [page-load]=300
)

declare -gA GROUP_ID=()

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

## Verify the dx-do binary, tenant config, and python3 are present before
## doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
    command -v python3 >/dev/null 2>&1 || \
        fatal "python3 is required (used to parse sli list-groups/sli export JSON output)."
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

## Load GROUP_ID[key]=sliGroupId entries from the state file, if it exists.
load_state() {
    GROUP_ID=()
    # An `if` guard, not `[[ -f ]] && source` -- the latter is this
    # function's last statement, so under `set -e` a nonexistent state
    # file (the common first-run case) would make load_state itself
    # return 1 and silently kill the whole script when called bare.
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist GROUP_ID to the state file.
save_state() {
    mkdir -p "${STATE_DIR}"
    {
        declare -p GROUP_ID | sed 's/^declare -A/declare -gA/'
    } > "${STATE_FILE}"
}

## Look up a sliGroupId by exact sliGroupName via `sli list-groups`,
## regardless of the state file. Prints the id, or nothing if not found.
#
# @param string $1
#   The exact sliGroupName to search for.
find_group_id() {
    local -r name="$1"
    run_dx_do_json sli list-groups "filter=${name}" output.format=json | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data:
    if row.get('sliGroupName', '').strip() == '${name}':
        print(row['sliGroupId'])
        break
" 2>/dev/null || true
}

## Print 'yes'/'no' for whether an existing SLI group already has an SLO
## and an alert defined, via `sli export`.
#
# @param string $1
#   The sliGroupId to inspect.
group_has_slo_and_alert() {
    local -r group_id="$1"
    run_dx_do_json sli export "sliGroupId=${group_id}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print('no')
    print('no')
    sys.exit(0)
slo = data.get('sloDefinition', {}).get('functions', [])
alerts = data.get('alertDefinition', [[]])
alert_count = sum(len(a) for a in alerts) if alerts else 0
print('yes' if slo else 'no')
print('yes' if alert_count > 0 else 'no')
"
}

## Create (or self-heal) one SLI group's filter, SLO, and alert.
#
# @param string $1
#   The SLI_KEYS entry to create/heal.
create_one() {
    local -r key="$1"
    local -r name="${SLI_GROUP_NAME[${key}]}"
    local group_id="${GROUP_ID[${key}]:-}"

    if [[ -z "${group_id}" ]]; then
        group_id="$(find_group_id "${name}")"
    fi

    if [[ -n "${group_id}" ]]; then
        info "'${name}' already exists (sliGroupId ${group_id}) -- re-applying its group filter (idempotent)."
        run_dx_do sli set-group-filter \
            "sliGroupId=${group_id}" \
            "groupFilter.sourceName.${SOURCE_CONDITION[${key}]}=${SOURCE_PATTERN[${key}]}" \
            "groupFilter.attributeName.regex=${ATTRIBUTE_PATTERN[${key}]}" \
            dry-run=false

        local heal_check has_slo has_alert
        heal_check="$(group_has_slo_and_alert "${group_id}")"
        has_slo="$(printf '%s' "${heal_check}" | sed -n '1p')"
        has_alert="$(printf '%s' "${heal_check}" | sed -n '2p')"

        if [[ "${has_slo}" != "yes" ]]; then
            info "'${name}' has no SLO yet -- adding it."
            add_slo "${group_id}" "${key}"
        fi
        if [[ "${has_alert}" != "yes" ]]; then
            info "'${name}' has no alert yet -- adding it."
            add_alert "${group_id}" "${key}"
        fi

        GROUP_ID[${key}]="${group_id}"
        return 0
    fi

    info "Creating SLI group '${name}'..."
    local create_json
    create_json=$("${DX_DO_BIN}" sli create-group \
        "sliGroupName=${name}" \
        "serviceName=${SERVICE_NAME}" \
        "sliName=${name}" \
        op=average \
        "aggregationInterval=${AGGREGATION_INTERVAL}" \
        "sliType=${SLI_TYPE[${key}]}" \
        "sliDescription=${SLI_DESCRIPTION[${key}]}" \
        "groupFilter.sourceName.${SOURCE_CONDITION[${key}]}=${SOURCE_PATTERN[${key}]}" \
        "groupFilter.attributeName.regex=${ATTRIBUTE_PATTERN[${key}]}" \
        dry-run=false 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization')
    echo "${create_json}"
    group_id=$(printf '%s' "${create_json}" | grep -o '"groupId": *[0-9]*' | head -1 | grep -o '[0-9]*$')
    [[ -n "${group_id}" ]] || fatal "Could not parse sliGroupId from dx-do output above."
    info "SLI group created: sliGroupId ${group_id}"

    add_slo "${group_id}" "${key}"
    add_alert "${group_id}" "${key}"

    GROUP_ID[${key}]="${group_id}"
}

## Add the SLO (objective + rolling percentage + error budget) to a
## group's SLI.
#
# @param string $1
#   The sliGroupId.
# @param string $2
#   The SLI_KEYS entry (for its SLO objective value).
add_slo() {
    local -r group_id="$1"
    local -r key="$2"
    local -r name="${SLI_GROUP_NAME[${key}]}"

    run_dx_do sli add-slo \
        "sliGroupId=${group_id}" \
        "sliName=${name}" \
        objectiveComparator=LE \
        "objectiveValue=${SLO_OBJECTIVE_VALUE[${key}]}" \
        "target=${SLO_TARGET}" \
        windowType=rolling \
        "windowDays=${SLO_WINDOW_DAYS}" \
        dry-run=false
}

## Add an alert on the SLO's rolling percentage to a group's SLI.
#
# @param string $1
#   The sliGroupId.
# @param string $2
#   The SLI_KEYS entry.
add_alert() {
    local -r group_id="$1"
    local -r key="$2"
    local -r name="${SLI_GROUP_NAME[${key}]}"

    run_dx_do sli add-alert \
        "sliGroupId=${group_id}" \
        "sliName=${name}" \
        target=slo-percentage \
        operator=LESS_THAN \
        "cautionThreshold=${ALERT_CAUTION_THRESHOLD}" \
        "dangerThreshold=${ALERT_DANGER_THRESHOLD}" \
        resolution=300 \
        dry-run=false
}

## Create (or self-heal) all 3 SLI groups. Safe to re-run.
cmd_create() {
    load_state

    local key
    for key in "${SLI_KEYS[@]}"; do
        create_one "${key}"
    done

    save_state
    info "Done. State saved to ${STATE_FILE}."
    info "Run '${SCRIPT_NAME} ${PLATFORM} check' to see each group's live status."
}

## Print each SLI group's live status and export summary.
cmd_check() {
    load_state

    local key name group_id
    for key in "${SLI_KEYS[@]}"; do
        name="${SLI_GROUP_NAME[${key}]}"
        group_id="${GROUP_ID[${key}]:-}"
        if [[ -z "${group_id}" ]]; then
            group_id="$(find_group_id "${name}")"
        fi

        if [[ -z "${group_id}" ]]; then
            info "'${name}': not found -- '${SCRIPT_NAME} ${PLATFORM} create' has not been run, or it was deleted outside this script."
            continue
        fi

        info "'${name}' (sliGroupId ${group_id}):"
        run_dx_do sli status | grep -A2 "^${group_id} " || info "  sliStatusCode 0 (healthy) -- not listed by 'sli status', which only surfaces nonzero statuses."
    done
}

## Permanently delete all 3 SLI groups. Prompts for confirmation unless
## -y/--yes is given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    load_state

    local skip_confirm="false"
    local arg
    for arg in "$@"; do
        case "${arg}" in
            -y|--yes) skip_confirm="true" ;;
        esac
    done

    if [[ "${skip_confirm}" != "true" ]]; then
        local reply
        read -r -p "Permanently delete all 3 BPA-Demo SLI groups (their SLIs, SLOs, and alerts)? [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    local key name group_id
    for key in "${SLI_KEYS[@]}"; do
        name="${SLI_GROUP_NAME[${key}]}"
        group_id="${GROUP_ID[${key}]:-}"
        if [[ -z "${group_id}" ]]; then
            group_id="$(find_group_id "${name}")"
        fi

        if [[ -z "${group_id}" ]]; then
            info "'${name}': not found -- already gone."
            continue
        fi

        info "Deleting '${name}' (sliGroupId ${group_id})..."
        run_dx_do sli delete-group "sliGroupId=${group_id}" "sliGroupName=${name}" dry-run=false || info "  already gone."
    done

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
        readonly APP_ID="bpa-demo-docker"
        readonly NAME_SUFFIX=""
        readonly SERVICE_NAME="BPA-Demo"
        ;;
    k8s)
        readonly APP_ID="bpa-demo-k8s"
        readonly NAME_SUFFIX=" K8s"
        readonly SERVICE_NAME="BPA-Demo K8s"
        ;;
esac
readonly STATE_FILE="${STATE_DIR}/bpa-demo-sli-${PLATFORM}.env"

declare -A SLI_GROUP_NAME=()
declare -A SOURCE_PATTERN=()
declare -A ATTRIBUTE_PATTERN=()
for _key in "${SLI_KEYS[@]}"; do
    _name="${SLI_GROUP_NAME_TEMPLATE[${_key}]}"
    _name="${_name//__NAME_SUFFIX__/${NAME_SUFFIX}}"
    SLI_GROUP_NAME[${_key}]="${_name}"

    _pattern="${SOURCE_PATTERN_TEMPLATE[${_key}]}"
    _pattern="${_pattern//__APP_ID__/${APP_ID}}"
    SOURCE_PATTERN[${_key}]="${_pattern}"

    _pattern="${ATTRIBUTE_PATTERN_TEMPLATE[${_key}]}"
    _pattern="${_pattern//__APP_ID__/${APP_ID}}"
    ATTRIBUTE_PATTERN[${_key}]="${_pattern}"
done
unset _key _name _pattern
readonly SLI_GROUP_NAME
readonly SOURCE_PATTERN
readonly ATTRIBUTE_PATTERN

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
