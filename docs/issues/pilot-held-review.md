# Pilot held review batch

Recorded: 2026-11-07 (Asia/Manila). Hold these items for a combined review. Recording them does not authorize implementation, SQL, deployment or changes to email services.

## Current disposition — 2026-11-08 (Asia/Manila)

### Current execution-review shortlist

This shortlist supersedes the historical proposals below. It is a review, not execution authorization.

Subsequent status: the user explicitly authorized implementing all nine together. They are implemented on `fix/pilot-held-ui-topup`, with manual 046 prepared but not executed. See [coordinated rollout and acceptance](../pilot-held-batch-rollout.md). The historical holds below are retained for traceability, not a claim that the implemented items are still unstarted. The pilot-notice concern remains excluded.

1. Simultaneous top-up safeguard: server-validated reviews tied to current member financial state; block outdated confirmations with intervening payment details; permit deliberate fresh review for a separate payment; replay committed request receipts before stale-review checks. Highest priority. Prepare manual SQL only after designing its interaction with existing APIs/clients.
2. Historical pass sources in refunds: keep eligible expired purchases, label purchased pass validity from historical evidence, show purchase/expiry details where known, and hide exhausted sources by default with a show-all control. Never infer historical expiry from current membership. Schema needs depend on available historical data.
3. Notification layout: Unread first, separate Pinned/Status and Read views suitable for phones; retain relevant read status notices and preserve per-user read state. Merge this with the earlier read/unread proposal rather than implementing twice.
4. Refund draft discard confirmation: cancel closing preserves work; confirmed closing clears unfinished form drafts only, never pending/history or unresolved financial request identities needed for safe retries.
5. Reason preset above Amount; custom reason appears only for Other.
6. Announcement recipient search preserving checked selections across searches, with selection count/review.
7. Report preset highlighting; clear preset highlights after manual calendar edits.
8. Reports icon-only Back button with accessible label and phone touch target.
9. Separate Revenue Today permission: review server enforcement and a scoped aggregate response; granting only this metric must not expose full financial reports or transaction rows. Manual SQL likely needed.

The user confirmed manual 045 succeeded and reported live passes for the implemented count/refund/account fixes. Treat earlier failure descriptions as history, not automatically outstanding work. Email reset entry-point coverage remains a testing clarification, not a new confirmed defect. No automatic change to Reports history or owner/staff session lifetime is approved by accepting observed navigation behavior.

### Excluded pilot-notice concern

The user confirmed TEST GYM's counted period remained November 8–21 after Provider activation on November 7. The bell stopped swinging after the owner confirmed the notice. Source inspection shows access begins on activation day, counted pilot days begin the following day, and reading the notice does not reset entitlement dates. At the user's request, exclude this from implementation: no demonstrated indefinite-pilot bypass and no countdown or notification change for this concern.

The user subsequently authorized proceeding with the other fixes. The announced first batch is limited to quick-cash interaction, visible refund search results, refund error dialogs, an overlapping-pending-request warning, and gym-specific offline recovery. These frontend changes are implemented on the review branch; merge/manual deployment still requires user review. See [first batch details](../pilot-first-fixes.md). Other proposals below remain held.

Email delivery was traced to Brevo API authentication (401), followed by insufficient Transactional email permissions (403). The user corrected the API configuration and confirmed member and staff recovery worked, including password change/sign-in. No application change or SQL was needed for that resolution. The earlier observations below are retained as history, not outstanding delivery failures.

Deployed function definitions supplied by the user confirmed payment receipt replay/locking and refund approval-time eligibility checks. Mocked lost-response/retry tests pass. This is not a live database concurrency execution test.

The public live offline trace reproduced the navigation sequence: Retry alone kept the gym URL; opening the launcher while offline moved the URL to `/`, and a later Retry loaded Command Center. Both deployed fallback assets matched source. No Super Admin authentication bypass occurred.

The user then instructed continuing and implementing the next batch. Active Passes, signed-in own password changes and clearer authentication warnings are implemented for review. Generated cash payout references, cash member notices and rejected-refund member notices are prepared behind migration 045 capability detection; the agent has not executed it. The user must manually apply 045 before those database features are active. See [second-batch rollout](../pilot-second-fixes.md). Remaining UI proposals (discard confirmation, reason ordering, recipient search, date highlighting, unread/read views and Revenue Today permission) remain held.

## Staff email delivery and password recovery failure

User-reported TEST GYM results:

- Owner edited the dummy staff email to an inbox the user described as verified.
- The interface reported “Email delivery failed”.
- Reopening/checking the staff record showed the new email: the edit persisted despite the delivery error.
- Owner-triggered “Send password recovery” also failed.
- Staff password-reset testing is blocked; successful delivery or recovery is not established.
- Member password recovery: user reported no email received, although this had worked previously. Delivery remains unverified; spam/junk checks and elapsed delivery time were not confirmed. Hold this with the staff recovery issue, but do not assume the same root cause without logs.

Review the application error handling and recovery flow alongside Supabase Auth/email-provider logs and configuration. Determine which operation committed before the error; avoid reporting a saved edit as entirely unsuccessful or encouraging repeated submissions. Do not assume a code defect or an external-provider cause without evidence. Do not record credentials, reset links or tokens.

## Confirm discarding unfinished refund drafts

Requested for later implementation: show “Discard unfinished request?” when closing Refunds with unfinished work. Preserve Review → Edit values and separate member drafts while the window remains open. The user prefers clearing unfinished drafts after confirmed closure. Submitted requests must remain in Pending review/History.

## Separate Revenue Today permission

Requested for later review: expose Revenue Today as a separate staff permission. The user clarified that it was missing from the permissions list, not necessarily missing from the dashboard. Reports & Analytics permission successfully enabled access to TEST GYM financial figures; removing it hid the reports menu again. Review the intended relationship with financial-report access before proposing implementation or database changes.

## Related warning-message issues

See [authentication warning messages](pilot-authentication-warning-messages.md) for “Invalid request” during suspended-staff sign-in and “Reporting access: Please sign in again” after admin logout/Back. Keep these in the same later review batch.

## Offline fallback returns gym users to the provider launcher

- User-reported live test: disconnecting displayed the “Connection interrupted” fallback with offline status and the payment/check-in uncertainty warning.
- While disconnected, neither navigation button restored the app; after reconnection, the user reported that both “Retry this page” and “Open project launcher” led to the Command Center rather than TEST GYM's portal.
- The user explicitly confirmed Super Admin still required email and password. No unauthorized Super Admin access was demonstrated. Classify this as recovery-navigation/context loss and unwanted provider-launcher exposure, not a confirmed authentication bypass.
- Hold as a priority review item. Proposed remedy: preserve the original gym destination and tenant context during retry and remove provider-launcher navigation from gym fallback pages. Verify the actual retry destination and fallback/cache behavior before implementing; root cause is not yet established.
- Later regression checks should cover offline → reconnect → retry from a tenant login/dashboard URL, preservation of gym context, absence of provider-launcher links in gym fallback pages, and continued enforcement of Super Admin authentication. Do not include credentials or tenant-link tokens in the issue record.

No implementation is authorized by saving this issue.

## Member notice when a refund request is rejected

- Live-test observation: the user found no member notification for the earlier rejected ₱20 refund request. The wallet remained unchanged. Whether the existing workflow promises such a notice has not been verified in code; do not classify this as a confirmed delivery defect yet.
- Held proposal: send the affected member a simple in-app rejection notice linked to the request, showing the amount, permanent request reference, rejected status and confirmation that their wallet balance did not change.
- Include a member-facing reason where appropriate; do not automatically disclose internal administrator notes. A default “Contact the gym for details” message is acceptable when no suitable public reason is provided.
- Preserve original request, rejection decision and audit history. No email is required for the pilot proposal. Review existing notice support, tenant/recipient isolation and duplicate prevention before implementation.
- Suggested checks: exactly one notice reaches the affected member after a successful rejection; no notice is sent for a failed decision; other members/staff do not receive it; wallet and financial reports remain unchanged; internal notes stay private.

Held for later review only; no implementation or database changes authorized.

## Overlapping pending correction requests

- User-reported test: after leaving one correction request pending against an eligible top-up, opening review for a second request against the same transaction showed no pending-request warning.
- The second request was not confirmed as submitted or approved. This observation does not establish that duplicate refunds or transfers can be approved. Existing server-side approval checks and pending-amount reservation behavior remain unverified for this scenario.
- Held review: determine whether to display an existing-pending-request warning and verify server-side eligibility checks, concurrent approval protection, and prevention of total approved corrections exceeding the eligible source amount. Do not assume reserving pending amounts is required before reviewing current behavior and policy.
- Suggested regression cases: two requests for the same source; sequential and concurrent approval attempts; retry of an uncertain approval; rejection/cancellation preserving or releasing eligibility; no duplicate wallet movements, cash impact or member notices.
- User confirmed cleanup: the second draft was discarded and the first pending test request rejected.

Held for review only; no code, financial policy or database changes authorized.

## Additional mock-trial notes (all 11 consolidated)

1. Generate a permanent cash payout reference on successful approval. Keep distinct from the refund request reference; reuse it on retries, not a fresh reference per attempt. A generated reference identifies a recorded payout and does not prove physical cash delivery. Review storage/API impact first.
2. Include the cash payout reference in successful cash-refund member notices and permanent history. Keep wallet destination wording distinct.
3. Refund member search: user reports searching an existing member's name returns no match. Reproduce and inspect before classifying root cause. Support selectable name/member-ID matches, partial names and preserved selection through Review → Edit; maintain tenant isolation.
4. Refund errors: show a visible dialog instead of relying on an error above the scrolled form. Preserve input and distinguish confirmed rejection from uncertain outcome. Uncertain financial outcomes must direct users to check status before retrying.
5. Move Reason preset above Amount; show editable reason only for Other.
6. Active Passes discrepancy: user reports four members, three with active passes and one without a selected plan, but dashboard shows four Active Passes. Inspect the count definition, validity/expiry and source data before confirming a defect. Distinguish approved accounts from valid passes.
7. Staff quick-cash top-up: selecting the ₱100 quick amount and Add Funds briefly showed an amount-validation warning, then confirmation and one successful credit. No duplicate credit observed. Investigate event timing and validation; ensure one submission and consistent amount.
8. Announcement recipient search: add member search for individual/multiple recipients; checked recipients must persist across different searches. Provide a selected count and review/removal without losing selections.
9. Report date presets: highlight only the selected Today/Last 7 Days/This Month/All Time preset; clear preset selection when the calendar range is manually edited.
10. Signed-in admin/staff own password change under My Account, like members. Review existing support and reauthentication/session requirements first. Do not confuse this with email-based recovery or permit changes to others' passwords.
11. Notifications: requested separate read/unread views, unread first. Proposed phone-friendly presentation is Unread/Read tabs with counts rather than side-by-side columns; preserve notices and per-user read state.

## Additional verification and performance observations

- Lost-response financial retries: live normal submission/double-tap tests did not simulate a server commit with a lost response. Verify existing request-ID retention and server idempotency with controlled automated tests, including concurrent requests; do not assume a new defect or rewrite working logic without evidence.
- Staff announcements arrived automatically after approximately 6–7 seconds in two observations; members received them sooner. No missing notice observed. Review expected polling/connection behavior only if faster delivery is needed.

## Proposed execution order (review only)

1. Highest: verify lost-response retries and overlapping approvals; investigate quick-cash contradictory validation and refund search; make financial errors visible without unsafe retry guidance.
2. High: restore reliable recovery-email delivery/error reporting and gym-specific offline recovery navigation.
3. Next: verify/correct Active Passes semantics; design stable generated cash payout references and corresponding notices/history.
4. Then: rejected-refund notices, signed-in own password change and clearer authentication warnings.
5. Finally: discard-draft warning, reason ordering, recipient search, date highlighting, unread/read views and separate Revenue Today permission.

These priorities do not authorize implementation or change financial policies. Inspect actual code and schema first; separately explain and obtain approval for any database-affecting change. Do not execute SQL. Keep unrelated deferred ideas outside this batch.

## Later mock-trial additions — held before implementation

The user's latest instruction is to save the following changes first and review simultaneous top-ups before implementing anything further. Earlier inline “implement this” annotations are subject to this explicit hold.

- Expired-pass refund display: retain eligible historical purchases for owner-reviewed refunds, label expired pass purchases using the purchased pass's historical validity (not the member's current pass), show purchase/expiry details where available, and mark missing historical expiry as unavailable rather than inventing it. Hide fully refunded sources by default with an explicit show-all option; preserve history and server eligibility checks. Inspect available historical purchase data before designing any database changes.
- Notification organization: Unread first, with separate Pinned/Status and Read tabs or collapsible sections suitable for phones. Reading relevant membership-status notices clears unread state without removing current status. Keep new unread notices immediately visible. Preserve per-recipient read-state isolation.
- Reports Back button: icon-only back arrow with accessible “Back to dashboard” label and adequate phone touch target; held with the interface batch.
- Top-up cancellation clarification: the member/amount confirmation with Cancel and Confirm top-up does appear. Cancel returns to the member top-up form, preserves the amount, and requires no separate cancellation notification. User confirmed pass.
- Rejection clarification: rejection is blocked when the internal reason is blank, as intended. User did not report failure with a populated valid reason.

### Simultaneous top-up review (not implemented)

User reported that an owner and staff member each independently confirmed a top-up to the same member at approximately the same time; both credited. These are distinct transaction requests, not demonstrated duplicate replay of one request. Existing member-row locking serializes writes but does not establish that two operators received only one cash payment.

User proposed a 20-second block. Review a stronger confirmation check: bind a server-validated review to the member's current financial state, and invalidate a second operator's old review when a top-up is committed. Return the intervening payment's amount/time/operator and require fresh review before a separate payment. Keep completed-request receipt replay ahead of stale-review checks so retries remain safe. An in-progress lock alone is insufficient if the second payment runs after the first commits. No arbitrary delay or automatic deduplication of equal amounts is approved. A second legitimate payment must remain possible after deliberate fresh review. Investigate exact implementation and migration needs before seeking execution approval.

The user subsequently accepted the plain-language workflow and instructed adding it to the implementation plan before raising another inquiry. Planned behavior: first confirmed top-up succeeds; a second outdated confirmation is blocked with the intervening transaction details; a genuine additional payment needs a fresh review; an exact committed-request retry returns its receipt without another credit. This is accepted plan scope, not authorization to execute now. No code or SQL for this safeguard has been prepared or executed.
