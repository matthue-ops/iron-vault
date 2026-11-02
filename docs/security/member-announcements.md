# Member announcements: stage two

The member profile has a Notices bell with an unread badge and a wide announcement dialog. Only notices currently within their gym's start/end schedule are returned. The end time is exclusive. Members can reopen active notices through the bell; expired, future and removed notices are unavailable to members.

Opening the profile automatically shows unread announcements once per member per content revision. Read receipts persist across devices. An atomic server claim prevents two simultaneous devices from both showing the automatic popup. Title, message and start/end schedule changes increment a separate content revision, including edits reverting earlier text. Pinning/unpinning alone does not. Opening the bell acknowledges only the exact ID/revision pairs fetched for display.

A popup claim is saved before delivery to the browser. If the connection is lost after the claim commits, that automatic popup may be missed; the notice remains available through the bell. This is display tracking, not proof the member actually read the message. No email, push notification, background operating-system notification or receipt audit is added.

While the profile stays open, the feed refreshes about once a minute and on window focus; newly published/updated notices get an unread badge. The automatic popup happens when the profile initializes, rather than interrupting an ongoing purchase or QR action. Expired notices are also removed locally at their known end time. Owner removal/edits propagate on the next refresh. A failed announcement request leaves the member profile usable and shows an unavailable message; no cached private notices are restored.

## Manual rollout

1. Ensure stage-one migration **024** completed successfully. If the earlier editor paste was truncated, copy its complete file through the final `COMMIT;` and run it manually first. Stage-one installation is not assumed confirmed.
2. Review and manually run **only** [member_announcements.sql](../../supabase/manual/member_announcements.sql). This is identical to `202611020025_member_announcements.sql`; do not run both copies. The exact file can be reapplied. It adds `content_revision` to the announcement table, its update trigger, a private member read-receipt table and a scoped member RPC. No existing member, plan, wallet, payment or report records are rewritten. Existing announcements start at content revision 1.
3. Test the matching preview with approved owner/member accounts. No Edge Function update is required. Merge the frontend PR after acceptance through the usual Vercel workflow.

Read receipts are keyed to the member, notice and content revision. Direct table access is revoked with RLS enabled; the RPC derives the member identity from `auth.uid()`, requiring an enabled, non-revoked member role, active member and active gym. It checks tenant scope independently of the browser and locks authority during reads/writes. It cannot list scheduled, expired, removed or other-gym notices. Receipts follow their member, announcement or gym if those records are explicitly deleted through existing authorized workflows. This change introduces no cleanup job or financial writes.

## Acceptance

Create a harmless current notice in gym A. Open a gym A member profile: confirm its popup appears, close it, reopen the profile/device and confirm it does not automatically repeat. Use the bell to read it again. Verify pinned notices appear first in the notice list. Change the message or schedule and confirm a new automatic popup on next profile initialization; change only pin status and confirm no repeat. Leave the page open and confirm new notices become unread through the badge. Verify expiry and removal hide notices and future notices remain hidden.

Check two simultaneous devices for one member, and a second member independently. Test member deactivation, role revocation, inactive gyms, wrong-gym requests and owner/staff requests against the member RPC. Confirm all are denied appropriately and normal QR, purchases, profile updates and sign-out still work. Test against the live backend using approved fixtures; local mocks cannot establish live authorization or concurrent database acceptance.

Local validation: controller/SQL contract tests, full existing test suite, SQL and PL/pgSQL parsing without execution, and mocked Chromium checks at 320, 375 and 1280 pixels. The agent did not execute SQL, deploy production or merge a PR.

## Member profile usability follow-up

On phones (below 640px), Notices and Sign Out use accessible icon-only 44px controls at the top right. An unread count and gentle bell animation indicate new notices; reduced-motion preferences disable the animation. An empty badge is hidden. Personal Information & Security is collapsed by default using a keyboard-accessible disclosure; its existing form and save behavior are preserved. No database or SQL change is required for this follow-up.
