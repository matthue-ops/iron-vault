# Staff access, targeted announcements and public launcher

## Rollout (manual)

1. Confirm migrations through **040** are already installed. Review and execute **only** `supabase/manual/staff_access_targeted_announcements.sql` in the Supabase SQL Editor. The matching numbered migration is `supabase/migrations/202611070041_staff_access_targeted_announcements.sql`; these are identical alternatives, not two scripts to execute. Never reapply older migrations after 041, because older function definitions would replace the new permission checks. No SQL was executed during development.
2. Update the existing **iv-branch-auth** Edge Function using the complete `supabase/dashboard/iv-branch-auth.ts`, or deploy its modular source from `supabase/functions/iv-branch-auth/index.ts`. Retain its existing Verify JWT OFF setting: public login/recovery actions coexist with authenticated actions, which explicitly validate the JWT and role. Do not change mail credentials. The new own-recovery action needs the existing configured mail delivery.
3. Merge/deploy the frontend. Check the staging scenarios below before live use. Until 041 is installed the new staff controls and targeted announcement authoring deliberately fail closed. Older, already published member announcements remain readable.

## Behavior and files

- `index.html` is a public, static project launcher with no Supabase client, legacy gym dashboard, login, sign-out or private-data reads. Launch Gym App goes to `/gym/`. Application-level authentication remains intact. The future Transport placeholder remains.
- `assets/subscriptions.js` renames the entry and page to Subscription, adds its icon, and allows the shared notification bell to include gym announcements. The original owner subscription operations are unchanged.
- `assets/staff-access.js` and `.css`, loaded by `gym/admin.html`, add My Account below Membership Pricing, self password-recovery mail, scoped menu visibility, owner staff checkboxes and Suspend/Reactivate/Remove controls. Former Staff is collapsed. Suspension/removal updates only that gym's binding; it never deletes Auth identities or history. Both actions show the person's name for confirmation. A reminder asks owners to suspend access promptly when a person leaves. Permissions and status are refreshed on focus and every minute; protected requests always verify on the server, even while an old page remains open.
- Ordinary staff menus contain only My Account and Sign Out. Existing desk operations remain; Manual Check-In now has an explicit grant. Grants for Reports, Export/Print, announcement management, pricing and read-only Subscription reveal only their associated menu/actions. A grant never converts a staff account into the registered owner.
- `assets/announcements.js` and its existing HTML form add Everyone in this gym, Members only, Staff only, and selected members/staff. An audience count is checked before the publish confirmation. Targets are resolved and frozen per saved publication; scheduling/content/audience changes update unread revisions. Pin changes keep recipients and unread revisions unchanged. Recipient lists are available only to authorized announcement managers. Recipients receive only their own eligible active notices through the bell.
- `assets/reports-ui.js` checks export permission before CSV, Print, and before/after asynchronous Excel generation. `gym/reports.html` installs that guard. Denial of Export does not revoke otherwise valid report reading. **A person who can read report data can still copy it or use their browser's own tools; the Export checkbox controls the app's supported export/print actions, not a DRM boundary.**
- `supabase/functions/iv-branch-auth/index.ts` adds authenticated `own_recovery`. The server derives both the identity and mail recipient; caller-supplied user IDs or addresses cannot select another account. Uses rate limiting and the existing recovery callback. The generated Dashboard entry contains the same code.

## Database changes in 041

Adds three RLS-protected private tables: staff_access, announcement_targets, and account_announcement_reads. Adds audience and audience_selection to iv_announcements. Existing publications default to members-only, preserving their member feed and read receipts. Existing active staff retain their current manual check-in and report-read access; report export starts ungranted. Existing deactivated staff are marked suspended. New staff permissions start ungranted; the owner chooses them explicitly. Permission updates synchronize the legacy report-read grant to avoid inconsistent controls.

Adds/updates scoped RPCs for permission/lifecycle management, pricing-only changes, read-only subscription views, audience preview, targeted publishing/pinning, private account notifications, member notice filtering and report-read authorization. The manual check-in RPC now checks its explicit permission before delegating to the existing admission logic. Current subscription entitlement, QR attendance, financial calculations, owner agreement acceptance, legal publication, subscription requests/payment approvals, staff provisioning, backups and purging keep their original authority. Staff can never grant privileges, manage staff or accept owner agreements via this feature.

Suspension and removal disable the tenant role, so normal sign-in and protected operations are rejected from existing sessions. Already displayed/cached information cannot be remotely erased; the live access check subsequently redirects. No authentication account, balance, transaction, attendance or audit-history row is deleted by 041 or ordinary staff removal. Full tenant purging retains its separately authorized behavior and cascades the new tenant-linked rows.

## Verification and limits

`npm test`, the Pages build, generated Dashboard/function checks and PostgreSQL grammar parsing are run locally. The database script is **parsed, never executed**, including in local tests. Browser tests use mocked RPCs; they do not prove deployed database behavior.

Before rollout, manually verify with separate owner/staff/member sessions in a test gym:

- Ordinary staff get only the two menu items; their own recovery request goes to their recorded inbox.
- Grant/revoke each permission; directly calling a protected RPC after revocation fails, including from an already-open session. Manual check-in fails without its grant; QR admission remains independent.
- Staff viewing Subscription cannot submit requests, payments, acceptances or administrative actions.
- Reports read without export remains readable; supported export/print operations are blocked until the export grant is added, including revocation during Excel preparation.
- Suspend blocks login/actions; Reactivate restores the saved grants. Remove moves the person to Former Staff without changing another gym or historical attribution.
- Publish to each audience and individual recipients. Other members/staff/gyms cannot retrieve the notice or recipient list. Read status persists across login. Scheduled, expired, archived and edited notices behave correctly; pinning does not broaden the audience.
- Private launcher has been removed: root makes no database reads and `/gym/` still authenticates normally.
