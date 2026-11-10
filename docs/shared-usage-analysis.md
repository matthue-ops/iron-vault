# Shared usage and offline pricing analysis

This batch preserves existing entry, account-status, renewal, payment, wallet, pricing, consent and subscription-approval behavior. It does not include a video tutorial, automatic member tiers or an owner price-proposal/acceptance workflow.

## Manual rollout

1. Confirm migrations through **052** are installed. Do not rerun earlier migrations blindly.
2. Manually execute the entire `supabase/manual/shared_gym_usage.sql` once in Supabase SQL Editor. It is identical to migration **053**, runs transactionally, and rejects duplicate installation. No live SQL was executed by the agent.
3. Deploy this frontend, then reload open windows. Until 053 is installed, usage displays unavailable with a retry button; existing subscription actions continue working.

The user explicitly approved the read-only database function after its scope was explained. It adds one STABLE security-definer RPC, `iv_gym_usage(text)`, with empty search path and authenticated-only execution. Existing role helpers verify enabled Provider or registered gym owner. Owners are scoped to their own gym; staff, members and anonymous callers are denied. No existing function is replaced, no table/index is added, and no records are inserted, updated or deleted.

## Shared usage

The gym owner's existing bottom subscription card becomes Subscription & Usage, retaining its plan, dates, status and subscription action. The four top operational statistics and their calculations remain unchanged. Staff keep their existing subscription visibility and receive no new usage permission.

Each Provider Gym Profile shows the same aggregate-source summary. The API returns only tenant ID, timestamp, explicit Philippine dates and counts; no member names, IDs, financial entries or raw attendance rows.

- Last **30 complete Philippine calendar days**, excluding today.
- Unique visitors = distinct recorded member IDs in that period.
- Check-ins = all saved attendance entries, including QR, manual and any other saved method.
- The preceding 30 complete days for comparison.
- Three completed calendar months for trend details, with exact start/end dates. No misleading monthly percentage comparison across unequal month lengths.

Both views display snapshot time. Calls at different times can differ if historical records were added or corrected between snapshots. Counts are not historical active-member counts and do not measure bandwidth. They never set a price.

Usage loads asynchronously when the owner card first receives an authenticated context or the provider opens a gym profile. Refresh usage is explicit; no polling/job is added. A read failure affects only the usage section. Identity/gym changes, sign-out and closing/hiding the Provider profile discard late responses and clear the usage detail dialog. Queries are bounded to the relevant gym and recent date range; the existing attendance table is scanned once per requested summary, with materialized aggregate input. No production query-plan or load test was run.

## Analysis menu and page

Provider → Subscription → **Analysis** opens `/gym/analysis.html` in a separate tab/window with no opener. The navigation entry remains in the provider menu. The analysis file itself is a blank, self-contained offline utility: anyone possessing its HTML can run it, but it has no API credentials, live data or database connection and confers no provider authority. This is not a new authenticated database-viewing page.

It reads current Iron Vault Overview XLSX/label-value CSV summaries; retains original report and snapshot dates; preserves genuine zeros and missing values; queues imports; checks duplicates; excludes overlapping periods until resolved; and separates demo data. No individual financial/attendance/activity rows or member names are retained. Legacy detail-only exports without Overview are rejected rather than guessed.

Standard price and each gym's current rate are manually entered references. Suggested price = standard price minus the entered discount. A manual override is optional. Calculations are PHP per 30 days. Actual notice eligibility, owner acceptance, payment and renewal remain outside the tool.

Save Project JSON downloads an editable version-2 project containing private notes. Export PDF uses the browser's **Save as PDF** dialog: Gym copy excludes private notes/cost contributions, Provider copy includes them. Base filenames match; PDF audience suffixes distinguish copies. Source metadata, manually corrected fields, assumptions and included trend evidence are preserved in the print report.

An Offline copy link downloads the original static HTML. All libraries are embedded (JSZip 3.10.1, MIT license included); no CDN, analytics, API connection or automatic browser storage is used. Projects stay in memory until exported. Keep JSON and provider PDFs private, and clear/close the standalone page on shared devices; it intentionally has no live-app sign-out connection. Existing service-worker behavior is untouched; download the standalone HTML for offline use.

## Verification

- `npm test`: 486 tests, including summary date/count validation and additive read-only SQL checks.
- `npm run build:pages` and diff checks.
- `PGLITE_MODULE=/path/to/@electric-sql/pglite node tests/database/shared-gym-usage.cjs`: real role helpers, owner/provider equality, Philippine midnight boundaries, distinct visitor counts, previous period and calendar-month totals, READ ONLY transaction compatibility, denied roles/cross-gym access and unchanged attendance rows.
- `node tests/browser/shared-usage.cjs`: actual owner/provider pages, unchanged subscription actions/top statistics, failure/retry, staff scope, late responses, sign-out, profile close and separate Analysis tab.
- `node tests/browser/analysis-offline.cjs`: synthetic current-app XLSX imports, zero/missing values, queues, duplicates/overlap, pricing, privacy-filtered PDF (including actual print rendering), JSON round-trip, safe imported text, demo separation, responsive layout and zero external service requests.
- Existing phone-interface, provider-notification and admin-menu browser regressions. Tests use mocked services; no live financial or account operation was performed.

Before production use, apply 053 manually and compare the same period/snapshot on an owner dashboard and Provider Gym Profile. For Excel analysis of the shared period, export the explicitly displayed date range from Reports. Already approved prices and coverage remain intact.
