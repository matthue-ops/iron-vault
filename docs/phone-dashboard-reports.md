# Phone dashboard and reports

Applies below 640 CSS pixels. Desktop continues using the dashboard roster, original revenue estimate, date controls and report tables. The compact dashboard statistics were already on the review branch and are included here.

## Changes

- `assets/admin-dashboard.css`, `gym/admin.html`: smaller phone heading, 2×2 desk actions and a Members button. Original Scan QR, Manual Check-In and Walk-In handlers remain.
- `assets/phone-members.js`, `assets/mobile-roster.js`: move the existing roster into a full-screen phone workspace, keeping the original search/filter handlers and authorized member profiles. Five members per page; preserve page, filters and scroll when returning from a profile. Restore the roster to its original location at desktop widths. No new member reads or writes.
- `assets/phone-revenue.js`: show Revenue Today on phones only. Read today's `iv_report_snapshot` through existing financial-report authorization, verify identity before/after and reject out-of-tenant rows. Reuse `reports-analysis.js` for exact-cent cash + wallet membership sales; exclude top-ups as additional revenue. This is membership sales, not net cash collected. No estimate is shown if the read fails. Refresh at most once per minute while visible, with refresh after financial actions and on returning to the page. Existing subscriptions and reporting permissions still apply. No query is made on desktop or for the hidden staff revenue card.
- `assets/phone-reports.js`, `assets/phone-reports.css`, `assets/reports-ui.js`, `gym/reports.html`: compact date menu with custom range Apply, 2-column summaries, compact report headings and expandable explanations. Money/Attendance/Activity records start collapsed on phones; 10 records per page, expandable record details, per-tab search/page preservation. Desktop records stay open and show 100 rows per page. Excel and CSV export all their existing record scopes; print retains its existing current-view scope and opens record sections before printing.

## Database impact

The additional read of today's transactions was explained and expressly approved in this session. It uses the existing `iv_report_snapshot` and `iv_can_read_financial_reports` RPCs with unchanged server-side authorization. No SQL migration, new schema, grant, data write, deletion or Edge Function deployment is needed. Historical records remain untouched. No live Supabase operation was executed during development.

## Verification

Run `npm test`, `npm run build:pages`, `node scripts/build-dashboard-functions.cjs --check`, and `node scripts/build-service-policy.cjs --check`.

`tests/phone-revenue.test.cjs` checks double-count prevention, date boundaries, cached totals after roster refresh, desktop no-read behavior, permissions, tenant isolation and stale responses after signout. `tests/browser/phone-workspaces.cjs` uses mock data and Chromium/Playwright at 320, 375, 430, 639, 640 and 1280px to check member pagination and return state, report cards, collapsed records, dates and desktop behavior. The browser script expects the session's cached Tailwind stylesheet at `/tmp/iv-admin-tailwind.css`.

Production behavior still requires the already existing subscription/report migrations to be installed. Deployment does not create records or change any subscription approval.
