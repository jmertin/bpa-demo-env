#!/usr/bin/env bash
# bpa-demo-agent-alerts.sh - Create, check, or delete per-source alerts for
# the telemetry sources that monitor the BPA-Demo application: the
# Infrastructure Agent (bpa-demo-infra-agent, hosting the MySQL/MariaDB DB
# Monitor extension), the PHP probe agent (bpa-demo-php-probe, reporting
# frontend URLs and the backend DB calls the app makes), and the browser/RUM
# pipeline (real-user page timing that the BPA Webserver Extension's
# business transactions correlate via BRTM and forward to the Experience
# Collector).
#
# `dx-done agent list` on this tenant shows only the first two as queryable
# "agents" -- the browser/RUM data is real telemetry (confirmed via
# `dx-done metric data` returning live series) but is attributed to a third,
# separate identity, `SuperDomain|Experience Collector Host|DxC Agent|
# Logstash-APM-Plugin`, which never appears in `agent list`/`query-by-regex`
# output. Despite that, a Metric Grouping with an explicit sourceNamePattern
# and useManagementModuleAgentExpression=false can still scope to it under
# the *existing* "BPA-Demo" Management Module -- verified empirically
# (create the grouping, then confirm matches via `metricgrouping
# list-metrics`) since `managementmodule update` is broken on this dx-do
# version and adding a second agentExpressions entry to the existing MM
# wasn't an option.
#
# Structure created (12 Metric Groupings + 12 Alerts, all attached to the
# existing "BPA-Demo" Management Module that
# bpa-demo-management-module.sh creates -- this script depends on that MM
# already existing and reads its id from that script's state file):
#
#   Infrastructure Agent (bpa-demo-infra-agent) -- DB Monitor extension:
#     1. DB Availability Down          LESS_THAN    warn=1     err=1
#     2. DB Connection Refusals        GREATER_THAN warn=0     err=5
#     3. DB Connection Pool Pressure   GREATER_THAN warn=80    err=95
#     4. DB Buffer Pool Cache Degraded LESS_THAN    warn=95    err=90
#     5. DB Slow Query Rate Rising     GREATER_THAN warn=1     err=5
#
#   PHP probe agent (bpa-demo-php-probe) -- app frontend + DB backend:
#     6. App Response Time High        GREATER_THAN warn=100   err=250
#     7. App Error Rate Rising         GREATER_THAN warn=2     err=5
#     8. App Concurrency Spike         GREATER_THAN warn=5     err=15
#     9. DB Backend Response Time High GREATER_THAN warn=50    err=150
#    10. DB Backend Query Storm        GREATER_THAN warn=20000 err=40000
#
#   Browser/RUM pipeline (Logstash-APM-Plugin) -- real-user page timing,
#   one series per tracked URL, matched with a wildcard across all of them
#   (there is no app-level aggregate the way the PHP probe has one):
#    11. Page Load Time High          GREATER_THAN warn=300    err=1000
#    12. Page Hits Spike              GREATER_THAN warn=10     err=20
#
# Thresholds come from real measurements pulled via `dx-done metric data`
# over a live 2-hour (infra/PHP) or 6-hour (browser) window on this tenant
# (2026-07-06), not guesses:
#
#   - DB Availability, Connection Refusal Rate, InnoDB Cache Hit Rate, and
#     Slow Query Rate were all flat/healthy for the entire sample
#     (available=1, refusals=0%, cache hit 97-99%, slow queries=0%) -- for
#     these the threshold is a standard operational health boundary with
#     headroom above/below that baseline, since there is currently no
#     DB-side failure signal in this demo to measure an anomaly against.
#   - App Average Response Time reuses the exact thresholds already
#     measured and validated by bpa-demo-management-module.sh's alert:
#     normal traffic ~6-7ms, the `trouble` use case ~350-690ms.
#   - App Errors Per Interval, App Concurrent Invocations, DB Backend
#     Response Time, and DB Backend Responses Per Interval are set from
#     the sample's own p90-p99 tail (e.g. DB Backend Responses Per
#     Interval: p90=5051, p95=25020, p99=50067 -- driven by the `trouble`
#     use case's 5000-sequential-read bursts) so the thresholds sit above
#     routine traffic and catch genuine storms/spikes.
#   - Page Load Time is real-user timing (network + render, not just
#     server response time), so it runs higher than the PHP-tier alert:
#     per-URL p95 across the sample ran ~114-592ms with one extreme
#     35204ms outlier on /shop; warn=300/err=1000 sits above the routine
#     p95-p99 band without tripping on that single outlier at every
#     evaluation. Page Hits Per Interval peaked at 11 (on /shop) with
#     everything else at 0-4; warn=10/err=20 sits just above that peak.
#
# Bug fixed 2026-07-10: the infra/php AGENT_SOURCE_PATTERN entries hardcoded
# the pre-DEPLOYMENT_NAME/DEPLOYMENT_POSTFIX identity literals
# (bpa-demo-host/bpa-demo-infra-agent/bpa-demo-php-probe), and 7 of the 10
# infra+php ALERT_ATTR_PATTERN entries hardcoded either the DB hostname
# literal "mariadb" (only ever true for Compose, never Kubernetes'
# 127.0.0.1-based paths, collision or not) or the application name literal
# "BPA-Demo" (which APMIA_APP_NAME no longer defaults to -- see CLAUDE.md's
# "Deployment identity" section). All 10 non-browser alerts had zero live
# matches as a result. Fixed by wildcarding every hardcoded segment
# ([^|]+ / bpa-demo-[^|]+) so these patterns match any deployment's real
# paths, present or future, instead of a specific literal that a future
# identity change could break again. `create` now self-heals: if an alert
# key is already recorded in the state file, it checks the live metric
# grouping's match count via `metricgrouping list-metrics` and re-applies
# the current attributeNamePattern/sourceNamePattern via `metricgrouping
# update` if it finds zero, instead of unconditionally skipping it (the
# prior behavior, which is why re-running `create` after the identity
# change did not pick up this fix on its own).
#
# Bug fixed 2026-08-21: all 5 php-tier metric groupings (php-resp-time,
# php-error-rate, php-concurrency, php-db-resp-time, php-db-query-storm)
# had zero live matches. Root cause: AGENT_SOURCE_PATTERN[php] required a
# trailing `(/usr/sbin/apache2)` on the source triplet's agent segment --
# true when this pattern was written, but the 2026-07-15 UnknownAgent fix
# (APMENV_INTROSCOPE_AGENT_AGENTAUTONAMINGENABLED=false +
# APMENV_INTROSCOPE_REMOTEAGENT_PROBE_AGENT_NAME, see CLAUDE.md's "PHP
# probe injection" section) disabled the IA's remote-agent auto-naming,
# and that auto-naming turns out to be exactly what appended the running
# process's executable path to the identity. Confirmed live via `nass
# query-metadata`: the current source is the bare
# `SuperDomain|bpa-demo-docker|php-probes|bpa-demo-docker`, with no
# `(/usr/sbin/apache2)` anywhere in the catalog, stale or otherwise. Not
# related to the front-controller/clean-URL revert (see CLAUDE.md's
# "Front controller" section) -- a user question about that revert's
# effect on bpa-demo-management-module.sh surfaced this as a separate,
# pre-existing regression from the earlier identity fix that nothing had
# re-verified against these five patterns since. Fixed by making the
# suffix optional (`(\(/usr/sbin/apache2\))?$`) rather than deleting it
# outright, so the pattern still matches if auto-naming is ever
# re-enabled. The same stale literal was also found and fixed the same
# day in bpa-demo-service.sh's PHP_PROBE_AGENT_PATTERN and the
# response-time/error-rate SLI templates and the agent-health dashboard
# template -- see each file's own history for its part of the fix.
#
# Bug fixed 2026-08-21: `create` and `delete` gave contradictory results
# (create said "already exists," delete said "does not exist") for the
# same 12 ids. Root cause: the parent "BPA-Demo" Management Module had
# been deleted and recreated at some point (mm-3562 -> mm-45705),
# cascade-deleting all 12 child Metric Groupings/Alerts this script had
# created under the old one; .state/bpa-demo-agent-alerts.env never
# detected this and kept referencing the dead ids. `create` reported
# "already created" from stale local state, then crashed with exit 255
# after healing only 1 of 12 keys -- heal_one()'s metricgrouping update
# call had no `||` fallback (unlike its sibling list-metrics call), so a
# 404 from updating a grouping whose parent MM no longer exists
# propagated straight through `set -euo pipefail` and killed the script.
# `delete` technically completed for all 24 resources (each already
# caught by an existing `|| info "already gone."` fallback) but printed
# a noisy raw Axios 404 dump for every one, reasonably read as "can't
# delete." Fixed by adding a grouping_exists() existence-probe helper;
# heal_one() now checks it first and falls through to create_one()
# (recreate from scratch) instead of attempting a doomed update on a
# nonexistent resource; cmd_delete()'s two delete loops now check
# existence first and print a clean "already gone" message instead of
# attempting the delete and catching the resulting error noise. Verified
# live: `delete` against the broken state completed cleanly (24 "already
# gone" messages, no crash) and cleared the stale state file; `create`
# from that clean state recreated all 12 resources fresh under mm-45705
# with no crash, and 3 spot-checked groupings confirmed real live
# matches. Not investigated: why the parent Management Module was
# deleted and recreated in the first place.
#
# Usage:
#   dxo2-scripts/bpa-demo-agent-alerts.sh create   - create the 12 metric
#                                            groupings + alerts. Safe to
#                                            re-run: self-heals any
#                                            already-created metric grouping
#                                            with zero live matches.
#   dxo2-scripts/bpa-demo-agent-alerts.sh check    - print whether each
#                                            exists and its current
#                                            definition.
#   dxo2-scripts/bpa-demo-agent-alerts.sh delete   - delete all 12 alerts
#                                            and metric groupings. Prompts
#                                            for confirmation; pass
#                                            -y|--yes to skip it.
#   dxo2-scripts/bpa-demo-agent-alerts.sh -h|--help - print this help.
#
# Prerequisites:
#   dxo2-scripts/bpa-demo-management-module.sh create must have been run
#   first -- this script attaches all Metric Groupings to that script's
#   "BPA-Demo" Management Module and reads its id from
#   dxo2-scripts/.state/bpa-demo-management-module.env.
#   tools/dx-do-<platform>              DX O2 CLI - see that script's own
#                                        header comment for download/setup.
#                                        Override the path with the DX_DO
#                                        environment variable if it lives
#                                        somewhere else.
#   ~/.dxdo/default.dxo2.config.json    dx-do tenant credentials - see
#                                        https://github.com/kialambroca/dx-do-dist
#                                        for how to generate this file.
#
# State:
#   Persists the 12 (Metric Grouping id, Alert id) pairs to
#   dxo2-scripts/.state/bpa-demo-agent-alerts.env (git-ignored) so
#   check/delete can find them again -- see bpa-demo-management-module.sh's
#   header comment for why (dx-do's classic-APM list commands don't
#   reliably round-trip an id by name). If that file is lost, the
#   resources still exist in the tenant -- each metric grouping's name is
#   prefixed "BPA-Demo Infra -", "BPA-Demo PHP -", or "BPA-Demo Browser -";
#   find and remove them via `dx-do metricgrouping list-by-managementmodule
#   managementModuleId=<mm-id>` (delete each alert referencing a grouping
#   before the grouping itself, or the server rejects the grouping
#   delete).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="${SCRIPT_DIR}/.."
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly DXDO_CONFIG="${HOME}/.dxdo/default.dxo2.config.json"
readonly STATE_DIR="${SCRIPT_DIR}/.state"
readonly STATE_FILE="${STATE_DIR}/bpa-demo-agent-alerts.env"
readonly MM_STATE_FILE="${STATE_DIR}/bpa-demo-management-module.env"

# Ordered alert keys -- index order is significant: it is the order MGs
# and alerts are created in, and the order arrays below are indexed by.
readonly ALERT_KEYS=(
    infra-availability
    infra-conn-refused
    infra-conn-pressure
    infra-cache-hit
    infra-slow-query
    php-resp-time
    php-error-rate
    php-concurrency
    php-db-resp-time
    php-db-query-storm
    browser-page-load
    browser-page-hits
)

declare -rA ALERT_AGENT=(
    [infra-availability]=infra
    [infra-conn-refused]=infra
    [infra-conn-pressure]=infra
    [infra-cache-hit]=infra
    [infra-slow-query]=infra
    [php-resp-time]=php
    [php-error-rate]=php
    [php-concurrency]=php
    [php-db-resp-time]=php
    [php-db-query-storm]=php
    [browser-page-load]=browser
    [browser-page-hits]=browser
)

declare -rA ALERT_MG_NAME=(
    [infra-availability]='BPA-Demo Infra - DB Availability'
    [infra-conn-refused]='BPA-Demo Infra - DB Connection Refusals'
    [infra-conn-pressure]='BPA-Demo Infra - DB Connection Pool Pressure'
    [infra-cache-hit]='BPA-Demo Infra - DB Buffer Pool Cache Hit Rate'
    [infra-slow-query]='BPA-Demo Infra - DB Slow Query Rate'
    [php-resp-time]='BPA-Demo PHP - App Response Time'
    [php-error-rate]='BPA-Demo PHP - App Error Rate'
    [php-concurrency]='BPA-Demo PHP - App Concurrency'
    [php-db-resp-time]='BPA-Demo PHP - DB Backend Response Time'
    [php-db-query-storm]='BPA-Demo PHP - DB Backend Query Volume'
    [browser-page-load]='BPA-Demo Browser - Page Load Time'
    [browser-page-hits]='BPA-Demo Browser - Page Hits'
)

declare -rA ALERT_NAME_MAP=(
    [infra-availability]='Infra Agent - DB Availability Down'
    [infra-conn-refused]='Infra Agent - DB Connection Refusals'
    [infra-conn-pressure]='Infra Agent - DB Connection Pool Pressure'
    [infra-cache-hit]='Infra Agent - DB Buffer Pool Cache Degraded'
    [infra-slow-query]='Infra Agent - DB Slow Query Rate Rising'
    [php-resp-time]='PHP Probe - App Response Time High'
    [php-error-rate]='PHP Probe - App Error Rate Rising'
    [php-concurrency]='PHP Probe - App Concurrency Spike'
    [php-db-resp-time]='PHP Probe - DB Backend Response Time High'
    [php-db-query-storm]='PHP Probe - DB Backend Query Storm'
    [browser-page-load]='Browser RUM - Page Load Time High'
    [browser-page-hits]='Browser RUM - Page Hits Spike'
)

declare -rA ALERT_ATTR_PATTERN=(
    [infra-availability]='MySQL Databases\|[^|]+\|phpapp:Availability$'
    [infra-conn-refused]='MySQL Databases\|[^|]+\|phpapp\|Connections:Connection Refusal Rate$'
    [infra-conn-pressure]='MySQL Databases\|[^|]+\|phpapp\|Resource Utilization:Connection Usage Rate \(%\)$'
    [infra-cache-hit]='MySQL Databases\|[^|]+\|phpapp\|InnoDB:Cache Hit Rate \(%\)$'
    [infra-slow-query]='MySQL Databases\|[^|]+\|phpapp\|Efficiency\|Query:Slow query rate \(%\)$'
    [php-resp-time]='Frontends\|Apps\|bpa-demo-[^|]+:Average Response Time \(ms\)$'
    [php-error-rate]='Frontends\|Apps\|bpa-demo-[^|]+:Errors Per Interval$'
    [php-concurrency]='Frontends\|Apps\|bpa-demo-[^|]+:Concurrent Invocations$'
    [php-db-resp-time]='Backends\|phpapp on [^|]+-3306 \(MySQL DB\):Average Response Time \(ms\)$'
    [php-db-query-storm]='Backends\|phpapp on [^|]+-3306 \(MySQL DB\):Responses Per Interval$'
    [browser-page-load]='Business Segment\|BPA Demo\|.*:Average Page Load Time \(ms\)$'
    [browser-page-hits]='Business Segment\|BPA Demo\|.*:Page Hits Per Interval$'
)

declare -rA ALERT_OPERATOR=(
    [infra-availability]=LESS_THAN
    [infra-conn-refused]=GREATER_THAN
    [infra-conn-pressure]=GREATER_THAN
    [infra-cache-hit]=LESS_THAN
    [infra-slow-query]=GREATER_THAN
    [php-resp-time]=GREATER_THAN
    [php-error-rate]=GREATER_THAN
    [php-concurrency]=GREATER_THAN
    [php-db-resp-time]=GREATER_THAN
    [php-db-query-storm]=GREATER_THAN
    [browser-page-load]=GREATER_THAN
    [browser-page-hits]=GREATER_THAN
)

declare -rA ALERT_WARNING=(
    [infra-availability]=1
    [infra-conn-refused]=0
    [infra-conn-pressure]=80
    [infra-cache-hit]=95
    [infra-slow-query]=1
    [php-resp-time]=100
    [php-error-rate]=2
    [php-concurrency]=5
    [php-db-resp-time]=50
    [php-db-query-storm]=20000
    [browser-page-load]=300
    [browser-page-hits]=10
)

declare -rA ALERT_ERROR=(
    [infra-availability]=1
    [infra-conn-refused]=5
    [infra-conn-pressure]=95
    [infra-cache-hit]=90
    [infra-slow-query]=5
    [php-resp-time]=250
    [php-error-rate]=5
    [php-concurrency]=15
    [php-db-resp-time]=150
    [php-db-query-storm]=40000
    [browser-page-load]=1000
    [browser-page-hits]=20
)

# 4-segment full agent path per reference-agent-expressions -- required on
# metricgrouping's sourceNamePattern when useManagementModuleAgentExpression
# is false. $-anchored so the three sources' alerts never conflate. Note
# that "browser" isn't a queryable `dx-done agent` entry (see header
# comment) -- its metrics are real, just attributed to a different
# 4-segment identity than the two agents `agent list` shows.
declare -rA AGENT_SOURCE_PATTERN=(
    [infra]='SuperDomain\|bpa-demo-[^|]+\|bpa-demo-[^|]+\|bpa-demo-[^|]+(%\d+)?$'
    [php]='SuperDomain\|bpa-demo-[^|]+\|php-probes\|bpa-demo-[^|]+(%\d+)?(\(/usr/sbin/apache2\))?$'
    [browser]='SuperDomain\|Experience Collector Host\|DxC Agent\|Logstash-APM-Plugin$'
)

## Print usage information.
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "${BASH_SOURCE[0]}"
}

## Print a formatted informational message to stdout.
info() {
    echo "[bpa-demo-agent-alerts] $*"
}

## Print a fatal error message to stderr and exit with status 1.
fatal() {
    echo "[bpa-demo-agent-alerts] ERROR: $*" >&2
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

## Verify the dx-do binary, tenant config, and parent Management Module
## are present before doing anything.
check_prerequisites() {
    [[ -x "${DX_DO_BIN}" ]] || \
        fatal "dx-do binary not found or not executable at ${DX_DO_BIN}. Download the latest release for your platform from https://github.com/kialambroca/dx-do-dist/releases, place it under tools/, chmod +x it, and re-run (or set DX_DO to its path)."
    [[ -f "${DXDO_CONFIG}" ]] || \
        fatal "dx-do tenant config not found at ${DXDO_CONFIG}. See https://github.com/kialambroca/dx-do-dist for how to generate it."
    [[ -f "${MM_STATE_FILE}" ]] || \
        fatal "Parent Management Module state not found at ${MM_STATE_FILE}. Run 'dxo2-scripts/bpa-demo-management-module.sh create' first."
}

## Run a dx-do command, stripping progress noise and defensively dropping any
## line containing an Authorization header (dx-do's own error handler has
## been observed to dump one on some failed requests).
run_dx_do() {
    "${DX_DO_BIN}" "$@" 2>&1 | grep -v -e '^ℹ' -e '^☒' -e '^…' -e '^☐' -e 'Authorization'
}

## Load the parent Management Module id from
## bpa-demo-management-module.sh's state file into MM_ID.
load_mm_id() {
    # shellcheck disable=SC1090
    source "${MM_STATE_FILE}"
    [[ -n "${MM_ID:-}" ]] || fatal "MM_ID not set in ${MM_STATE_FILE} -- re-run 'bpa-demo-management-module.sh create'."
}

## Load ids from this script's own state file into MG_IDS/ALERT_IDS
## (associative arrays keyed by ALERT_KEYS entries), if it exists.
load_state() {
    declare -gA MG_IDS=()
    declare -gA ALERT_IDS=()
    # An `if` guard, not `[[ -f ]] && source` -- the latter is this
    # function's last statement, so under `set -e` a nonexistent state
    # file (the common first-run case) would make load_state itself
    # return 1 and silently kill the whole script when called bare.
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
    fi
}

## Persist MG_IDS/ALERT_IDS to the state file.
#
# `declare -p` emits `declare -A NAME=(...)` with no `-g` -- sourcing that
# verbatim from inside load_state() would redeclare the array *local* to
# that function (bash's default for `declare` in a function body), so the
# populated values vanish the moment load_state() returns and every
# create/check/delete call sees empty arrays. Force `-g` so the sourced
# declaration attaches to the global the caller actually reads.
save_state() {
    mkdir -p "${STATE_DIR}"
    {
        declare -p MG_IDS | sed 's/^declare -A/declare -gA/'
        declare -p ALERT_IDS | sed 's/^declare -A/declare -gA/'
    } > "${STATE_FILE}"
}

## Create the metric grouping + alert for one alert key. Populates
## MG_IDS[$1] / ALERT_IDS[$1].
#
# @param string $1
#   The alert key (an entry of ALERT_KEYS).
create_one() {
    local -r key="$1"
    local -r agent="${ALERT_AGENT[${key}]}"

    info "Creating Metric Grouping '${ALERT_MG_NAME[${key}]}'..."
    local mg_json
    mg_json=$(run_dx_do metricgrouping create \
        name="${ALERT_MG_NAME[${key}]}" \
        managementModuleId="${MM_ID}" \
        attributeNamePattern="${ALERT_ATTR_PATTERN[${key}]}" \
        sourceNamePattern="${AGENT_SOURCE_PATTERN[${agent}]}" \
        useManagementModuleAgentExpression=false \
        active=true \
        dry-run=false)
    echo "${mg_json}"
    local mg_id
    mg_id=$(printf '%s' "${mg_json}" | grep -o '"id": *"[^"]*"' | head -1 | sed 's/.*"\(mg-[0-9]*\)".*/\1/')
    [[ -n "${mg_id}" ]] || fatal "Could not parse Metric Grouping id from dx-do output above for '${key}'."
    MG_IDS[${key}]="${mg_id}"
    info "Metric Grouping created: ${mg_id}"

    info "Creating Alert '${ALERT_NAME_MAP[${key}]}'..."
    local alert_json
    alert_json=$(run_dx_do alert create \
        name="${ALERT_NAME_MAP[${key}]}" \
        managementModuleId="${MM_ID}" \
        metricGroupingId="${mg_id}" \
        compareOperator="${ALERT_OPERATOR[${key}]}" \
        warningThreshold="${ALERT_WARNING[${key}]}" \
        errorThreshold="${ALERT_ERROR[${key}]}" \
        active=true \
        dry-run=false)
    echo "${alert_json}"
    local alert_id
    alert_id=$(printf '%s' "${alert_json}" | grep -o '"id": *"[^"]*"' | head -1 | sed 's/.*"\(simplealert-[0-9]*\)".*/\1/')
    [[ -n "${alert_id}" ]] || fatal "Could not parse Alert id from dx-do output above for '${key}'."
    ALERT_IDS[${key}]="${alert_id}"
    info "Alert created: ${alert_id}"
}

## Check whether a metric grouping id actually exists under MM_ID.
## Returns 0 if it does, 1 if not (a plain existence probe -- no output).
#
# @param string $1
#   The metricGroupingId to probe.
grouping_exists() {
    local -r mg_id="$1"
    "${DX_DO_BIN}" metricgrouping detail metricGroupingId="${mg_id}" managementModuleId="${MM_ID}" >/dev/null 2>&1
}

## Re-apply the current attributeNamePattern/sourceNamePattern to an
## already-created metric grouping that has zero live matches (e.g. after a
## deployment identity change broke a previously-working pattern -- see "Bug
## fixed 2026-07-10" in this script's header).
#
# @param string $1
#   The alert key (an entry of ALERT_KEYS).
heal_one() {
    local -r key="$1"
    local -r agent="${ALERT_AGENT[${key}]}"
    local -r mg_id="${MG_IDS[${key}]}"

    # Bug fixed 2026-08-21: a recorded mg_id can be a genuinely dead
    # reference, not just "zero live matches" -- e.g. if
    # bpa-demo-management-module.sh's parent Management Module was ever
    # deleted and recreated (a fresh `create` there mints a brand new
    # MM_ID), every child Metric Grouping/Alert this script created under
    # the old one is cascade-deleted along with it, orphaning this
    # script's own state file. `metricgrouping update` on a nonexistent
    # grouping 404s, and that 404 previously propagated straight through
    # `run_dx_do`'s pipefail-checked pipeline with no `||` fallback,
    # killing the whole script under `set -e` after healing only the
    # first key -- which is what made `create` appear to say "already
    # exists" (really: "already created" per stale local state, then a
    # fatal crash) while `delete` simultaneously said the opposite ("does
    # not exist") for the very same ids. Detect the dead-reference case
    # up front and recreate from scratch instead of trying to update
    # something that isn't there.
    if ! grouping_exists "${mg_id}"; then
        info "'${key}' (${mg_id}) no longer exists (its parent Management Module was likely deleted and recreated) -- recreating from scratch."
        create_one "${key}"
        save_state
        return 0
    fi

    local metrics_json
    metrics_json=$("${DX_DO_BIN}" metricgrouping list-metrics metricGroupingId="${mg_id}" managementModuleId="${MM_ID}" output.format=json 2>/dev/null || true)
    local match_count
    match_count=$(printf '%s' "${metrics_json}" | grep -c '"SuperDomain|' || true)
    if [[ "${match_count}" -gt 0 ]]; then
        info "'${key}' (${mg_id}) has ${match_count} live matches -- nothing to do."
        return 0
    fi

    info "'${key}' (${mg_id}) has ZERO live matches -- self-healing with the current attributeNamePattern/sourceNamePattern."
    run_dx_do metricgrouping update \
        metricGroupingId="${mg_id}" \
        managementModuleId="${MM_ID}" \
        attributeNamePattern="${ALERT_ATTR_PATTERN[${key}]}" \
        sourceNamePattern="${AGENT_SOURCE_PATTERN[${agent}]}" \
        useManagementModuleAgentExpression=false \
        dry-run=false
}

## Create all 12 metric groupings + alerts. Safe to re-run: self-heals any
## already-created metric grouping with zero live matches instead of just
## skipping it.
cmd_create() {
    load_mm_id
    load_state

    if [[ "${#MG_IDS[@]}" -eq "${#ALERT_KEYS[@]}" ]]; then
        info "All ${#ALERT_KEYS[@]} alerts already created -- checking each metric grouping actually matches something."
        local key
        for key in "${ALERT_KEYS[@]}"; do
            heal_one "${key}"
        done
        info "Run '${SCRIPT_NAME} check' to see their current definitions."
        return 0
    fi

    local key
    for key in "${ALERT_KEYS[@]}"; do
        if [[ -n "${MG_IDS[${key}]:-}" ]]; then
            heal_one "${key}"
            continue
        fi
        create_one "${key}"
        save_state
    done

    info "Done. State saved to ${STATE_FILE}."
    info "Alerts evaluate every 60s -- allow at least that long after triggering an anomaly before checking for a raised alarm."
}

## Print whether each metric grouping/alert exists and its current definition.
cmd_check() {
    load_mm_id
    load_state

    if [[ "${#MG_IDS[@]}" -eq 0 ]]; then
        info "No state file at ${STATE_FILE} -- '${SCRIPT_NAME} create' has not been run here."
        info "The resources may still exist under a different state file/machine -- check 'dx-do metricgrouping list-by-managementmodule managementModuleId=${MM_ID}'."
        exit 1
    fi

    local key
    for key in "${ALERT_KEYS[@]}"; do
        if [[ -z "${MG_IDS[${key}]:-}" ]]; then
            info "'${key}': not created yet."
            continue
        fi
        info "'${key}' Metric Grouping (${MG_IDS[${key}]}):"
        if run_dx_do metricgrouping detail metricGroupingId="${MG_IDS[${key}]}" managementModuleId="${MM_ID}"; then
            :
        else
            info "  not found -- may have been deleted outside this script."
        fi

        info "'${key}' Alert (${ALERT_IDS[${key}]:-?}):"
        if run_dx_do alert detail alertId="${ALERT_IDS[${key}]:-}" managementModuleId="${MM_ID}"; then
            :
        else
            info "  not found -- may have been deleted outside this script."
        fi
    done
}

## Delete all alerts and metric groupings. Prompts for confirmation unless
## -y/--yes is given.
#
# @param string[] "$@"
#   Remaining arguments after the 'delete' subcommand (e.g. -y, --yes).
cmd_delete() {
    load_mm_id
    load_state

    if [[ "${#MG_IDS[@]}" -eq 0 ]]; then
        info "No state file at ${STATE_FILE} -- nothing recorded here to delete."
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
        read -r -p "Delete all ${#MG_IDS[@]} per-agent alerts and metric groupings from the DX O2 tenant? [y/N] " reply
        [[ "${reply}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    fi

    # Delete alerts before metric groupings -- the server rejects a
    # grouping delete while any alert still references it.
    #
    # Checked existence first, rather than attempting the delete and
    # catching a failure, since 2026-08-21: a recorded id can be a fully
    # dead reference (its parent Management Module was deleted and
    # recreated since -- see heal_one()'s header comment), and every
    # delete attempt against a dead id 404s with a raw multi-line Axios
    # error dump that reads as "the script can't delete this" even though
    # the outcome (nothing to delete) is perfectly fine.
    local key
    for key in "${ALERT_KEYS[@]}"; do
        [[ -n "${ALERT_IDS[${key}]:-}" ]] || continue
        if ! "${DX_DO_BIN}" alert detail alertId="${ALERT_IDS[${key}]}" managementModuleId="${MM_ID}" >/dev/null 2>&1; then
            info "Alert '${key}' (${ALERT_IDS[${key}]}) already gone -- nothing to delete."
            continue
        fi
        info "Deleting Alert '${key}' (${ALERT_IDS[${key}]})..."
        run_dx_do alert delete \
            alertId="${ALERT_IDS[${key}]}" \
            managementModuleId="${MM_ID}" \
            alertName="${ALERT_NAME_MAP[${key}]}" \
            dry-run=false || info "  already gone."
    done

    for key in "${ALERT_KEYS[@]}"; do
        [[ -n "${MG_IDS[${key}]:-}" ]] || continue
        if ! grouping_exists "${MG_IDS[${key}]}"; then
            info "Metric Grouping '${key}' (${MG_IDS[${key}]}) already gone -- nothing to delete."
            continue
        fi
        info "Deleting Metric Grouping '${key}' (${MG_IDS[${key}]})..."
        run_dx_do metricgrouping delete \
            metricGroupingId="${MG_IDS[${key}]}" \
            managementModuleId="${MM_ID}" \
            name="${ALERT_MG_NAME[${key}]}" \
            dry-run=false || info "  already gone."
    done

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
