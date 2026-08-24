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

## O2/Platform ("Services") Universe — superseded, no longer a console-only exception (2026-08-24)

Historical note: this section used to document a required manual console
step (create the first Universe by hand through the wizard) because
`dx-do o2-universe create` always produced an **unscoped** Universe
(its `tas` view filter was the bare `{"op": "ALL"}`, missing the fields
a `SERVICE`-scoped filter carries) — confirmed to **crash the console's
own edit UI** when opened in that state, with no `o2-universe update`
command to narrow the filter afterward either. It no longer applies.

The `dx-do` maintainer replaced `o2-universe` outright with
`service-universe`, whose `create`/`update` both take `serviceNames=`
and produce a correctly `SERVICE`-scoped filter from the start —
verified live via a `dry-run=true` preview before ever touching the
tenant for real. `dxo2-scripts/bpa-demo-services-universe.sh` was
rewritten to use it and its `create` fallback (creating a fresh,
correctly-scoped Universe with no console step) was restored. See that
script's own header comment, `dxo2-scripts/dx-do-o2-universe-issue.md`'s
2026-08-24 resolution update, and `CLAUDE.md`'s dxo2-scripts section for
the full history. The tenant's previously-tracked `VIEW618` no longer
exists (not investigated why); the script now tracks `VIEW621`, an
already-correctly-scoped Universe adopted rather than duplicated.

---

## SLI/SLO — superseded, no longer a console-only exception (2026-08-21)

Historical note: this section used to document manual console workarounds
for `sliId` 2767/2768/2769 (the old `dx-do` v6.4.0 CLI's `sli` command
group had no `update` and `import` refused on any name collision, so a
live SLI's filter or SLO could only be edited by hand in the console). It
no longer applies. Investigating a user question about the app's
front-controller revert surfaced that the tenant's entire SLI subsystem
had been reset — `sli list-groups` returned zero groups tenant-wide, and
`sli export` on both a project id and the tenant's own unrelated
pre-existing example returned an identical null response; see CLAUDE.md's
dxo2-scripts section and TOBEDONE.md's SLI/SLO section for the full
finding. At the user's request, SLI/SLO monitoring was rebuilt from
scratch under `dx-do` v7.2.1's structurally different `sli` command
surface (`create-group`/`add-slo`/`add-alert`/`set-group-filter`, all
real, working, idempotent-preview commands — see `dx-do help slis`),
which needs no console editing at all: `dxo2-scripts/bpa-demo-sli.sh`
creates and self-heals all three SLI groups (Response Time, Error Rate,
Client-Side Page Load Time) entirely via CLI, including their SLOs and —
new, not present on any of the original three — an alert on each SLO's
rolling percentage.

Two technical findings from the old console-based era are still true and
worth keeping as institutional knowledge, in case a future console-only
exception ever needs them again:

- The console's SLI filter editor uses structured conditions (`contains`/
  `starts_with`/`ends_with`), not raw regex — a pattern crafted for the
  raw NASS API (anchors, character classes) is rejected there.
- The editor's two-step "filter then refine" workflow was confirmed (via
  `nass query`) to **replace** the first filter's condition rather than
  AND it with the second, silently over-matching multiple incompatible
  metric types under one filter. Never resolved through the console;
  moot now that the CLI path builds a correctly-ANDed structured filter
  directly (`groupFilter.<field>.<condition>` atoms — same field ORs,
  different fields AND, confirmed working via `sli filter-test`).
- `sli list`'s old `totalMetrics` field (superseded by `sli list-groups`'
  same-named field in the new model) was never a match-count for the
  specifier — it appears to count computed time-series intervals, not
  "how many sources matched." Verify specifier scope with `nass query`/
  `sli filter-test`, not `totalMetrics`.

See `dxo2-scripts/bpa-demo-sli.sh`'s own header comment for the new
model's two fresh landmines found while rebuilding (a `regex` filter
condition silently broken by a trailing `$` anchor; the PHP probe's
app-level metric aggregates not being visible in the SLI subsystem's
service-scoped view).
