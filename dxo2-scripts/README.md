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
dxo2-scripts/<name>.sh create        # create the resource; safe to re-run
dxo2-scripts/<name>.sh check         # print whether it exists + its definition
dxo2-scripts/<name>.sh delete [-y]   # delete it (prompts unless -y/--yes)
dxo2-scripts/<name>.sh -h|--help     # usage
```

`create` is idempotent: it checks for the resource first and warns instead
of failing if it already exists. `delete` prompts for confirmation by
default since it mutates shared tenant state visible to everyone with
console access -- pass `-y`/`--yes` for non-interactive use.

Scripts managing classic-APM resources (Management Modules, Metric
Groupings, Alerts) persist the ids `create` returns to a local
`.state/<script-name>.env` file (git-ignored) so `check`/`delete` can find
them again -- `dx-do`'s list commands for these resource types return
wrapped table output with no raw-JSON mode, so reliably re-discovering an
id by name alone isn't practical. If the state file is lost, the resources
still exist in the tenant; find them by name via the relevant `dx-do list`
command and remove them manually (each script's header comment says which).

## Scripts

| Script | Manages |
|---|---|
| `bpa-demo-service.sh` | The `"BPA-Demo"` DX O2 Service -- groups the php-probe's frontend URLs, the BPA Webserver Extension's business transactions, the BPA WebServer Agent's own reporting identity (`Experience Collector Host\|DxC Agent\|Logstash-APM-Plugin`, where the Browser Agent/BA snippet's page-load and page-hits timing actually lands), and the mysql backend database (both the php-probe's inferred dependency and the DB Monitor extension's own CI) under one console view. There is no separate content group for a "Browser Agent" entity -- the `Custom Business Application Agent (Virtual)` path that shows the same values isn't a real topology entity (confirmed empirically: no content-query attribute matches it), so the BPA WebServer Agent group already covers it. `create` is safe to re-run against a Service that predates this group -- it detects and adds anything missing rather than no-op'ing outright. |
| `bpa-demo-management-module.sh` | The `"BPA-Demo"` APM Management Module, a Metric Grouping matching every tracked frontend URL's response time, and an Alert that catches the `trouble` use case (5000 sequential DB reads/request) via a response-time threshold. `empty_basket` and `locked` have no currently-observable APM signal to alert on -- see the script's header comment for why. `create` self-heals a Metric Grouping with zero live matches (see the script's "Bug fixed 2026-07-06" header comment -- a missing `SuperDomain\|` prefix on the inherited agent pattern silently matched nothing). |
| `bpa-demo-agent-alerts.sh` | 12 Metric Groupings + Alerts across three telemetry sources, all attached to the same `"BPA-Demo"` Management Module -- five for the Infrastructure Agent's DB Monitor extension (availability, connection refusals, connection pool pressure, buffer pool cache hit rate, slow query rate), five for the PHP probe agent (app response time, error rate, concurrency, DB backend response time, DB backend query volume), and two for the browser/RUM pipeline (page load time, page hits per interval -- attributed to a `Logstash-APM-Plugin` identity that never shows up in `dx-done agent list`, scoped in anyway via an explicit `sourceNamePattern` since `managementmodule update` is broken on this dx-do version). Depends on `bpa-demo-management-module.sh create` having been run first. Thresholds are measured from live metric windows, not guessed -- see the script's header comment for the readings behind each one. |
| `bpa-demo-universe.sh` | The `"BPA Demo universe"` **APM Universe** (`dx-do apm-universe` -- see `bpa-demo-services-universe.sh` for the other, separate universe type the tenant also needs) -- a topology/metric-data scope populated with 3 explicit metric-source agent paths, covering all 4 of the app's named telemetry identities: the Infrastructure Agent, the PHP probe agent, and the BPA WebServer Agent (which covers both the "BPA agent" and the "Browser agent" -- see the Alerts section above for why there's no fourth, independent Browser Agent entity). Unlike a Service, a Universe has no content-query membership mechanism over the CLI -- sources are added one at a time via `apm-universe add-metric-source`, and `create` self-heals by adding any of the 3 that are missing. `apm-universe create` does not honor `dry-run` (silently ignored, creates for real immediately) -- see the script's header comment for this and other CLI landmines found while writing it. **Known limitation:** the Triage/Topology console view is driven by a different, legacy-shaped filter (`views.tas`) that `add-metric-source` never touches -- see `BUGS` for the full writeup; fixing it needs a manual console step. |
| `bpa-demo-services-universe.sh` | The `"BPA Demo"` **O2/Platform Universe** (`dx-do o2-universe` -- a.k.a. "Services Universe" in the console; a different resource from the APM Universe above, with its own id space) -- created because the tenant needs both universe types until the product merges them. `o2-universe create` accepts no scoping parameters at all (extras are silently ignored), so a CLI-created Universe is always unscoped (`{"filter": {"op": "ALL"}}` on both its `tas` and `nass` views) -- **confirmed to crash the console's edit UI** when opened in that state (2026-07-07; see `dx-do-o2-universe-issue.md`). There is no `update`/`add-view` command to narrow it afterward either, so this script deliberately does **not** fall back to `o2-universe create` when its state file is missing/stale -- it fails with instructions for manual console creation instead (pick a Service scope in the console's own creation wizard, which avoids the crash entirely). The currently-tracked instance (`VIEW618`) was created that way. `delete` still uses `apm-universe delete`, which works across both universe types since `o2-universe` has no `delete` command of its own. |
| `bpa-demo-sli.sh` | Three **SLI groups** (Service Level Indicators, `dx-do sli` -- see the SLIs section below) bound to the `"BPA-Demo"` Service: Frontend Response Time, Frontend Error Rate, Client-Side Page Load Time. Each has an SLO (rolling-percentage/error-budget) and an alert on the SLO's rolling percentage. Uses `dx-do` v7.2.1's structured `sli create-group`/`add-slo`/`add-alert`/`set-group-filter` surface -- no JSON templates, no file-based import. `delete` runs `sli delete-group`, which really does delete the SLI, its SLO, and its alerts (unlike the old CLI's service-unbind-only `exclude-service`). |
| `bpa-demo-agent-health-dashboard.sh` | The `"BPA-Demo · Agent Health"` **Dashboard** (`dx-do dashboard` -- see the Dashboards section below) in the existing `"BPA-Demo"` folder: one traffic-light circle per deployed agent, rolling up that agent's own alerts, plus each agent's basic metrics. Includes a "Deployment" dropdown variable (`docker`/`k8s`, defaults to "All") so the Infrastructure Agent/PHP Probe panels can be scoped to one deployment or show both together -- see "2026-07-10" below for why that's needed and two bugs found shipping it. This dx-do build's `dashboard` command group has no `dashboard-create`/`dashboard-delete`/`validate-layout`/`dashboard-render` at all -- `create` uses `dashboard-import` (fresh) or the classic export -> edit -> `dashboard-update` workflow (upsert; `dashboard-import`'s documented `preserveUid=true overwrite=true` upsert doesn't work on this build -- `overwrite=` is silently ignored), and `delete` prints manual console-removal instructions since no CLI command exists for it. |

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
