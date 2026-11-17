# Clearer Reports workspace

This is a frontend presentation change using the existing authorized Reports snapshot, financial analysis, date filters, permissions, CSV/XLSX exports and history. No database query, SQL migration or financial calculation is changed. No SQL is needed for this update.

- **Overview:** separated plan revenue, wallet top-ups, current unused credits and visits. Plan revenue remains gross membership sales before refunds; it is not a new accounting/revenue-recognition calculation. Cash received is labelled separately. The chart shows the last 14 dates with recorded activity from the selected period, not invented weekly totals. Revenue breakdown, five recent check-ins, membership activity and a compact expiring-pass link remain available. Explanations and roster insights open in Report guide. Daily totals have a separate view instead of nested expandable sections. Money and Attendance detail views preserve their searches, pagination, original exports and print behavior.
- **Member Credits:** replaces the alert-only list with current positive balances, name/member-number search, 100-row pages and an export-permission-checked print action. Printing includes all matching rows across pages. Balances use the current loaded member snapshot, independently of the report date range. The report context identifies a search when filtering.
- **Activity & Audit:** opens the existing system activity/session view; payment and top-up records stay in Money details.

The workspace uses only the existing report data. Clearing report access clears the new summaries and credit list too. Overview/credit printing rechecks role and export permissions, account, tenant, view and snapshot version before printing. User-initiated browser printing cannot be technically prevented for information already visible to an authorized viewer.

Validation: `npm test`, `npm run build:pages`, and `NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/browser/reports-workspace.cjs`. The browser fixture uses actual Reports markup and modules with synthetic data, at 320/390/1280 px. It verifies no doubled revenue, view isolation, credit search/pagination/full matching-row printing, permission denial and data cleanup. Browser tools require Playwright and local Chromium; no real Supabase data or financial operations are used.

Deploy the matching static frontend after review. No schema update, merge or deployment is performed automatically.

## Business-style refinement

The three main views use understated tabs above one toolbar. Date selection, the Overview View dropdown (Summary / Money details / Attendance / Daily totals), Print & Export, and Report guide are centralized. Redundant card-level navigation and separate print/export buttons are removed. The print menu describes its scope: Overview, current credit matches, Daily totals, or the current detail-table page. XLSX still exports the original four-sheet workbook; CSV remains available in Money, Attendance and Activity detail views. No new combined all-views print workflow is implied.

Plan Revenue replaces the ambiguous Earned Revenue label, with Before refunds underneath. Revenue by day keeps its existing values, dates, amounts and last-14-recorded-day scope prominently on Overview. The palette uses neutral controls, subtle borders and a single accent, with two-column cards on phones. Expiring passes open in a small readonly dialog; Report guide opens separately. Dialogs and menus close when report data is cleared. Printed output excludes navigation and dialogs.

Regression coverage additionally checks date-menu and Escape behavior, daily-table view and printing, guide/expiry dialogs, the single export menu, absence of redundant controls, export routing, and cleanup on access loss. No SQL is required.
