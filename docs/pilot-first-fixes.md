# Pilot first-priority fixes

## Scope

User-authorized first batch, 2026-11-08 (Asia/Manila). No SQL, financial policies, RPC arguments, database queries, role permissions or Edge Functions changed.

- Quick cash amounts now populate the custom amount input. Add Funds is the single route to confirmation. Disable top-up controls before awaited authorization/confirmation and prevent overlapping clicks. Preserve the amount after cancellation or uncertain outcomes; clear it only after a confirmed transaction. Existing stable financial request IDs and server eligibility/receipt checks remain in use.
- Refund member and corrected-recipient search display clickable matches for name/member ID, with an explicit empty-result message. Retain the select control and selected member rather than silently switching accounts when typing.
- Refund errors display a modal over the active form/review without clearing it. Uncertain submitted outcomes explicitly warn that the action may already exist and instruct checking Pending review/History before retrying, creating replacements or paying cash again. Authentication cleanup closes all dialogs.
- Show an advisory warning for other pending cases against the same source in the form and review. This uses the existing list snapshot; it is not a reservation or a guarantee that another operator has not submitted a new case. Existing server approval validation remains authoritative.
- Remove the launcher link from the fallback. Retry captures/reuses the current original URL; no tenant/account data is stored or cached. Bump the public offline cache to v2 so old launcher links are replaced when the updated worker activates. Existing offline clients must reconnect to receive the update.

## Validation

- Full Node suite: 413 tests passed.
- Local Chromium at 320/375/1280: visible exact/partial-name and ID search, retained member selection, no-match feedback, pending warning, definitive/uncertain error dialogs, form preservation, committed-request response loss and same-ID retry, sign-out cleanup, actual quick-cash markup/handlers with delayed confirmation, double-click blocking, cancellation, and uncertain top-up retry without a second mocked credit.
- Existing refunds, offline fallback, three-defect, pending-payment and saved-issues browser suites pass. Subscription review passes at its configured widths. Staff-access browser verification uses the existing temporary Tailwind CSS prerequisite.
- Offline browser checks cover query/hash-preserving gym login/dashboard retry, readable gym slug retry, repeated offline retry, public-only cache, no launcher links, HTTP errors and first-ever offline visits.
- Pages build, generated Dashboard-function consistency and whitespace checks pass.

No live member/account/financial mutations were performed by the agent. Mocked tests do not replace a controlled deployed smoke test or a live database concurrency test. No merge or manual production deployment authorized/performed.

## Post-deployment smoke checks

1. Quick ₱100 fills the amount; Add Funds opens one review. Cancel preserves the value. Confirm one dummy payment and reconcile one record.
2. Search refund members by partial name and ID; click the visible match and verify the review recipient.
3. Trigger an invalid refund amount: a visible dialog appears; dismissing it preserves input.
4. With one dummy request pending, review another draft for that source: see the warning; discard the second draft and cancel/reject the first afterward.
5. Refresh online to receive the updated worker, go offline at a gym URL, verify no launcher link exists, reconnect and Retry: remain in that gym.

All remaining pilot proposals stay in [the held review batch](issues/pilot-held-review.md).
