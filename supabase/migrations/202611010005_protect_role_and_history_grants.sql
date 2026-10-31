-- MANUAL REVIEW/EXECUTION ONLY. Behavior-changing ACLs; no records are changed.
-- Requires reviewed M4 table ownership/RLS and existing postgres-owned definers.
-- Order: after 001/002; independent of optional creator-default files 003/004.
-- Existing authenticated RPC EXECUTE and service_role grants are not changed.
-- SECURITY DEFINER postgres functions keep their existing table-write authority.
-- Role and log tables currently have SELECT policies only; no legitimate direct
-- authenticated INSERT/UPDATE/DELETE path is enabled by the supplied policies.
-- Failure aborts this transaction; ROLLBACK. Do not restore unsafe blanket grants
-- as a compatibility workaround. Does not itself repair the two read policies.
BEGIN;
SET LOCAL search_path = pg_catalog;
DO $preflight$
DECLARE item text; signature text; function_oid oid;
BEGIN
 FOREACH item IN ARRAY ARRAY['iv_user_roles','iv_financial_transactions',
   'iv_attendance_logs','iv_activity_logs','iv_staff_sessions'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname=item AND c.relkind='r'
    AND pg_get_userbyid(c.relowner)='postgres' AND c.relrowsecurity AND NOT c.relforcerowsecurity) THEN
   RAISE EXCEPTION 'Ownership/RLS differs from reviewed M4 for %',item;
  END IF;
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['public.iv_topup(text,numeric,uuid)',
   'public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)',
   'public.iv_checkin(text,text)','public.iv_log_event(text,text,text)',
   'public.iv_staff_event(text,text)','public.iv_member_auth_signup()'] LOOP
  function_oid:=to_regprocedure(signature)::oid;
  IF function_oid IS NULL OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=function_oid
    AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres') THEN
   RAISE EXCEPTION 'Expected postgres SECURITY DEFINER dependency missing/changed: %',signature;
  END IF;
 END LOOP;
END
$preflight$;
REVOKE ALL PRIVILEGES ON TABLE public.iv_user_roles,
 public.iv_financial_transactions, public.iv_attendance_logs,
 public.iv_activity_logs, public.iv_staff_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.iv_user_roles,
 public.iv_financial_transactions, public.iv_attendance_logs,
 public.iv_activity_logs, public.iv_staff_sessions TO authenticated;
-- Explicit column ACLs can survive a table-level REVOKE. Clear them as well.
DO $columns$
DECLARE item record;
BEGIN
 FOR item IN SELECT c.relname,a.attname FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='public' AND c.relname IN ('iv_user_roles','iv_financial_transactions',
   'iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
   AND a.attnum>0 AND NOT a.attisdropped LOOP
  EXECUTE format('REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON TABLE public.%I FROM PUBLIC, anon, authenticated',
   item.attname,item.attname,item.attname,item.attname,item.relname);
 END LOOP;
END
$columns$;
DO $verify$
DECLARE relation_name text; role_name text;
BEGIN
 FOREACH relation_name IN ARRAY ARRAY['public.iv_user_roles','public.iv_financial_transactions',
  'public.iv_attendance_logs','public.iv_activity_logs','public.iv_staff_sessions'] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(role_name,relation_name,'INSERT')
    OR has_table_privilege(role_name,relation_name,'UPDATE')
    OR has_table_privilege(role_name,relation_name,'DELETE')
    OR has_table_privilege(role_name,relation_name,'TRUNCATE')
    OR has_table_privilege(role_name,relation_name,'TRIGGER')
    OR has_any_column_privilege(role_name,relation_name,'INSERT')
    OR has_any_column_privilege(role_name,relation_name,'UPDATE')
    OR (role_name='anon' AND has_any_column_privilege(role_name,relation_name,'SELECT')) THEN
    RAISE EXCEPTION 'Unexpected inherited/direct write or anonymous read privilege for % on %',role_name,relation_name;
   END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated',relation_name,'SELECT') THEN
   RAISE EXCEPTION 'Authenticated RLS-filtered SELECT was not retained for %',relation_name;
  END IF;
 END LOOP;
END
$verify$;
COMMIT;
-- Expected: authenticated SELECT only (subject to RLS), no anon SELECT/writes.
SELECT table_name,grantee,privilege_type FROM information_schema.table_privileges
WHERE table_schema='public' AND table_name IN ('iv_user_roles','iv_financial_transactions',
 'iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
 AND grantee IN ('PUBLIC','anon','authenticated') ORDER BY table_name,grantee,privilege_type;
