# DX O2 Manual Configuration

Some DX O2 tenant configuration cannot be done via the `dx-do` CLI that
`dxo2-scripts/*.sh` uses (either because the CLI has no command for it, or
because the command that exists refuses in a way that has no workaround —
see each section below for the specific limitation). This file records
exactly what was configured by hand in the console, with the settings used
and the reasoning, so the steps are repeatable if the tenant is reset or a
different tenant user needs to redo them.

For everything that *can* be scripted, see `dxo2-scripts/README.md` and the
scripts themselves — this file is deliberately scoped to the console-only
exceptions.

---

## O2/Platform ("Services") Universe — initial creation (`bpa-demo-services-universe.sh`)

### Why this is manual

`dx-do o2-universe create` always produces an **unscoped** Universe (its
`tas` view filter is the bare `{"op": "ALL"}`, missing the fields a
`SERVICE`-scoped filter carries) — confirmed to **crash the console's own
edit UI** when opened in that state. There is no `o2-universe update` (the
command group is only `create, export, list, services`) to narrow the
filter afterward either, so a CLI-created Universe can't be fixed once
created — only avoided in the first place.

`bpa-demo-services-universe.sh create` deliberately does **not** fall back
to `o2-universe create` when its state file is missing/stale, since that
call is confirmed to always produce a console-breaking result. It fails
with these instructions instead.

### Steps taken

1. In the console: **New Universe** (Services/Platform Universe, not the
   APM Universe type).
2. Label: `"BPA Demo"`.
3. Scope **both** the `tas` view and the `nass` view to
   **Service → "BPA-Demo"** up front, in the creation wizard — this is the
   step that avoids the unscoped-shape crash entirely (the wizard always
   produces the `SERVICE`-scoped filter shape; only the raw API call skips
   it).
4. Note the resulting `viewId` (`VIEW###`) via
   `dx-do o2-universe list output.format=json` and record it in
   `dxo2-scripts/.state/bpa-demo-services-universe.env` as
   `UNIVERSE_ID=<id>` (git-ignored — this file only exists per-tenant).

Once created this way, `bpa-demo-services-universe.sh create`'s self-heal
check (`o2-universe export` on the recorded id) works normally for
`check`/`delete` too — only a fresh from-scratch `create` would hit the
crash-prone unscoped path again. The currently-tracked instance is
`VIEW618`.

---

## SLI: "BPA-Demo Frontend Response Time" (sliId 2767) — filter definition

### Why this is manual

`dxo2-scripts/bpa-demo-sli.sh` creates and self-heals this SLI, but the
`dx-do sli` command group has no `update` command — only `exclude-service`,
`export`, `import`, `include-service`, `list`. `sli import` refuses
unconditionally on a name collision (confirmed live, repeatedly, including
with the real existing `groupId` and `dry-run=false`):

```
Refusing to import: an SLI named 'BPA-Demo Frontend Response Time' already exists (sliId 2767).
```

So once the SLI exists, its filter can only be edited through the console's
own SLI editor.

### Background: why the filter needed fixing at all

The SLI's filter originally matched an exact agent identity
(`SuperDomain|bpa-demo-php-probe|php-probes|bpa-demo-infra-agent
(/usr/sbin/apache2)`) and the literal application name `BPA-Demo`. Both went
dead when `DEPLOYMENT_NAME`/`DEPLOYMENT_POSTFIX` was introduced (see
`CLAUDE.md`'s "Deployment identity" section) — the real identity became
`bpa-demo-k8s`/`bpa-demo-docker`, dropping the SLI to `totalMetrics: 0`.

### Console filter builder — not raw regex

The console's SLI filter editor takes structured conditions
(`field` + `condition` + `value`), not a raw regex string — this is why a
regex crafted for the raw NASS API (anchors, character classes) gets
rejected there. Each condition is one of:

| Condition | Meaning |
|---|---|
| `contains` | substring match |
| `starts_with` | prefix match |
| `ends_with` | suffix match |

### Steps taken (2026-07-10)

1. **First filter** (matches Source + Metric):
   - Source: **Contains** `php-probe`
   - Metric: **Ends with** `Average Response Time (ms)`
2. **Refine** (a second Source + Metric pair, applied via the editor's
   "refine" action):
   - Source: **Contains** `bpa-demo`
   - Metric: **Starts with** `Frontends|Apps|bpa-demo`

The intent of the two steps together: narrow to the PHP probe agent's own
frontend page-level response-time metric, excluding nested
`Called Backends|...SQL...` sub-metrics and any non-response-time attribute
(errors, concurrency, etc.) under the same prefix.

### Current status — NOT fully resolved yet

As exported via `dx-do sli export sliId=2767`, the persisted specifier is:

```json
{
  "op": "SPEC",
  "sourceNameSpecifier": {
    "op": "REGEX",
    "pattern": ".*bpa-demo.*",
    "ignoreCase": true
  },
  "attributeNameSpecifier": {
    "op": "AND",
    "specifiers": [
      {
        "op": "REGEX",
        "pattern": "Frontends\\|Apps\\|bpa-demo.*",
        "ignoreCase": true
      }
    ]
  }
}
```

**The "refine" step appears to have replaced the first filter's condition
rather than ANDing with it** — the persisted `attributeNameSpecifier` only
carries the *second* filter's `starts_with` pattern; the first filter's
`ends_with Average Response Time (ms)` restriction is not present anywhere
in the computed specifier. Confirmed via `dx-do nass query` against this
exact pattern: it matches five different metric types under the same
`Frontends|Apps|bpa-demo*` prefix, not just response time —

```
Average Response Time (ms)  117
Errors Per Interval          117
Responses Per Interval       117
Stall Count                  117
Concurrent Invocations        24
```

— averaging milliseconds together with raw counts, which is not a
meaningful "response time" value. `sli list` still reports `totalMetrics: 78`
(not the ~22 the user expected from the two filters together), consistent
with this diagnosis.

**Open item:** re-check whether both Source/Metric condition pairs need to
be entered as members of the *same* filter group (rather than a first
filter plus a separate "refine" action) for the console to AND them
together in the persisted specifier, rather than the second replacing the
first. Until resolved, the SLI's computed average is not restricted to the
response-time metric alone.

### Reusable template

`dxo2-scripts/templates/bpa-demo-response-time-sli.json` carries the last
known-good *importable* version of this SLI's specifier (for a fresh
`bpa-demo-sli.sh create` on a tenant where the SLI doesn't exist yet) — it
does not yet reflect the console-only edits above, since those can't be
pushed back through `sli import` (see "Why this is manual"). Once the
filter-group question above is resolved and the specifier is verified
correct, update that template file by hand to match, so a fresh SLI created
elsewhere starts from the corrected definition instead of the original
dead-literal one.

---

## SLIs: Error Rate + Client-Side Page Load Time (sliId 2768, 2769)

Two new SLIs, added 2026-07-10 as starting points for the user to fine-tune
in the console (the same reason `bpa-demo-response-time-sli.json` isn't kept
in sync with 2767's live edits — a script here would go stale the moment
console tuning starts):

- **`"BPA-Demo Frontend Error Rate"`** (`sliId 2768`) —
  `dxo2-scripts/templates/bpa-demo-error-rate-sli.json`. PHP probe agent,
  `Frontends|Apps|<app>:Errors Per Interval` (app-level aggregate).
  `sli_type: "Errors"`.
- **`"BPA-Demo Client-Side Page Load Time"`** (`sliId 2769`) —
  `dxo2-scripts/templates/bpa-demo-page-load-time-sli.json`. Browser Agent
  (`Experience Collector Host|DxC Agent|Logstash-APM-Plugin`),
  `Business Segment|BPA Demo|<url>:Average Page Load Time (ms)`. This is
  real client-side/End-User Experience data (measured in an actual
  visitor's browser), not the classic server-side APM path — it just
  happens to surface through the same NASS metric catalog as everything
  else. `sli_type: "Latency"`. Reads `totalMetrics: 0` right now — expected,
  since the traffic generator only drives plain HTTP requests with no real
  browser executing the BA snippet.

Both templates were verified against real data via `nass query` *before*
import this time, specifically to avoid repeating 2767's over-matching
mistake (see the section above). Imported cleanly as new resources — no
name collision, since `sli import`'s refusal only triggers on an existing
name.

**Landmine found while checking these:** `sli list`'s `totalMetrics` field
is not a match-count for the specifier. `sliId 2768` showed `totalMetrics:
78` despite matching exactly one real source (confirmed via `nass query`);
it appears to count aggregated time-series intervals computed over time,
not "how many sources matched" (`sliId 2767` also shows `78`, for an
unrelated reason — coincidence, not a shared bug). `sliId 2769` correctly
showed `0`, consistent with genuinely no data flowing yet. Use `nass query`
to verify a specifier's match set; don't infer correctness from
`totalMetrics`.

### SLO layer — modeled on 2767's now-confirmed-working structure, not yet pushed

`sli export sliId=2767` (re-pulled fresh at the user's request) showed the
user had since added a real, working `sloDefinition` to it via the console:
a 3-function pipeline —

1. `comparator`: is the raw SLI value `LE 200` (ms)? (5-minute window)
2. `percentage`: rolling 1-day % of windows that passed the comparator
3. `errorbudget`: is that rolling percentage `GE 98`%? (rolling 1-day)

This resolves this project's earlier "attributeType codes and errorbudget
units aren't documented" uncertainty (see `bpa-demo-sli.sh`'s "Why no SLO
yet" header comment) — we now have a real, confirmed-working example to
copy exactly (`attributeType: 258` for the threshold output, `4097` for the
percentage, `2` for the error budget) instead of guessing.

Added the identical 3-function structure to both new templates, with
thresholds matching this project's own already-measured alert baselines
(`bpa-demo-agent-alerts.sh`'s WARNING thresholds, not guessed):

- **Error Rate**: comparator `LE 2` (errors/interval) — matches
  `ALERT_WARNING[php-error-rate]=2`.
- **Page Load Time**: comparator `LE 300` (ms) — matches
  `ALERT_WARNING[browser-page-load]=300`.
- Both: error budget `GE 98`%, rolling 1 day — same as 2767.

**Confirmed via a `sli import` dry-run that this can't be pushed to the
live 2768/2769 either** — same collision refusal as the filter fix, since
both SLIs now exist. Adding the SLO layer to the live resources needs the
console's own SLO editor, using the three values above. Worth checking
first whether that editor is also a structured builder (like the SLI
filter one) rather than a raw-JSON paste.
