-- SELECT-only manual inspection; no role/default changes or RPC execution.
-- M1-M7 need not be rerun. M5A did not include executor/creator memberships.
SELECT current_user AS executing_role,session_user AS session_role,
 current_setting('server_version_num') AS server_version_num;
SELECT target.rolname AS default_creator,
 current_user=target.rolname AS is_creator,
 (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS executor_is_superuser,
 pg_has_role(current_user,target.oid,'MEMBER') AS executor_is_member,
 pg_has_role(current_user,target.oid,'USAGE') AS executor_inherits_privileges
FROM pg_roles target WHERE target.rolname IN ('postgres','supabase_admin');
-- This predicts ordinary PostgreSQL authority, not a guarantee that Supabase
-- permits changing platform-owned settings. Native permission failures must stand.
SELECT child.rolname AS member_role,parent.rolname AS granted_role,m.admin_option
FROM pg_auth_members m JOIN pg_roles child ON child.oid=m.member
JOIN pg_roles parent ON parent.oid=m.roleid
WHERE child.rolname IN ('anon','authenticated',current_user)
ORDER BY member_role,granted_role;
-- Do not adopt/overwrite an existing private application namespace without review.
SELECT n.nspname,pg_get_userbyid(n.nspowner) AS owner FROM pg_namespace n
WHERE n.nspname='ironvault_private';
