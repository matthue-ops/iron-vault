# Phase 1 manual migrations

**Prepared only; none executed or assumed applied.** Review [the complete coordinated cutover](../../docs/security/phase1-cutover.md) and [single progress tracker](../../docs/security/phase1-status.md). They supersede historical partial-stage holds and repeated prerequisite lists.

**One-file option:** [phase1_security_install.sql](../manual/phase1_security_install.sql) is an atomic combined installation for an untouched inspected schema, excluding optional 004, with preservation assertions. Use EITHER this bundle OR the individual path, never both. It was generated only; no SQL executed.

Run each approved file separately in numeric order, 001 through 015. The only optional file is **004**, which changes supabase_admin defaults and must be skipped if platform authority is unavailable. Never escalate managed-role membership. Existing 001/002/007/011/012 definition/policy guards must not be bypassed; if a file was already manually committed, verify that fact rather than rerunning it blindly.

| Number | Scope | Existing data effects |
| --- | --- | --- |
| 001 | API TRUNCATE removal | No record changes. |
| 002 | Existing function execution restrictions | Authenticated ordinary RPC/service execution retained. |
| 003/004 | Creator/public-schema future defaults | Existing objects unchanged; 004 optional. |
| 005 | Role/history direct-write protection | Authenticated RLS SELECT retained; no record changes. |
| 006/007 | Explicit report permissions and M4 isolation fix | New permission objects, corrected policy correlation; no historical rewrite. |
| 008/009 | Permission tenant FK and tenant/contact uniqueness | No merges/deletions; duplicates abort safely. |
| 010/011 | Receipt foundation and server financial APIs | Original ledger/request IDs retained; old RPC signatures validated through secure core. |
| 012 | Base write closure, safe views, scoped profile/settings/deactivation APIs | Adds enabled/default-true and disabled_at role fields; no account/history deletion. |
| 013 | Member wallet purchases and opaque daily pass tickets | No initial balance/history change; old unsigned QR codes cease authorizing entry. |
| 014 | Branch mappings, account jobs, real-address verification/recovery | Backfills six scoped identities from the snapshot; no Auth table writes or account recreation in SQL. Trigger attachment preserved. |
| 015 | Server report snapshots and atomic profile restore | No financial/credential restore or historical rewrite. |

001–015 require coordinated matching Edge/app cutover; do not publish old HTML against the closed base tables. The earlier 010/011 warning is resolved by including 012–015, not by applying 011 alone. See the runbook for exact secrets/configuration and the four functions to deploy only after separate authorization. SMTP settings already configured for Supabase Auth are not automatically available as Edge secrets.

Every file has a transaction and metadata verification; failures require ROLLBACK and review. A later failure does not undo earlier commits. Fix forward while preserving records; never restore public ALL policies, unsafe financial bodies or blanket grants. Files 009 and integrity changes can acquire write-blocking locks; use the scheduled maintenance window. Public-schema default cleanup alone cannot revoke global PUBLIC EXECUTE, so per-object ACLs are set explicitly. Only iv_visible_gyms() intentionally allows anonymous safe branding reads.

Read-only acceptance is in ../verification/phase1_acceptance.sql. Capture its V1/V2 preservation baseline before application and compare after; do not invoke mutating RPCs from SQL Editor as an authorization test. Test real RLS with actual authenticated/anonymous clients and dedicated approved fixtures. No SQL, Supabase call, reset, deployment or merge was performed by the agent.

### 016: Optional member email confirmation

For installations through 015, run only `202611010016_member_optional_email_verification.sql`, then manually deploy the updated standalone `iv-branch-auth` and `iv-create-member` functions. Members can sign in without email proof; approval and revocation still apply. Existing non-revoked ACTIVE/PENDING member roles blocked by the former mail gate are enabled. Owner/staff activation is unchanged. Password recovery still requires an emailed recovery token. No SQL has been executed by the agent.

### 017: Super Admin permanent tenant purge

After 016, manually run only `202611010017_super_admin_tenant_purge.sql` and deploy the new standalone `iv-purge-tenant` function (JWT ON). The migration installs definitions, not a purge invocation. See `docs/security/tenant-purge.md` for review, confirmation, resumable Auth cleanup and limits. No live deletion has been performed by the agent.

### 018–020: Short display codes, staff contact policy and clearer reports

For an existing installation through 017, run only `supabase/manual/usability_update.sql` once; it combines 018, 019 and 020 atomically. Internal IDs, balances and history are preserved. Then update existing iv-branch-auth (JWT OFF), provision-gym-tenant (JWT ON), and the frontend. See docs/security/usability-update.md. No SQL executed by the agent.

### 022: Activity names and roles

After installed 020/021, manually run only `supabase/manual/activity_actor_names.sql` (same contents as `202611020022_activity_actor_names.sql`). It replaces the report snapshot function and appends tenant-scoped actor names/roles; it does not rewrite records or change permissions. Apply SQL before merging the matching frontend. No Edge update is needed. See `docs/security/activity-actor-names.md`.

### 023: Historical wallet values in Money

After installed 022, manually run only `supabase/manual/wallet_after_history.sql` (same as `202611020023_wallet_after_history.sql`). It reads saved balances from exactly linked financial receipts in the existing report RPC; no transaction, balance, receipt or ledger data is rewritten. Unavailable history is labeled rather than guessed. Apply SQL before the matching frontend; no Edge update is needed. See `docs/security/wallet-after-history.md`.

### 024: Admin announcements, stage one

After installed 023, manually run only `supabase/manual/admin_announcements.sql` (same as `202611020024_admin_announcements.sql`). Adds announcement storage and owner/staff-scoped RPCs; owner writes only, Remove archives. Existing account, balance, plan and financial records are preserved. New notices follow the existing explicitly confirmed whole-tenant purge. Apply SQL before the matching frontend; no Edge update is needed. Member-profile display and notification delivery are not included. See `docs/security/admin-announcements-stage1.md` for rollout and acceptance checks. No SQL executed by the agent.

### 025: Member announcement display and read receipts

After successful 024, manually run only `supabase/manual/member_announcements.sql` (same as `202611020025_member_announcements.sql`). Adds announcement content revisions, a private per-member read-receipt table and a member-only active-notice RPC. Text/schedule edits become unread; pin-only edits do not. Existing member/financial data remains intact. Apply SQL before the matching frontend; no Edge update needed. See `docs/security/member-announcements.md`, including claim-delivery limits and live acceptance checks. No SQL executed by the agent.

### 026: Readable gym portal URLs

After installed 025, manually run only `supabase/manual/gym_portal_urls.sql` (same as `202611030026_gym_portal_urls.sql`). Adds private persistent URL mappings and an insert trigger for new gyms; appends `portal_slug` to the existing safe branding view without changing its role/status projection. Existing tokens, accounts, balances, plans and history are preserved. Apply SQL before reviewing the matching frontend/Vercel routing; no Edge update is needed. Original key-based links and printed entrance QRs remain supported. See `docs/security/gym-portal-urls.md` for assignment rules, optional read-only verification and rollout. No SQL executed by the agent.

### 027: Live member, desk and Super Admin updates

After installed 026, manually run only `supabase/manual/live_dashboard_updates.sql` (same as `202611030027_live_dashboard_updates.sql`). Adds a protected identifier-only signal table, scoped read helpers/checkpoints, deferred source-change triggers and Realtime publication membership for that signal table only. Existing financial/profile/role records are not rewritten. Client signal access is read-only and role/gym/member scoped. Apply SQL before the matching frontend; no Edge update is needed. See `docs/security/live-dashboard-updates.md` for publication requirements, read-only verification and mandatory multi-device/RLS acceptance. No SQL executed by the agent.

### 042–043: Linked refunds, account notices and pending-payment verification

After confirmed 041, apply `supabase/manual/refunds_member_notices.sql` (042), then `supabase/manual/pending_payment_verification.sql` (043), once each. Numbered files are identical review copies, not additional SQL to run. Preserve original financial/acceptance records; adds private adjustment/notice/verification/reminder tables and scoped RPC wrappers. Staff request/approval grants remain off until selected. Optional reminder Edge deployment, secrets, Vault and schedule are separate manual setup; no email or scheduler is activated by these migrations. Deploy matching frontend after SQL succeeds. See [operational safeguards](../../docs/operational-safeguards-review.md) for impacts, date policy and required staging acceptance. No SQL executed by the agent.

### 044: Refund usability, short references and member entry feedback

After confirmed 043, manually apply `supabase/manual/refund_usability_entry_feedback.sql` once (identical numbered 044 copy). Adds a private unique reference registry, a separate actual cash payout receipt, readable refund audit snapshots and authorized latest-entry method data. Existing ledger/history stays intact; old codes are not automatically backfilled. Requires the matching frontend; no Edge/reminder configuration changes. See [the 11-item implementation and staging checklist](../../docs/refund-usability-entry-feedback.md). No SQL executed by the agent. Do not rerun 042/043.
