# Owner login without email confirmation

The working baseline is the owner's report: **001–017 installed; 018–020 NOT applied**. No SQL or backend deployment was performed by the agent.

Owner creation no longer requires SMTP or sends an activation email. The service still creates a confirmed **private Auth identifier**, binds its protected provisioning metadata, and preserves the separate unverified contact address. The new completion RPC enables the role and activates the gym atomically. Owners, staff and members sign in with their contact email and password without proving inbox ownership. Existing gym approval for members remains separate: PENDING members are not made ACTIVE.

## Targeted manual rollout

1. In the correct Supabase project's SQL Editor, run the **entire** `supabase/manual/owner_login_update.sql` in one operation. This is migration 021 only and supports a database at 017 directly. Do not run the original full installation package, and do not assume 018–020 are installed. No Auth credentials, IDs, balances, membership approvals or history are replaced.
2. Manually update the Edge functions using the matching generated `supabase/dashboard/provision-gym-tenant.ts`, `iv-branch-auth.ts`, and `iv-create-member.ts` entries (or deploy their modular sources). Preserve JWT settings in `supabase/config.toml`. The other generated entries change because the bundler includes the shared provisioning helper in every entry; no purge deployment or operation is needed for this fix.
3. Manually release the app changes to the reviewed Vercel `iron-vault` project when ready. This agent has not deployed production, and PR #2 must remain Draft. Production is https://ironvaultph.vercel.app.

The SQL is repeatable. It restores completed, unverified owner gyms in PROVISIONING only when the tenant, role, completed provisioning job and protected Auth request metadata agree and `disabled_at IS NULL`. It enables unverified roles only in ACTIVE gyms and leaves inactive memberships, explicit revocations and gym suspensions intact. It does not mark contacts verified. Incomplete or inconsistent provisioning remains blocked for administrator investigation, rather than being bypassed in the browser.

If the usability changes are wanted later, the regenerated `supabase/manual/usability_update.sql` now includes **018, 019, 020, then 021** atomically. Do not run 019 after 021 without reapplying 021 last: the old 019 definitions restore the owner gate. If 018–020 have already been installed, run only the targeted owner update, not the usability bundle. Optional display-code lookup in 021 uses `to_jsonb` so it works with or without the 018 column.

## Acceptance after your manual rollout

- Create a gym with a syntactically valid temporary owner contact and password while mail delivery is unavailable; creation succeeds, the gym is ACTIVE, and owner sign-in works. Retry a completed creation request without creating another account.
- Sign in to an existing gym previously held only by owner email verification, using its existing contact/password. Check the same tenant and existing records.
- Unconfirmed staff and members can sign in; self-registered members still require gym approval for active services. Invalid email/password, revoked accounts and suspended gyms remain denied. An owner from another gym must not gain tenant access.
- Password recovery requires receiving and following the recovery email. A temporary address without a working inbox cannot recover a password. No recovery token is returned by the gateway. Verified contact changes still require both address proofs.
- Following a suspension/revocation, an old verification link must not reactivate the gym or restore revoked access.

Local tests execute the actual provisioning/gateway/controller source against mocks, plus SQL contract and syntax checks. They do not establish PostgreSQL execution, hosted integration, mail delivery or production acceptance. No live credentials are needed for these local checks.
