-- OPTIONAL creator/namespace compatibility reference; no new inspection request.
-- Current cutover uses guarded migrations; managed-creator 004 may be skipped.
-- Do not rerun completed initial/M/T inspections. See docs/security/phase1-cutover.md.
-- CANONICAL REMAINING INSPECTION FILE. SELECT-only, manual execution by owner.
-- Do NOT repeat initial 2A-4F, M1-M7 or T1-T5. They are completed inspections.
-- This consolidates ONLY the previously outstanding default-creator/namespace
-- questions. If already answered, return those existing results instead of rerunning.
-- Run each R1-R4 SELECT separately and export under its labeled filename. For an
-- empty result report "0 rows, success"; return errors unchanged. No RPCs invoked.
-- R1/R2: needed to decide which creator-scoped defaults can safely be changed.
-- supabase_admin changes are optional and must not delay urgent RLS correction.
-- R3: identifies inherited grants that can defeat effective privilege assertions.
-- R4: avoids overwriting an existing private namespace in migration 006.
-- Full progress, retrieval instructions and completion gates: docs/security/phase1-status.md.

-- SELECT-only manual inspection; no role/default changes or RPC execution.
-- M1-M7 need not be rerun. M5A did not include executor/creator memberships.
-- R1_executor.csv: retain current/session role and server version.
SELECT current_user AS executing_role,session_user AS session_role,
 current_setting('server_version_num') AS server_version_num;
-- R2_creator_authority.csv: capability only, not authority to escalate roles.
SELECT target.rolname AS default_creator,
 current_user=target.rolname AS is_creator,
 (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS executor_is_superuser,
 pg_has_role(current_user,target.oid,'MEMBER') AS executor_is_member,
 pg_has_role(current_user,target.oid,'USAGE') AS executor_inherits_privileges
FROM pg_roles target WHERE target.rolname IN ('postgres','supabase_admin');
-- This predicts ordinary PostgreSQL authority, not a guarantee that Supabase
-- permits changing platform-owned settings. Native permission failures must stand.
-- R3_memberships.csv: explicit API/executor inherited-privilege dependencies.
SELECT child.rolname AS member_role,parent.rolname AS granted_role,m.admin_option
FROM pg_auth_members m JOIN pg_roles child ON child.oid=m.member
JOIN pg_roles parent ON parent.oid=m.roleid
WHERE child.rolname IN ('anon','authenticated',current_user)
ORDER BY member_role,granted_role;
-- Do not adopt/overwrite an existing private application namespace without review.
-- R4_private_namespace.csv: an empty result means this namespace is absent.
SELECT n.nspname,pg_get_userbyid(n.nspowner) AS owner FROM pg_namespace n
WHERE n.nspname='ironvault_private';
