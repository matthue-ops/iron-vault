# Pass durations and attendance membership history

## Manual deployment

After migration 028, run **one copy** of `supabase/manual/attendance_membership_history.sql` in the gym project's Supabase SQL Editor. It is identical to migration 029. Then deploy the matching frontend. The agent has not run this SQL against any database.

## Behavior

New weekly purchases include today as day 1: a 4 November purchase is valid through 10 November, with six days after the first day. The existing monthly product is **30 calendar days**, not a calendar month: 4 November through 3 December, with 29 days after the first day. Day passes remain valid only on the purchase date. Access expires at midnight immediately after the final valid date (Asia/Manila). Missed visits still consume calendar time; scanning does not deduct an additional day.

Existing expiry dates and completed financial receipts are not shortened or rewritten. Previously saved completed financial requests retain their original outcomes under existing idempotency handling. Old passes may therefore legitimately have longer dates than newly purchased passes.

A private BEFORE INSERT trigger on `iv_attendance_logs` reads the matching tenant/member under a row lock and overwrites any supplied snapshot with the actual membership plan, expiry, status, Manila business day and remaining days. This happens in the same transaction as admission, covering QR and manual check-in. Existing admission authorization, entitlement checks and duplicate-entry restrictions remain unchanged. No new client write grants or public execution privileges are added.

The existing authorized report RPC serializes complete attendance rows, so it exposes the added snapshot without a replacement RPC. Table, CSV, Print and Excel use the same saved values. Remaining days exclude the check-in day. A day-pass row shows “Valid on [date].” Names and member codes still come from available current profiles. Overview validity cards remain current statistics.

Old rows deliberately retain NULL history. They show “History unavailable” for historical membership fields; current plans and receipts are not used to invent what was true at an earlier entry. No existing attendance, wallet, purchase or membership rows are backfilled or deleted.

## Validation and remaining project checks

Automated tests cover weekly/monthly first and last dates, missed days, leap-year boundaries, Manila dates, day passes, unchanged snapshots after renewals, legacy rows, and shared table/CSV/Print/Excel values. SQL syntax is parsed without running SQL. The migration retains the existing price/discount calculation and changes only weekly/monthly day offsets in the terms function.

After applying SQL in your project, test a new weekly and monthly purchase, then a manual and QR admission. Renew later and confirm the older attendance values remain unchanged. Check first-day remaining days (6 / 29), final-day validity and next-day denial in a test tenant. Existing old passes are intentionally preserved. A real Supabase execution and authorization integration test remains for the project owner; local tests do not prove the deployed migration is installed.
