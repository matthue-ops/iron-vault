# Stage 6 — custom gym membership plans

Scope: additional gym membership plans, not the provider's subscription products. No SQL was executed against the live database. Existing gym/member approvals, agreements, financial and admission behavior remain enforced. No existing plan, receipt, balance or expiry is rewritten during installation.

## Manual installation order

1. Confirm migrations through **058** are installed. A merged PR is not proof of SQL installation. Do not rerun previous migrations blindly.
2. Execute **only** `supabase/manual/custom_membership_plans.sql` as one complete transaction in Supabase SQL Editor. It is identical to `supabase/migrations/202611180059_custom_membership_plans.sql`; do not execute both copies. Guards reject a missing prerequisite or repeat installation.
3. Deploy the reviewed Stage 6 frontend, then refresh existing/installed app tabs. No Edge function update is required specifically for Stage 6. Previously required Edge deployments remain separate requirements for their features.
4. Use a disposable gym/member to verify a new plan, discount, wallet/cash purchase, expiry, QR/manual admission, reports and archive behavior before using real sales. Never collect money twice when retrying an unresolved transaction.

## Interface

Gym admin menu → **Custom Membership Plans**. The entry is available to the gym owner and staff explicitly granted the existing **Membership Pricing** (`pricing_manage`) permission. Staff without that permission can use available plans for their existing authorized desk-sale workflow, but cannot create/edit/archive plans. Provider pricing remains read-only, consistent with migration 049; no provider pricing-write grant is added.

Create/edit fields: name, base price in PHP and duration in calendar days. Archive stops new quotes/sales; restore makes the plan available again. There is no destructive plan-delete control. Existing day/week/month plans and their current price/discount controls remain in place.

Members see additional plan cards below existing choices. The desk plan picker also lists custom choices. Prices displayed on cards are base prices; the existing server quote and confirmation show the applicable member discount and exact wallet/cash split. A retry control remains available for unresolved membership payments, including a plan subsequently renamed or archived. It uses the original financial operation rather than creating a new sale. A first uncommitted sale against an archived/stale plan still fails safely.

Names are 1–60 characters; reserved built-in/no-plan names and control characters are rejected. Prices must be positive, at most PHP 10,000,000, with at most two decimal places. Duration is a whole number from 1 to 3650 days. Zero-price/complimentary, visit-count, scheduled-start, pause/freeze, family and recurring billing plans are outside this stage.

A duration includes the purchase date, using Asia/Manila: one day expires today, seven days expires today + 6, ninety days expires today + 89. Expiry remains inclusive. Existing built-in durations remain unchanged. Like existing plans, a valid pass cannot be replaced with another purchase or automatically extended early.

Stored custom labels use **Custom · Plan name · N days**. This keeps human-readable names/durations in existing members, receipts, attendance, audit, refund sources and report exports. The duration is also part of the purchase key, so changing duration after a quote invalidates the old choice even if the price is unchanged. A changed price is rejected by the existing authoritative price check. Renaming a plan changes future purchase keys only.

Desktop, phone portrait and landscape are supported. Forms preserve their values on resize. Long lists scroll inside the picker/dialog; they do not push the page wider. Account/gym changes, sign-out and late-response checks clear the custom-plan workspace.

## Database and compatibility

New private tables:

- `membership_plans`: gym-scoped stable ID, name, price, duration, archived flag, revision, last editor/time. A case-insensitive unique name is enforced per gym. No direct browser writes/read grants.
- `membership_plan_purchases`: immutable request-linked snapshot of plan ID/revision, original display label, duration, base/charged prices, member discount, expiry, actor and time. It is inserted atomically with the existing financial operation. Explicit existing tenant/member/receipt deletion cascades clean up these new dependent records; normal archiving never deletes snapshots.

`iv_membership_plans` is the scoped catalogue/management API. Default staff grants are unchanged. Revision checks reject conflicting edits. Identical save retries do not create duplicates; archive/restore retries keep the requested state. IDs cannot be used to update another gym's records.

Important existing functions are changed narrowly:

- `plan_terms`: built-ins delegate unchanged to the preserved prior function. Custom plans use the current active catalogue row, existing member-discount/whole-peso rounding, and inclusive duration.
- `iv_financial_transaction`: completed receipts delegate first through original actor/payload replay checks. New purchases prevent replacing any active built-in/custom pass, then delegate the actual money/ledger/member update to the existing 046/044/032 chain. Custom purchase snapshots are written before the same transaction commits. Snapshot/status-update failure rolls back the sale, wallet and ledger together. Existing top-up review, cash split, financial activity, subscription triggers and agreements are not bypassed or replaced.
- `valid_entitlement`: built-ins delegate unchanged. Custom passes require a matching private purchased snapshot and the current active member/gym and unexpired date. An arbitrary custom-looking string is not a backend entitlement. Catalogue edits/archive do not revoke a valid purchased snapshot.
- `iv_verify_entry_qr`: only its recognized-plan predicate is extended to purchased custom passes. Credential lookup, wrong-gym rejection, photo/member details, legal checks and entered-today checks remain intact. `iv_approve_entry_qr`, `record_admission`, generated QR issuance and Manual Check-In retain their existing lock/admission paths. No QR is regenerated by a plan change.
- Member status notifications: custom status refresh is delayed until its atomic purchase snapshot exists, avoiding a transient false "no pass" message. Existing built-in status logic and compact notification feed remain intact.

The new selector uses existing purchase controllers. The member roster, expiry filters and reports recognize custom labels for display; backend eligibility still requires the private snapshot. Attendance continues recording the purchased label/expiry at entry. Financial/refund history uses the original receipt and ledger descriptions, never the newly edited catalogue name/price. Wallet top-ups remain prepaid credit, not extra earned plan revenue.

## Backup and rollback limitations

Existing profile exports remain profile exports: they do not become complete backups of private catalogues, entitlement snapshots or the financial ledger. A profile-only import into another gym cannot manufacture a custom purchased entitlement. Use the established full database backup/retention process for complete recovery. Cross-gym transfer/import is outside this stage.

Do not roll the frontend/database back blindly after custom plans are sold. An old frontend can omit custom choices or mislabel them; old eligibility functions would reject existing custom passes. Retain 059's entitlement/verification compatibility until all affected passes expire or a reviewed replacement migration handles them. Never delete purchase snapshots or rewrite member labels/expiry to force a rollback. Prefer a scoped forward fix. Provider subscription access and normal gym isolation are unchanged.

## Verification

Run unit tests/build, the synthetic actual-SQL custom-plan suite, existing card/workflow/scanner regressions and the custom-plan browser suite. Coverage includes management permissions, cross-gym ID collision, invalid price/duration, revisions/retries, discounts, wallet/cash, atomic failure rollback, active-pass protection, archived/renamed snapshots, inclusive expiry, permanent/generated/manual shared allowance, member status/report display, mobile/landscape and sign-out/gym-change cleanup. Hosted integration and real sales are not exercised by these local tests.
