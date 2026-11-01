# Short codes, staff contact and clear reports

## Owner-run rollout

The existing installation must already include 001–017. Run the entire `supabase/manual/usability_update.sql` once in SQL Editor. It atomically applies 018 (display codes), 019 (staff sign-in/contact policy) and 020 (report metadata/purchase receipts). Do not rerun the initial installation bundle. The agent has parsed this SQL, not executed it.

Update these **existing** Edge functions using the complete standalone files from `supabase/dashboard/`:

| Function | File | Verify JWT |
| --- | --- | --- |
| iv-branch-auth | iv-branch-auth.ts | OFF |
| provision-gym-tenant | provision-gym-tenant.ts | ON |

No new secret is needed. Keep `APP_URL=https://ironvaultph.vercel.app` and the production origin in `CORS_ORIGINS`. Review the application preview, then promote the matching deployment in Vercel's **iron-vault** project. PR remains Draft until the remaining acceptance is complete.

## Display codes

Persisted unique codes such as GYM-0001 and MEM-0001 are added to existing and future rows. Internal IDs, tenant keys, portal links, QR ticket verification, Auth bindings, receipts and foreign keys are unchanged. Codes are globally unique within their type, grow beyond four digits without truncation and are not recycled after purge. Existing rows receive codes once; sequences may have gaps. The safe views append one column without changing existing columns or authorization. Profile/branding APIs never accept display-code changes.

Master lists/branch inspection, active and pending rosters, manual search, member profile, report details and saved export views show the code. Member sign-in accepts the short code, an existing internal member ID, or the contact email, always scoped to the selected gym and protected by the existing password. Internal IDs remain in exports and maintenance operations such as purge confirmation.

## Staff

Owner-created staff can sign in immediately without mail delivery or prior contact verification. Owner provisioning still requires email verification. Existing staff blocked only by verification become enabled when their gym is active; disabled_at revocations remain intact. Public signup cannot create staff. Staff report permissions are unchanged and are not granted by email editing. New staff creation/correction and verified administrative contact changes reject an email already used by another owner/staff account in that gym, avoiding ambiguous Admin / Staff sign-in. A partial unique index enforces this under concurrency; conflicting legacy contacts cause installation to roll back instead of being silently changed.

Staff Management → Registered Staff → Edit name / email lets the gym owner correct an **unverified** staff contact directly. It remains unverified; password recovery is mailed to the corrected address. Any previous recovery token is replaced without sending mail before the contact changes, and old contact-confirmation actions are invalidated. The same private Auth identity/password is preserved. A verified contact still requires proof at both old and new addresses. Owners can only edit staff in their own active gym; global Super Admin can also manage staff from branch inspection. Recovery still requires control of the email inbox.

## Reports

- Period metrics use Manila dates: net cash = top-ups + cash pass payments − recorded cash refunds. Gross membership sales = cash pass payments + wallet pass spending. Do not add cash and sales totals together. Top-ups are prepaid credit, not a second pass sale.
- Purchase counts use canonical purchase receipts, so split wallet/cash payments count once. Older ledger sales without receipts remain in monetary totals but cannot be honestly counted as purchase events; the card explains this limit. Repeat purchases require an earlier recorded receipt for that member.
- Current wallet credit, pending approval counts and valid-pass/expiry lists are explicitly current snapshots, not historical closing balances. Valid passes must have an active member, known plan and valid unexpired date. Registration counts use immutable created_at rather than date_joined, which legacy renewal logic changes.
- Daily money/attendance, unique visitors, QR/manual mix, busiest hours, and seven-day expiry lists accompany the summary. Last 7 Days includes exactly seven Manila dates; This Month and date validation are available. All-Time queries from 1900 through today.
- Search and pagination apply to the current detail log. CSV includes all matching rows, not just the visible page; it checks report permission again and neutralizes spreadsheet formulas. Existing permission revocation and printing checks remain. Print covers the current view.
- Arithmetic uses integer cents. Unsupported financial kinds, negative/non-cent/invalid amounts are disclosed and excluded from summary calculations, while detail records remain visible. Current snapshot attributes in ledger rows are labeled accordingly. These are operational reports, not profit/tax statements.

## Acceptance

After owner deployment: verify a short code in Master and a member profile; sign in as that member using the code; create staff with an unconfirmed address; sign in as staff, then owner-correct the contact to a real inbox and test password recovery. Verify report access remains blocked for ordinary staff without the financial permission. Test a split-payment purchase and ensure one receipt, correct cash/sales totals and no top-up double counting. Compare a CSV with the filtered report. No live data, SQL, Edge functions or production deployment were changed by the agent.
