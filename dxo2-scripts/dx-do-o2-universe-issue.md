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
