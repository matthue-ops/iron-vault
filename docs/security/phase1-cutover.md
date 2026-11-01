# Phase 1 coordinated cutover and acceptance

This is the concrete review/run sequence for the implementation branch. **Nothing here has been executed against Supabase.** Do not apply a subset and publish incompatible HTML. PR #2 remains for review; merge/deployment need separate authorization. Keep existing accounts, balances and history. No reset/rebuild is required.

## What is implemented

Browser identity is Supabase Auth with enabled database role assignments. Public gym discovery uses a deliberately anonymous, safe branding projection; private members use scoped views. Ordinary profile/branding edits use dedicated RPCs; base owners/members privileges and public ALL policies are removed. Financial operations lock state, use trusted prices/terms/discounts and store bound request receipts. Members may purchase only for themselves with wallet funds; owner/staff desk purchases may record cash. Cash collection is an authorized desk assertion, not external payment verification.

New branch accounts have separate Auth identities and private randomized aliases, real contact mappings, recoverable provisioning jobs, real-address verification and recovery. Existing Auth IDs/passwords are retained. Existing confirmed users are mapped without account recreation; on successful legacy login or authorized recovery/contact change their Auth email identifier rotates through supported Auth administration, with a protected retry marker, while their web login remains the selected gym plus real contact email. Recovery token replacement through the Auth API and retry behavior require actual provider acceptance testing. The public contact email is not the private Auth identifier.

New roles are disabled until real-address verification; self-registered members also require gym approval. Existing enabled roles default true. The existing auth.users trigger stays attached but rejects the obsolete user-metadata signup route. It never trusts metadata for privileged role assignment. Staff require explicit report permission; role revocation/deactivation retains rows. Daily QR tickets are unguessable, server-stored and expire at Manila midnight; they are not offline cryptographic signatures. Old ID/date-only passes stop authorizing entry; manual admission remains an authorized desk action.

Reports use one stable scoped server snapshot, so API row limits do not silently drop ledger totals. Directory/roster reads keyset-page until empty. Backup restore is explicitly profile/branding-only for existing records, atomically checked; it cannot restore money, identities, entitlements or roles from browser JSON. Keep financial/database disaster recovery in supported project backups with separate approval. Normal removal is clearly deactivation/suspension; nonzero wallets must be settled first. No permanent erasure or row deletion is implemented.

## 1. Review and preserve the target

- Review the branch and all SQL files. Verify the intended Supabase project. Confirm which files, if any, were already committed manually; no file is assumed applied and guarded files are not blindly rerunnable.
- Keep the existing site available until a scheduled coordinated maintenance cutover. Use an isolated staging clone/target first where available, with the existing inspected schema, supported Auth identities and matching code. Never run a staging bootstrap or reset against the existing project.
- Keep a secure supported project backup. Export only V1/V2 from supabase/verification/phase1_acceptance.sql as the before/after financial/account preservation baseline. Do not put raw data or credentials into GitHub/chat. This is acceptance evidence, not a repeat inspection request.
- Native SQL/PLpgSQL parsing and mocks do not prove PostgreSQL semantic resolution, actual ACLs, concurrency, SMTP delivery, deployed Deno dependency loading or end-to-end operation. These must be accepted before calling the release complete.

## 2. Prepare the Edge configuration privately

Use Dashboard → Edge Functions → Secrets. Do not paste secret values here. Existing built-in SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY stay server-side. New source/config is under supabase/functions and supabase/config.toml.

| Binding | Configuration |
| --- | --- |
| APP_URL | `https://ironvaultph.vercel.app` (origin, no trailing application subpath). |
| CORS_ORIGINS | Exact allowed origins, comma-separated; default is APP_URL. Include a reviewed staging origin only when testing that target. No wildcard. |
| SMTP_HOST | Reuse the known Brevo host `smtp-relay.brevo.com`. |
| SMTP_PORT | `587` (TLS upgrade required). |
| SMTP_USER | Existing Brevo SMTP username, entered privately by the owner. |
| SMTP_PASSWORD | Brevo SMTP credential, entered privately; never source control. |
| SMTP_FROM | Verified sender email from your existing delivery configuration. |
| Alternative: BREVO_API_KEY | Optional HTTP delivery credential instead of SMTP_USER/PASSWORD; use SMTP_FROM or MAIL_FROM as verified sender. Obtain in Brevo privately if SMTP credentials are unavailable. No new key is needed if SMTP works. |

The functions cannot automatically read encrypted Supabase Auth SMTP settings; add the required Edge bindings privately. Check actual delivery before enabling registration/recovery. A configured value is not evidence of working mail. SMTP failure leaves accounts/jobs intact for a same-request retry; no destructive cleanup. Existing Auth SMTP stays configured for the global Super Admin/native provider flows. No existing Auth Hook/template is required for the custom branch confirmation/recovery routes. Optional provider notifications to private aliases need a separately configured send-email hook or app notifications; do not rely on native mail to deliver to an alias.

Keep Email provider enabled. Existing screenshots establish confirmation off and secure email change on; branch verification is enforced by disabled role/mapping state, independent of that native confirmation toggle. Consider disabling **native** “Allow new users to sign up” at cutover: branch registration uses admin.createUser and does not need direct public Auth signup. This prevents unmapped native users consuming quota; existing sign-ins and supported administration remain. Do not change settings until the owner approves the cutover. Align the native minimum password length to the app's 8-character rule after checking existing-user password behavior; no account reset is required. Public gateway has persisted email/gym/action throttles; provider/edge abuse protection is additional defense.

## 3. Manually execute approved migrations, one file at a time

The owner alone runs SQL Editor operations. All files are in supabase/migrations. Run numeric 001 → 015 in order; **004 is optional** if Supabase does not permit managed-creator defaults. Each file commits separately. No file deletes an existing row, drops an existing table/column, resets accounts or rewrites historical financial values. 012 adds enabled/default-true and disabled_at role metadata; 014 backfills private contact mappings.

| File | Result |
| --- | --- |
| 001 | Remove owner/member API TRUNCATE. |
| 002 | Remove PUBLIC/anon function execution; preserve ordinary authenticated RPCs and service rights. |
| 003 | Narrow postgres public-schema future defaults. |
| 004, optional | Same for supabase_admin only with actual platform authority; never escalate membership. |
| 005 | Protect authority/history tables from direct writes. |
| 006 | Explicit audited staff report permissions. |
| 007 | Correct financial/attendance member+tenant policy correlation. |
| 008 | Permission tenant FK, NO ACTION. |
| 009 | Member email uniqueness within tenant, preserving cross-gym reuse. |
| 010 | Private financial request receipts. |
| 011 | Transaction/quote APIs and compatible original topup/purchase signatures. |
| 012 | Scoped projections, enabled roles, profile/settings APIs, deactivation and base-table closure. |
| 013 | Member wallet-only purchases and server daily pass issuance/redemption. |
| 014 | Branch mappings, service-only account jobs, email actions, rate limits, preserved trigger and verified contact lifecycle. |
| 015 | Scoped untruncated report snapshot and atomic profile restore, report/audit permission checks. |

Run included final metadata verification after each approved file and record success/file name. If any transaction errors, ROLLBACK and return the error; do not bypass guards, drop constraints, delete data or change fingerprints to force success. Earlier committed files are not automatically rolled back. Public-schema default cleanup does not cancel global PUBLIC EXECUTE: all newly created functions deliberately set their per-object ACLs. **iv_visible_gyms() is the sole deliberately anonymous branding entry point.** Service-only account RPCs deny authenticated/anon execution.

Keep traffic in maintenance during 011–015 and matching backend/app cutover. The earlier financial hold is resolved in code by 012's write closure and 013's member path, not by deploying 011 alone. Once approved, apply the whole matching package; do not reopen public ALL access as rollback. After identity alias rotation begins, an old HTML/gateway version cannot be used as rollback for real-email native sign-in: fix forward or pause service while keeping data intact.

## 4. Publish only after separate deployment authorization

Owner-authorized deployment must include the complete shared helper folder and pinned imports. Functions:

1. provision-gym-tenant — replace supplied implementation, JWT verification true.
2. iv-create-member — replace supplied implementation, JWT verification true.
3. iv-admin-correct-member-email — new secure dual-address correction endpoint, JWT verification true.
4. iv-branch-auth — new public gateway, verify_jwt false; authenticated actions explicitly validate getUser/current enabled role inside the function.

Use supabase/config.toml for flags. Do not disable verification on the protected three to work around token errors. Confirm current JWT signing-mode compatibility in staging; existing screenshots show legacy verification true on the original two functions. With newly asymmetric keys, use the platform's documented verification path and test it rather than weakening caller checks.

Publish the matching six HTML files plus all assets together after database/backend acceptance. Both master entry points now use the same trusted provisioning workflow. Existing global Super Admin login remains direct Supabase Auth. New branch accounts must verify email and members wait for approval. Clear stale browser caches/refresh clients after cutover; old cached scripts cannot write private base tables. Already downloaded data cannot be retroactively revoked.

## 5. Acceptance endpoint — pass all required cases

- Run all read-only metadata checks in supabase/verification/phase1_acceptance.sql. V1/V2 match the baseline before any deliberately approved test transactions. Auth count, original IDs/roles, wallet totals and all ledger/attendance rows are preserved by schema cutover.
- Use actual anonymous and authenticated clients, never SQL Editor/service-key bypass, for allow/deny checks. Existing Super Admin, both gym owners and all four members keep their current passwords and IDs; verify legacy alias rotation and repeat login/recovery. Confirm prior native recovery tokens are replaced by the supported Auth generateLink call; do not assume provider behavior from mocks.
- Register the same contact at gyms A/B with different passwords; verify each separately, approve membership, then prove A credentials cannot open B (unless intentionally equal passwords). Same-gym duplicate rejected atomically. Email correction/recovery changes only the selected account. Verify both old/new address proofs and expired/replayed links. An administrator correcting a never-verified new account uses new-address proof only; a previously verified contact cannot use this exception.
- Owner/staff/member/Super Admin workflows: branding/pricing, staff account creation/name/recovery/revocation, member registration/approval/profile/avatar, cashier top-up, cash/wallet/mixed purchase, member wallet purchase, manual and camera/upload QR admission, reporting, safe export/profile restore, logout/browser Back/session expiry and wrong-tenant URL/body requests.
- Direct base SELECT/write and role/ledger manipulation denied. Members cannot top up or declare cash; staff cannot override price, expiry, balance or discount. Classification changes use approved gym discount defaults; custom member discounts require administrator authority.
- Financial same-key concurrent retries return the same original result with one mutation; changed actor/tenant/member/payload rejected. Cash-only path receives a receipt; insufficient wallet, NULL/NaN/infinity/negative/fractional values and stale prices/expiry fail. Different keys cannot repurchase an already-valid plan. Ledger/receipt failure rolls back all wallet/entitlement changes.
- Staff reports denied by default; owner grant/revoke works only in tenant; disabled staff remain denied. Report totals include deactivated profiles and exceed API row limits correctly. Audit/session privacy must not bypass report permission.
- Passes require real server tickets, matching tenant/day, active valid entitlement and current operator role; old ID/date text, fabricated/used/expired tickets and simultaneous admissions denied. Member daily QR generation never writes counters locally.
- Deactivation/suspension preserves every identity/history row and rejects unresolved wallets; deliberate owner restoration of a verified member works. No erasure/reset test is authorized.
- Backup restore is profile/branding-only and rejects unknown accounts/tenant moves; it must not modify balances/ledger/roles/passwords. The UI states this limitation explicitly.

An owner-invoked staging HTTP harness is in tests/integration/security.test.cjs. It is excluded from npm test, requires explicit staging variables and mutation consent, hard-refuses the existing project host, performs no SQL/deletions and retains its dedicated one-unit top-up as test audit history. It has NOT been run. Native mocks are not a substitute for all acceptance cases above.

## Current validation limits and stop conditions

Local Node tests, Deno SDK type checking, TypeScript/JavaScript syntax checks, SQL/PLpgSQL parsing and mocked Chromium flows are reported in phase1-status.md. PostgreSQL semantic execution/real locks/RLS, deployed Deno module loading, SMTP/Brevo delivery and deployed end-to-end operation remain unverified. Do not claim the web app is deployed/working on the existing project until these acceptance steps pass. If a migration or provider flow fails, preserve records, pause the affected operation and fix forward; never reset accounts or restore unrestricted policies.

Provisioning retries retain the original Auth identity and password; they never reset credentials. If the original creation password is unknown, use the verified recovery flow rather than starting another account request. Pending staff remain visible to administrators for revocation but cannot sign in before verification. New owner invites can be resent while a gym is PROVISIONING; verification re-enables the portal controls.
