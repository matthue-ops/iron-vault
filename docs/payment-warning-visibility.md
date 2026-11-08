# Payment warning visibility

The user confirmed the deployed simultaneous-top-up test: two reviews opened at a starting balance of PHP 300; first confirmed payment increased the balance to PHP 400, and the second review was rejected. The warning appeared only briefly. This follow-up changes presentation/error classification, not financial policy or database behavior.

- A definitive outdated top-up review (`IV004`, without a prior unresolved outcome) remains visible for six seconds with a Close button. It may be dismissed earlier.
- Unknown payment outcomes remain open until acknowledged. Background notifications cannot replace them, and another payment confirmation cannot open over them. Explicit sign-out/account change still clears private dialog content.
- Errors carry typed code/uncertainty metadata to the existing admin top-up/purchase UI. Transport failure, mismatched response identity and unresolved earlier outcomes remain classified as uncertain; request IDs and receipt-replay behavior are preserved.
- Ordinary success/validation notices retain the existing two-second behavior; payment confirmations still require an explicit decision.

No SQL or Edge Function change required. 434 Node tests pass, with local Chromium checks at 320/375/1280 for six-second timing, early Close, persistent uncertain outcomes, unchanged confirmations, sign-out cleanup and prior top-up/retry behavior. Tests use controlled timers/mocked services; no live payment was made by the agent.

## Remaining live acceptance from 046

The simultaneous stale-review financial check has passed. After reviewing/deploying this follow-up, verify the warning remains readable for six seconds and Close works. No need to repeat already-passed financial mutations just to time the popup.

If not yet covered, complete the remaining [046 checklist](pilot-held-batch-rollout.md):

1. A fresh review for a genuinely separate payment works; another member's top-up is unaffected.
2. Expired historical refund sources remain selectable, unknown history is labelled unavailable, and exhausted sources show only with Show all.
3. Close/Cancel retains refund drafts; Close/Discard clears known unsubmitted entries; pending/history stay intact. Reason precedes Amount.
4. Announcement selections persist across different searches and can be reviewed/removed before publishing.
5. Unread is first; read notices persist in the appropriate Read or Pinned/Status view, with independent account read states.
6. Date presets highlight exclusively, calendar changes clear them, and the Back icon works on phone/desktop.
7. Staff with Revenue Today only sees the aggregate but not Reports/export/raw financial rows; revocation hides/denies the metric.

Real lost-response and database concurrency verification require controlled testing, not repeated manual real-money submissions or clearing request storage. The pilot-countdown concern stays excluded.
