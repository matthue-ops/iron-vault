# Proposal: monthly report delivery, archives and controlled retention

Status: **PROPOSAL ONLY — NOT IMPLEMENTED OR ENABLED**  
Prepared: November 2, 2026, Asia/Manila  
Purpose: preserve the agreed plan for a future implementation review.

Saving or merging this document does not approve database changes, enable a
scheduler, send email, or authorize deletion. No implementation SQL accompanies
this proposal. Follow `AGENTS.md`: explain database impact and obtain explicit
approval before implementation; the user manually executes any Supabase SQL.

## 1. Intended outcome and scope

- Each gym owner receives their own previous-month report by email.
- The same report is archived privately and downloadable from the existing
  Super Admin dashboard. Super Admin does not receive monthly email copies.
- The tenant receives an in-app notification describing the delivery status.
- Older records become candidates for cleanup only after the age, archive,
  delivery, dependency and approval conditions below pass.
- Gym accounts, members, current balances, plans, expiry dates, access rules and
  daily operations remain intact.

Extend the existing reporting and Super Admin interfaces rather than replacing
them. Keep unrelated UI and functions unchanged. Existing manual CSV, Excel,
Print, report viewing and profile restore behavior must remain available.

## 2. Exact calendar rule

**Keep the current month plus the previous three complete calendar months live.**
Calculate all boundaries on the server using Asia/Manila, not browser time and
not an approximate 90-day interval.

Example on **May 1, 2026**:

| Month | Treatment |
| --- | --- |
| May | Keep: current month |
| April, March, February | Keep: three complete months of buffer |
| January and earlier | May be evaluated for eligibility; not automatically deleted |

Thus January first becomes age-eligible on May 1. Its report would normally have
been generated on February 1. The earlier 15-day idea is superseded by this
calendar buffer; no additional 15-day timer is assumed. Any extra advance-warning
period must be explicitly decided before implementation.

Age is only one condition. A missing archive, failed email, active dependency or
retention hold keeps the records, however old they become.

## 3. Monthly archive and delivery workflow

1. **Schedule:** on the 1st of each month, generate the previous complete Manila
   calendar month. A suggested run time is 01:00 Manila time; finalize the time
   before implementation. Support safe manual retry and catch-up for missed runs.
2. **Capture a consistent snapshot:** bind the archive to one gym's internal ID,
   one month and one archive version. Record exact source record IDs, original
   timestamps, counts and an archive manifest. Do not rely only on UI pagination.
3. **Generate the Excel report:** Overview, Money, Attendance and Activity, using
   the established calculations and labels. Use the gym's name and date range in
   the downloadable filename. Distinguish period totals from current snapshots.
   A report generated on February 1 must not describe current balances as verified
   January 31 closing balances unless that separate calculation is implemented.
4. **Generate a recovery archive:** store the original report records in a
   machine-readable format such as JSON/NDJSON, preserving IDs and relationships.
   Include the minimum identity/label context needed to understand them later.
   Do not add passwords, Auth secrets, verification tokens, or unnecessary profile
   images. This is separate from the owner's Excel attachment.
5. **Store and verify:** upload both files to private storage. Verify successful
   read-back, checksums, workbook readability, source-to-archive counts and complete
   contents. Register the files in the Super Admin dashboard only after successful
   verification. Never call an incomplete or truncated archive ready.
6. **Deliver to the owner:** send the workbook to a verified reporting recipient.
   Ordinary login with an unconfirmed contact email stays unchanged. Missing or
   unverified reporting recipients hold delivery and cleanup, not gym operation.
7. **Record delivery:** distinguish queued, provider-accepted, delivered, bounced
   and failed states. Provider acceptance is not delivery; delivery is not proof
   of reading. Use authenticated provider events where supported. If delivery
   cannot be established, hold cleanup for review.
8. **Notify the tenant:** notify the owner in the tenant interface only with the
   actual status, such as report emailed or delivery failed. Preserve the report
   month, notification time and delivery attempt history.
9. **Retry and alert:** retry failed generation/upload/delivery in a bounded,
   idempotent way. Surface unresolved failures in Super Admin. A failure must not
   stop check-in, sales, sign-in or other normal gym functions.

Default delivery is an Excel attachment. If a report exceeds provider limits,
hold the send or use an explicitly approved secure-link alternative; never omit
records silently. Super Admin receives the private dashboard archive, not email.

## 4. Archive access and recovery

- Keep storage private and separated by internal tenant ID, month and version.
  Gym display names and short codes are labels, not authorization boundaries.
- Super Admin can find a gym/month, see generation and delivery status, and
  download the Excel or recovery archive through checked, short-lived links.
- Owners receive only their gym's workbook. Do not expose archives to other gyms,
  anonymous users or staff without the appropriate report permission. Review the
  exact archive access matrix before implementation.
- Log archive access, delivery changes, holds, approvals and cleanup outcomes.
- A replacement archive gets a new version and invalidates old cleanup approval.
  Preserve the audit history instead of overwriting evidence of the old version.
- Keep recoverable database backups separately and test restoration. The existing
  Excel export and profile-only ZIP restore do not constitute full log/financial
  recovery. Do not use the profile restore UI to recreate deleted history.
- An encrypted external hard-drive copy may be an extra backup. It must not be
  the only archive or the live storage behind dashboard downloads.

Archive retention is a separate decision from live-database retention. Do not
delete archives simply because their source rows have been cleaned up. Define
storage duration, access responsibilities and deletion rules before launch.

## 5. Record classification from the current code

These are code-level candidates, not permission to delete live rows. Verify the
live schema, foreign keys, triggers and all consumers before building cleanup.

| Records | Initial treatment | Reason / dependency |
| --- | --- | --- |
| `public.iv_activity_logs` | Candidate after all gates | Not the source of role authority; retain a trustworthy audit archive and any records under investigation. |
| `public.iv_staff_sessions` | Candidate after all gates | Sign-in/out history, not the actual Supabase authentication session. |
| `public.iv_attendance_logs` | Candidate for completed, archived business days after all gates | Today's records support duplicate-admission checks. Preserve member check-in state and counters. |
| `public.iv_financial_transactions` | Exclude from the first cleanup release | Some legacy request IDs in this table are the remaining duplicate-payment safeguard. Modern rows also need complete archive/report handling. Review individually in a later phase. |
| `ironvault_private.financial_requests` | Keep live under the current implementation | Required for replay-safe payments, saved Wallet after, purchase counts and renewal identification. No current expiry or safe compaction policy exists. |
| `ironvault_private.daily_passes` | Optional separate technical cleanup proposal | Only expired, past-business-day tickets are candidates; current tickets must remain. Not part of the monthly report cleanup by default. |
| Accounts, profiles, Auth users, role bindings, report permissions, branch mappings and provisioning jobs | Preserve | Support current access, identity, account completion/retry and historical attribution. |

Also preserve current wallet balances, plans, expiry dates, cumulative amounts,
scans/check-in counters and last-check-in dates. Cleanup must not reset these
fields, recreate profiles or cascade-delete related operational records.

Other temporary records, such as expired email actions or rate-limit windows,
require a separate review. For example, one confirmed address proof may still be
needed while the second proof remains valid. Do not delete every confirmed email
action or reset an active rate-limit window as part of report cleanup.

## 6. Eligibility: every gate must pass

Evaluate a batch identified by **gym + calendar month + record category + archive
version**. It is eligible for review only when:

1. The entire selected record set is outside the current month and three-month
   buffer, with no current-day admission data.
2. The category is explicitly allowed for cleanup. Money and private payment
   receipts are excluded from the first release.
3. Excel and recovery archives are verified, complete, readable and accessible
   from Super Admin; a tested recovery route and database backups exist.
4. The relevant report's delivery is confirmed and tenant notification recorded.
   Failures or unknown delivery status hold the batch.
5. No active subscription depends on the records. Use the original purchase's
   saved expiry, not just a member's mutable current profile expiry. In the current
   implementation, a pass remains valid through its expiry date in Manila.
6. No unresolved payment, refund, dispute, support investigation or retention hold
   involves the records. If the system cannot establish this, require an explicit
   hold/review outcome rather than assuming none exist.
7. Accounting, contractual and applicable retention requirements permit removal.
   The calendar buffer alone does not establish this.
8. Request replay protection, stored financial outcomes, current account state and
   all required relationships are preserved. Transactions and top-ups do not
   expire merely because a subscription expired.
9. The source set still matches the verified archive manifest. Changed or newly
   backdated rows require re-archiving and renewed review, not a broader deletion.
10. Super Admin approves the exact tenant, month, category, archive version and
    record counts during the pilot. Eligibility itself never grants approval.

For the pilot, if any category in a monthly batch has an unresolved dependency,
hold the month rather than attempting clever partial cleanup. Show each hold
reason and the next reevaluation date. Preserve the entire batch if checks fail.

## 7. Proposed job and review state

These are conceptual states, not an implemented table design:

`Pending → Generating → Archive verified → Delivery confirmed → Tenant notified`

Then, separately:

`Age eligible → Dependency review → Held OR Awaiting approval → Approved → Cleaning → Completed`

Generation and delivery failures remain visible with retry history. Keep archive,
delivery, notification, hold and cleanup status separately so a single green
"completed" flag cannot accidentally authorize deletion.

Future records should capture internal tenant ID, business month, archive version,
file keys/checksums, source IDs/counts, snapshot time, delivery evidence,
notification time, hold reasons, approval scope/actor/time, cleanup progress and
outcome. Do not store credentials or unrestricted public file links in these jobs.
Keep this control/audit metadata outside the rows being removed.

## 8. Controlled cleanup behavior

- Keep deletion **disabled by default**. First implement eligibility previews only.
- Show Super Admin exact row counts by table/category, verified archive links,
  holds, protected data and what the operation will remove.
- Use small, tenant-scoped, resumable batches and a single active lease per job.
  Scheduled retries must not duplicate email or repeat completed work.
- Delete only the reviewed, archived record IDs. Never use an unbounded command
  based solely on a date or tenant name. Do not use the existing whole-tenant
  purge function for routine retention.
- Revalidate eligibility and approval immediately before each destructive batch,
  using suitable transactions/locking to prevent races with live operations.
- Stop safely on mismatched counts, changed data, access loss, missing archives or
  dependency failures. Do not weaken constraints or remove extra records to force
  success. Record partial progress and a clear recovery procedure.
- Preserve an independent cleanup audit and manifest. Keep gym operations running
  while failures are investigated. Provide a pause/disable control.

Deleting rows makes database space reusable; it does not necessarily shrink the
reported database file immediately. Measure real table/index growth and supported
maintenance behavior before promising a storage saving.

## 9. Historical report behavior after cleanup

Once a month's live rows have been removed, ordinary historical queries cannot
produce a complete report for that month. For example, keeping payment receipts
while removing ledger rows can leave purchase counts but zero displayed sales.

The application must identify archived months and offer the saved report instead
of presenting an incomplete live report as zero activity. A date range containing
both archived and live months must be handled explicitly: provide separate archive
files/live results or a verified combined-report implementation. Do not silently
combine incomplete totals. Keep existing current-month reports unchanged.

## 10. Phased implementation

### Phase A — monthly archives and email, no deletion

Add consistent snapshot generation, Excel and recovery archives, private storage,
Super Admin file/status listing, owner delivery, tenant notifications, retries and
failure alerts. Verify tenant isolation and delivery before enabling the schedule.

### Phase B — eligibility and manual review, still no deletion

Measure storage growth. Add exact calendar rules, manifests, hold controls and a
dry-run preview showing candidates and exclusions. Exercise restore procedures.

### Phase C — narrowly approved cleanup pilot

Only after separate database approval and tested recovery, enable Super Admin
approved cleanup of older Attendance, Activity and sign-in/out logs. Keep Money,
private receipts and all current operational state excluded. Verify normal gym
operations and archived-report access after each pilot run.

### Phase D — optional later changes

Consider unattended cleanup only for explicitly approved categories after the
pilot succeeds. Consider Money cleanup separately, including any durable legacy
request-ID markers and retained receipt policy. Each requires its own design,
tests and approval; this proposal does not authorize either.

## 11. Acceptance checks before any deletion feature is enabled

- Two gyms cannot receive or download each other's reports or archives.
- All four Excel sheets contain the correct complete Manila month, without
  pagination/search filtering, with current snapshots clearly labeled.
- Archive manifests, record counts, checksums and a restore exercise agree.
- A generation, upload, email, notification or verification failure blocks cleanup
  and gives Super Admin a useful status and safe retry.
- Calendar tests cover month ends, leap years and Manila/UTC boundaries; January
  is held through April and becomes age-eligible on May 1.
- Active subscriptions, expired-date boundary days, unresolved cases and unknown
  dependencies hold the batch. New source rows invalidate old approval.
- Wrong-tenant jobs, overlapping workers, lost connections and repeated requests
  cannot remove unapproved records or duplicate delivery.
- Current check-in protection, QR issuance/redemption, wallets, renewals,
  membership access and reporting remain correct after a cleanup pilot.
- Legacy payment request safeguards and all private financial receipts remain.
- Archived month views do not display incomplete live totals as complete reports.
- Access and cleanup audit records survive and can explain exactly what happened.

Use dedicated test fixtures and an approved test target. Follow the standing rule
that the user executes Supabase SQL; no live deletion test is implied here.

## 12. Decisions required when work resumes

Before writing implementation code or SQL, confirm:

1. Reporting recipient verification and provider delivery-evidence capability.
2. Storage provider, archive retention period, backup/recovery responsibilities,
   attachment limits and the approved delivery fallback.
3. Initial eligible categories and the live constraints/consumers protecting them.
4. How active-plan dependencies, disputes and other holds will be established.
5. Whether manual Super Admin approval remains mandatory after the pilot.
6. The exact implementation stage, rollout target, tests and approval boundary.

Do not treat this document as confirmation that any requirement is installed.

## Current code references

- [Financial retry and admission rules](../../supabase/migrations/202611010013_member_wallet_and_daily_passes.sql)
- [Historical wallet/report receipt dependencies](../../supabase/migrations/202611020023_wallet_after_history.sql)
- [Client payment retry persistence](../../assets/financial-requests.js)
- [Four-sheet Excel export and its limitations](four-sheet-excel-export.md)
- [Existing tenant purge, a separate destructive workflow](tenant-purge.md)

This proposal can be revisited after measuring pilot storage and usage. Keeping
data while the archive/recovery process is developed remains the default.
