# Admin announcements: stage one

Adds an Announcements button beside Reports & Analytics on the gym admin page. Owners can create, preview, edit, schedule, pin/unpin and remove notices. Staff can read notices but cannot manage them. Schedules use Manila time; the end time is exclusive. Status reflects the server time displayed in the panel; Refresh updates it.

This stage does not display notices on member profiles or send emails/push notifications. Member display is a separate later stage.

## Manual rollout

1. On an installation already through migration 023, review and manually run **only** [admin_announcements.sql](../../supabase/manual/admin_announcements.sql) in Supabase SQL Editor. It is identical to migration `202611020024_admin_announcements.sql`; do not run both copies. The exact file can be reapplied.
2. If SQL succeeds, open the matching branch preview and perform the acceptance checks below. No Edge Function update is needed. A new preview origin may need the existing authentication CORS allowlist updated.
3. Review and merge the frontend PR through the normal workflow after acceptance. Vercel handles the production deployment.

SQL creates `iv_announcements`, its index and three scoped RPCs. It does not modify existing member, balance, plan or financial records. Owner actions append entries through the existing activity logger. Direct table access is revoked and RLS enabled; the RPCs independently require an enabled owner/staff account in the selected active gym, with writes restricted to its owner. Members and unrelated gyms cannot use these APIs.

Remove archives the notice and retains it in the owner-only Removed view. This feature does not enable automatic deletion. The new table's tenant foreign key cascades only when an existing, explicitly confirmed whole-gym purge deletes that gym. Notice creator/editor references remain linked to Auth identities.

Concurrent edits use versions: a stale edit must reload and reopen Edit. New drafts keep a stable ID for safe retry after an uncertain create response. The list is paginated in groups of 20; pinned notices appear first within the selected view.

## Acceptance checks

Use approved test accounts and harmless notices. As owner, create and preview a notice, confirm Manila start/end times, edit, pin/unpin, filter schedules and remove it. Confirm it remains in Removed. As staff, confirm notices are readable and management controls are absent; direct write RPC attempts must also fail. With another gym's account, member credentials or revoked access, confirm the APIs deny access to the first gym. Confirm ordinary member operations, reporting and check-in still work.

Local checks cover controller authorization, unsafe text, stale responses, concurrent edit rejection, retry identity and SQL permission contracts. Mocked Chromium checks cover owner/staff flows at 320, 375 and 1280 pixels. SQL and PL/pgSQL were syntax-parsed only; these checks do not establish live database acceptance. No SQL execution, deployment or merge was performed by the agent.
