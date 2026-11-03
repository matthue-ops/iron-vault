# Live updates for members, gym desks and Super Admin

Owner approved secure change signals and extended the scope to Super Admin. This stage updates `gym/memberprofile.html`, `gym/admin.html` and both Super Admin entry pages. It does not change report calculations, payment processing, admission rules or login authorization.

## Behavior

A committed top-up updates the member's balance and other open desk views. Purchases update plan and expiry; accepted check-ins update entry indicators. Registrations, approval/status changes, permitted profile edits, gym branding/pricing and staff/report-access changes refresh the relevant displays. Super Admin receives authorized changes across gyms, including counts and an open View Branch panel. The branch member table now includes Entry today, using Manila dates.

The normal healthy-connection target is roughly 1–2 seconds after commit, not a delivery guarantee. No automatic transaction is performed by a refresh. The displayed value is read again from the secure views; an incoming signal's payload never supplies a balance or grants admission. A balance change alone is not proof of a particular payment: use the transaction result/history and the existing safe retry flow to resolve an uncertain payment.

A small status line distinguishes live, reconnecting, fallback, offline and unavailable states. Hidden/offline pages stop subscriptions. Returning to the page reconnects and catches up. While visible, a read-only checkpoint runs about every 20 seconds to detect missed signals and recheck access. Network failures back off; they retain the last confirmed display. Auth/access failures clear the protected display and require sign-in again. A revoked account may not receive a signal precisely because it no longer has access; the checkpoint catches that loss while the existing server rules deny new actions immediately.

Checkpoints exchange a digest and, only when needed, a small identifier/revision list. The browser compares revisions and reads changed records rather than repeatedly downloading full rosters. Initial connection, explicit focus/reconnect catch-up, removed checkpoints, or gym-wide permission changes can require a full scoped read. A Manila day change also refreshes today's entry indicators. Current report pages retain their existing refresh/export behavior; this stage targets the member and dashboard screens above.

## Database scope

Manual migration 027 adds `iv_live_signals` with only kind, entity ID, gym ID, revision and change time. It contains no names, email, phone, password, balance or payment amount. One row is retained per changed member/gym plus a system checkpoint; it is not another transaction history. Member deletion leaves an identifier-only invalidation; whole-gym purge removes that gym's signals through its foreign key and emits a global invalidation for Super Admin.

New protected helper functions and SELECT-only RLS allow:

- Enabled, non-revoked members of an active gym: their own member signal and their gym-setting signal.
- Enabled, non-revoked owner/staff accounts: signals for their active gym.
- Enabled, non-revoked global Super Admin: all signals, including system changes.
- Anonymous clients: no signal or checkpoint access.

Clients have no INSERT/UPDATE/DELETE grant on the signal table. Private trigger functions are not executable by API roles. The new RPC is a read-only, scoped checkpoint. Existing account, financial, attendance and profile permissions remain unchanged.

Deferred constraint triggers emit signals after business statements finish in the same transaction, reducing early metadata-lock inversion. They observe members, gyms, roles and staff report permissions. They do not rewrite existing source records. Rollback produces no committed signal. WebSocket delivery is not part of the payment transaction; source writes do not wait for a browser to acknowledge receipt.

Only the new signal table is added to `supabase_realtime`. This migration does not publish member, role, payment or credential tables. Browser subscriptions request INSERT/UPDATE events only, avoiding Postgres DELETE subscription limitations. Existing unrelated publication membership is not modified. The installation aborts if the publication is missing, publishes all tables, or does not support INSERT/UPDATE; review that configuration rather than bypassing privacy controls.

## Browser safeguards

Every data refresh verifies identity and scope before and after the read. Replies for an earlier account, role, gym or page lifecycle are dropped. Bursts coalesce and refreshes do not overlap. The coordinator is paused around local payment/admission/profile/registration actions, including an unfinished action across tab pause/reconnect, so older reads cannot replace newly written results. It never creates or clears financial request IDs.

The adapters use dedicated read-only paths, not repeated legacy initialization/load paths that can call profile saves. Dirty and focused fields, selection, searches, open disclosures and scroll state are preserved. Read-only balances/statuses and plan/expiry fields still update. Existing expired-plan presentation is derived locally without saving entitlement changes. An open scanner is not restarted. Super Admin's branch member renderer is separate from its staff form renderer; member updates do not reopen/reset that panel. Explicit user actions retain their normal form-reset behavior.

## Manual rollout

1. Confirm the existing installation through 026. Review and manually run **only** [live_dashboard_updates.sql](../../supabase/manual/live_dashboard_updates.sql), identical to `202611030027_live_dashboard_updates.sql`. Copy the entire file through its final `COMMIT;`; do not run both copies. The exact file can be reapplied without resetting revisions. DDL briefly locks affected objects, so use a quiet period.
2. Run the optional read-only [verification queries](../../supabase/verification/live_dashboard_updates.sql) yourself. Confirm the signal table is in the publication, SELECT policy is scoped, client writes are denied, and the four triggers are deferred. Do not publish source business tables as a workaround.
3. Test the matching branch preview using approved accounts on at least two devices. If preview sign-in needs its exact origin added to the existing CORS settings, do that through the established authentication setup. No Edge Function deployment is required.
4. Perform the live acceptance below, then review/merge the frontend PR through the normal Vercel workflow. No production promotion or SQL execution is performed by the agent.

Without 027 installed, the existing pages still load normally and show automatic updates unavailable; manual refresh remains usable. SQL success and hosted Realtime acceptance are not assumed.

## Live acceptance

Use harmless, approved fixtures and reconcile every actual payment. Keep a member profile, owner desk, staff desk and Super Admin View Branch open. Record a single top-up: verify balance changes everywhere without reloading. Check a plan purchase, QR/manual entry, registration/approval, pricing change, staff deactivation and report-permission change. Confirm counts, plan/expiry and entry indicators; verify owner/staff/member limitations remain enforced.

Keep an unsaved name, custom amount, staff draft and search open during updates. Confirm they remain intact and the scanner does not restart. Simulate a connection interruption and reconnect; check catch-up. Test revoked member/staff/Super Admin access and account changes during a delayed read. With real authenticated clients, verify that anonymous, other-gym and other-member subscriptions cannot receive protected signals or records. Do not rely on SQL Editor's privileged role to establish RLS correctness.

Validation prepared locally: 273 Node tests passed; SQL, SQL/PLpgSQL bodies and publication block syntax parsed without execution. Mocked Chromium shared-state tests verified updates across member, owner, staff and both Super Admin pages, unsaved forms/search, scanner continuity, permission/branding changes, checkpoint/reconnect catch-up, offline recovery with a pending local action, member/Super Admin revocation, gym creation/status/removal counts and zero background financial/profile writes. These tests simulate event delivery; they do not prove hosted publication/RLS behavior, backend concurrency or actual production latency. The user must complete live acceptance after manually installing SQL.
