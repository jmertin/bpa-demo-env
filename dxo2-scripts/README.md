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
