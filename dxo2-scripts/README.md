# dxo2-scripts/

Scripted DX O2 tenant configuration changes for the BPA-Demo application
(Services, inventorize rules, and similar tenant-side setup that isn't part
of the application's own build/deploy pipeline in `build-scripts/`).

These scripts exist so that anyone running the demo can create, check, and
tear down this tenant configuration **without needing an AI assistant** --
each one is a self-contained, human-readable CLI.

## Prerequisites (all scripts)

- **`tools/dx-do-<platform>`** -- the [`dx-do`](https://github.com/kialambroca/dx-do-dist)
  CLI. Download the latest release for your platform from
  <https://github.com/kialambroca/dx-do-dist/releases>, place it under
  `tools/` (git-ignored -- see `tools/README.md`), and `chmod +x` it. Set
  the `DX_DO` environment variable to override the expected path.
- **`~/.dxdo/default.dxo2.config.json`** -- your DX O2 tenant credentials.
  See the `dx-do` project's own documentation for how to generate this file.

## Convention

Every script in this directory follows the same shape:

```bash
dxo2-scripts/<name>.sh <docker|k8s> create        # create the resource; safe to re-run
dxo2-scripts/<name>.sh <docker|k8s> check         # print whether it exists + its definition
dxo2-scripts/<name>.sh <docker|k8s> delete [-y]   # delete it (prompts unless -y/--yes)
dxo2-scripts/<name>.sh -h|--help                  # usage
```

**`<docker|k8s>` is a required platform argument, added 2026-08-26 at the
user's request, and must come first.** Every script exits with an error
before doing anything else (no tenant call, no `.config` read) if it's
missing or isn't exactly `docker` or `k8s` -- see "Docker/Kubernetes
separation" below for why and what each script actually does with it.

`create` is idempotent: it checks for the resource first and warns instead
of failing if it already exists. `delete` prompts for confirmation by
default since it mutates shared tenant state visible to everyone with
console access -- pass `-y`/`--yes` for non-interactive use.

Scripts managing classic-APM resources (Management Modules, Metric
Groupings, Alerts) persist the ids `create` returns to a local
`.state/<script-name>-<docker|k8s>.env` file (git-ignored) so `check`/`delete`
can find them again -- `dx-do`'s list commands for these resource types
return wrapped table output with no raw-JSON mode, so reliably
re-discovering an id by name alone isn't practical. If the state file is
lost, the resources still exist in the tenant; find them by name via the
relevant `dx-do list` command and remove them manually (each script's
header comment says which).

## Docker/Kubernetes separation

Added 2026-08-26: the user reported that Browser Agent/AXA telemetry (and,
on inspection, several other resources across this directory) mixed both
the Docker Compose and Kubernetes deployments' data together with no way
to tell them apart in the console -- e.g. one shared Metric Grouping
matched `bpa-demo-docker` *and* `bpa-demo-k8s` in a single wildcarded
regex, so a `trouble`-use-case spike or a DB outage on either deployment
fired the identical alert. Every script now takes the required
`<docker|k8s>` platform argument documented above; what it actually does
with it falls into two groups:

- **Genuinely duplicated per platform** (`bpa-demo-service.sh`,
  `bpa-demo-management-module.sh`, `bpa-demo-agent-alerts.sh`'s infra/php
  tiers, `bpa-demo-universe.sh`, `bpa-demo-services-universe.sh`,
  `bpa-demo-sli.sh`'s response-time/error-rate groups, `bpa-demo-axa-app.sh`):
  the previously-wildcarded identity segment (`bpa-demo-[^|]+` or similar)
  became a literal, platform-specific one (`bpa-demo-docker` /
  `bpa-demo-k8s`), and the resource itself was duplicated -- one instance
  per platform, tracked in separate state files. The pre-existing shared
  instance was repointed to be the "docker" one (same name, corrected
  pattern) rather than deleted and recreated; a new "k8s" instance was
  created alongside it. Where the underlying `dx-do` API can't remove an
  already-added entry (`apm-universe`'s metric sources), the old
  wildcarded entry stays in place, harmlessly inert, alongside the new
  literal one -- same "no remove command" limitation already documented
  for that script before this change.
- **Not duplicated -- already solved at the runtime/viewer level**
  (`bpa-demo-agent-health-dashboard.sh`, `bpa-demo-application-dashboards.sh`):
  these dashboards already had a Grafana template variable ("Deployment"
  or "Application(s)") that lets a viewer pick one platform, both, or
  either -- duplicating the whole dashboard would just be a second copy of
  the identical thing. Here the platform argument instead sets that
  variable's *default* selection at creation time, so a fresh viewer sees
  one platform by default while still being free to pick otherwise.
- **The two browser-tier alerts and one browser-tier SLI group
  (`bpa-demo-agent-alerts.sh`, `bpa-demo-sli.sh`) and the Browser
  Agent/BPA WebServer content group (`bpa-demo-service.sh`,
  `bpa-demo-universe.sh`) are deliberately left shared** -- there is
  still only one Browser Agent identity (`Logstash-APM-Plugin`) per
  script today, so there is nothing to duplicate against yet. Splitting
  `bpa-demo-axa-app.sh`'s AXA application in two (see the AXA section
  below) may eventually make a real per-platform Browser Agent split
  possible, once real browser traffic against both deployments confirms
  whether the two AXA apps' data actually lands under distinguishable
  paths -- not yet verified, so not yet acted on.

## Scripts

| Script | Manages |
|---|---|
| `bpa-demo-service.sh` | The per-platform `"BPA-Demo"`/`"BPA-Demo K8s"` DX O2 Service -- groups the php-probe's frontend URLs, the BPA Webserver Extension's business transactions, the BPA WebServer Agent's own reporting identity (`Experience Collector Host\|DxC Agent\|Logstash-APM-Plugin`, where the Browser Agent/BA snippet's page-load and page-hits timing actually lands, shared across both platforms), and the mysql backend database under one console view. There is no separate content group for a "Browser Agent" entity -- the `Custom Business Application Agent (Virtual)` path that shows the same values isn't a real topology entity (confirmed empirically: no content-query attribute matches it), so the BPA WebServer Agent group already covers it. `create` is safe to re-run against a Service that predates this group -- it detects and adds anything missing rather than no-op'ing outright. |
| `bpa-demo-management-module.sh` | The per-platform `"BPA-Demo"`/`"BPA-Demo K8s"` APM Management Module, a Metric Grouping matching that platform's tracked frontend URL response time, and an Alert that catches the `trouble` use case (5000 sequential DB reads/request) via a response-time threshold. `empty_basket` and `locked` have no currently-observable APM signal to alert on -- see the script's header comment for why. `create` self-heals a Metric Grouping whose pattern is stale or has zero live matches. |
| `bpa-demo-agent-alerts.sh` | 12 Metric Groupings + Alerts per platform across three telemetry sources, all attached to that platform's own Management Module -- five for the Infrastructure Agent's DB Monitor extension (availability, connection refusals, connection pool pressure, buffer pool cache hit rate, slow query rate; literal per-platform DB Monitor hostname too -- `mariadb` for docker, `127.0.0.1` for k8s), five for the PHP probe agent (app response time, error rate, concurrency, DB backend response time, DB backend query volume), and two for the browser/RUM pipeline (page load time, page hits per interval -- shared across both platforms, no per-platform Browser Agent identity exists yet). Depends on `bpa-demo-management-module.sh <docker\|k8s> create` having been run first for the same platform. Thresholds are measured from live metric windows, not guessed -- see the script's header comment for the readings behind each one. |
| `bpa-demo-universe.sh` | The per-platform `"BPA Demo universe"`/`"BPA Demo K8s universe"` **APM Universe** (`dx-do apm-universe` -- see `bpa-demo-services-universe.sh` for the other, separate universe type the tenant also needs) -- a topology/metric-data scope populated with 3 explicit metric-source agent paths: the Infrastructure Agent and PHP probe agent (literal per-platform identity) and the BPA WebServer Agent (shared, covers both "BPA agent" and "Browser agent"). Unlike a Service, a Universe has no content-query membership mechanism over the CLI -- sources are added one at a time via `apm-universe add-metric-source`, and `create` self-heals by adding any of the 3 that are missing; since `apm-universe` also has no "remove source" command, the docker Universe's pre-split wildcarded entries stay in place alongside the new literal ones, harmlessly inert. `apm-universe create` does not honor `dry-run` (silently ignored, creates for real immediately) -- see the script's header comment for this and other CLI landmines found while writing it. **Known limitation:** the Triage/Topology console view is driven by a different, legacy-shaped filter (`views.tas`) that `add-metric-source` never touches -- see `BUGS` for the full writeup; fixing it needs a manual console step. |
| `bpa-demo-services-universe.sh` | The per-platform `"BPA Demo service universe"`/`"BPA Demo K8s service universe"` **O2/Platform Universe** (`dx-do service-universe` -- a.k.a. "Services Universe" in the console; a different resource from the APM Universe above, with its own id space) -- created because the tenant needs both universe types until the product merges them, scoped via `serviceNames=` to that platform's own Service from `bpa-demo-service.sh`. Was blocked on a confirmed console-crash bug in the old `o2-universe` command group (see `dx-do-o2-universe-issue.md`) until the `dx-do` maintainer replaced that group outright with `service-universe` on 2026-08-24, a full CRUD surface (`create`/`update`/`delete`/`get`/`list`/`export`, dry-run by default) that fixes it. `create` self-heals both by name (if the state file is lost) and by filter correctness (re-applies `serviceNames` via `update` if it's ever found to have drifted). |
| `bpa-demo-sli.sh` | Three **SLI groups** per platform (Service Level Indicators, `dx-do sli` -- see the SLIs section below) bound to that platform's own Service: Frontend Response Time, Frontend Error Rate (both literal per-platform identity, group names suffixed `" K8s"` on that platform since sli group names must be unique per tenant), Client-Side Page Load Time (shared across both platforms, no per-platform Browser Agent identity yet). Each has an SLO (rolling-percentage/error-budget) and an alert on the SLO's rolling percentage. Uses `dx-do` v7.2.1's structured `sli create-group`/`add-slo`/`add-alert`/`set-group-filter` surface -- no JSON templates, no file-based import. `delete` runs `sli delete-group`, which really does delete the SLI, its SLO, and its alerts. |
| `bpa-demo-agent-health-dashboard.sh` | The single, shared `"BPA-Demo · Agent Health"` **Dashboard** (`dx-do dashboard` -- see the Dashboards section below) in the existing `"BPA-Demo"` folder -- NOT duplicated per platform (see "Docker/Kubernetes separation" above). One traffic-light circle per deployed agent, rolling up that agent's own alerts, plus each agent's basic metrics. Includes a "Deployment" dropdown variable (`docker`/`k8s`/"All") so the Infrastructure Agent/PHP Probe panels can be scoped to one deployment or show both together; the required `<docker\|k8s>` argument sets which value that dropdown defaults to on (re)creation, not a duplicate dashboard. This dx-do build's `dashboard` command group has no `dashboard-create`/`dashboard-delete`/`validate-layout`/`dashboard-render` at all -- `create` uses `dashboard-import` (fresh) or the classic export -> edit -> `dashboard-update` workflow (upsert), and `delete` prints manual console-removal instructions since no CLI command exists for it. |
| `bpa-demo-application-dashboards.sh` | Three more single, shared **Dashboards** in the existing `"BPA-Demo"` folder -- `"BPA-Demo · Application Overview"`, `"BPA-Demo · Application Drilldown"`, `"BPA-Demo · Transaction Details Drilldown"` -- also NOT duplicated per platform; the required `<docker\|k8s>` argument instead sets each dashboard's own "Application(s)" dropdown (queried live from the raw data's `app_alias` field) to default to that platform's identity. Templated from dashboards the user exported by hand from the console (`jm-dashboards/bpa/`), not authored from scratch. Unlike every other dashboard/alert/SLI in this project, these query the BPA WebServer Extension's raw captured-transaction Elasticsearch index (`AIOps_BPAMetadata` datasource, `ao_aum_captured_data_2*`) directly -- per-request rows (`app_alias`, `bt_name`, `res_status`, `server_time`, client/server IPs, `transaction_id`, ...), not a NASS metric-catalog aggregate. Same create/check/delete shape and dashboard-import/export-edit-update upsert pattern as `bpa-demo-agent-health-dashboard.sh` (array-driven over all three). See the Dashboards section below for what each one shows. |
| `bpa-demo-axa-app.sh` | One **AXA application** (`dx-do axa` -- Application Experience Analytics, DX O2's mobile/browser Real User Monitoring surface) per platform -- `"BPA Demo AXA"` (docker; unchanged name, `axa` has no rename command) and `"BPA Demo AXA K8s"` (k8s; new) -- created because the demo's Browser Agent snippet needs an AXA application to generate it, normally a console-only step. `create` self-heals by name, then fetches the resulting BrowserAgent snippet (`axa get-application-snippet`) and patches it directly into the checked-in `.config.example`'s matching `APMIA_BROWSER_SNIPPET_DOCKER`/`APMIA_BROWSER_SNIPPET_K8S` line -- safe to commit since the snippet is a client-side `<script>` tag meant to be embedded in every page, not a secret like the rest of `.config`. `compose.sh` reads only the `_DOCKER` variable, `deploy.sh` only `_K8S` -- see `build-scripts/compose.sh`/`deploy.sh`'s own comments. See the AXA section below. |

## Alerts

13 alerts total, all `GREATER_THAN`/`LESS_THAN` threshold alerts on the
`"BPA-Demo"` Management Module, evaluated every 60s. "Warning"/"Error" are
the two severities DX O2 raises for the same alert at increasing threshold
breach; both use the same comparison direction.

### Trouble-use-case alert (`bpa-demo-management-module.sh`)

| Alert | Monitors | Triggers when |
|---|---|---|
| Trouble User - High Response Time | Every tracked frontend URL's average response time (PHP probe agent) | `> 100ms` (warning) / `> 250ms` (error) -- catches the `trouble` demo user (`usecases/trouble.php`, 5 000 sequential DB reads/request); normal traffic runs ~6-7ms |

### Infrastructure Agent -- DB Monitor extension (`bpa-demo-agent-alerts.sh`)

| Alert | Monitors | Triggers when |
|---|---|---|
| Infra Agent - DB Availability Down | MariaDB `Availability` gauge (1 = up) | `< 1` (both warning and error) -- the DB Monitor extension can no longer reach MariaDB |
| Infra Agent - DB Connection Refusals | MariaDB connection refusal rate | `> 0` (warning) / `> 5` (error) -- any refusal is a signal; sustained refusals are worse |
| Infra Agent - DB Connection Pool Pressure | MariaDB connection usage rate (%) | `> 80%` (warning) / `> 95%` (error) -- approaching the connection limit |
| Infra Agent - DB Buffer Pool Cache Degraded | InnoDB buffer pool cache hit rate (%) | `< 95%` (warning) / `< 90%` (error) -- normally 97-99%; a drop means the buffer pool is undersized for the working set |
| Infra Agent - DB Slow Query Rate Rising | MariaDB slow-query rate (%) | `> 1%` (warning) / `> 5%` (error) -- normally 0% |

### PHP probe agent -- app frontend + DB backend (`bpa-demo-agent-alerts.sh`)

| Alert | Monitors | Triggers when |
|---|---|---|
| PHP Probe - App Response Time High | App-level average response time (all URLs aggregated) | `> 100ms` (warning) / `> 250ms` (error) -- app-wide counterpart to the trouble-use-case alert above |
| PHP Probe - App Error Rate Rising | App-level errors per interval | `> 2` (warning) / `> 5` (error) |
| PHP Probe - App Concurrency Spike | App-level concurrent invocations | `> 5` (warning) / `> 15` (error) -- baseline is ~0 on this low-traffic demo |
| PHP Probe - DB Backend Response Time High | Average response time of the PHP app's calls to the MariaDB backend | `> 50ms` (warning) / `> 150ms` (error) |
| PHP Probe - DB Backend Query Storm | Backend responses per interval (query volume) | `> 20 000` (warning) / `> 40 000` (error) -- catches query-volume bursts like the `trouble` use case's 5 000-read requests |

### Browser/RUM pipeline -- BPA WebServer Agent (`bpa-demo-agent-alerts.sh`)

Reported per-URL via the `Logstash-APM-Plugin` identity (see `CLAUDE.md`'s
`dxo2-scripts/` section for where this data actually comes from -- the
Browser Agent/BA snippet, relayed into APM by the BPA plugin).

| Alert | Monitors | Triggers when |
|---|---|---|
| Browser RUM - Page Load Time High | Real-user page load time (ms), per tracked URL | `> 300ms` (warning) / `> 1000ms` (error) -- this is client-side network+render time, not server response time, so it runs higher than the PHP-tier alerts above |
| Browser RUM - Page Hits Spike | Real-user page hits per interval, per tracked URL | `> 10` (warning) / `> 20` (error) -- peaked at 11 on `/shop` in the measured sample, 0-4 elsewhere |

## SLIs

An SLI (Service Level Indicator) is a different resource type from the
Alerts above: instead of a threshold on a raw agent metric, it's a metric
*computed and written onto the Service's own topology vertex*, tagged
`is_sli: true`. As of `dx-do` v7.2.1, `sli` has a real, structured
command surface (`create-group`, `add-sli`, `add-slo`, `add-alert`,
`set-group-filter`, `delete-group`, all dry-run by default) -- see
`dx-do help slis` for the full SLI-group/SLI/SLO/alert model. This
replaced the older `sli export`/`import`-only surface (no update, refused
on name collision) after the tenant's entire SLI subsystem was found to
have been reset on 2026-08-21 -- see CLAUDE.md's dxo2-scripts section and
TOBEDONE.md's SLI/SLO section for the investigation.

`bpa-demo-sli.sh` creates 3 independent SLI groups, each with 1 SLI + 1
SLO (objective/rolling-percentage/error-budget) + 1 alert (on the SLO's
rolling percentage), all bound to the `BPA-Demo` Service:

| SLI group | Computes | SLO objective |
|---|---|---|
| BPA-Demo Frontend Response Time | Average of every `Frontends\|Apps\|bpa-demo-*\|URLs\|<page>:Average Response Time (ms)` from the PHP probe agent | `LE 200`ms, 98% target, rolling 1-day |
| BPA-Demo Frontend Error Rate | Average of every `Frontends\|Apps\|bpa-demo-*\|URLs\|<page>:Errors Per Interval` from the PHP probe agent | `LE 2`, 98% target, rolling 1-day |
| BPA-Demo Client-Side Page Load Time | Average of every `Business Segment\|BPA Demo\|<page>:Average Page Load Time (ms)` from the Browser Agent (`Logstash-APM-Plugin` identity) | `LE 300`ms, 98% target, rolling 1-day |

Every alert fires caution below 98% / danger below 90% of the SLO's
rolling percentage. The Page Load Time group currently registers
`sliStatusCode 5` ("no metrics matching") -- not a bug, browser-agent
auto-injection is currently reverted (see CLAUDE.md's "PHP probe
injection" section), so there's no live client-side data at all right
now; it lights up on its own once/if that resumes.

**Landmine found while building this:** the `regex` filter condition is
silently broken by a trailing `$` anchor -- `foo$` matches zero metrics
with no error, `foo` (same pattern, no anchor) matches correctly. The
match is effectively start-anchored/prefix-style already; omit trailing
`$` entirely on any `sli` filter pattern. See `bpa-demo-sli.sh`'s header
comment for the full writeup, including a second landmine (the PHP
probe's app-level metric aggregates aren't visible in the SLI
subsystem's service-scoped view, only per-URL ones are).

`create` is safe to re-run: for an existing group it re-applies the group
filter (`set-group-filter` is idempotent) and adds the SLO/alert only if
missing, rather than erroring on the old CLI's name-collision refusal.

## Dashboards

`bpa-demo-agent-health-dashboard.sh` creates `"BPA-Demo · Agent Health"` in
the existing `"BPA-Demo"` dashboard folder (a dashboard's title can't equal
its containing folder's title, hence the `· Agent Health` suffix). Every
data panel carries a `description` (Grafana's "i" hover icon, top-left of
the panel) naming its real telemetry source. Six sections, covering **four
distinct telemetry sources** -- it's easy to conflate the last two, since
both are published under the same `Logstash-APM-Plugin` agent identity, but
they observe the same requests from opposite ends:

| Section | Source | Panels |
|---|---|---|
| Agent Status (row) | -- | 3 `grafana-polystat-panel` traffic-light circles -- Infrastructure Agent, PHP Probe Agent, Browser Agent |
| Infrastructure Agent -- Host + MySQL DB | DB Monitor extension, querying MariaDB directly | DB Availability (stat), Connection Refusal Rate, Buffer Pool Cache Hit Rate, Slow Query Rate (graphs) |
| PHP Probe Agent -- Inside the PHP Process | PHP probe, instrumented in the PHP process itself | App Response Time, App Error Rate, App Concurrency, DB Backend Response Time (graphs) |
| Browser Agent -- Real User Monitoring | BA JavaScript snippet, executed in a real visitor's **browser** -- client-perceived timing (network + render included) | Page Load Time, Page Hits, Resource Time To First Byte (graphs) -- the first two will likely show 0/no-data under the traffic generator alone (plain HTTP requests, no real browser); the third has real historical data from earlier manual browser testing |
| BPA WebServer Plugin -- Inside Our Apache Server | `mod_caplugin`, running in **our own Apache server** -- server-side per-business-transaction timing of the *same* requests | Response Time, Backend Server Time, Responses Per Interval, Errors Per Interval (graphs) |
| Network + Overhead Time | (comparison of the two sections above) | One graph overlaying the BPA plugin's Response Time and Backend Server Time -- the visual gap approximates time spent outside backend processing (network transit + plugin overhead) |

Each traffic light queries the reserved `Custom Metric Agent (Virtual)`
alert-status metric (`Alerts|BPA-Demo:<alert name>`, published by the EM for
every alert on an active Management Module) with a regex matching every
alert belonging to that agent's tier, and rolls up to the *worst* (`max`)
severity among them via a polystat composite -- green only if every alert
for that agent is currently OK. This reuses the alerts already created by
`bpa-demo-management-module.sh`/`bpa-demo-agent-alerts.sh`; it creates no new
alert. All query patterns (the alert-status regexes and the metric graphs)
were verified live against real `dx-do metric data` output before being
wired into the dashboard JSON, including confirming the lights show a real
mix of ok/warning/critical rather than being trivially all-green.

**Bug fixed 2026-07-09: every panel still rendered empty despite that
verification.** `metric data`'s `agentExpression` regime strips the
`SuperDomain|` prefix before matching, but the dashboard's own NASS query
engine (`basicFilters[].sourceNameSpecifier[].pattern` -- the same
mechanism `dx-do nass query` exposes directly) matches the **full**
`metric.source` string, which always starts with `SuperDomain|`. Every
`sourceNameSpecifier` pattern in the template was written in the bare
3-segment form (correctly verified against `metric data`, which
normalizes the prefix away) and so matched zero rows against the
dashboard's actual query surface -- the same "3-/4-segment path regime"
confusion documented under `reference-agent-expressions` and the
`bpa-demo-management-module.sh` bug, hitting a third API surface this
time. Found via the empirical-discovery move: a `dx-do nass query`
`FROM_METADATA` + `KEEP` probe with the bare pattern returned zero rows;
the identical pattern with `SuperDomain\|` prepended returned the real
metric. Fixed by prepending `SuperDomain\|` to all 13
`sourceNameSpecifier` patterns (3 polystat + 10 metric-graph targets);
re-verified every one of the 18 panels' query patterns individually
against the raw `nass query` API before redeploying. **`dx-do metric
data` is not a valid stand-in for verifying a dashboard's own NASS query
shape** -- verify `sourceNameSpecifier` patterns with `dx-do nass query`
instead.

**2026-07-09: split into 4 real sources, added descriptions, added a
network-time comparison.** The original build's "Browser/RUM" section
conflated two genuinely distinct telemetry sources that happen to publish
under the same `Logstash-APM-Plugin` agent identity: the **Browser
Agent** (client-side, `Business Segment|BPA Demo|<url>:...`) and the
**BPA WebServer Plugin** (server-side, `Business Segment|[BPA Demo]<ip
running Apache>/<port>|<X-Page-ID>:...` -- the `[BPA Demo]<ip>:<port>`
segment identifies which Apache instance reported it; stale entries from
before the `172.28.0.0/24` static-IP fix are still visible in the
catalog and harmless, since the section's patterns wildcard the IP).
Split into their own sections, added a dedicated **BPA WebServer
Plugin** section (Response Time, Backend Server Time, Responses/Errors
Per Interval, all wildcarded across business transactions and IPs), and
added the Browser Agent's real per-resource `Average Time To First Byte
(ms)` metric -- confirmed via `nass query` to have genuine non-zero
historical data (from earlier manual browser testing), unlike the
page-level Page Load Time/Page Hits metrics which stay at 0 under the
traffic generator alone.
For the requested "network time" panel: looked into a true computed
difference (`Response Time - Backend Server Time`) via Grafana's
`calculateField` transform, but this dx-do build has no `dashboard-render`
to visually confirm how the AIOps NASS datasource plugin actually names
its output fields -- shipping an unverifiable transform risked silently
doing nothing. Shipped the verified alternative instead: both metrics as
separate lines on one graph, so the gap is visible by eye. The transform
is a reasonable follow-up once it can be checked in the console's own
panel editor (where the real field names are visible).

**2026-07-10: identity collision emptied the DB Monitor/PHP Probe panels
again -- an operational cause, not an authoring bug this time.** The
Docker Compose and Helm/Kubernetes deployments both defaulted to
identical DX O2 agent identity strings; running them concurrently made
DX O2 suffix the second connection's identity with `%1`, and the
dashboard's exact-anchored patterns matched neither. Separately, 5
panels also hardcoded the literal hostname segment `mariadb`/
`mariadb-3306`, which only ever matched Compose's naming and never
Kubernetes' `127.0.0.1`-based paths, collision or not. Fixed at the
`.config` layer with two new variables, `DEPLOYMENT_NAME` +
`DEPLOYMENT_POSTFIX` (see `CLAUDE.md`'s "Deployment identity" section),
which give every APMIA-based agent a distinguishable identity per
deployment (`bpa-demo-k8s` / `bpa-demo-docker`). Wildcarded the
hardcoded literals and made the identity match tolerant of an optional
`%N` suffix in the dashboard template.

**Added a "Deployment" dropdown variable** (`docker`/`k8s`, defaults to
"All") once the identities above were fixed, since the old plain
`bpa-demo-host`/`bpa-demo-infra-agent`/`bpa-demo-php-probe` literals no
longer existed at all. Interpolated via Grafana's `${deployment:regex}`
format into all 8 DB-Monitor/PHP-Probe `sourceNameSpecifier` patterns.
Two bugs found while shipping this:
- The self-heal upsert script only ever merged `panels`/`title`/`tags`
  from the template into the live export -- it silently dropped the new
  `templating` block on the first push (version bumped, variable never
  appeared). Fixed by also merging `dashboard.templating`.
- The "All" option showed as the initial dropdown label but vanished
  from the actual open list once a specific value was picked, with no
  way back short of a page reload. This build's `custom`-type variable
  dropdown renders its open list directly from the stored `options`
  array rather than regenerating it from `query`+`includeAll` each
  render -- the array only ever listed `docker`/`k8s`, so "All" was
  never a real, re-selectable entry. Fixed by adding an explicit
  `{"text": "All", "value": "$__all"}` entry as `options[0]`, matching
  the shape Grafana's own UI generates when "include All option" is
  checked by hand.

**PHP probe `UnknownAgent` root cause, per Broadcom's PHP agent naming
docs.** Kubernetes' PHP probe reported under the generic fallback
`UnknownAgent` instead of its real identity even after the collision fix
above. Per Broadcom's docs, the metric path's agent-name segment is the
`{collector}` variable -- the Infrastructure Agent's own `agentName`,
resolved at the moment the PHP probe first registers with the IA's
PHP-collector socket. `apache-php`'s entrypoint started Apache with no
wait for the `dx-o2-agent` sidecar's collector socket to be listening; in
Kubernetes (separate containers, no guaranteed start order, JVM
cold-start + EM handshake under a CPU limit) the probe's first
registration could race ahead of the IA and permanently fall back to the
placeholder -- Compose's lighter startup made it unlikely to lose that
race, which is why only Kubernetes showed the symptom. Fixed with a wait
loop in the entrypoint (polls the collector port, 60s cap, warns and
continues on timeout); not yet confirmed against the live cluster, since
that needs an image rebuild + redeploy with no cluster access from the
environment that made the fix.

**Landmines found on this dx-do build, none of which match some dx-do
documentation written for newer builds:**
- `dashboard-export`/`dashboard-import`/`dashboard-update` all take
  `dashboardExportFile=`, not `dashboardFile=`.
- `dashboard-import`'s `overwrite=` parameter is silently ignored (no
  "ignoring extra args" warning for `overwrite` itself, but the request
  body always shows `"overwrite":false` regardless of what's passed) --
  attempting the documented `preserveUid=true overwrite=true` upsert
  fails with HTTP 412 `version-mismatch` because the payload is missing
  the `version` field Grafana requires for a plain non-overwrite save.
- `dashboard-update` does **not** resolve a numeric id from a bare
  `dashboard.uid` on this build -- it fails with `Export dashboard does
  not have an id!` even when `uid` is set and live. The classic export
  -> edit -> update workflow (get the real numeric `id` + `meta.folderId`
  via `dashboard-export`, splice in the regenerated panels, then
  `dashboard-update`) is what actually works, and is what `create`'s
  self-heal path does.
- There is no `dashboard-create`, `dashboard-delete`, `validate-layout`,
  or `dashboard-render` command at all in this build's `dashboard` group
  -- geometry was hand-verified (24-column grid, no overlaps) instead of
  linted, and there's no way to screenshot the result for a visual
  self-check; verification instead relied on `dashboard-export`/`check`
  (correct panel count/types/titles) and direct `metric data` queries
  confirming every panel's underlying query returns real data.

### `bpa-demo-application-dashboards.sh` -- BPA WebServer Extension raw-capture dashboards

2026-08-21: the user exported three more BPA-related dashboards by hand
from the console (Dashboards -> JSON Model -> Export) into
`jm-dashboards/bpa/` and asked for them to be templated and created in
the `"BPA-Demo"` folder the same way `bpa-demo-agent-health-dashboard.sh`
was. Unlike every other dashboard/alert/SLI in this project, all three
query the **`AIOps_BPAMetadata`** Grafana datasource directly against
the BPA WebServer Extension's raw captured-transaction Elasticsearch
index (`ao_aum_captured_data_2*`) -- one document per HTTP
request/response `mod_caplugin` actually captured (`app_alias`,
`bt_name`, `res_status`, `server_time`, `res_size`/`req_size`,
`req_metadata_client_ip`/`req_metadata_server_ip`,
`req_header_x_forwarded_for`, `reqUrl.keyword`, `transaction_id`), not a
NASS metric-catalog aggregate. There is no metric-catalog equivalent of
"list me the individual slow requests" -- that's exactly the gap these
three fill.

| Dashboard | Templating vars | Panels |
|---|---|---|
| `"BPA-Demo · Application Overview"` | `application` | Success Rate (piechart: HTTP <500 vs. 5xx), Average Response Time heatmap, Response Count (graph), and three "Performance Overview" tables -- dashboard time range, fixed last-24h, fixed last-7d -- each breaking ART/percentiles/size/volume/count/server-errors out per Business Transaction |
| `"BPA-Demo · Application Drilldown"` | `application`, `bt_name` | Server Errors (graph), ART by Server IP (heatmap -- spot one slow backend instance), Unique Client IPs / Forwarded Client IPs (stat -- the latter is the real client when behind a reverse proxy), Performance Overview (BT-level) + Performance Overview Details (URL-level) tables |
| `"BPA-Demo · Transaction Details Drilldown"` | `application`, `bt_name`, `httpStatus`, `resTime` (min response time threshold), `Filters` (ad hoc) | Transaction Details (by time/client IP/server IP), a "Total Filtered Transactions" stat, a raw-captured-document table (intentionally unaggregated -- narrow the filters first or it returns up to 10 000 raw documents), Filtered Transaction List keyed by `transaction_id` |

Templating (from the raw export -> template step):
- `id`/`uid`/`version`/`iteration`/`gnetId` stripped so a fresh import
  mints its own (matches `bpa-demo-agent-health-dashboard.sh`'s
  template convention).
- Titles prefixed `"BPA-Demo · "` to match the existing dashboard in the
  same folder, and the original `"Transaction Details  Drilldown"`
  double-space typo fixed to a single space.
- `tags` set to `["bpa-demo", "BPA"]` -- keeps the dashboards' own
  built-in "BPA" cross-link dropdown (each dashboard's `links[1]` lists
  every dashboard tagged `BPA`) working, while also matching this
  project's `bpa-demo` tagging convention.
- A human-readable `description` (the "i" hover icon) added to every
  data panel that lacked one, grounded in the actual ES fields each
  panel's `targets[].metrics`/`bucketAggs` query (verified by reading
  each panel's raw JSON, not guessed from the title alone). The one
  panel that already had a description (the response-time heatmap) was
  left as-is.

Same create/check/delete shape as `bpa-demo-agent-health-dashboard.sh`,
just array-driven over all three keys in one script instead of one
script per dashboard -- `create` uses `dashboard-import` for a fresh
dashboard and the same export -> edit -> `dashboard-update` upsert
workaround for an existing one (this build's `dashboard-import
overwrite=true` and `dashboard-update`-from-bare-uid limitations apply
identically here; see the landmines list above). `delete` prints manual
console-removal instructions per dashboard, same as before. The
`AIOps_BPAMetadata` datasource is referenced by plain name, not a
templated `${DS_...}` input, so it must already exist on the target
tenant -- true here since the source dashboards were exported directly
from this same tenant.

Verified live: `create` imported all three into the `"BPA-Demo"` folder
with the expected panel counts/types/titles (`check`'s output matches
the original exports exactly); re-running `create` upserted all three
in place by uid (version 1 -> 2, no duplicates) instead of re-importing;
`dashboard-export` after the upsert confirmed `tags`, `templating`, and
every panel's `description` survived the export -> edit -> update
round-trip.

## AXA

`dx-do axa` (Application Experience Analytics) is DX O2's mobile/browser
Real User Monitoring surface -- a genuinely different resource type from
every other telemetry source this project's scripts manage (Services,
Universes, Management Modules/Metric Groupings/Alerts, SLI groups,
Dashboards). An AXA **application** definition is what a BrowserAgent
(BA) snippet is generated *for* -- the exact `<script>` tag this
project's `APMIA_BROWSER_SNIPPET` config variable carries (see
`CLAUDE.md`'s ".config required variables" and "PHP probe injection"
sections). Normally obtained by hand via DX O2 Settings -> Manage
Mobile/Browser Web Monitoring -> App to Monitor -> Web App.

`bpa-demo-axa-app.sh create` does that step via the CLI instead: creates
(self-healing by name) the `"BPA Demo AXA"` application, fetches its
BrowserAgent snippet via `axa get-application-snippet`, and patches it
directly into the checked-in `.config.example`'s `APMIA_BROWSER_SNIPPET`
line -- unlike every other value in `.config`/`.config.example`, the
snippet is safe to commit: it's a client-side tag meant to be embedded in
every page and visible via view-source, not a credential. Named
`"BPA Demo AXA"` rather than plain `"BPA Demo"` to avoid colliding with
the many other tenant resources already using that exact name (the
Service, both Universe types, the Management Module, the SLI groups --
none of which are AXA applications, but `axa list-applications` has no
type qualifier to disambiguate by if the names collided).

Two landmines found live while writing this:
- `axa create-application` has no `dry-run` parameter at all (confirmed
  via `dx-do help describe group=axa command=create-application`) and
  rejects duplicate names outright -- `create` here always checks `axa
  list-applications` for an existing entry by name first, rather than
  calling create and handling the rejection, unlike the dry-run-gated
  `service-universe create`/`sli create-group` elsewhere in this
  project.
- `axa get-application-snippet` silently ignores `output.format=json`
  (prints "ignoring extra args" and always returns pretty-printed,
  multi-line HTML with leading whitespace per attribute line) --
  `fetch_snippet()` strips the usual progress-noise lines plus blank
  lines, then collapses the remaining HTML to the single-line form this
  project's `.config` already uses elsewhere via
  `' '.join(text.split())`. The patch itself writes the snippet to a
  temp file and passes file paths into a single-quoted (non-
  interpolating) python heredoc, rather than embedding the raw snippet
  text into inline python source via bash string interpolation -- the
  snippet's many `/`, `:`, and `"` characters make sed-delimiter or
  shell-string-interpolation approaches fragile, the same class of bug
  `entrypoint.sh`'s `bundle.properties` patching hit and solved by
  picking `@` as a delimiter unlikely to appear in a value.

`create` is safe to re-run: always re-fetches and re-syncs the snippet
into `.config.example` even if the application already existed, so it
also serves as a "resync the template" operation after any tenant-side
change. `delete` additionally resets `.config.example`'s
`APMIA_BROWSER_SNIPPET` back to the empty placeholder, since the
snippet would otherwise reference a deleted application.

Verified live: `create` created the application (key
`4ab13890-...`), and `.config.example`'s `APMIA_BROWSER_SNIPPET` line
was patched with a single-line snippet identical in shape to the
existing, separately/manually-created `"BPA Demo"` AXA application's own
snippet already live in this tenant's real `.config` -- confirmed via
`git diff .config.example` that only that one line changed. Re-running
`create` is idempotent (`axa list-applications` confirms exactly one
`"BPA Demo AXA"` entry, no duplicate).
