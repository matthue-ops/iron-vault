# Provider agreement workflow: database changes for approval

The requested workflow cannot safely be implemented as UI-only changes. Existing `service_versions.data` stores operational plan prices/durations with the agreement; renewal quotes and approval previews read that payload. The current selector is global and date-based. The existing draft is a single `service_settings.draft` record.

The proposed migration will:

1. Add a private versioned draft library containing each set of three pasted documents, a name/version, last-saved time and revision. Migrate the existing saved draft without publishing it. Provide provider-only create/read/edit/preview/delete operations. Draft deletion cannot delete a published version or acceptance record.
2. Add private per-gym agreement applicability/transition records. Existing gyms keep their applicable earlier version until explicitly accepting a newer one or reaching its publication-plus-30-day deadline in Philippine time. New gyms receive the newest published version at registration. Multiple publications must never make a gym revert to an older version. Deadline application is recorded separately from explicit owner acceptance; it must never insert a false acceptance record. Reading a notice does not change either state.
3. Add independent, revisioned operational subscription settings, seeded from the existing applicable configuration. Pricing/durations and related billing controls can be saved without publishing documents. Preserve existing price-change notice protections. Existing approved periods and requests keep their original policy/amount/date snapshots; no ledger, member balance, approved plan or acceptance history is rewritten.
4. Add/wrap provider draft/settings and agreement-selection APIs. Keep registered-owner-only acceptance, provider-only publication/settings control, existing Gym Terms prerequisites and manual pilot approval. Update future quote/approval paths to use the intended settings and applicable agreement independently; test stale previews and duplicate requests.
5. Return transition notices as pinned until accepted or the deadline has applied, and pending subscription requests as pinned provider notices until the request is acted on. Read receipts clear unread indicators without resolving either pending action. Notifications and deadlines must not depend on the owner opening the app or reading a notice.

No SQL will be executed against the live Supabase instance by the agent. The migration and identical manual copy will be prepared for review and manual execution after approval, with prerequisite/compatibility guards and disposable PostgreSQL tests. Financial, attendance, refund, member-login and installation behavior remain outside the change.

Frontend-only work staged so far: uniform four document controls, initially collapsed document content, enabled unchecked acknowledgment, agreement-only initial gym navigation, and grouping existing pending/payment/report actions under Subscription. These are not deployed and the full batch will not be published as complete before the database behavior is implemented and tested.

## Implemented rollout

The database changes above were approved in chat. Migration 051 and its identical manual copy implement the private draft library, independent subscription settings, and per-gym agreement transition. All validation here uses a disposable embedded PostgreSQL database and mocked browser services.

1. Confirm migrations through **050** have already been applied. Do not skip existing migrations or rerun them blindly.
2. In Supabase SQL Editor, manually execute the entire `supabase/manual/provider_agreement_workflow.sql` file once. It runs in a transaction and refuses duplicate installation or unexpected prerequisite function bodies. Do not run snippets individually. The agent has not run this SQL against Supabase.
3. Deploy this frontend only after 051 succeeds, then reload existing open application windows. The old document save/publish endpoint deliberately rejects outdated clients, preventing prices and documents from becoming coupled again.
4. Check provider Service Agreement Settings: imported saved draft, New draft, edit/save/preview, confirmation, publication and published history. Only unpublished drafts can be deleted; deletion hides the draft without destroying its stored record.
5. Check provider Subscription submenu: prices/settings, pending requests, payment options and reports. Changed prices require the existing advance-notice interval (at least 30 days). Operational settings do not publish legal documents; approved periods retain frozen amounts/dates/policies.
6. Check an existing gym: its previously applicable terms remain until explicit acceptance or the new publication's 30-day deadline. Reading the pinned notice only records reading. Automatic applicability is separately labeled `effective_after_notice`; it never creates an acceptance receipt. Later accepted publications cannot revert when an earlier deadline arrives.
7. Check a newly registered gym: newest published documents, agreement-only initial window, four aligned controls, initially closed document body and enabled unchecked acknowledgment. Gym Terms completeness and manual provider pilot approval remain mandatory. Acceptance alone does not start the pilot.
8. Check pending provider notices remain pinned after reading and stop being pinned once the actual request is acted on. Read notifications remain compact until opened.

Document publication is immediate in Philippine time. Existing-gym deadlines are publication day plus 30 calendar days, evaluated by the server independently of app visits. There is no new background job and no false acceptance insertion. Historical publications and genuine acceptance receipts are preserved. Existing legacy draft source is retained privately alongside its imported rendered documents. No financial, attendance, member-wallet or installation records are rewritten.

The default new publication does not enforce legal consent: the app distinguishes actual checkbox acceptance from automatic contractual applicability requested for the notice deadline. The provider remains responsible for the legal sufficiency of the document wording and notice process.

### Reproducible checks

- `npm test` and `npm run build:pages`.
- `PGLITE_MODULE=/path/to/@electric-sql/pglite node tests/database/provider-agreement-workflow.cjs` runs 051 against real legacy portal/approval function bodies; checks permissions, draft revisions/retries/deletion, immediate publication, new gyms, deadlines, actual checkbox evidence, read-versus-pending notices, settings notice protection and unchanged approved periods.
- The same environment variable with `node tests/database/subscription-management.cjs` checks the existing approval/refund/upgrade/report engine.
- `node tests/browser/agreement-onboarding.cjs`, `node tests/browser/provider-agreements.cjs`, and `node tests/browser/held-notifications-setup.cjs` use local page assets and mocked services. Chromium/Playwright are required. These tests never publish real documents, approve real plans or send email.
