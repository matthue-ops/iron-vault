# Gym subscriptions, owner onboarding and service documents

## What changes

Two per-gym plans: Dashboard Only (default PHP 999) and Dashboard + Member Portal (default PHP 1,800 total). A first 14-day full-feature pilot requires registered-owner service-document acceptance, published gym/platform member documents and explicit Super Admin activation. Prices, durations and document fields start as editable drafts. No documents are published or periods activated by installation.

All existing gyms enter setup-only access on installation. Their records, credentials, balances, attendance, existing legal versions and acceptance records remain intact. Setup allows the registered owner to complete legal details and billing. Staff/operational and member access is blocked until activation. Plan checks run in the database; browser controls are supplementary.

## Manual rollout order

1. Confirm migrations through **034** are installed in the gym Supabase project. Back up using your normal project process.
2. Run **`supabase/manual/gym_subscriptions.sql` once in the SQL Editor**. It is the exact copy of migration `202611050035_gym_subscriptions.sql`; do not run both. The agent never executes SQL, including against a local database. Reapplying is intentionally rejected.
3. For the improved subscription-specific Edge error messages, update the five generated dashboard entries from `supabase/dashboard`: `iv-create-member`, `provision-gym-tenant`, `iv-admin-correct-member-email`, `iv-branch-auth`, `iv-purge-tenant`. Keep existing environment secrets. Verify JWT stays **OFF for iv-branch-auth**, **ON for the other four**. The existing Edge RPC names and provisioning behavior are preserved; these bundle changes only add safe IV003 diagnostic text. Do not replace APP_URL/CORS settings with example values.
4. Create/review the PR, then merge and let Cloudflare build. Refresh open sessions. Do not deploy the frontend before SQL: the owner screen deliberately fails closed when the subscription APIs are unavailable.
5. Super Admin opens **Service Agreement Settings**. Complete actual identity/address, support working days, tax/payment instructions, service providers/regions, refund/outage policies, backup/retention/deletion procedures and liability terms. Defaults are not a legal compliance certification. Matt Hue must accurately identify the actual individual provider. Do not claim a registered company or address that does not exist.
6. Save draft, preview all three documents, review, and publish only when ready. Initial publication can be effective today in Philippine time. Later publications require at least 30 days notice; price increases must satisfy any longer currently promised notice too. Unresolved fields intentionally block publication.
7. The registered owner opens the new bell / Subscription & Billing panel, publishes their gym documents and explicitly accepts the appropriate service version. Platform member documents must also be published through the existing legal editor. Super Admin reviews eligibility and activates the first pilot through **Gym subscriptions**.

No SQL, Edge deployment, merge, live payment, pilot activation or agreement publication is performed by the agent. Existing gyms are not automatically given free days. A missing original-owner binding blocks activation rather than assigning billing to staff; review the account mapping using the existing account-management process.

## Dates and entitlements

All calculations use database time in Asia/Manila, not the browser clock. Activation opens access immediately; counted pilot/ordinary new paid days start tomorrow. Day counts are inclusive: approved Nov 5 -> pilot Nov 6–19 -> an early approved paid period Nov 20–Dec 19. Early renewals preserve remaining days. During paid grace, renewal starts at the original renewal date; after suspension it starts counting tomorrow, with immediate approval-day access.

Current paid expiry gets the recorded grace days (default 7), with dashboard only. Pilot expiry gets zero grace. After final access, owner reporting/export lasts the recorded export window (default 30 days); billing and own legal/subscription history remain available. Data is preserved. Retention-review dates and owner notices are provided, but this release does **not automatically erase records or infrastructure backups**. The published deletion procedure must describe the actual manual review/deletion process and any lawful holds. Do not publish a stronger automatic-deletion promise.

A downgrade approval records the next plan and effective date but does not create a free paid period. Renewal payment is still required. Upgrades prorate the recorded plan difference over remaining counted days and retain expiry. New quotes require renewed owner confirmation if dates, price or agreement version changed. Future approved periods retain their policy snapshots even after new service publications.

## Approvals, billing and notifications

Owner accepts service/DPA documents and acknowledges the Privacy Notice; this is separate from member legal acceptance and from an exact paid-plan confirmation. Receipts snapshot gym/owner identity, version and timestamp. Super Admin verifies external payments and records the reference; no automatic charging or actual refund transfer is performed by the app. Cancellation/refund issues are handled through published billing contacts/policies; extensions are the implemented in-app service-credit mechanism. Payment references must identify an actual unique receipt, not a generic repeated word such as “cash.”

Approvals and extensions use request IDs; completed retries do not add another paid period or extension. Duplicate payment references are rejected per gym. Reasoned extensions preserve approval history and reschedule future reminders. One pilot is enforced per tenant; the Super Admin eligibility checkbox additionally requires manual verification that the same business has not already used another tenant's pilot.

Onboarding, welcome, service-version, payment, start, reminder (7/3/1), expiry/grace, suspension and retention-review notices are persisted only for the fixed registered owner. Future notices have Philippine availability timestamps and become visible even if the owner was offline; no browser must remain open. They are in-app notices, not email/push delivery. Superseded future period notices are hidden after renewal, never erased. Staff receive operational access explanations, not private billing histories or legal-acceptance controls.

## Server enforcement and compatibility

New private tables use RLS and no direct browser/service-role grants. Public billing/document RPCs require exact registered-owner or enabled global Super Admin authority. Only owner acceptance is allowed; Super Admin cannot accept for the owner. Member login lookup, public signup/operator provisioning, daily tickets, QR attendance, member-data reads, money/attendance writes, staff management and announcements are covered by entitlement checks. Existing approval, member Terms, membership, balance, tenant isolation, report permissions and transaction-receipt safeguards remain in force. Existing member sessions lose private access at entitlement expiry. Manual service does not require member Terms acceptance.

The existing member legal documents are not replaced by tenant service documents. Provider/gym field guidance supports hover, focus, click and phone tap. Draft text changes do not silently change operational algorithms: duration/price fields control future quotes; more extensive behavioral policy changes require corresponding implementation review before publication.

## Required post-install verification

The automated suite uses source contracts and mocked browser/RPC responses. SQL and PLpgSQL are parsed **without execution**, so these are not database integration tests.

On test gyms after manual installation, verify:

- Owner sees setup, can edit/publish gym legal details, and cannot register/admit/top-up before activation. Staff and members cannot bypass with existing credentials or direct RPC calls.
- Staff and a different gym owner cannot retrieve billing or accept service agreements. Original owner email changes do not change the notification recipient account ID.
- Missing requirements prevent activation. Owner acceptance records exact gym/owner snapshots; no pilot clock starts until Super Admin approval.
- First pilot activates once; a repeated activation request cannot add another pilot. Check tomorrow's counted start and inclusive end.
- Owner confirms an exact quote; early pilot payment starts after pilot. Compare normal, early, grace and after-suspension renewal dates. Reject stale quotes.
- Retrying the same payment/extension and reusing a payment reference cannot grant duplicate days. Run concurrent approvals on a staging project to verify row locks and rollback behavior.
- Dashboard plan and grace permit manual service but reject member login/QR/self-service, including old sessions/tickets. Paid plan does not remove pending/member-Terms restrictions.
- At the first day after grace, operations fail server-side. Owner read-only reports/exports remain available only for their allowed window.
- Scheduled notices appear once, stay readable after offline periods, and old future expiry notices are superseded on renewal. Registered-owner-only bell counts remain private.
- Draft saves do not change published versions. Publishing price changes early is rejected. Previously accepted versions/approved future prices stay intact.

Do not move the production clock or rewrite existing business records to simulate dates. Use controlled test periods in a separate staging project and review outcomes before real billing.
