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
