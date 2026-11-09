# Held appearance and revenue correction

Run the complete `supabase/manual/revenue_today_lock_compatibility.sql` (migration 050) once in Supabase SQL Editor, after the existing 046 migration. Then deploy this frontend through the reviewed PR. Do not rerun earlier migrations. No live database operation was performed by the implementation.

The SQL changes only the volatility declaration of `iv_revenue_today(text)` and reloads PostgREST's schema cache. A STABLE RPC gets a read-only transaction in PostgREST, while its existing staff authorization check uses `SELECT FOR SHARE`. VOLATILE permits that lock; the function body, sales calculation, grants, security-definer settings, tenant restrictions and subscription check stay unchanged. The function still does not write financial records.

Login now reads `accent_color` from the existing public branding view. No additional data, policies, grants, Edge Functions or secrets are introduced. All original sign-in, registration, reset, verification, legal and subscription access handlers remain in use. Member and Join have equal-width buttons; Admin/Staff is an accessible icon-only button on the right. Member remains the initial selection. Decorative login glows and buttons follow the saved preset, rather than sampling the logo.

Subscription selected tabs/current-plan card and Staff Management controls follow the preset. Warning/error dialogs remain red, confirmation/success dialogs remain green. Changes to the member feedback script are color values only: confirmation/cancel resolution, repeat-click guard and timers are preserved. Scan QR remains the only highlighted desk action; the earlier neutral Register Walk-In change is retained.

Validation:
- `npm test`
- `PGLITE_MODULE=/path/to/@electric-sql/pglite node tests/database/revenue-lock-compatibility.cjs`: disposable PostgreSQL reproduces the read-only error and verifies unchanged function body/grants, correct totals, excluded top-ups and retained tenant/permission/subscription restrictions.
- Compile temporary Tailwind CSS with `scripts/prepare-phone-test-css.cjs`, then `node tests/browser/held-appearance.cjs` and `node tests/browser/phone-interface.cjs`.
- `npm run build:pages` and `git diff --check`.

Browser services are mocked. After SQL and frontend deployment, verify live Revenue Today against membership sales for the Philippine business date (not net cash received). Check a permitted staff account and a staff account without revenue permission. Confirm all five presets on the login page, Subscription and Staff Management, then test member/admin form switching and red/green dialogs. A live smoke check is still required; no real payments or account changes are made by the browser suite.
