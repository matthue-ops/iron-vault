# Held bundle Stage 2 — Reports loading performance

Based on inspected main `a38a130`, including merged member-list Stage 1. Preservation of working behavior is the priority. This stage changes frontend loading/rendering only. **No database queries, RPC arguments, SQL, stored functions, financial calculations, permissions, subscription rules or exports' record scope are changed. No SQL is required.**

## Changes

- A generic loading screen is present in the initial HTML while the private page remains hidden. It reports access checking, data loading and report preparation. It contains no gym/member details, supports reduced motion, and is excluded from printing. Reports initialize at DOMContentLoaded instead of waiting for unrelated images/fonts to complete window load.
- ReportsUI computes the existing analysis once per accepted render and shares its model/version with the workspace. The obsolete full-table render is no longer invoked. Manila date/hour formatter objects are reused; date rules and financial arithmetic are unchanged.
- Money, Attendance and Activity tables render only when opened. Daily totals, the expiring-pass list, guide insights and Member Credits render on demand. Overview still shows its four figures, Revenue by day, revenue breakdown and five recent check-ins. Legacy standalone report panels remain usable without the workspace.
- Formatted rows are cached only in memory for the current report snapshot/view. Pagination/search reuse them. The cache clears on refresh and sign-out/access denial. Excel copies cached cells before applying numeric export formats; exporting cannot change later CSV or screen values.
- Print and export scopes remain unchanged: detail printing uses the current table page, credits print all matching rows, and XLSX includes all selected-period records across the original four sheets, including sections not opened onscreen.
- Date-request generation is rechecked after awaited rendering, and phone/workspace wrappers discard stale results. A superseded request or sign-out cannot unhide the page afterward. Phone rotation refreshes the current layout without switching Credits or Daily totals back to Summary.

The existing before/after report permission checks, identity binding, tenant lookup, single `iv_report_snapshot` request and backend authorization are retained. This does not bypass subscription access or cache report data persistently.

## Validation

Run from the repository root:

```sh
npm test
npm run build:pages
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/browser/reports-workspace.cjs
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/browser/phone-workspaces.cjs
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/browser/reports-performance.cjs
```

Browser tools require Playwright and `/usr/bin/chromium`. Install tools in a disposable directory outside the app if needed. The existing phone-workspaces fixture requires `/tmp/iv-admin-tailwind.css`, compiled from the admin/report markup and assets with Tailwind 3.4.17. No test calls live Supabase or performs financial operations.

The performance fixture uses actual initialization, role-check helpers and report modules with synthetic API responses: 2,000 financial records, 180 check-ins, 230 activity/session records and 240 members. It checks one analysis, zero legacy full-table renders and zero initial detail-table rows; all records remain present in the workbook. It also checks cache-safe CSV after Excel export, lazy daily/expiry/credit views, overlapping responses, permission revocation, sign-out during rendering and portrait/landscape layouts at 320/390/844/1280 px. A separate fixture proves DOM-ready initialization occurs while an image is still pending.

These are work-count and correctness checks, not a measured live speed claim. Network, CDN bootstrap, authentication round trips and backend snapshot processing still contribute to loading time. The first response still contains the same complete snapshot. If live loading remains slow after frontend rollout, measure request timings before proposing a separately approved backend/query change.

## Release

Review and deploy only the matching static frontend after approval. No migration or Edge Function deployment is needed. Nothing is merged or deployed automatically. Reverting this stage's frontend commit restores the earlier rendering behavior without changing stored data. Other held bundles remain untouched.
