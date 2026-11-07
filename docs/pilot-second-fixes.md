# Pilot second batch — counts, refunds and account controls

Prepared 2026-11-08 (Asia/Manila), on user instruction to continue and implement. SQL preparation follows the user's earlier authorization; only the user executes it. No live account changes, email requests, payments or SQL execution by the agent.

## Implemented scope

- Active Passes now shares Reports' validity rule: ACTIVE account, recognized plan, real expiry date on/after the current Philippine business day. Approved members with no pass no longer count. This counts valid passes, not remaining entries; an admitted member can still hold a valid pass today.
- My Account provides current/new/confirmation password fields for owners/staff. It rechecks own identity and gym role, verifies the current password and updates only that same account through a temporary non-persistent Auth client. It never accepts another account's email or ID from the form. The temporary session cannot replace the browser's main login. Password fields clear on completion/closure. Email reset remains a separate option. Supabase password policies still apply.
- Generic admin sign-in rejection now explains checking credentials/gym link or asking the owner to confirm access without revealing whether an account exists or is suspended. Signed-out Reports warnings use session/access wording instead of “Reporting access”.
- With 045 installed, cash approval requires actual handover confirmation and generates a permanent six-character payout reference server-side. The request reference remains distinct and unchanged. Successful cash notices, refund history and existing Activity snapshots carry the payout reference. Failed approvals roll back reference allocation; committed retries return the existing receipt.
- Rejection offers an optional separate member-facing reason. Internal decision notes remain internal. A successful rejection produces one notice with amount, request reference and unchanged-wallet explanation; blank public reasons use “Contact the gym for details.” No email is sent.

## Manual SQL — review and run once

1. Confirm 044 is installed. The user supplied deployed definitions and table-presence results consistent with 044.
2. Review and manually run [045](../supabase/manual/pilot_refund_references_notices.sql) in the Supabase SQL Editor. Run the whole file, including BEGIN/COMMIT. Do not rerun previous migrations or apply both copies.
3. Confirm success before treating generated payouts/notices as deployed. Deploy the matching frontend after review. No new Edge Function or secrets are required.

045 extends the private reference-kind constraint, adds `refund_cases.member_decision_reason`, preserves the old RPC as a non-callable private base, and wraps approval/rejection under the same permissions and lock order. A transition trigger inserts future notices with unique event keys. The base still performs balance/eligibility/review checks. Existing data is not backfilled or rewritten. No unrestricted balance-edit feature is introduced.

Without 045, the frontend continues requiring the existing manual payout receipt and does not promise rejection notices. The count/password/warning changes do not depend on 045.

## Validation and limits

Automated Node checks cover pass counts/expiry boundaries, password identity/reauthentication/error handling, and SQL artifact invariants. Browser tests cover legacy/new refund capabilities, mandatory handover confirmation, generated reference display/history, lost-response same-request retry, separated internal/public rejection fields and own password controls. All browser services are mocked.

426 Node tests pass. Relevant browser suites pass at 320/375/1280, including prior pilot fixes, refunds, staff permissions, registration/navigation, pending payments and the three-defect regressions. Pages build, generated Dashboard-function consistency and whitespace checks pass. A standalone PostgreSQL syntax parser accepted the 19 migration statements and all three PL/pgSQL function bodies without connecting to or executing against a database.

No PostgreSQL or PL/pgSQL was executed, even locally. SQL artifact checks are not runtime proof. The manual migration and real notice/idempotency behavior require user-controlled deployment testing.

## Post-migration acceptance

1. With three valid-pass members and one approved member without a plan, see four total members and three Active Passes. Confirm expired/no-plan/inactive members do not count; expiry today remains valid.
2. Approve a dummy cash refund. Without handover confirmation, approval must fail. With confirmation, no typed receipt is required; record distinct request/payout references. Member notice and History show the same payout code. Verify exactly one refund, notice and expected balance movement.
3. Retry the same approved case through a controlled test: no extra wallet movement, reference or notice. Existing manually recorded receipts remain unchanged.
4. Reject a dummy request using different internal/public reasons. Member sees only the public reason and request reference. Both wallets/financial totals remain unchanged. Blank public reason asks the member to contact the gym.
5. Attempt foreign-gym/unprivileged approvals and rejections: denied. Verify existing approval checks still block over-eligible amounts/stale reviews.
6. As dummy owner and staff, test incorrect current password, mismatch, successful change and old-password rejection. Sign-out/account switch during verification must not restore main login or change another account. Secure-password policies may require additional Auth configuration; do not weaken them to bypass an error.

Remaining held UI proposals are in [the batch record](issues/pilot-held-review.md); this batch does not implement them.
