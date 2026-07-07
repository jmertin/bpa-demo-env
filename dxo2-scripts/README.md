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
| `bpa-demo-sli.sh` | The `"BPA-Demo Frontend Response Time"` **SLI** (Service Level Indicator, `dx-do sli` -- see the SLIs section below) bound to the `"BPA-Demo"` Service. `sli` has no native create/delete: `create` runs `sli import` against a tracked JSON template (`templates/bpa-demo-response-time-sli.json`), and `delete` runs `sli exclude-service` (unbinds the service; the SLI definition itself is never deleted -- there is no command for that). Raw SLI only for now, no SLO/error-budget/alert layer -- see the script's header comment for why. |

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
`is_sli: true`. `dx-do`'s `sli` command group has no native create/delete --
a new SLI is made by `sli import`-ing a raw SLI export JSON file bound to a
target service (`serviceName=`); the unbind counterpart is `sli
exclude-service` (there is no `sli delete`).

| SLI | Computes | Bound to |
|---|---|---|
| BPA-Demo Frontend Response Time | Average of every `Frontends\|Apps\|BPA-Demo\|URLs\|<page>:Average Response Time (ms)` metric from the PHP probe agent, via a `REGEX` specifier that excludes nested `Called Backends\|...SQL...` sub-metrics -- page load time, not blended with DB query time. Surfaces the `trouble` use case's slowdown regardless of which page the trouble user visits. | `BPA-Demo` Service |

Raw SLI only (`sliId 2767` in this tenant, 52 live matched metrics at
creation). No SLO (rolling-percentage/error-budget) or alert layer yet --
the tenant's two existing SLI examples with a full SLO pipeline use
`attributeType` numeric codes and an `errorbudget` threshold whose exact
semantics differ between the two examples in ways that couldn't be fully
verified from the outside; see `bpa-demo-sli.sh`'s header comment for the
full reasoning. Treat the SLO layer as a follow-up once those semantics are
confirmed.
