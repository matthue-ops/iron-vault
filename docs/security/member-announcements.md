# Member announcements: stage two

The member profile has a Notices bell with an unread badge and a wide announcement dialog. Only notices currently within their gym's start/end schedule are returned. The end time is exclusive. Members can reopen active notices through the bell; expired, future and removed notices are unavailable to members.

Opening the profile only updates the unread badge and bell animation; it never opens an automatic popup or claims a notice. Read receipts persist across devices and are saved when the member opens the bell, acknowledging only the exact ID/revision pairs fetched for display. Title, message and start/end schedule changes increment a content revision and become unread again; pinning/unpinning alone does not.

The feed refreshes about once a minute and on window focus. Expired notices are removed locally at their known end time. Owner removal/edits propagate on the next refresh. A failed announcement request leaves the profile usable and displays an unavailable message. No email or push notification is sent. Previously saved read receipts are retained. The installed RPC's legacy claim mode remains for compatibility, but this frontend never invokes it.

## Manual rollout

1. Ensure stage-one migration **024** completed successfully. If the earlier editor paste was truncated, copy its complete file through the final `COMMIT;` and run it manually first. Stage-one installation is not assumed confirmed.
2. Review and manually run **only** [member_announcements.sql](../../supabase/manual/member_announcements.sql). This is identical to `202611020025_member_announcements.sql`; do not run both copies. The exact file can be reapplied. It adds `content_revision` to the announcement table, its update trigger, a private member read-receipt table and a scoped member RPC. No existing member, plan, wallet, payment or report records are rewritten. Existing announcements start at content revision 1.
3. Test the matching preview with approved owner/member accounts. No Edge Function update is required. Merge the frontend PR after acceptance through the usual Vercel workflow.

Read receipts are keyed to the member, notice and content revision. Direct table access is revoked with RLS enabled; the RPC derives the member identity from `auth.uid()`, requiring an enabled, non-revoked member role, active member and active gym. It checks tenant scope independently of the browser and locks authority during reads/writes. It cannot list scheduled, expired, removed or other-gym notices. Receipts follow their member, announcement or gym if those records are explicitly deleted through existing authorized workflows. This change introduces no cleanup job or financial writes.

## Acceptance

Create a harmless current notice in gym A. Open a gym A member profile: confirm no dialog opens automatically, but the bell indicates an unread notice. Reload before reading and confirm it remains unread. Open the bell and confirm the notice displays and its unread indication clears. Reopen the profile or another device and confirm read status persists. Change the message/schedule: confirm the badge returns without any automatic popup. Pin-only changes must not mark it unread. Verify expiry/removal hide notices and future notices remain hidden.

Check two simultaneous devices for one member, and a second member independently. Test member deactivation, role revocation, inactive gyms, wrong-gym requests and owner/staff requests against the member RPC. Confirm all are denied appropriately and normal QR, purchases, profile updates and sign-out still work. Test against the live backend using approved fixtures; local mocks cannot establish live authorization or concurrent database acceptance.

Local validation: controller/SQL contract tests, full existing test suite, SQL and PL/pgSQL parsing without execution, and mocked Chromium checks at 320, 375 and 1280 pixels. The agent did not execute SQL, deploy production or merge a PR.

## Member profile usability follow-up

On phones (below 640px), Notices and Sign Out use accessible icon-only 44px controls at the top right. An unread count and gentle bell animation indicate new notices; reduced-motion preferences disable the animation. An empty badge is hidden. Personal Information & Security is collapsed by default using a keyboard-accessible disclosure; its existing form and save behavior are preserved. No database or SQL change is required for this follow-up.
