# Coordinated held batch — all nine items

Prepared 2026-11-08 (Asia/Manila) on the user's explicit implementation instruction. No SQL, live payments, account changes, merge or manual deployment performed by the agent.

## Included

1. Top-ups obtain a server review before confirmation. It binds the request ID, actor, tenant, member, amount, wallet and top-up revision. Another committed top-up or changed wallet invalidates an old review. The rejection shows the latest top-up amount/operator/time. A separate legitimate payment needs a fresh review; no arbitrary 20-second block. Completed receipts replay before these checks, preserving unknown-outcome retry safety.
2. Refund sources show the purchased plan/expiry when linked immutable receipt data exists. Expired purchases remain eligible under unchanged server checks. Missing historical expiry, including unlinked legacy/split cash rows, is explicitly unavailable; the current member pass is never used to invent it. Fully refunded sources hide by default with Show fully refunded transactions available.
3. Notifications have Unread, Pinned / Status, and Read views. New unread activity is shown first. Individual Mark read actions persist exact recipient/revision state. Reading a panel no longer marks unseen items read. Relevant read status/pinned notices remain in their own view. Existing agreement acceptance and pilot dates are unchanged.
4. Closing Refunds prompts before discarding. Cancel retains entries; confirmed discard clears known unsubmitted drafts, not pending/history or unknown-outcome request identities. Escape follows the same rule; auth cleanup still closes immediately.
5. Reason preset and optional Other text precede Amount.
6. Announcement recipient search keeps selections across searches, shows a count and offers selection review/removal.
7. Date presets show a single selected state. Manual calendar changes clear it, including phone custom-date edits before Apply.
8. Reports Back is an icon with a screen-reader label and 44-pixel touch target.
9. Revenue Today has its own staff checkbox, off by default. The server returns only today's membership-sales total for the authorized gym. Granting this metric does not grant Reports, exports, member financial amounts or transaction rows. The dashboard uses the same Revenue Today aggregate at all widths; top-ups are not added again as sales.

## Manual SQL and deployment order

1. Review [046](../supabase/manual/pilot_topup_reviews_ui.sql). It requires confirmed 045, adds private top-up review/revision tables, wraps existing payment/staff/refund RPCs, and adds aggregate-only Revenue Today access. Review records expire after ten minutes; expiry does not delete financial records. It does not change pass prices, refund eligibility, existing balances, ledger history, subscription dates or prior receipts.
2. Manually run the entire file once, including BEGIN/COMMIT. Do not run both the manual and numbered copy. The guard prevents reapplying. No Edge Functions or secrets need updating.
3. Deploy the matching reviewed frontend and refresh all open admin/staff pages. Until refreshed, older clients cannot initiate new unreviewed top-ups; this is intentional fail-closed enforcement. Coordinate deployment before collecting cash. Purchases/check-ins remain on their existing paths.
4. Configure the separate Revenue Today staff grant deliberately. Existing report grants are preserved, but do not automatically acquire the new metric grant. Reports remains independently controlled.

Previously committed payment receipts remain retryable without a new review. A legacy unresolved request with no confirmed receipt must be reconciled; do not erase its ID or create a replacement blindly. Cancelled/unsubmitted review IDs can be discarded safely. The new private review/revision tables follow member/tenant deletion via foreign keys; no existing financial/history cleanup is performed.

## Validation

- 430 Node tests pass, including real client review/retry state against modeled concurrent outcomes, grant isolation and notification read-state behavior.
- Local Chromium suites cover refunds and both 045 capabilities, actual top-up controls, staff lifecycle/permissions, recipient search persistence, historical expiry/exhaustion filtering, reason order, native discard/cancel, notification views, date presets/Back icon, registration/navigation, subscriptions, offline recovery and phone workspaces.
- The standalone parser accepted 21 SQL statements and all five PL/pgSQL bodies without any database connection/execution.
- Pages build, generated Dashboard consistency and whitespace checks pass.

SQL parsing/static checks and mocked tests do not prove actual PostgreSQL concurrency or permissions. Complete the manual acceptance below after migration/deployment.

## Acceptance checklist

- Two operators open a ₱100 top-up confirmation for the same dummy member before either confirms. First confirms once. Second must be rejected with intervening payment details; only ₱100 credited. For a genuinely separate payment, reopen review and confirm; total ₱200. Verify records and actor attribution.
- Repeat original request after an uncertain response in controlled testing: same receipt, no extra credit. Do not deliberately disconnect a real payment or clear request storage to test this.
- Cancel a top-up review, then perform another ordinary operation: no leftover submitted-payment lock. Let a review expire: it requires fresh review, with no credit from expiry.
- Staff with only Revenue Today sees the metric but cannot open Reports/export or fetch raw financial rows. Revoke the grant: metric hides and aggregate RPC denies access. Other-tenant and suspended accounts are denied.
- Refunds: an expired purchase is labelled from its historical receipt; an unavailable expiry is labelled unavailable. Exhausted sources are hidden until Show all. Server still rejects excess refunds and unsafe corrections.
- Enter a refund draft; Close/Cancel retains it; Close/Discard clears it. Submitted/uncertain requests retain safe retry identity. Review/Edit still preserves entries; reason fields appear above Amount.
- Search for recipient A and check; search B and check; search A again: checked state persists. Review/remove selected recipients before publishing; targeting isolation remains intact.
- Unread activity is visible despite older pinned/status items. Mark one read: badge clears for that item only; it appears in Read or Pinned/Status, including after refresh. Another account retains its own unread state. Read failures preserve unread status.
- Select each report preset: only that button highlights. Edit either calendar date: none highlights. Back shows only an arrow, retains an accessible label, and returns to the appropriate dashboard.

The investigated pilot-notice concern is excluded: Provider activation fixes the period, counted days start the following Philippine day, and reading the notice does not reset the pilot.
