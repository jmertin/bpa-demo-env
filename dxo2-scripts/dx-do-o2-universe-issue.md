# dx-do issue: `o2-universe create` produces Universes that are inaccessible in the DX O2 console

## Summary

`dx-do o2-universe create` only accepts a `name=` parameter. There is no
CLI command, on creation or afterward, to populate the Service-scoped
filter (`views[].filter.serviceFilter.values` / the `tas` view's
`filter.filter.values`). A Universe created this way defaults to an
unscoped `{"op": "ALL"}` filter matching the entire tenant -- and, more
importantly, appears to become permanently inaccessible via the DX O2
console's own Universe detail/edit page, even though the same Universe
is visible and partially manageable (an enable/disable toggle works)
from the console's list view.

## Environment

- `dx-do` v6.3.5 (node v24.3.0, linux-x64)
- Universe type: **O2/Platform Universe** (`dx-do o2-universe`), referred
  to as "Services Universe" in the console -- distinct from the older
  **APM Universe** type (`dx-do apm-universe`), which does not have this
  problem (see "Related, working case" below).

## Steps to reproduce

1. `dx-do o2-universe create name="<any label>"`
2. Note the created universe's `viewId` -- `create`'s own output never
   prints it; cross-reference by label via `o2-universe list
   output.format=json` (redirect to a file, not a pipe -- large tenants
   can exceed dx-do's ~64KB pipe-truncation limit on list output).
3. In the DX O2 console, navigate to wherever Services Universes are
   listed. The new universe IS listed, and its enable/disable toggle
   works from that list.
4. Navigate into the universe's detail/edit page (in this session's
   case, a URL of the shape
   `https://<tenant-gateway>/<tenant-id>/digital-oi/settings/universes/universe/<viewId>`).
5. Observe: HTTP 404 Not Found. The console never renders the detail/edit
   page for this universe.

## Expected behavior

Either:
- the console's detail/edit page opens for any Universe regardless of
  how it was created or how its filter is currently scoped, so the user
  can add a Service scope after the fact; or
- `dx-do o2-universe` exposes a command to set an initial Service scope
  (at `create` time or via a separate `update`/`add-service` command),
  so a Universe is never left in this unscoped, unopenable state to
  begin with.

## Actual behavior

- The created Universe has, for its `tas` view,
  `filter.filter.op = "ALL"`, and for its `nass` view,
  `filter.serviceFilter = {"op": "SERVICE", "values": []}` -- i.e. it
  matches the entire tenant's topology, not any specific scope.
- The console's detail/edit page 404s for this universe specifically.
- List-level actions (the enable/disable toggle) work fine on the same
  universe -- the console does track/recognize it; only the dedicated
  detail/edit route fails.
- No other console entry point (context menu, alternate action button)
  was found that could configure the Service scope instead of the
  404ing detail page.

## Root cause analysis

Compared the broken universe's raw definition (via `dx-do o2-universe
export universeViewId=<id>`) against an existing, console-editable
Universe on the same tenant with an otherwise identical shape (label
`CRepo`, predates this session, known to be editable via the console).
The only meaningful structural difference:

```json
// Broken universe -- created via `o2-universe create`, unscoped, 404s in console
"tas":  { "filter": { "filter": { "op": "ALL" } } }
"nass": { "filter": { "serviceFilter": { "op": "SERVICE", "values": [] } } }
```

```json
// Working universe -- pre-existing, console-editable
"tas":  { "filter": { "filter": {
            "op": "SERVICE",
            "values": ["CRepo", "PHP Probe", "VCenter", "DB Backend", "Frontend", "BPA Monitor"],
            "includeServiceHierarchy": true,
            "excludeSubServices": false
          } } }
"nass": { "filter": { "serviceFilter": {
            "op": "SERVICE",
            "values": ["CRepo", "PHP Probe", "VCenter", "DB Backend", "Frontend", "BPA Monitor"]
          } } }
```

Every other field (`access`, `attributes`, top-level `views[]` shape,
permission arrays) is structurally identical between the two
universes. This strongly suggests the console's detail/edit page
requires a non-empty, Service-scoped `serviceFilter.values` array to
render -- an unscoped (`"op": "ALL"`) or empty-`values` Universe breaks
that specific route.

This produces a chicken-and-egg problem: `o2-universe` has no CLI
command to populate `serviceFilter.values` after creation (confirmed --
the entire command group is `create, export, list, services`; `create`
silently ignores any parameter beyond `name=`, logged as `ignoring extra
args`), and the console's own edit page is the only place to add a
Service scope -- but that page 404s *before* a Service scope exists.
There is currently no way, CLI or console, to fix an
`o2-universe`-CLI-created universe's scope once it's created.

## Related, working case: `dx-do apm-universe`

The older APM Universe type (`dx-do apm-universe create` /
`add-metric-source` / ...) does not have this specific problem --
its detail page is reachable and its scope is adjustable via
`add-metric-source` (though that command has its own, unrelated
limitation: it can only populate the `nass` view's agent-list filter,
not the `tas` view's legacy `{vertices, items, joins}` filter, which is
what actually drives the console's Topology/Triage graph view -- a
separate finding, written up in this repo's `BUGS` file).

## Impact

Any Universe created via `dx-do o2-universe create` is, in its default
state:

1. Functionally useless for scoping purposes -- it matches the entire
   tenant, not the intended application/service.
2. Permanently stuck that way -- there is no supported path, CLI or
   console, to narrow its scope after creation.

## Suggested fixes (any one would resolve this)

1. Add an `update` / `add-service` / `set-filter` command to
   `dx-do o2-universe` that can set `views[].filter.serviceFilter.values`
   (and/or the `tas` view's `filter.filter.values`) after creation.
2. Allow `o2-universe create` to accept a `services=<name1>,<name2>,...`
   (or similarly-shaped) parameter to populate the Service scope at
   creation time, so the unscoped intermediate state is never reached.
3. Fix the console's detail/edit page to not 404 on a Universe with an
   empty/`ALL` filter -- ideally rendering an empty-state "add a service
   to scope this universe" UI instead of failing to route at all.

## Workaround

None found. The only mitigations confirmed during this investigation:

- `dx-do apm-universe delete id=<id> name=<label>` can delete an
  `o2-universe`'s id despite being a different CLI command group --
  this is the only way to remove a broken/unscoped universe, since
  `o2-universe` itself has no `delete` command at all.
- Recreating the universe through the console's own "create universe"
  flow (rather than via `dx-do`), if that flow requires picking a
  Service scope up front, would avoid the broken state entirely -- not
  yet confirmed to work, since the console-side creation flow wasn't
  exercised in this investigation.

## Reproduction artifacts

This tenant currently has a live example of the broken state:
`dxo2-scripts/bpa-demo-services-universe.sh` in this repo creates it
(label `"BPA Demo universe"`, an O2 Universe) as part of a demo-app
alerting/observability setup. See that script and
`dxo2-scripts/README.md` for the full context this issue was found in.

## Update 2026-07-07: independently reconfirmed, workaround found

The user hit the same root cause again, this time reporting it as the
console **crashing** on open rather than **404**ing (both against the
same underlying unscoped-filter state -- plausibly two different failure
modes in the console's edit-page code for the same missing-fields
condition, or the same bug described loosely). Confirmed by diffing the
crashing Universe (`viewId VIEW617`, created by
`bpa-demo-services-universe.sh` via `o2-universe create`) against a
Universe the user created manually through the console's own wizard
(`viewId VIEW618`, label `"BPA Demo"`, scoped to the existing `"BPA-Demo"`
Service). The diff is exactly the shape difference already documented
above (`tas` filter `{"op": "ALL"}` vs. the full `SERVICE`-shaped filter;
`nass` `serviceFilter.values: []` vs. `["BPA-Demo"]`) -- same bug, same
fix.

**Workaround confirmed working**: creating the Universe through the
console's own wizard (pick a Service scope up front) produces a
Universe that opens/edits fine in the console -- this resolves the
"Related, working case" question left open in the Workaround section
above. `VIEW617` was deleted (`dx-do apm-universe delete id=VIEW617
name="BPA Demo universe"`, the cross-group delete workaround already
documented); `bpa-demo-services-universe.sh` now points at `VIEW618` and
no longer attempts `o2-universe create` as a fallback -- it fails with
instructions for manual console creation instead, since that call is now
confirmed to always produce a console-breaking Universe. See that
script's header comment for the current state.

## Update 2026-07-07 (2): root cause confirmed by the developer fixing it

Per the developer working the fix: the console's data model for Universes
changed (to require the `SERVICE`-scoped shape), **but the change was
never enforced at the API level** -- `o2-universe create` (and, by
extension, `dx-do`) still accepts and produces the old unscoped shape
without complaint. This matches the empirical finding above exactly: it's
not that the console is buggy in isolation, it's a model/API version
mismatch -- the write path (API) still speaks the old schema, the read
path (console edit UI) only speaks the new one.

Practical implication once the API-level fix ships: `o2-universe create`
should start either rejecting scope-less creation or producing a
correctly-`SERVICE`-scoped Universe by default. Either way,
`bpa-demo-services-universe.sh`'s current refusal-with-manual-instructions
behavior (see above) should be revisited then -- it may become safe to
let `create` call `o2-universe create` again. Re-test with a fresh,
disposable Universe (not `VIEW618`) before restoring that fallback, and
watch for a signature change in `o2-universe create`'s required
parameters (a `services=`/scope-shaped param finally being honored rather
than silently ignored, per the "ignoring extra args" behavior documented
above).

## Resolved 2026-08-24: `o2-universe` replaced outright by `service-universe`

The user reported the maintainer had shipped an API-level fix and asked
for this script to be re-checked. `o2-universe` no longer appears in
`dx-do`'s command-group list at all -- it's been replaced by
`service-universe`, a full CRUD surface (`create`, `update`, `delete`,
`get`, `list`, `export`, `add-access`, `remove-access`) that resolves
every issue documented above:

1. **Scoping at creation, confirmed live.** `service-universe create
   label="..." serviceNames="BPA-Demo" dry-run=false` produces exactly
   the correctly-`SERVICE`-scoped shape this issue asked for --
   verified via a `dry-run=true` preview (the default) before ever
   touching the tenant for real:
   ```json
   "tas":  { "filter": { "filter": {
               "op": "SERVICE", "values": ["BPA-Demo"],
               "includeServiceHierarchy": true, "excludeSubServices": false
             } } }
   "nass": { "filter": { "serviceFilter": { "op": "SERVICE", "values": ["BPA-Demo"] } } }
   ```
   Identical in shape to the console-wizard-created `VIEW618`/`VIEW621`
   examples referenced throughout this issue.
2. **`update` now exists** (`viewId=`, `label=`, `description=`,
   `serviceNames=`, `inactive=`, all optional except `viewId=`, dry-run
   by default) -- a Universe's scope can be corrected after creation
   without recreating it.
3. **`delete` now exists natively** (`viewId=` + `label=` required to
   match, as a typo-proof confirmation -- same pattern as `dashboard
   folder-delete`), so the `apm-universe delete`-on-an-o2-universe-id
   cross-group workaround this issue's Workaround section documented is
   no longer needed.
4. **Consistent `viewId=` naming** across every subcommand -- the old
   `create`-uses-`name=`-but-`export`-uses-`universeViewId=`
   inconsistency this issue implicitly worked around is gone.

`bpa-demo-services-universe.sh` was rewritten to use `service-universe`
throughout, self-heals a drifted `serviceNames` filter via `update`
instead of refusing, and its `create` fallback (disabled since the
2026-07-07 workaround) is restored. The live tenant's existing
`VIEW618`-successor Universe (`VIEW621`, label "BPA Demo service
universe" -- `VIEW618` itself no longer exists; not investigated when or
why) was adopted as the tracked instance rather than creating a
duplicate, since `service-universe get` confirmed it was already
correctly `SERVICE`-scoped. See that script's own header comment and
`CLAUDE.md`'s dxo2-scripts section for the live-verification detail.
This issue is closed -- no outstanding action for the `dx-do` maintainer.
