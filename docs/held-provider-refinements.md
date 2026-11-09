# Held provider refinements: combined rollout

This batch includes the provider notification asset fix previously pushed separately. Deploy the combined branch, not the standalone notification branch.

## Manual SQL and deployment order

1. Confirm migrations through **051** are installed. Do not rerun 051 or earlier migrations blindly.
2. Manually execute the entire `supabase/manual/held_provider_refinements.sql` in Supabase SQL Editor once. It is identical to migration `202611100052_held_provider_refinements.sql`, uses a transaction, rejects duplicate installation, and checks the original pending-query text before changing it. The agent has not run live SQL.
3. Deploy the combined frontend, then reload open app windows. The provider manifest and page theme use dark navy; an installed application's OS title bar may require relaunch/browser manifest refresh to update.

## Intended functional effects

- The pending queue's SQL alias changes from `r` to `queue_row` only inside that SELECT. Payment/approval calculations, sorting, permissions, transactions and balances are preserved.
- The subscription portal keeps its existing implementation behind a private wrapper. Owners receive the latest document plus only their genuine previously accepted versions. Only the latest publication may be accepted, including through old clients or direct API calls. Historical versions remain readable, and existing receipts are not changed. The prior 30-day applicability rule remains unchanged and never fabricates acceptance.
- The owner paid-plan chooser uses server agreement eligibility after automatic applicability, instead of requiring a new explicit receipt. Initial unaccepted gyms remain ineligible. Quote/payment/approval authority stays on the server.
- Gym Terms & Privacy validation warnings list missing/invalid required fields and focus the first one. Valid details highlight Publish in the gym preset. A preview and checked review acknowledgment are still mandatory. Busy state prevents duplicate in-flight clicks; confirmed success opens a green message. Failed requests retain form values. No legal publishing database function is changed.
- Provider navigation groups Provider Details and Service Agreement Settings under Platform Details; Subscription retains its existing actions. Bullet decorations do not change accessible button names. Groups have no arrows. Notification script/style loading is fixed; messages stay compact until opened.
- Copying a gym link leaves its button content/size intact and briefly highlights it. Provider title-bar theme changes to dark navy; gym installation identity and scope are unchanged.
- The latest publication stays visible in provider history; older publications are in a closed disclosure. Draft functionality and historical records stay intact.

Existing approval previews may require review again after a publication is deleted, because the existing approval fingerprint includes the version catalogue. This protects stale approvals; it does not change completed approvals.

## Test-data cleanup boundaries

Provider-only cleanup requires selecting one publication, previewing its identifier and dependencies, confirming it is an unused test publication, and a second explicit permanent-deletion confirmation. The server repeats eligibility checks and protects the latest publication. All version foreign-key references and known subscription JSON snapshots block deletion, including Test-gym assignments/transitions, receipts, periods and requests. The preview names referencing gyms with Test/Live labels.

No related gym/account, payment, ledger, period, request, acceptance or transition data is removed. Referenced Test-gym records require a separate approved cleanup; this tool deliberately does not offer that cleanup. A publication being old or past its notice deadline does not by itself make it deletable. Collapsed history handles clutter when publications remain protected.

Eligible cleanup deletes only the unused service version and its publication-index row. A request-ID audit remains. A corresponding private source draft is retained, marked deleted and hidden from editing; its published pointer is cleared safely. No cascade is used. Retrying an identical successful deletion returns the recorded result; changed requests or stale previews are rejected.

## Validation

- `npm test`: 483 existing tests.
- `npm run build:pages` and `git diff --check`.
- Disposable PostgreSQL: `PGLITE_MODULE=/path/to/@electric-sql/pglite node tests/database/provider-agreement-workflow.cjs`. Runs 051 and 052 against the real historical function bodies, including actual pending-queue SQL; tests new-gym document visibility, historical acceptance restrictions, cleanup roles/dependencies/confirmation/stale previews/retries, and unchanged subscription periods and acceptance counts.
- Existing subscription approval/refund/upgrade/report tests: same environment variable with `node tests/database/subscription-management.cjs`.
- Mocked real-page Chromium tests: `tests/browser/held-provider-refinements.cjs`, `agreement-onboarding.cjs`, `provider-notifications.cjs`, `held-notifications-setup.cjs`, `provider-agreements.cjs`, and `phone-interface.cjs`. These do not contact live services or publish/delete real data.

After manual rollout, check the pending queue with a real pending request; new and existing gym version views; gym publication warning/review/success states; provider notification expansion/read state; and cleanup preview protection. Only perform a real cleanup on an explicitly selected unused test publication.
