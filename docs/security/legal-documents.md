# Legal documents, public details and signup acknowledgment

## Deployment (user-operated; nothing has been executed/deployed by the agent)

1. After migration **029**, manually run **one copy** of `supabase/manual/legal_documents.sql` in the gym Supabase project's SQL Editor. It is identical to migration 030.
2. Update the **iv-branch-auth** Edge Function. For Dashboard deployment, replace its entire index.ts with `supabase/dashboard/iv-branch-auth.ts` and deploy. Keep **Verify JWT OFF** for this public gateway; its authenticated actions continue checking their own user and role authorization. Alternatively use `supabase functions deploy iv-branch-auth --no-verify-jwt` from an authorized local CLI. Do not change APP_URL, CORS settings, or other function settings for this feature. Other generated bundles are refreshed for source consistency but do not need redeployment for this feature.
3. Merge/deploy the frontend PR to Cloudflare. The existing Pages build includes the two new HTML pages and legal assets automatically.
4. Super Admin: open **Platform Legal Details**, enter the actual operator identity, address, public/support and privacy emails, retention/deletion practices and current infrastructure providers/processing locations. Optional extra terms/privacy information may be supplied. Preview, confirm review and publish.
5. For each gym: its owner uses **Terms & Privacy** in the admin header, or Super Admin uses **Gym Terms & Privacy Details** in Edit Tenant Details. The business name is prefilled; login emails are deliberately not copied. Enter public/legal details and retention practices. Membership, refund, age/guardian and additional policies are optional and omitted when empty. Preview, confirm review and publish.
6. Test member self-registration, both pinned legal links, and the receipt in the gym legal editor before inviting real members.

**Self-registration pauses until BOTH platform and gym documents are published.** Existing accounts, sign-in, recovery, wallets, plans and staff-operated member creation continue working. The new SQL rejects old public signup clients without legal acceptance. No acceptance is invented for older accounts or staff-created members. Existing unfinished public provisioning jobs from before migration have no acceptance and may require investigation before retrying; do not delete Auth accounts or provisioning jobs as an automatic workaround.

## Ownership and publication

Drafts and versions live in private tables with direct privileges revoked and RLS enabled. The management RPC authorizes enabled, non-revoked global Super Admin accounts, or the enabled owner of the exact active gym. Staff and members cannot manage legal settings. Super Admin manages the platform and may oversee any gym. All fields are explicit public-document fields; the operator should avoid entering unnecessary personal information.

Save Draft leaves the published version unchanged. Preview uses the same server renderer as Publish, without persisting changes. Publishing requires business name, address, public email, privacy email and a retention description; platform publication also requires infrastructure providers/locations. Publishing freezes the full Terms and Privacy bodies, data, publication time and version ID. Later template, policy, name or contact edits cannot rewrite the old bodies. The editor lists prior published versions for inspection. It requires previewing the current field values and confirming review before publication. Wording is a draft tailored to this app, not a claim of legal review: have the actual operator/gym policies reviewed before launch. Declared retention and provider practices must match reality; this feature does not implement automatic cleanup or new marketing subscriptions.

Published Terms and Privacy pages are `/gym/terms.html?key=GYM_TOKEN` and `/gym/privacy.html?key=GYM_TOKEN` (Cloudflare also serves their extensionless forms). They include both platform and gym sections. Signup links pin **both** published version IDs; archived links continue rendering those immutable versions. The public RPC only returns published versions of the platform and that exact active gym, never drafts or another gym's documents. All document and policy content renders with `textContent`, not HTML.

## Signup enforcement and receipts

The unchecked required checkbox is a Terms agreement and Privacy Notice acknowledgment, not optional marketing consent. The client sends accepted=true and the displayed platform/gym version pair. The public Edge Function validates and normalizes that pair and puts only those three legal fields into the protected provisioning payload.

A private BEFORE INSERT trigger on provisioning requests checks the currently published versions under row locks. This independently rejects bypassed checkboxes, stale/wrong-gym versions, missing publication, and old Edge Function callers. A precise transaction-rolled-back preflight error allows the client to discard only its unprepared retry key and ask for a reload/review. Network failures retain retry keys as before.

Completion of an already prepared signup uses the originally accepted published pair, even if a newer version is published during the in-flight operation. A trigger records server accepted_at (request creation), recorded_at, member/user IDs and the exact pair in the same transaction that completes the member account. Auth creation remains resumable and is not deleted as compensation. Existing completed requests retain their previous behavior without fabricating consent. Manual enrollment by authorized staff/owners does not claim that a member agreed.

Owner/Super Admin can load a gym's acceptance records in its legal editor; ordinary users and public visitors cannot. Member deactivation retains receipts. The existing deliberate full-tenant purge cascades that gym's drafts, versions and acceptance records through owners; platform records remain. There are no Auth foreign keys on legal audit identities that would inadvertently retain dedicated Auth accounts during a tenant purge.

Publishing a material change does not automatically email members or force existing users to reaccept. The editor warns the publisher to communicate changes through their actual process. A later mandatory reacceptance workflow would be a separate implementation.

## Independent layout fixes included

Admin/Staff Forgot password is beside the Password label; its Resend email confirmation link is below Sign In. Member resend is inside the member form, so it does not appear above Join. Join has “Already registered? Resend email confirmation.” below Create Account and uses the signup email field. Existing role-scoped recovery/resend endpoints and password visibility behavior are retained.

## Validation and production checks

Automated tests exercise signup validation, exact/normalized version payloads, missing/false agreement, pinned links, late-response scoping, retry safety, SQL security contracts, and form placement. Local browser checks cover mobile/desktop previews, publishing/history UI, escaped document content, signup/resend sources, and legal page navigation with mocked APIs. SQL/PLpgSQL are parsed without executing SQL. Real deployed RLS/RPC authorization, concurrent publication/registration, acceptance transaction behavior, and tenant purge integration still need project-level verification after the user installs the migration. Confirm staff/other-tenant accounts receive denial and public API calls cannot retrieve drafts.
