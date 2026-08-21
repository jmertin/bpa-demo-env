# To Be Done — Known Shortcomings

A snapshot, as of 2026-07-10, of things that are known to be broken,
incomplete, or unverified in this project. Unlike `CHANGELOG` (a history of
what changed) or `DX-O2_MANUAL_CONFIGURATION.md` (steps that *were*
completed by hand), this file tracks what's still **outstanding** — pick
from here for next steps. Update it as items get resolved; remove an entry
once it's actually fixed and verified, don't just mark it done in place.

---

## PHP application

### Browser-agent auto-injection reverted — does not currently work at all

At the user's request, the per-page-wrapper-file workaround for the PHP
probe's Frontend-start/SCRIPT_NAME gating bug was fully reverted on
2026-08-19: the 11 wrapper files (`app/src/shop.php`, `basket.php`, etc.)
are deleted, and — at the user's further request the same day — `vhost.conf`'s
`RewriteRule`/root-redirect were removed entirely rather than just
repointed, so there is now no clean-URL rewriting at all. Every page is
reached as `index.php?page=<slug>`; every internal link, form action, and
redirect across the app (`templates/layout.php`, every `pages/*.php` file,
and `traffic-generator/generator.py`) was updated to match. See
`bug_php_probe.md` for the original diagnosis and `CLAUDE.md`'s "Front
controller" / "PHP probe injection" sections for what changed.

This is a deliberate, intentional state, not a regression to fix — but it
does mean the browser-agent snippet no longer injects into any page
response, under any traffic source (synthetic or real browser). This
supersedes the "Browser Agent RUM data sits at 0" coverage-gap item below,
which assumed injection worked and only synthetic traffic was the gap.
Reapplying the workaround (see `bug_php_probe.md`'s "Fix — Per-Page
Wrapper Files" section) is the way back if browser-agent RUM data is
needed again.

**Resolved 2026-08-21:** the PHP probe's separate `Frontends|Apps|<app>|URLs|<url>`
response-time/error-rate metrics do NOT depend on the same "Frontend
start" gate as BA injection — confirmed live via `nass query-metric-data`
that `Frontends|Apps|bpa-demo-docker|URLs|/index.php:Average Response Time (ms)`
has fresh, actively-updating data post-revert. The real, confirmed change:
the URL segment comes from `SCRIPT_NAME` (not `REQUEST_URI`), so every
page now collapses into one shared `/index.php` bucket instead of
distinct per-page ones — real per-business-page granularity is gone, but
the metric itself is alive. See CLAUDE.md's "PHP probe injection" section
for the full finding.

### `dxo2-scripts/` PHP-tier metric groupings/content queries broke separately — fixed 2026-08-21

Found while investigating the item above (unrelated to the front-controller
revert itself): `bpa-demo-agent-alerts.sh`'s five PHP-tier metric groupings
and `bpa-demo-service.sh`'s PHP-probe content group all hardcoded a
trailing `(/usr/sbin/apache2)` on the agent identity, which stopped
appearing once the 2026-07-15 UnknownAgent fix disabled the IA's
remote-agent auto-naming (the thing that had been appending the running
process's path). All had zero live matches. Fixed by making the suffix
optional in both scripts plus the response-time/error-rate SLI templates
and the agent-health dashboard template; re-ran each script's self-heal
and confirmed live matches returned via `metricgrouping list-metrics` and
a re-exported dashboard. The two old SLI templates were superseded
entirely by the 2026-08-21 SLI/SLO rebuild below (raw CLI flags now, no
template files at all) rather than patched in place.

### Resolved 2026-08-21 — `bpa-demo-universe.sh`'s own, separate stale-identity bug fixed

Found while grepping for the `(/usr/sbin/apache2)` literal above, but a
genuinely different root cause: this script's `METRIC_SOURCES` array
still hardcoded the *pre-`DEPLOYMENT_NAME`/`DEPLOYMENT_POSTFIX`* literal
identities (`bpa-demo-host`, `bpa-demo-php-probe`,
`bpa-demo-infra-agent(/usr/sbin/apache2)`) as `EXACT` metric sources —
confirmed via `apm-universe export` that neither had ever actually been
added to the live Universe; this script was simply missed in the
2026-07-10 batch fix every other `dxo2-scripts/` file got. Fixed by
switching both to wildcarded `REGEX` patterns (reusing the ones already
fixed in `bpa-demo-agent-alerts.sh`/`bpa-demo-service.sh`). Also fixed a
second bug found live while verifying: the self-heal's presence check
didn't account for JSON backslash-escaping and kept re-adding duplicate
`REGEX` specifiers on every re-run — fixed by escaping before the check.
`apm-universe` has no "remove metric source" command, so the pre-existing
stale `EXACT` entries and two duplicate `REGEX` pairs added during
testing remain in the live Universe — harmless (the specifier list is
`OR`'d) but not cleaned up.

---

## Agents / identity

### Stale metric-catalog entries from the pre-identity-fix era

The NASS metric catalog still carries dead historical sources
(`bpa-demo-host`, `bpa-demo-infra-agent%1`, `bpa-demo-php-probe`, and the
generic `UnknownAgent` fallback) from before `DEPLOYMENT_NAME`/
`DEPLOYMENT_POSTFIX` existed. Harmless — wildcarded patterns skip over them
— but nobody has confirmed whether/when the tenant naturally ages these
out, or whether they need manual pruning.

---

## SLI / SLO

### Resolved 2026-08-21 — SLI/SLO monitoring rebuilt from scratch under the new SLI-group model

The tenant's entire SLI subsystem was found to have been reset —
`sliId` 873/2767/2768/2769 (the old raw-`sli export`/`import`-era
resources) were all gone: `sli list-groups` returned `[]` tenant-wide,
`sli export` on both a project id and the tenant's own unrelated
pre-existing example returned an identical null response, and the old
SLI-derived metrics had vanished from the catalog entirely. The
underlying `BPA-Demo` service and its metrics were unaffected — this was
specifically an SLI-layer reset (cause not determined: a genuine SaaS-side
subsystem migration, given how different the new model looks, or
something tenant-specific).

At the user's request, rebuilt fresh under `dx-do` v7.2.1's real,
structurally different `sli` command surface (`create-group`/`add-slo`/
`add-alert`/`set-group-filter`, all dry-run-by-default write commands —
see `dx-do help slis`). `dxo2-scripts/bpa-demo-sli.sh` was rewritten from
scratch (the old script and its three now-schema-incompatible JSON
templates deleted) to create and self-heal all three SLI groups purely
via CLI flags, no files needed:

| SLI group | sliGroupId | SLO objective | Alert |
|---|---|---|---|
| BPA-Demo Frontend Response Time | 2958 | `LE 200`ms, 98% target, rolling 1-day | caution <98%, danger <90% of SLO percentage |
| BPA-Demo Frontend Error Rate | 2959 | `LE 2`, 98% target, rolling 1-day | same |
| BPA-Demo Client-Side Page Load Time | 2960 | `LE 300`ms, 98% target, rolling 1-day | same |

(Corrected 2026-08-21, found during an unrelated doc-verification pass: the
original ids recorded here were 2955/2956/2957. The live tenant's
`.state/bpa-demo-sli.env` and `sli list-groups` show 2958/2959/2960 as the
three groups that actually exist today -- the originals are gone, not
duplicated. See `bpa-demo-sli.sh`'s own header comment and `CLAUDE.md`'s
dxo2-scripts section for the full finding.)

This closes out every previously-open item in this section: the SLI
2767 filter-mixing bug (the new CLI's structured `groupFilter.*` atoms
AND correctly across fields, confirmed via `sli filter-test` — the old
console "filter then refine" replace-not-AND bug doesn't reproduce), the
SLO layer never reaching 2768/2769's live resources (now built directly
via `sli add-slo`), and no alert ever being wired to an SLO (now built via
`sli add-alert`, targeting the SLO's rolling percentage — an improvement
over the original three SLIs, none of which ever had this). See
`bpa-demo-sli.sh`'s own header comment for two new landmines found while
building this (a `regex` filter condition silently broken by a trailing
`$` anchor; the PHP probe's app-level metric aggregates not being visible
in the SLI subsystem's service-scoped view) and `CLAUDE.md`'s
dxo2-scripts section / `DX-O2_MANUAL_CONFIGURATION.md` for the full
history.

The Client-Side Page Load Time group currently registers `sliStatusCode
5` ("no metrics matching") — not a new problem, browser-agent
auto-injection is still reverted (see the "PHP application" section
above), so there's no live client-side data at all right now; it lights
up on its own if that ever resumes, same as the original SLI 2769's own
lifelong `totalMetrics: 0` before the reset.

---

## Dashboards

### PHP-probe frontend panels can't show Kubernetes data until `UnknownAgent` is fixed

The "BPA-Demo · Agent Health" dashboard's PHP-Probe panels only match
sources whose agent segment starts with `bpa-demo-` — by design, to avoid
pulling in unrelated tenants' data under the generic `UnknownAgent` name.
Until the fix above is confirmed, selecting "k8s" in the Deployment
dropdown will show empty PHP-Probe panels even though the underlying data
is real (just misfiled under `UnknownAgent`).

### Network-time comparison is two lines, not a computed difference

The "BPA Plugin: Response Time vs Backend Server Time" panel ships as two
overlaid lines (visually approximating network + overhead time) rather
than a true `Response Time − Backend Server Time` computed field via
Grafana's `calculateField` transform. Skipped because this dx-do build has
no `dashboard-render`, so the AIOps NASS datasource's actual output field
names couldn't be visually confirmed before shipping — an unverified
transform risked silently doing nothing. Worth revisiting once
`dashboard-render` or console access is available to check the real field
names in the panel editor.

### BPA WebServer Plugin's own cardinality leak via the HTML `<title>` tag

Separate from the (already-fixed) `X-Page-ID` numeric-order-id leak: the
BPA WebServer Plugin's own "Business Segment" label concatenates the
page's `<title>` tag content with the `X-Page-ID`. The order-confirmation
page's title still contains the order number (e.g.
`BPA-Demo – Order #294 Confirmed`), so the plugin produces one distinct
series per completed order at its own tier —
`Business Segment|[BPA Demo]<ip>:<port>|BPA-Demo – Order #294 Confirmed-ORDER-CONFIRM-SUCCESS`
— the same cardinality-explosion shape as the original bug, just via a
different label. Confirmed live via `nass query` (2026-07-09); not fixed.
Likely needs a tenant-side capture-rule change (the app's own `<title>`
content is legitimate, not a code bug this time).

---

## Alerts / Management Module

### `empty_basket` and `locked` use cases have no observable APM signal

Neither returns an HTTP error status, and BPA's payload metrics only
expose request/response size in bytes, not extracted field values — so
there's nothing to threshold-alert on today. Catching `empty_basket` needs
the `X-Basket-Total` response header (already emitted by `checkout.php`)
exposed as a captured BPA attribute — this was being configured
tenant-side as of the last check but never appeared on live checkout
transactions even after a `dxo2` restart and repeated fresh traffic.
Revisit once that capture rule is confirmed working, then extend
`bpa-demo-management-module.sh`/`bpa-demo-agent-alerts.sh` to match.

---

## Universes / Topology

### APM Universe Topology view only shows the PHP probe, not the other 3 entities

`bpa-demo-universe.sh`'s "BPA Demo universe" scopes 3 metric sources
correctly (NASS count confirms it), but the console's Triage/Topology view
is driven by a separate, legacy-shaped `views.tas` filter that
`apm-universe add-metric-source` never touches — it only ever surfaces the
`bpa-demo-php-probe` generic frontend. Confirmed via direct TAS query that
scoping `views.tas` by Service membership (`BPA-Demo`) *would* correctly
show all 4 entities. No CLI command exists to set this filter
(`apm-universe` has no `update`; `o2-universe` can't set a custom filter at
create time or after). **Fix requires a manual console step** — exact menu
path not confirmed yet (no console access when this was investigated). See
`BUGS` for the full writeup.

### O2/Platform ("Services") Universe — CLI-created instances are permanently broken

Documented as a Broadcom/dx-do product limitation, not something to fix in
this repo: `o2-universe create` always produces an unscoped Universe whose
console detail/edit page 404s, with no CLI path to add a scope after the
fact. Worked around for our own Universe by creating it through the
console's wizard instead (`VIEW618`, scoped to `BPA-Demo` from the start)
— but this is a workaround, not a fix, and anyone else creating an
o2-universe via `dx-do` will hit the same dead end. Full reproduction +
suggested fixes for the dx-do maintainer:
`dxo2-scripts/dx-do-o2-universe-issue.md`.

---

## AIOps

### Situations never form from BPA-Demo's alarms

Confirmed real alarms fire correctly — both a same-tier cluster (triggered
`trouble` use case live) and a genuine two-tier cluster (stopped `mariadb`
for ~2 minutes, confirmed both the Infrastructure Agent and PHP probe
tiers alarmed within ~90s of each other) — but `dx-do situation query`
returned `[]` across ~25 minutes of combined polling either way. No fix
identified from the CLI alone. Needs the console's own Situations view
checked directly, or confirmation from Broadcom on what enables Situation
correlation for a tenant this size. See `BUGS` for the full test writeup.

---

## Coverage gaps (by design, not bugs — listed for completeness)

- **Browser Agent RUM data sits at 0** under the traffic generator alone
  (`traffic-generator/generator.py` drives plain HTTP, no real browser
  executes the BA JavaScript snippet). Page Load Time SLI (`2769`) and the
  dashboard's Browser Agent page-level panels won't show real numbers
  without either a human clicking through the app or real browser
  automation (e.g. Playwright/Selenium) added to the traffic generator.
- **Resource-level Browser Agent metrics** (Time To First Byte, Resource
  Load Time) *do* have real historical data from earlier manual testing —
  only the page-level aggregates (Page Load Time, Page Hits) are actually
  gapped.
