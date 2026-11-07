# Pilot held review batch

Recorded: 2026-11-07 (Asia/Manila). Hold these items for a combined review. Recording them does not authorize implementation, SQL, deployment or changes to email services.

## Current disposition — 2026-11-08 (Asia/Manila)

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
