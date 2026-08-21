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
