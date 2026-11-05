# Pending profile access and optional walk-in contact

## Deploy in this order

1. In the gym project's Supabase SQL Editor, apply `supabase/manual/pending_access_optional_contact.sql` after migration 033. This is migration 034, not an additional copy to execute. Run it once. Do not assume it was applied by the agent.
2. Update these generated dashboard Edge entries, keeping existing environment secrets:
   - `iv-create-member.ts`: Verify JWT ON.
   - `iv-branch-auth.ts`: Verify JWT OFF (public route, authenticated actions verify the actor).
   - `iv-admin-correct-member-email.ts`: Verify JWT ON.
3. Merge the frontend branch and let Cloudflare Pages build. Refresh open sessions.

The other generated dashboard files are kept synchronized with shared modules but need no deployment for this feature. No SQL, Edge deployment or production test was performed by the agent.

## Database impact

Missing walk-in email is stored as SQL NULL, not a generated contact inbox. Account identity remains the existing unique Auth user ID. The private branch-account primary key moves from `(tenant_id, role, contact_email)` to `user_id`; a UNIQUE constraint preserves the original tenant/role/contact uniqueness for supplied addresses. Its existing unique user constraint remains. Contact columns in member profiles, provisioning jobs and email-action base addresses become nullable. Owner/staff accounts still require contact email. No rows, columns, credentials, balances, acceptance records or history are deleted or rewritten. Existing IDs, passwords and contact addresses remain unchanged. The migration does not use CASCADE: unexpected foreign-key dependencies abort rather than drop them.

Only an authorized operator can create a member without email. Public self-signup and owner/staff creation still require valid email. Required passwords remain 8–128 characters. Multiple no-email members are distinct by Auth user ID and Member ID; the original request ID still governs creation retries. The private Auth alias is not a contact email and is not displayed to users.

An email-less member signs in using Member ID and password. Email recovery cannot work without a real inbox. They can later add a real email and prove ownership of that new inbox; existing verified contacts retain dual-inbox change confirmation. Admin contact correction and audit scope remain in place.

Pending members can read their own profile/live checkpoints and review/accept published Terms. Self-service profile writes, QR passes and purchases remain blocked until approval. Approval does not create Terms acceptance. Terms acceptance does not change membership status. Financial/admission action functions and their ACTIVE/Terms checks are not relaxed. Inactive/revoked members, inactive gyms and foreign-member access remain denied. Denial redirects capture the gym token before private state is cleared.

## UI and verification

The profile shows an approval banner and locks protected features. Walk-in password is required beside Initial Plan; only the obsolete barcode input on this registration form is removed. Existing card data is retained. Staff tabs highlight the selected view at equal widths. Mobile Member/Admin login forms have matching field spacing and height.

Tests use mocked Supabase responses and syntax parsing only; no SQL was executed, including locally. After deployment verify: pending sign-in stays open through background refresh, accepted Terms do not approve membership, approval enables only appropriately accepted features, revocation still exits to the gym link, two separate no-email walk-ins can be registered and sign in by their IDs, valid-email registration remains supported, completed retries reuse the account, and adding a first email requires proof before recovery can use it.
