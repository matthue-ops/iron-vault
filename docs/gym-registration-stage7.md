# Stage 7 — universal gym registration and shared-owner branches

This stage adds a public registration website and provider-approved branch linking. It does not deploy a public marketing website for each gym; that remains Stage 8. No SQL, real registration, email, pilot, payment, merge or deployment was executed against production during implementation.

## Manual rollout order

1. Confirm migration **059** and all its prerequisites are installed. Stage 6 is merged through PR #74, but a merge does not prove SQL installation.
2. Execute **`supabase/manual/universal_gym_registration.sql` (060)** as a complete transaction in Supabase SQL Editor.
3. Execute **`supabase/manual/shared_owner_branches.sql` (061)** as a complete transaction next.
4. Each manual file is identical to its numbered migration (`202611180060_universal_gym_registration.sql`, `202611180061_shared_owner_branches.sql`). Execute one copy of each, never both copies. Stop on a guard/schema error; do not delete existing mappings to force installation.
5. Manually deploy **iv-gym-registration** as a new Edge function using `supabase/dashboard/iv-gym-registration.ts` (complete generated file), with **Verify JWT OFF**. It includes public registration/login plus authenticated actions that verify `getUser` and SQL authority themselves.
6. Manually update **iv-branch-auth** using `supabase/dashboard/iv-branch-auth.ts`, preserving **Verify JWT OFF**. This includes Stage 5's assisted recovery and now resolves shared-owner credentials/recovery correctly. Keep existing APP_URL, CORS_ORIGINS, Auth and mail secrets/configuration appropriate for the actual site. No secret is included in this branch. The new static config repeats only the existing public anon key.
7. Other generated Dashboard files contain the shared helper declarations because of the bundler. Their existing controllers do not change; no purge, finance or member-provisioning Edge deployment is needed for Stage 7.
8. Deploy the reviewed frontend, then refresh installed apps/tabs. Review published platform registration Terms/Privacy before sharing the link. No new public owner can register if those documents are unavailable.
9. Verify the hosted flow using a disposable gym/account/inbox: registration, login before pilot, terms/setup, provider review, branch approval, switch, normal contact change and recovery. Confirm real email delivery, Auth session exchange, router/CDN configuration and device-specific installation behavior. Local fixtures do not establish hosted SMTP or every device's PWA behavior.

## New gym registration

Provider menu → **Gym Registration** contains the public registration link and QR, **Add Gym Manually**, and **Branch applications**. Existing manual registration is moved into that menu; its original form, pricing/staff/logo logic and server controls remain available. Existing gym profile, portal-link, entrance-QR, subscription and inspection controls are retained.

Public URL: `/gym/register.html` (Pages may canonicalize the extension). Owner enters gym/owner names, contact email, password, business address and optional gym phone; reviews published registration Terms and Privacy and explicitly accepts. Registration version/time are recorded separately from subscription agreements. The browser persists only an opaque request ID, the accepted publication UUID and a details hash for uncertain retries—never a password or confirmation token. A retry displays that original publication. A fresh stale-publication request returns to current document review before creating Auth data. A pending attempt also offers an explicitly confirmed new-request action; it never removes the earlier server-side job or gym.

Owner creation uses the same protected private Auth identifier and original `iv_finish_branch_account` completion path. A valid temporary contact can sign in without inbox confirmation. Incomplete Auth creation is retained for a safe retry; no account/data is deleted as compensation. Completed retries return the original public gym destination without creating another Auth identity.

Success directs the owner to `/g/<gym-id>/login?key=<public-portal-key>`, their existing branded portal. They sign in using their owner email/password and can install that gym's app when supported. The universal registration website is not a universal app installer. No member photo, gym logo or identity is fabricated. The new gym starts with the standard configurable base prices (PHP 100 day / 600 week / 2000 month and 20% student/senior defaults); owners/permitted staff can adjust rates through existing controls before operations begin.

New self-registered gyms are **Live**, but Live is only a provider administrative tag. Their owner role is enabled and the gym status allows login/setup. Their subscription remains **setup**: no pilot/paid period is inserted, pilot_used stays false, and operational/member-portal entitlements stay false until the existing provider pilot approval requirements are met. Business details seed an unpublished gym document draft only; the owner must still review/publish gym documents and accept current service agreements. Existing pilot duration, eligibility review, agreements, payment and subscription APIs are not relaxed.

Public registration is throttled by email, source-address bucket and overall registration window. It cannot supply a role, actor, arbitrary Auth user or pilot/payment fields. It creates no financial transaction.

## Existing owners and additional branches

An owner may use the registration website's **Existing owner** sign-in to choose an authorized gym. If an email belongs to separate older accounts, the original gym link disambiguates; matching emails are never automatic proof that accounts should be merged.

Owner menu → **Add Gym Branch** uses the authenticated owner account, not a new email/password. The owner provides branch details and accepts the current registration publication. Requests are account-scoped, revisioned and duplicate/retry safe. Status labels: Awaiting provider review, Approval in progress, Approved, Not approved or Cancelled. Owners may cancel before provider provisioning begins. Published-document changes before review can require cancelling and resubmitting with a fresh acceptance rather than silently substituting terms.

Provider → Gym Registration → Branch applications. Provider reviews ownership/details and explicitly approves or rejects with a reason. Approval uses a durable provisioning job; a timeout or interrupted Auth/SQL step can be resumed with the same application. A different reviewer cannot silently take over an in-progress approval. An approved retry returns the existing branch, without another gym/account.

Approval creates a separate gym and links it to that logical owner account. Its subscription, agreements, pilot, members, staff grants, payments, wallet/financial history, attendance, reports and card credentials remain separate. Approval does not start a pilot, charge an owner, collect a payment, grant extra staff rights or combine business records. Existing staff do not gain access to a new branch automatically. Required branch setup and the normal provider pilot approval still apply.

**Switch Gym / Branch** appears when the owner has more than one currently authorized active gym. Disabled/suspended/revoked branch access is not returned as available. Closing/signing out/changing context clears sensitive dialogs and pending responses. Forms keep their values during phone rotation/resizing. Desktop, portrait and landscape layouts are tested locally.

## Authentication design and preservation

Existing Auth IDs, passwords and the single-gym role model are not converted or loosened. Existing owners receive self-links in new private tables; separate existing accounts are never merged automatically.

- `owner_accounts` represents the logical credential account, contact and owner name.
- `owner_gym_links` maps each approved gym to its existing tenant-bound owner Auth identity and that logical credential account.
- A newly approved branch receives its own protected tenant-bound Auth identity with an undisclosed random password. The owner never needs to create or manage that password. Their normal shared email/password authenticates the logical account; a service-side exchange then obtains a session only for the selected approved branch.
- The exchange derives actor identity from verified JWTs, checks approved links/current roles/gym status, validates the generated OTP user ID, and repeats branch authorization before returning tokens. No magic/recovery link secret is returned to the browser, and no email is sent for a branch session exchange.
- Each destination uses the existing project/gym-specific browser storage namespace and `/g/<id>/` app scope. Switching does not replace another gym's stored session or the provider session. Bootstrap/chooser and owner-recovery sessions are nonpersistent. A URL or routing alias is never authorization.
- Normal table/RPC access continues seeing exactly the authenticated branch's original owner role. The logical owner cannot directly scan, purchase or inspect another branch with a first-gym token; they must obtain its authorized context. Existing business/admission functions are unchanged.

New service-only registration/owner APIs have no anon/authenticated execute grant. Public browser APIs expose only published registration documents and the caller's own branch summaries/applications. Provider queues require an enabled global provider. New tables have RLS and no direct browser/service table grants; definer functions implement the scoped operations.

## Owner email, password and recovery

A linked owner uses one logical email/password across linked gyms. The UI warns that owner email changes affect all linked owner portals. Ordinary changes still require the existing address proofs; provider-assisted recovery still requires ownership checking and new-inbox confirmation. A confirmed owner contact propagates to linked owner contact mappings, without changing private Auth identifiers or enabling suspended/revoked roles. A collision with a staff/admin email in any linked gym rejects the whole change. Contact confirmation, assisted recovery and branch completion coordinate on the logical-account lock so stale approval cannot restore an older email.

Shared-owner **My Account → password change** verifies the current canonical password at the gateway, binds the expected authenticated user, and updates only that logical Auth account. Legacy owner and staff password-change paths remain unchanged. Passwords are never stored in registration/application payloads, browser retry storage or activity messages.

Forgot Password for a shared owner sends to the current canonical inbox and uses the logical Auth identity, not an undisclosed branch password. The gateway rechecks that contact before delivery. Shared resets use `/gym/owner-recovery.html`, a nonpersistent recovery page that updates the verified Auth user's password and then returns to the original gym sign-in. Stage 5 assisted recovery invalidates the logical account's prior recovery token before confirming the new contact. No password reset activates a gym/pilot/subscription. This feature does not claim to forcibly terminate every previously issued branch session; respond to a suspected compromise by reviewing/revoking the affected branch/account access through established security controls.

If the original gym is explicitly purged while other approved branches remain, the logical Auth account is retained through its new ownership reference; it can still authenticate to the remaining branch. The purge framework's existing shared-FK protection provides this retention without modifying purge behavior. Removing the last gym removes unneeded ownership metadata, except where pending branch applications require retaining the logical account for review. Retained identities/application history require controlled account/retention review; there is no new automatic account-deletion job. Existing member, finance and gym purge confirmation controls are preserved.

## Data and rollback

060: private gym-registration jobs, version/time acceptance, published-document API and service-only creation helper. 061: private logical owner accounts, approved links, branch applications, scoped owner/provider APIs, owner enrolment/contact/cleanup triggers, and narrowly wrapped contact confirmation/recovery for serialization. Provider requests and owner approval/rejection updates use the existing compact notification systems with deduplicated notice keys. No old member/financial/attendance/card/plan/subscription-period rows are rewritten during installation.

Do not blindly roll back after branch identities are created. An old gateway would expect the branch's private random password, and an old recovery flow could target the wrong credential identity. Keep matching Stage 7 SQL/gateways/frontend while linked branches exist, or use a reviewed migration plan that restores independent ownership without erasing business records. No destructive rollback file or automatic unlink/account merge is provided. Prefer a forward fix and retain normal backups.

Validation covers actual disposable SQL and synthetic Edge/browser flows: version acceptance, service-only access, Auth proof binding, duplicate/timeout retries, owner/staff/provider permissions, branch review, zero automatic pilot periods, current setup-only subscription state, cross-gym rejection even for one logical owner, separate storage namespaces, contact proofs/sync, revocation, canonical recovery/password targets, QR readability, preserved manual registration, mobile/landscape and cleanup. Existing scanner, card, financial/custom-plan and subscription tests remain relevant. Hosted Auth/email/PWA integration requires the manual acceptance checks above.
