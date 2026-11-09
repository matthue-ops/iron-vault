# Provider-controlled subscriptions (048)

This batch covers subscription management only. It does not change gym/member finances, check-ins, authentication methods, installation or recovery features.

## What changes

- Owners request Dashboard Only or Dashboard + Member Portal. Provider can fulfill a request or assign a paid plan directly. Existing agreement acceptance and required published documents remain prerequisites. Pilot activation retains its existing date/eligibility rules.
- Paid default: one month / 30 days and the published price. Edit unlocks 1–120 whole months and a positive total with two-decimal precision. Each month is exactly 30 days. When months change, suggest the multiplied standard total until the Provider explicitly edits the amount. Existing complimentary days remain attached when a scheduled paid plan is changed. Only the Provider can override duration/price.
- A server-owned preview shows current, future and resulting coverage. Review is mandatory; positive collections require explicit manual payment verification. References are optional. Provider note/reason is required for complimentary days, changes, cancellations, refunds, returns and rejections.
- Complimentary days attach to a selected current/scheduled paid period, retain its plan and shift later coverage forward. Use 1–3650 whole days. No standalone free plan, new revenue or automatic pilot extension.
- Active Dashboard upgrades use the recorded monthly-price difference / 30 times remaining counted days, rounded to two decimals; the Provider may edit the charge. Expiry stays unchanged. Approval-day courtesy access before counted days does not inflate the remaining-day charge. Queued renewals continue to block a mid-period upgrade.
- Early renewals follow all approved coverage. After suspension, approval restores access immediately and counting starts tomorrow. Paid grace remains per agreement; a renewal during grace keeps the original renewal date.
- Pending payment verification/correction grants no extra operations. Pilot gets no grace. Reports remain within the agreed export window, Subscription remains available. Reading a notice never changes dates.
- Future paid periods activate from server date logic without further clicks, a cron task or an open browser. Provider can preview them, and owners may request changes/cancellation. The existing approval stays effective until a new decision. Once active, silent editing/cancellation is blocked: use an upgrade, complimentary extension or separately recorded manual refund.
- Changes to scheduled plans retain immutable before/after history and shift later coverage to avoid overlap. A lower price/cancellation only flags a possible manual settlement; it does not record a refund. Record an external refund separately, with confirmation that money actually left the Provider and a reason. Cumulative refunds cannot exceed recorded verified collections for that period.
- One timeline per gym; separate active/scheduled/request states. Provider menu includes Pending subscriptions ordered by expiry, Payment options, and Subscription reports. Reports filter by gym, Philippine dates, plan and event type, and export CSV with spreadsheet-formula escaping.
- Each positive payment/upgrade/change collection gets one numbered payment acknowledgment; complimentary days get an extension confirmation. View, print or download self-contained HTML (and use the print dialog to Save as PDF if desired). These are not represented as official tax invoices. No PDF receipt uploads are accepted.
- Payment methods can be added/edited/disabled/deleted. Deletion is logical to preserve references; historical snapshots remain immutable. Images are private, optimized to at most 1600px / 2 MiB, and viewed via short-lived signed URLs. No public image URLs or overwrite permission. Restrictive Storage guards protect this bucket even alongside older permissive policies.
- Every approval/decision sends the registered owner one persistent notice with notes and a record number. Complimentary notices include old/new expiry and shifted dates; complete details remain in Payment History. No email or automatic money transfer is introduced.

## Duplicate and failure protections

All new subscription mutations lock the gym subscription row. Enabled role rows are share-locked and authority is rechecked; period overlap is checked with a deferred constraint trigger. Each provider preview has an actor-bound ID, complete server quote, fingerprint and ten-minute expiry. Other approvals, schedule changes, method edits, role/gym changes or a changed business date require fresh review. Completed previews replay before expiry/freshness checks, returning the same period, ledger record, notice and acknowledgment.

Each new owner request carries a stable UUID and exact submitted payload. One unresolved new request per gym is permitted; imported legacy requests retain their IDs. Existing pending requests must be resolved/fulfilled before direct assignment. A successful request retry returns the original result before rechecking changed dates/methods. Distinct genuine renewals may be added after prior approval and are explicitly shown in Preview.

The UI keeps unresolved request/commit identities and exact retry data in sessionStorage, scoped by actor and gym (provider approvals also include backend host). On an unknown response, retry the exact submission; do not clear browser data, collect payment again or start a replacement. Reopening Subscription in the same tab exposes Retry same approval. Across a lost/closed tab, inspect the server timeline, pending queue and transaction history before another action; these are authoritative. Backend protections remain active if browser state is lost.

## Before SQL

1. Confirm migration 047 and its prerequisites are installed. Back up normally. Save the current deployed commit.
2. Run **supabase/manual/subscription_control_preflight.sql** (read only). Save the results. It identifies access depending on pending verification, unresolved requests, legacy delay-day calculations and overlapping periods.
3. Review affected gyms. Installing 048 removes pending-payment provisional access immediately; if the existing period/grace has ended, operations stop while agreed owner reporting/Subscription remain. Review any previously promised compensation manually; old interval/verification records are retained. New automatic delay compensation is retired.
4. Existing approved payments are imported once into the new report ledger with HIST identifiers and original approval timestamps/amounts; no new payment/access/notice is created. Historical identity labels use current display names with the original quote preserved, not invented historical identity evidence.
5. Existing unresolved legacy requests retain original quotes/references and can be reviewed. Legacy unpaid downgrade scheduling requests targeting an active/expired period are not paid entitlement: return/reject those and arrange a proper renewal; do not invent free coverage.
6. New paid quotes require an applicable published agreement with paid_days = 30. Other existing approved terms/periods remain unchanged. Do not silently republish or overwrite accepted agreements. If your publication differs, review/publish it using the existing explicit process first.

## Manual deployment order

1. Review and run **supabase/manual/provider_subscription_control.sql** once, in full, including BEGIN/COMMIT. It is identical to migration 202611090048_provider_subscription_control.sql; do not run both. Guards reject reinstallation and pre-existing overlapping periods without changing records.
2. Confirm success. No Edge Function deployment, secrets or mail settings are needed.
3. Merge/deploy the matching frontend; refresh all Provider/owner tabs. Old subscription financial controls deliberately fail closed after SQL rather than bypassing preview/review. Existing gym/member transactions continue on their original APIs.
4. Provider menu → Payment options: add actual bank/e-wallet details and payment QR. Then run the acceptance list below using dummy gyms.

New private tables hold payment methods, image metadata, requests, previews and transaction/acknowledgment snapshots. Approved periods gain cancellation/revision/complimentary-day metadata. Legacy extension-day metadata is derived only where the original immutable paid quote establishes it; dates and money are not rewritten. No historical approvals are deleted or changed by migration. Current unresolved requests are copied; open legacy verification intervals/jobs are closed/cancelled without sending messages. The legacy verification-reminder worker returns no jobs; owner expiry reminders and the Provider pending queue remain.

## Acceptance checklist

- Owner request displays exact dates, one-month price and Waiting for approval. Optional reference/image omitted works. Uploaded PNG/JPEG/WebP is viewable only to that owner and Provider; other gym, staff and anon cannot read it. PDF is rejected. Method edits/deletion preserve the submitted snapshot.
- Direct assignment shows any existing request before a second assignment. Defaults are locked; Edit permits 3 months = 90 days with a custom amount. Preview and both required confirmations gate paid approval. Missing agreements block new access.
- Two independent previews of the same schedule: first approval succeeds, second is stale. Replaying the first returns the exact same acknowledgment and creates no extra collection/period/notice. Test actual concurrent sessions in a controlled dummy-gym window.
- Add five complimentary days to Dashboard Only: same plan, no collection; future dates shift by five days. Preview/owner note/extension confirmation show all affected dates. No standalone or pilot complimentary grant.
- Upgrade a current Dashboard period without a queue: calculated difference and remaining counted days are correct, override requires Edit, expiry unchanged. With queued renewal, upgrade is blocked.
- Early approved renewal says Scheduled and begins after the previous period without another approval/login. Pilot expiry has no grace; paid grace is dashboard only; pending requests do not change either boundary. Expired reporting follows the accepted export window.
- Owner change/cancel request alone does not alter approved dates. Provider confirmation records before/after and notifies owner. Cancellation does not count as a refund. Record an actual external refund separately; excess refunds are rejected.
- Payment History acknowledgment views/print/download remain after notices are read. Complimentary confirmation has zero revenue. Filtered report/CSV counts verified collection once, shows refunds separately and never adds revenue on scheduled activation.
- Unknown response: Retry same approval/request resolves the original. Definitive rejection retains form values and requires refreshed preview where applicable. Sign-out/account change closes private dialogs and blocks late results.
- Smoke-test unchanged gym top-up/refund/QR/manual entry and permissions.

## Validation and limits

- npm test covers new invariants, CSV escaping, document escaping and existing regressions.
- node tests/browser/provider-subscriptions.cjs uses actual subscription UI, legacy mounting, browser image encoding and mocked Auth/RPC/Storage at phone/desktop sizes. It covers locked fields, discounts, confirmations, unknown-outcome replay, stale preview, complimentary shifts, owner requests and reports/acknowledgments.
- tests/database/subscription-management.cjs runs the complete new migration in disposable embedded PostgreSQL against synthetic pre-048 table/helper fixtures. Set PGLITE_MODULE to a temporary @electric-sql/pglite installation. It exercises actual SQL role/RLS, paid approvals, replay, stale reviews, import, dates, scheduled changes, cancellation/refund, upgrade, ledger and Storage guards. It never connects to Supabase. Fixture helpers do not prove the full hosted migration chain, Storage HTTP behavior or independent live PostgreSQL connections.
- SQL/PLpgSQL parsing and Pages build are also checked. Hosted migration, Storage and true multi-session concurrency require the manual acceptance above.

Retain payment-proof/QR objects under the disclosed record-retention policy. This batch does not introduce automatic storage deletion or a cron retention service. Replace/delete methods without erasing referenced images; purge/retention cleanup must use your reviewed Storage API process, not SQL deletion from storage.objects. Do not clear historical evidence to resolve a UI issue.

## Rollback

Do not blindly deploy the old subscription writer after 048: it cannot represent the new custom/complimentary/cancellation history. Keep the compatible frontend or disable new subscription writes while a separately reviewed forward fix is prepared. No automated database rollback, image deletion or refund is supplied. Existing accepted agreements and approved-period evidence must remain intact.
