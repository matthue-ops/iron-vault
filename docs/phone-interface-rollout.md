# Phone interface refresh

This release reorganizes existing controls for phones. Existing payment, refund, attendance, subscription scheduling, authentication and backup handlers remain in place. Small screens use compact dashboard tiles, Unread-first notifications, consistent reports, concise tenant cards, menu-based profile sections and a dedicated member QR dialog. Long records and forms may still scroll; controls remain readable and usable.

Owners and staff with the existing subscription_read permission see the dashboard subscription summary. Staff without that permission retain the previous desk arrangement. Report amounts, filters, pagination, exports and Current versus selected-period meanings are preserved.

## Deliberate behavior changes

- Providers can view existing gym membership prices but cannot change them through settings or staff-pricing APIs. Provider profile restores preserve current prices while restoring other allowed profile fields. Gym owners and authorized staff retain their existing pricing controls. Initial tenant registration is unchanged.
- Registered gym owners can save one of five presets for their own active gym. Providers can choose presets and retain the existing Advanced custom color control. Emerald, Blue, Violet, Teal and Amber apply to both gym dashboard and member portal. Staff permissions are unchanged.
- Revenue Today queues a fresh aggregate read when an older request is still finishing after a tenant/session refresh. The existing calculation, API and permission checks are unchanged.

QR generation still uses the existing server API, including legal acceptance, expiry and used-pass checks. Closing and reopening an unused QR revalidates and returns the same daily pass. Server-confirmed entry replaces the QR with the existing success feedback and timer. This UI does not issue another purchase or attendance record.

## Release order

1. Review and run the complete `supabase/manual/phone_appearance_pricing.sql` once in Supabase SQL Editor. It is identical to migration 049. Existing prerequisite migrations must already be installed; the script checks them. Do not rerun earlier subscription SQL.
2. Deploy this frontend through the usual reviewed merge/Pages workflow.
3. Refresh online before testing installed apps so the current assets load.

No live SQL has been executed by this implementation. No new Edge Function deployment or secret is required.

## Validation

- `npm test`: unit and regression checks, including the reproduced Revenue Today request race.
- `PGLITE_MODULE=/path/to/@electric-sql/pglite node tests/database/phone-appearance-pricing.cjs`: full 049 against disposable local PostgreSQL fixtures, including authorization and restore behavior.
- Install Tailwind 3 in a temporary directory, then run `TAILWIND_CLI=/path/to/tailwindcss/lib/cli.js node scripts/prepare-phone-test-css.cjs`.
- `node tests/browser/phone-interface.cjs`: real page markup/scripts with mocked service responses at 320, 390 and 1280 pixels; original menus, backup controls, QR reuse and accepted feedback.
- `node tests/browser/phone-workspaces.cjs`: report and roster navigation/filters/print at phone and desktop widths.
- `npm run build:pages` and `git diff --check`.

Browser tests isolate external services: they do not validate a deployed Supabase instance or make real purchases. After deployment, smoke-test owner/staff permissions, one dummy top-up/refund, QR/manual attendance, report export and backup controls. Verify the same unused QR reopens, successful scanning replaces it, and both gym and member pages use the saved preset.
