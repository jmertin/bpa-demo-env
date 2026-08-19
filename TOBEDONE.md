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

**Also open, not investigated:** whether the PHP probe's separate
`Frontends|Apps|<app>|URLs|<url>` response-time/error-rate metrics — the
ones `dxo2-scripts/`'s alerts and SLIs are built on — depend on the same
"Frontend start" gate as BA injection. All of this project's `nass query`
verification of those metrics happened while the wrapper-file workaround
was active (`SCRIPT_NAME` was never `/index.php` during that testing), so
whether they still report per-URL data now is unverified. Check this
first if per-URL alerts/SLIs go quiet after redeploying past this revert.

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

### SLI 2767 ("BPA-Demo Frontend Response Time") filter still not fully correct

The console's "filter then refine" approach appears to **replace** the
first filter's condition rather than AND it with the second — the live
specifier only carries the second filter's pattern
(`Frontends\|Apps\|bpa-demo.*`), with no restriction to
`Average Response Time (ms)` specifically. Confirmed via `nass query`: it
still averages in `Errors Per Interval`, `Responses Per Interval`,
`Stall Count`, and `Concurrent Invocations` alongside the real response-time
values — mixing incompatible units into one "average."

**Open question:** does the console require both Source/Metric condition
pairs to live in the *same* filter group to be ANDed, rather than a filter
+ a separate "refine" action? See `DX-O2_MANUAL_CONFIGURATION.md`'s SLI
section for the full detail. Needs another console pass to actually
resolve, not just document.

### SLO layer not pushed to any of the 3 SLIs' live resources

`sliId 2767` has a real, working SLO (comparator → rolling percentage →
error budget) configured by hand in the console. The identical structure
was added to the **templates** for `sliId 2768` (Error Rate) and `2769`
(Page Load Time), with thresholds pulled from already-measured alert
baselines — but confirmed via `sli import ... dry-run=true` that this
cannot be pushed to the live resources via CLI (same name-collision
refusal as the filter fix). Needs manual console entry for both — see
`DX-O2_MANUAL_CONFIGURATION.md` for the exact threshold values
(`LE 2` errors/interval, `LE 300`ms page load, both `GE 98%` error budget).

### No alert wired to any SLO's error budget

The tenant's own richest example (`sliId 873`, "CEmperf DB Errors") chains
all the way to an alert on the error-budget breach. None of our 3 SLIs have
that last step yet, even once/if the SLO layer above gets applied.

### SLI/SLO scripts are one-off imports, not self-healing

`bpa-demo-sli.sh` only manages `sliId 2767`. The two newer SLIs
(2768/2769) were created via one-off `sli import` calls, not a proper
create/check/delete script — deliberately, since the user is still
fine-tuning both in the console and a script would go stale immediately
(the same trap the *first* SLI's own template fell into). Worth
formalizing into a script once the filters/SLOs are settled, if repeatable
creation on a fresh tenant is ever needed.

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
