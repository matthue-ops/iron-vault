# Stage 5 — provider card design, member QR export and owner inbox recovery

This change preserves existing member, wallet, payment, attendance, subscription, permission and gym-isolation behavior. No live SQL, emails, production downloads, merge or deployment was performed during implementation. Tests use disposable synthetic records.

## Manual rollout order

1. Confirm migration **057** and its prerequisites are installed. A merged PR does not prove SQL was applied.
2. In Supabase SQL Editor execute **only** `supabase/manual/provider_design_qr_owner_recovery.sql`, as one complete transaction. It is identical to `supabase/migrations/202611180058_provider_design_qr_owner_recovery.sql`; do not execute both. Guards stop a missing prerequisite or repeat installation.
3. Manually update **iv-branch-auth** using the modular source, or paste the complete generated `supabase/dashboard/iv-branch-auth.ts` into its Dashboard entry. Preserve `verify_jwt = false`: public login/confirmation actions are intentional, and authenticated provider actions validate `getUser` and enabled roles themselves. Existing mail configuration, APP_URL and allowed origins must remain correct for the actual deployment; do not change secrets or mail providers just for this update. No other Edge function deployment is needed.
4. Deploy the reviewed frontend and refresh open/installed app tabs. SQL/Edge/frontend must all match before using assisted recovery. The provider QR button is intentionally absent until 058 supplies its permission flag.
5. Verify with a disposable gym and inbox you control: save design, download/scan QR, initiate recovery, confirm the new inbox and use **Admin / Staff → Forgot Password**. Test real email delivery and a physical print proof yourself; local tests do not establish hosted delivery or printer quality.

Do not run SQL against live accounts merely to test. Do not rerun old migrations to undo this one.

## Shared gym ID design

Provider: Physical IDs → select gym → select member → **Gym Card Design**. The gym owner retains the same control. The editor says **Applies to all members of this gym**; the chosen member is only a sample. Staff and members gain no editing rights.

The existing authorization helper signature is retained, but now accepts an enabled global provider as well as the active gym owner. The same helper protects design APIs and private background uploads, so provider access remains consistent across editing/storage. Existing production entitlement checks still apply; no subscription expansion is introduced.

Saving keeps every permanent QR unchanged. The existing design row retains latest actor/time/revision. New private `physical_id_design_events` stores an actor/time/revision entry for each new revision, without images, QR payloads or full card snapshots. Same-revision retries do not create repeat events. Both tables follow gym deletion through existing cascades.

## Download Member QR — provider only

Provider: Physical IDs → select gym/member → **Download Member QR**. The action downloads a ZIP with:

- `member-qr.svg`: scalable, black modules on white, four-module quiet zone.
- `member-qr-2048.png`: 2048 × 2048 pixels with integer module placement and a white quiet zone.
- Print notes: preserve proportions/quiet zone and scan a physical proof. Use at least a 26 mm square area for this permanent payload.

A complete photo/logo is not required for QR-only output; full-card production requirements are unchanged. Missing photo/logo still blocks **Download ID** when appropriate. QR-only output uses the same current permanent credential as the preview. No new credential, request, attendance, payment, wallet deduction or issued status is created.

Authorization locks the member before the current card, rechecks gym production access and provider authority, and rejects obsolete/revoked credentials, including a previously successful request retried after revocation. Existing operations provide retry identity; one audited authorization per operation. `physical_id_events` records actor/time/version/format. No QR payload is stored in operation results or activity messages. Files are built in memory and emitted only after successful current-card authorization and context checks. Nothing is uploaded publicly.

A previously downloaded QR cannot be recalled. The existing lost-card workflow revokes its credential; every saved copy then stops granting entry. A copied visible QR still requires normal staff verification and a valid pass. Downloading never marks the member entered or the card issued.

## Provider-assisted owner email recovery

Use **Edit gym → Recover owner email** only when the owner cannot receive mail at the old address. Normal owner/provider email-change flows retain their existing checks and address proofs; this is a separate action.

1. Verify the person's identity and ownership of the selected gym through your support process outside the app. A checkbox is a provider attestation, not automatic identity verification. Do not put identity documents or unnecessary personal details in the reason.
2. Enter a different working email, a brief reason and the explicit ownership-check confirmation. Send confirmation.
3. A 30-minute link goes only to the new inbox. Until it is confirmed, the current contact email and password remain unchanged.
4. Following the link confirms the new contact. The owner then uses **Forgot Password** in that gym's Admin / Staff portal to receive a separate reset link at the new address. The provider never receives a recovery token or sets/reads a password.

The new service-role-only `iv_owner_contact_recovery` RPC supports prepare/inspect/confirm. Browsers, including authenticated providers, cannot call it directly. The Edge gateway authenticates the provider and derives actor identity from `getUser`; the database independently checks the enabled, non-revoked global role. The owner/tenant is derived from the gym mapping, not an arbitrary target Auth user supplied by a browser.

Private `owner_contact_recoveries` stores request ID, gym/user/provider IDs, base/new contacts, reason, token hash, timestamps and status. No plaintext confirmation token or password is stored. Records cascade when the gym is explicitly purged, preserving existing purge behavior. This table is security/support history; do not include its contents in compact public activity messages.

A request stays pending until confirmation; a newer request cancels older pending requests. Retrying the same request refreshes its token and sends a fresh link—**only the latest link works**. If mail fails, no address changes; retry the same dialog submission. Confirmed requests are harmless retries. Expiry, contact changes, an occupied admin-portal email, revoked provider/owner access or an inactive gym reject confirmation. Existing suspended/disabled access is never enabled.

Before committing a newly confirmed contact, the gateway replaces the owner's outstanding Auth recovery token using `generateLink` without sending it to the lost inbox. If this fails, contact confirmation does not proceed. This Auth operation and SQL commit cannot share one transaction: a later SQL failure can invalidate an old reset link while leaving the email unchanged; the user can safely retry the newest confirmation. Existing contact-change links carry the prior base email and become invalid when the address changes. A new verification link is not itself a password-reset credential.

Existing signed-in sessions are **not** forcibly revoked by this feature. For a suspected account compromise, use the established account/security response process; inbox recovery is not a claim to have terminated all sessions. Existing passwords, Auth identities/private aliases, role grants, gym status, subscription status and business records are preserved. No pilot activation occurs.

## Compatibility and rollback

058 adds wrappers around Physical ID query/action APIs, a narrow shared design permission change, private design audit history and private recovery history/service RPC. It does not replace entry verification, check-in, finance, notifications, ordinary contact confirmation or password-change functions.

Frontend-only rollback removes new controls while SQL records remain. Do not delete recovery/design audit records or drop the schema/bucket as a routine rollback. A coordinated Edge rollback makes pending `OR1` confirmation links unavailable; re-upgrade or deliberately expire/reissue requests under a reviewed recovery plan. Never restore a database snapshot merely to roll back this UI: that would also roll back unrelated business records. Prefer a scoped forward fix.

## Local validation

`npm test`, `npm run build:pages`, Dashboard bundle consistency; actual SQL/PGlite Stage 5 plus existing card appearance/workflow/permanent QR suites; Chromium Stage 5 plus existing card preview/output/scanner suites. Stage 5 tests cover provider/owner/staff/member permission boundaries, private backgrounds, current/revoked QR authorization, no duplicate audit on retry, readable SVG/PNG, missing-logo QR export, recovery proof/collision/expiry/supersession/revocation/stale-contact rules, normal confirmation compatibility, responsive portrait/landscape and sign-out cleanup.
