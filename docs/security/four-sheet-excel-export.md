# Four-sheet Excel report

Reports → Overview now has **Export all reports (.xlsx)** beside At a glance. The workbook uses the selected report period and gym name, for example `FITNESS_GYM_REPORTS_2026-11-01_2026-11-30.xlsx`.

Sheets, in order:

1. **Overview**: gym, selected dates, Manila timezone, export time, snapshot time, the four primary Overview metrics, Money totals, attendance summary, receipt/registration counts, daily totals and current expiring passes. Period values and current snapshots are explicitly distinguished. Outstanding credit and valid passes are not presented as historical month-end balances.
2. **Money**: all period transactions, including historical Wallet after where available. Amounts are numeric PHP cells; missing history stays Unavailable.
3. **Attendance**: all period visits, entry methods and the currently available member/pass information, matching the existing report.
4. **Activity**: both administrative events and account sessions for the period, with the same name/role and member reference labels used in Activity.

The all-report export ignores table searches, pagination and the Activity subtype filter. It preserves the current tab, search and subtype selection. Existing per-table CSV and Print controls remain unchanged. Detail sheets have header filters, frozen metadata/header rows, readable widths and wrapped text. User-supplied text is stored as explicit Excel string cells, not formulas or external links. The filename sanitizes filesystem-invalid characters while preserving the gym name. Excel text/row limits produce an error instead of a partial or corrupt download.

The export uses the already-loaded, authorized tenant report data. It makes no new data query or database write and changes no SQL, Edge Function, schema, payment calculation or access rule. Existing report authorization is checked before generation and again before download. A sign-out, revoked permission, changed account, tenant, report period or report refresh during generation prevents the old workbook from downloading. Concurrent clicks do not start duplicate exports.

JSZip **3.10.1** loads on demand from the same pinned cdnjs package used elsewhere in the app. A dependency failure is reported without hiding the report. The matching development dependency and lockfile are included for reproducible native tests: `npm ci`, then `npm test`. The small local writer creates a standard write-only OOXML `.xlsx`; it does not parse uploaded workbooks.

## Rollout and acceptance

No SQL or Edge deployment is needed. Review the branch preview, open Overview, select the desired date range and download the workbook. Open it in Excel or another compatible reader; confirm the four sheets, actual gym name in the filename, selected dates, current-vs-period labels, numeric PHP values and matching record counts. Try a table search and confirm the all-report workbook still contains every period record. CSV/Print should continue to export only their existing table view.

Merge the reviewed PR into `main` when satisfied; Vercel deploys it automatically. No manual promotion is needed. Downloading a workbook does not modify shared production data. This feature downloads a file for manual attachment; it adds no email sending or scheduling.

## Validation

207 native Node tests passed, including real XLSX ZIP/XML structure, four-sheet ordering, filename rules, string/formula safety, numeric/zero/historical money, empty periods, complete exports beyond 100 rows, ignored table filters, CSV/Print regressions, permission revocation, report changes, dependency failures and duplicate clicks. Mocked Chromium checks downloaded workbooks at 320, 375 and 1280 pixels; OpenPyXL 3.1.5 independently opened each file and verified sheets, values, number types, metadata, filters and frozen panes. No live database, SQL, email, production deployment or merge was performed by the agent. Hosted acceptance remains user-run.
