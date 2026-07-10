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
