# Registered owner Service Agreement acknowledgment

## Inspection findings

The application already had three rendered, tenant-specific documents; one unchecked owner checkbox; a disabled-until-checked acceptance button; fixed registered-owner authorization; exact document-hash verification; timestamped acceptance with gym/user identities and immutable text snapshots; a unique tenant/owner/version receipt; persistent accepted state across logins; and a separate Provider-only pilot activation gate. Paid plan confirmations and quotes were already separate. No second acknowledgment system or staff privilege was introduced.

Missing pieces were the requested exact acknowledgment text/button label, explicit Free Pilot Conditions access and explicit agreement-type/document-reference/method receipt metadata. This change adds only those and checks the strengthened receipt before new pilot activation.

## Modified files

- `assets/subscriptions.js`: Service Agreement entry in pending setup; four document access points; direct Free Pilot section link in Terms; exact mandatory checkbox wording; Accept and Continue; receipt persistence/re-login behavior; explicit pending-manual-approval status; separate optional-payment notice. Missing pilot sections disable new acknowledgment. Existing valid acceptance remains complete and is not requested again on every login.
- `assets/subscriptions.css`: scoped style/focus treatment for the pilot document link and section anchor.
- `supabase/manual/owner_agreement_acknowledgment.sql` and its exact migration copy `202611060040_owner_agreement_acknowledgment.sql`: additive receipt evidence and narrow server-side guards. No deletion, activation, pricing, period-date, staff/member privilege, QR or reporting change.
- `tests/owner-agreement-acknowledgment.test.cjs`: authorization/receipt/migration contracts, exact text, historical evidence, repeat acceptance, activation separation and optional-payment separation.

## Database changes

Four nullable columns are added to the existing private `service_acceptances` table:

| Column | Recorded meaning |
| --- | --- |
| agreement_type | New receipts: gym_owner_service_and_pilot; historical equivalents: gym_service_bundle |
| document_versions | Separate Terms, Privacy, DPA and Free Pilot entries referencing their immutable published bundle ID/version label; pilot conditions point to Terms |
| acceptance_method | dashboard_checkbox for new receipts; legacy_recorded_owner_acceptance for preserved receipts |
| acknowledgment_text | The exact new statement, stored for new acknowledgments only |

Tenant ID, accepting user ID, server acceptance timestamp, gym/owner identity snapshots and exact rendered documents already existed and are reused. All three documents currently publish as one immutable bundle, so their individual reference entries correctly share the bundle ID; this does not invent independently published version numbers. Pilot conditions are incorporated in that same Terms version.

Equivalent historical text receipts with existing snapshots receive metadata identifying them as legacy. Their timestamps, document content and historical acknowledgment wording are not changed. No new-text statement is attributed retroactively. Existing valid current receipts continue satisfying the pilot gate. Incomplete old evidence is not silently overwritten; it requires Provider review.

The existing public subscription RPC is wrapped; its previous implementation moves to a private, non-callable helper. Authorization remains the enabled fixed registered-owner account or global Provider, and only the registered-owner account can accept. That account acts as the gym's authorized representative. Ordinary staff cannot gain authority by checking a box. No separate delegated-representative role/grant is added.

New acceptance requires the exact checkbox statement, explicit accepted=true, all three documents and an identifiable Free Pilot section, plus the existing current-identity/review-hash checks. Metadata comes from the database, not caller-supplied user IDs, timestamps or method names. Repeated acceptance returns the original receipt without changing its date or creating duplicates.

Acceptance never invokes pilot activation. New activation requires Provider authority and a valid receipt from the fixed registered owner for the currently applicable published documents. Existing business-eligibility, member-document, first-pilot and date/counting checks still run. Safe retries of already completed activation remain idempotent; new Terms cannot revoke an existing approved period.

## Manual deployment

1. Confirm migrations through **039** are installed. Do not rerun earlier installers or test cleanup.
2. Run `supabase/manual/owner_agreement_acknowledgment.sql` once in Supabase SQL Editor. It is identical to migration **040**; run only one copy. The agent never executes SQL, including locally.
3. Merge the frontend PR and let Cloudflare build. No Edge Function update is needed. Refresh open owner sessions before new acceptance; older browsers do not send the new exact statement and will be asked to refresh/review.
4. Review the current published Terms and confirm a clear Free Pilot heading (for example `2. FREE PILOT`) exists. The link navigates directly to that section; no separate pilot document or duplicate agreement is required. A new version missing the section cannot receive new acknowledgment until the Provider publishes corrected documents. Existing valid receipts are not invalidated by this UI change.
5. Owner completes gym legal details, reviews all four document access points and checks the single statement, then selects Accept and Continue. The gym remains pending manual Provider approval. The acceptance itself does not charge, choose a paid plan or consent to optional paid features.

Saving/editing drafts does not change published documents. Optional paid features continue to require separate exact quote/plan confirmation; declining them does not alter existing approved access. This change does not activate the pilot, charge anyone or publish new Terms automatically.

## Tests and staging verification

Automated local checks cover SQL contracts, exact client/server wording, private API revocation, legacy receipt preservation, repeat/idempotent acceptance, manual activation gates and unchanged optional-payment paths. SQL is parsed only, not executed. Local browser tests use actual UI code and mocked Supabase responses at phone and desktop sizes: four document links, pilot anchor, one unchecked required checkbox, disabled button, recorded acceptance, pending status, repeat login, staff denial and unchanged existing paid access.

After manual deployment, verify with actual Test accounts:

1. As the registered owner, open Service Agreement before pilot activation. All four documents/access points must be available; the single checkbox starts unchecked and Accept and Continue is disabled.
2. As ordinary staff (including direct authenticated RPC calls), attempt acceptance: deny and create no receipt. As Provider, attempt to accept for the owner: deny. Another gym's owner must also be denied.
3. Submit owner acceptance with accepted=false, missing/wrong statement, a stale review hash or another tenant/version: deny without inserting or modifying a receipt.
4. Accept the correct version. In SQL Editor inspect the private receipt's tenant/user, unchanged document reference, server timestamp, agreement type, four version entries, method, exact statement and immutable snapshot. Acceptance alone must create no pilot period and leave setup pending.
5. Sign out/in and reopen Agreement: show accepted state without another acknowledgment. Retry the same valid acceptance: preserve receipt count and original timestamp. Inspect a preexisting equivalent receipt: legacy method, no fabricated new statement/date.
6. Attempt new pilot activation without receipt or as owner/staff: deny. As Provider with a current valid owner receipt and all existing setup checks, explicitly activate once. Retry the same activation ID: no second period.
7. Publish a subsequent version and confirm it does not interrupt approved paid access. Decline/leave an optional paid quote unconfirmed: existing approved periods and access remain unchanged.

The agent has not applied SQL or performed live account/activation tests. Database permissions, row locking and receipt persistence must be verified in the test project after the user's manual migration.
