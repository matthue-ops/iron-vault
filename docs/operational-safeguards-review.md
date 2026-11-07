# Operational safeguards — combined implementation

Branch: `feat/operational-safeguards`. Includes the prepared offline-navigation fallback. This package is for one combined PR. No SQL, live backend request, deployment or email has been executed by the agent.

## What changes

- `assets/financial-requests.js`: known subscription/authorization rollbacks (`IV003`, `42501`) release payment retry keys. Unknown transport outcomes retain their existing request identity.
- `assets/staff-access.js`: in-memory permission drafts survive asynchronous refreshes, alongside expanded rows and scroll. A changed saved permission set or staff state flags a conflict and requires discard/review. Sign-out/removal clears drafts. Polling stops on pagehide, resumes once on pageshow, and stops on sign-out. Adds separate request/approval refund grants, ungranted for staff by default.
- `assets/refunds.js`, `assets/refunds.css`, `gym/admin.html`: Refunds menu with New, Pending review and History. Original transaction selection, partial amount caps, editable reason presets, cash/wallet/correction destinations, optional wrong-account credit transfer, and review before request/approval. Cash approval records confirmed external payout and reference; the app does not send money. Positive-wallet member removal opens settlement; existing server zero-balance removal guard remains.
- `assets/reports-analysis.js`, `assets/reports-ui.js`: separate totals/history/export for wallet refunds and outgoing/incoming credit corrections. Gross membership sales retain their original definition. Cash refunds reduce net cash; wallet refunds and credit corrections do not invent cash movements. Financial rows keep immutable balance snapshots.
- `assets/member-announcements.js`: financial notices and current status remain visible after reading, with resolved status labelled separately. Account notices display their actual recording time, without an artificial expiry date. Existing audience rules for general announcements remain.
- `assets/subscriptions.js`: pending verification/correction states, original submission time, date/access policy, correction action, Provider return/reject actions and a fresh server-date review before approval. Existing free-pilot acceptance/manual activation and untracked legacy requests continue through their existing paths.
- `gym/admin.html`, `gym/profile.html`: live-profile QR presentation notice. This is an instruction, not technical screenshot detection. Existing server QR checks are preserved.
- `supabase/functions/iv-provider-reminders/index.ts`, its generated Dashboard entry, generator and config: scheduled private-secret worker with durable daily claims and per-job mail idempotency key. It sends no mail until separately deployed/configured/scheduled.
- New Node/browser tests cover changed calculations, notice read persistence, refund UI review, permissions/refresh, date review and reminder failures. The manual database acceptance checklist below is still required.

## Manual database rollout

Confirm migrations through **041** are installed. Back up and use a disposable staging gym first.

1. Run **either** `supabase/manual/refunds_member_notices.sql` **or** its identical numbered copy `supabase/migrations/202611070042_refunds_member_notices.sql`, once.
2. Run **either** `supabase/manual/pending_payment_verification.sql` **or** its identical numbered copy `supabase/migrations/202611070043_pending_payment_verification.sql`, once.
3. Deploy the updated frontend after SQL succeeds. Missing SQL fails visibly; do not treat generated scripts as installed.
4. For email reminders, separately deploy `iv-provider-reminders` from the modular source or paste the complete `supabase/dashboard/iv-provider-reminders.ts` file. JWT verification is OFF for this worker only; it authenticates the server scheduler with its own 32+ character secret and rejects browser origins.
5. Configure Edge secrets through the Dashboard: `REMINDER_JOB_SECRET`, `PROVIDER_NOTIFICATION_EMAIL`, `BREVO_API_KEY`, `SMTP_FROM` (or `MAIL_FROM`), and the correct HTTPS `APP_URL`. Supabase supplies its URL/service-role environment. Never put secret values in Git or chat. This worker uses Brevo's API; existing password-recovery SMTP settings are unchanged.
6. Enable pg_cron/pg_net and create the two Vault secrets named in `supabase/manual/provider_reminder_schedule.sql`; manually run that optional schedule script. It refuses to replace an existing named schedule. Inspect job states and mail delivery in staging before enabling production reminders.

042 adds private `refund_cases` and `member_updates` tables, two notice triggers and scoped RPCs/wrappers. It extends the staff permission allow-list without granting existing staff either refund permission. 043 adds private `payment_verifications`, `verification_intervals`, `provider_reminder_jobs`, wraps subscription status/portal and adds a service-only reminder RPC. RLS and revoked direct/API execution protect internal records/functions. Existing original ledger entries and acceptances are not rewritten. Tenant purge retains its authorized cascading behavior; ordinary member removal remains deactivation with history retained.

## Financial behavior

Every adjustment references an original eligible credit/pass-payment ledger row or a later incoming wallet credit. Previously approved adjustments reduce its remaining eligible amount. Pending requests do not reserve money; approval rechecks the cap and wallets under locks and requires a fresh review hash. Two reviewers cannot approve the same case twice.

- Cash refund of wallet credit deducts the refunded amount from that wallet and records an external payout. Cash refund of a pass cash/wallet payment records payout without deducting money already spent from the wallet.
- Wallet refund of a pass payment credits the wallet. An existing top-up cannot be “refunded to wallet” a second time.
- Credit correction reverses erroneous wallet credit; an optional same-gym active recipient receives the correction atomically. No cash refund is implied. A spent balance cannot be driven below zero; the owner must resolve it explicitly. Incoming transfer notices do not expose the other member's identity.
- Refund approval does not automatically cancel a valid pass. The review screen states this; review membership separately.
- Member notices are inserted in the same transaction as successful top-ups/approved adjustments. Reading a status is separate from resolving it; gym approval/pass changes resolve the earlier status without marking it read. Login does not recreate an unchanged current status. Pending members receive their own account status, without opening general announcements beyond existing entitlement rules.

## Subscription policy

The owner must acknowledge the displayed `pending-review-v1` policy when first submitting a payment reference. A confirmed plan alone does not create provisional access. One unresolved request remains enforced by the existing workflow.

| Submission timing | During Provider review | Approval dates |
| --- | --- | --- |
| Before/on final covered day | Retain existing features; no unapproved upgrade | Full quoted paid duration after approval, or after already approved days, whichever is later |
| During paid grace | Dashboard only, including beyond grace | Original renewal due date; consumed grace counts. Automatically add Provider-review calendar days beyond grace |
| Already suspended/setup | No automatic operational restoration | Full quoted duration after approval; existing pilot/setup requirements remain |

Returned submissions have a 48-hour dashboard-only provisional correction window where eligible; existing approved access is preserved. Correction cannot reset the original submission timestamp. Missing that deadline ends provisional access; a later correction does not automatically restore it. Rejection/cancellation ends provisional access, but does not erase money records or perform a refund.

Compensation counts each distinct Philippine calendar date beyond grace that overlaps Provider review, **excluding any date overlapping owner-correction time**. This avoids counting the same date twice and conservatively excludes mixed correction/review dates. Example: paid-through Nov 10, grace Nov 11–17, submitted during grace, approved Nov 20, no corrections: **3 days added**, with reason “Automatic extension—delayed Provider approval.” Retrying approval returns the original result without another extension. A very long owner correction that exhausts the paid period requires a fresh agreed quote/payment settlement; it is not silently approved with no usable days.

The Provider reviews final dates and amount before confirmation. Original accepted price/policy/version are retained. Existing approved periods are never shortened. If another approved period changed a grace renewal's schedule during review, approval fails for deliberate resolution rather than silently overlapping periods. Existing submitted payments from before 043 remain on their existing review path; they are not automatically enrolled with an invented submission date.

First email becomes due after 24 hours and at/after 9 AM Philippine time; later daily jobs become due at 9 AM. The optional scheduler checks every ten minutes. One durable job per request/day prevents routine duplicate sends. Failed/ambiguous delivery is quarantined as `needs_review`, with a Provider-console notice; it is not automatically resent, because email and database completion cannot be one atomic transaction. A new daily reminder can still be created while verification remains pending. This is not a guarantee that external email will arrive. Mail failures do not suspend access, postpone approval or change compensation. Old uncompleted jobs are cancelled rather than sending a backlog of stale reminders.

## Database acceptance still required (user-run, staging)

Local tests use mocked services and SQL syntax/contract checks; they do not prove PostgreSQL installation, RLS or concurrent transaction behavior. The agent does not execute SQL, including locally.

1. Grant neither refund permission to staff; direct preview/list/request/approve calls must fail. Request-only can request/cancel own case but cannot approve; approve-only can review/approve but cannot request. Suspend/revoke each while its screen is open; the next action must fail. Cross-gym/source/member/request combinations must fail without writes.
2. Top up once, replay the same request ID and confirm exactly one ledger row/notice. Request partial cash/wallet refunds, review, change balance before approval, and confirm stale-review rejection. Re-review; approve; replay approval and verify one adjustment/notice only. Approve two cases concurrently against the same remaining source: the cap and wallet must hold.
3. Try over-refund, negative amount, non-finite amount, spent-credit reversal, refund-to-wallet of existing credit, inactive recipient, cross-gym target and duplicate payout approval. All must fail atomically. Correct a wrong-account credit; check both balances and both private notices. Confirm reports distinguish cash/wallet/correction without double-counting sales.
4. Settle remaining credit through cash refund, then deactivate the member. History and actor snapshots must remain; no unusable credit is issued to an inactive member. Existing zero-wallet removal still succeeds; nonzero removal stays blocked by the server.
5. Pending member sees Awaiting approval; reading keeps it visible. Owner approval resolves it without marking it read and shows Purchase a pass. Valid pass shows its end date. At expiry refresh, show Purchase a pass again without duplicate unchanged-status notices. Other members cannot read/acknowledge these notices.
6. Test reference submission before expiry, on expiry, during grace and after suspension; cross Manila midnight. Verify only current entitlements persist, full late periods/manual approval, original grace due date and three-day example above. Reject/cancel, test correction within/after 48h, and confirm owner-correction dates are excluded. Repeated approvals add no days. A new terms publication does not suspend an approved subscription.
7. Test reminders with a staging mailbox after setting submission timestamps for the test fixture: before24h none; due one/day; correction/rejected/approved none. Concurrent worker claims must not duplicate jobs. Simulate uncertain mail/completion; inspect quarantine and Provider notice before any manual resend. Never expose the job secret to frontend code.
8. On phone and desktop, check normal login, QR/manual entry, member purchases, staff revocation, report export and audience-targeted announcements. Test offline navigation on a previously online device, then Retry online. See `docs/offline-fallback.md` for first-visit/cache limitations.

## Existing safeguards reused

Existing financial request IDs, row locks, balance checks and server quotes address uncertain outcomes/concurrent transactions/price changes. Role revocation protects subsequent requests. Existing server date helpers use Asia/Manila. Archive restore review preserves backup scope; no automatic restore/deletion is introduced. Existing targeted announcement publication retains audience count and confirmation.

## Local validation completed

- 404 Node tests pass, including reports, notice persistence, SQL contracts, retry keys and mocked reminder transport failures.
- Real Chromium checks pass at 320, 375 and 1280 pixels for refunds (review/payout confirmation/history/sign-out), staff permission drafts/lifecycle/polling, owner payment-policy correction, Provider recomputed-date review and offline service-worker navigation. Existing subscription approval error/retry/success checks also pass at 375 and 1280 pixels. All backend responses are mocked or local.
- Both migration files and PL/pgSQL bodies parse successfully without execution. The optional schedule script is syntax-parsed only. Pages build, generated Dashboard consistency and whitespace checks pass.
- Live PostgreSQL authorization, concurrency, installation and real mail delivery are unverified until the user completes the staging checklist.
