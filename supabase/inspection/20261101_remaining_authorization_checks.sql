-- SELECT-only, manual execution by the owner. No RPCs are invoked.
-- Only missing result sets and previously uninspected objects are requested.
-- If these exact results already exist, return them rather than rerunning.
-- No emails, passwords, password hashes, tokens or keys are returned.

-- M1: Missing first result from 4A (the supplied file contains provider counts only).
SELECT count(*) AS total_auth_users,
  count(*) FILTER (WHERE nullif(btrim(email),'') IS NOT NULL) AS users_with_email,
  count(*) FILTER (WHERE nullif(btrim(email),'') IS NOT NULL
    AND email_confirmed_at IS NULL) AS email_unconfirmed,
  count(*) FILTER (WHERE nullif(encrypted_password,'') IS NOT NULL)
    AS users_with_password_credentials,
  count(*) FILTER (WHERE nullif(encrypted_password,'') IS NULL)
    AS users_without_password_credentials
FROM auth.users;

-- M2: Missing first result from 4E (the supplied file contains cross-tenant count only).
WITH duplicates AS (
  SELECT tenant_id,lower(btrim(email)) AS normalized_email,count(*) AS records
  FROM public.members
  WHERE nullif(btrim(email),'') IS NOT NULL
  GROUP BY tenant_id,lower(btrim(email)) HAVING count(*)>1
)
SELECT count(*) AS duplicate_groups_within_tenant,
  coalesce(sum(records),0) AS affected_member_records FROM duplicates;

-- M3: Role vocabulary/scope is not present in the aggregated 4D result.
SELECT role::text AS role_name,count(*) AS bindings,
  count(*) FILTER (WHERE tenant_id IS NULL) AS unscoped_bindings,
  count(*) FILTER (WHERE member_id IS NOT NULL) AS member_links
FROM public.iv_user_roles GROUP BY role::text ORDER BY role_name;

-- M4: 2A-2C covered owners/members, not these authority/history tables.
WITH targets AS (
 SELECT c.oid,c.relname,c.relowner,c.relrowsecurity,c.relforcerowsecurity
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind IN ('r','p')
   AND c.relname IN ('iv_user_roles','iv_financial_transactions',
     'iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
)
SELECT t.relname AS table_name,pg_get_userbyid(t.relowner) AS owner,
 t.relrowsecurity AS rls_enabled,t.relforcerowsecurity AS rls_forced,
 r.rolname AS api_role,
 has_table_privilege(r.oid,t.oid,'SELECT') AS can_select,
 has_table_privilege(r.oid,t.oid,'INSERT') AS can_insert,
 has_table_privilege(r.oid,t.oid,'UPDATE') AS can_update,
 has_table_privilege(r.oid,t.oid,'DELETE') AS can_delete,
 has_table_privilege(r.oid,t.oid,'TRUNCATE') AS can_truncate
FROM targets t CROSS JOIN pg_roles r
WHERE r.rolname IN ('anon','authenticated') ORDER BY table_name,api_role;

SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
FROM pg_policies WHERE schemaname='public'
 AND tablename IN ('iv_user_roles','iv_financial_transactions',
   'iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
ORDER BY tablename,policyname;

SELECT c.relname AS table_name,a.attname AS column_name,r.rolname AS api_role,
 has_column_privilege(r.oid,c.oid,a.attnum,'SELECT') AS can_select,
 has_column_privilege(r.oid,c.oid,a.attnum,'INSERT') AS can_insert,
 has_column_privilege(r.oid,c.oid,a.attnum,'UPDATE') AS can_update
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid CROSS JOIN pg_roles r
WHERE n.nspname='public' AND c.relkind IN ('r','p')
 AND c.relname IN ('iv_user_roles','iv_financial_transactions',
   'iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
 AND a.attnum>0 AND NOT a.attisdropped AND r.rolname IN ('anon','authenticated')
ORDER BY table_name,column_name,api_role;

-- M5: Determine whether public search_path has an untrusted schema CREATE risk.
SELECT rolname AS api_role,
 has_schema_privilege(oid,'public','CREATE') AS can_create_in_public
FROM pg_roles WHERE rolname IN ('anon','authenticated') ORDER BY rolname;

-- Direct API-role memberships, to explain any inherited execution/table grants.
SELECT child.rolname AS member_role,parent.rolname AS granted_role,m.admin_option
FROM pg_auth_members m JOIN pg_roles child ON child.oid=m.member
JOIN pg_roles parent ON parent.oid=m.roleid
WHERE child.rolname IN ('anon','authenticated') ORDER BY member_role,granted_role;

-- M6: rls_auto_enable is an event trigger, not a row trigger or an ordinary RPC.
SELECT e.evtname,e.evtevent,e.evtenabled,e.evttags,n.nspname AS function_schema,
 p.proname AS function_name,pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_event_trigger e JOIN pg_proc p ON p.oid=e.evtfoid
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='rls_auto_enable' ORDER BY e.evtname;

-- Table types/constraints, ordinary trigger attachments and indexes remain in
-- 20261101_trigger_dependencies.sql; do not repeat if those results already exist.

-- M7: Future function/table privileges must not silently recreate the same exposure.
SELECT owner.rolname AS object_creator,
 CASE WHEN d.defaclnamespace=0 THEN '(global)' ELSE n.nspname END AS schema_name,
 d.defaclobjtype AS object_type,d.defaclacl AS default_acl
FROM pg_default_acl d JOIN pg_roles owner ON owner.oid=d.defaclrole
LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
WHERE d.defaclobjtype IN ('f','r') AND (d.defaclnamespace=0 OR n.nspname='public')
ORDER BY object_creator,schema_name,object_type;
