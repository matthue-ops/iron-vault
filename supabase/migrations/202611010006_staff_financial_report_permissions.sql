-- MANUAL REVIEW/EXECUTION ONLY; not applied by the agent.
-- Classification: additive objects + behavior-changing permission APIs; no existing
-- accounts, role bindings, balances, transaction or attendance rows are changed.
-- Requires 005 (role/history direct writes protected), reviewed iv_log_event,
-- standard Supabase auth.users UUID identity, and an unused ironvault_private schema.
-- 003/004 are independent; per-object ACLs below protect every new function even
-- when PostgreSQL's global PUBLIC EXECUTE default remains enabled.
-- Run once, then 007. Failure aborts all new objects; ROLLBACK before other SQL.
-- Do not overwrite an existing private schema/function to force this migration.
-- Owner FK for tenant_id is deferred until the owner's key/type constraints are
-- supplied; grant API validates the tenant and current staff role instead. The
-- read helper requires that role on every request, so stale grants never suffice.
-- No normal member deletion or destructive test reset is implemented here.
BEGIN;
SET LOCAL search_path = pg_catalog;
DO $preflight$
DECLARE relation_name text; role_name text; signature text;
BEGIN
 IF to_regnamespace('ironvault_private') IS NOT NULL THEN
  RAISE EXCEPTION 'ironvault_private already exists; inspect it or confirm an earlier application, do not overwrite';
 END IF;
 FOREACH signature IN ARRAY ARRAY['public.iv_can_read_financial_reports(text)',
  'public.iv_set_staff_financial_report_access(text,uuid,boolean)',
  'public.iv_list_staff_financial_report_access(text)'] LOOP
  IF to_regprocedure(signature) IS NOT NULL THEN
   RAISE EXCEPTION 'New permission API name already exists: %. Inspect before continuing',signature;
  END IF;
 END LOOP;
 FOREACH relation_name IN ARRAY ARRAY['public.iv_user_roles','public.iv_activity_logs'] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(role_name,relation_name,'INSERT')
    OR has_table_privilege(role_name,relation_name,'UPDATE')
    OR has_table_privilege(role_name,relation_name,'DELETE')
    OR has_table_privilege(role_name,relation_name,'TRUNCATE')
    OR has_any_column_privilege(role_name,relation_name,'INSERT')
    OR has_any_column_privilege(role_name,relation_name,'UPDATE') THEN
    RAISE EXCEPTION '005 has not established role/audit write protection for % on %',role_name,relation_name;
   END IF;
  END LOOP;
 END LOOP;
 IF md5(pg_get_functiondef(to_regprocedure('public.iv_log_event(text,text,text)')::oid))
  IS DISTINCT FROM '6277dda4611a2662780c5cc6bd52342e' THEN
  RAISE EXCEPTION 'iv_log_event differs from the reviewed definition; inspect before using it for permission audit';
 END IF;
END
$preflight$;
CREATE SCHEMA ironvault_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA ironvault_private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA ironvault_private TO authenticated, service_role;
CREATE TABLE ironvault_private.staff_report_permissions (
 tenant_id text NOT NULL,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 permission text NOT NULL CHECK(permission='financial_reports_read'),
 granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 granted_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
 PRIMARY KEY(tenant_id,user_id,permission)
);
ALTER TABLE ironvault_private.staff_report_permissions OWNER TO postgres;
ALTER TABLE ironvault_private.staff_report_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ironvault_private.staff_report_permissions
 FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION ironvault_private.is_gym_administrator(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT EXISTS (
  SELECT 1 FROM public.iv_user_roles actor
  WHERE actor.user_id=auth.uid() AND (
   (actor.role='super_admin' AND actor.tenant_id IS NULL)
   OR (actor.role='owner' AND actor.tenant_id::text=p_tenant
    AND EXISTS(SELECT 1 FROM public.owners gym WHERE gym.id::text=p_tenant))
  )
 );
$function$;
CREATE FUNCTION ironvault_private.can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT ironvault_private.is_gym_administrator(p_tenant) OR EXISTS (
  SELECT 1 FROM public.iv_user_roles actor
  WHERE actor.user_id=auth.uid() AND actor.role='staff' AND actor.tenant_id::text=p_tenant
   AND EXISTS(SELECT 1 FROM public.owners gym WHERE gym.id::text=p_tenant)
   AND EXISTS(SELECT 1 FROM ironvault_private.staff_report_permissions permission
    WHERE permission.user_id=actor.user_id AND permission.tenant_id=p_tenant
     AND permission.permission='financial_reports_read')
 );
$function$;
CREATE FUNCTION public.iv_can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $function$
 SELECT ironvault_private.can_read_financial_reports(p_tenant);
$function$;
CREATE FUNCTION public.iv_set_staff_financial_report_access(p_tenant text,p_user uuid,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF p_user IS NULL OR p_enabled IS NULL OR nullif(btrim(p_tenant),'') IS NULL THEN
  RAISE EXCEPTION 'Tenant, target account and explicit permission state are required';
 END IF;
 IF NOT ironvault_private.is_gym_administrator(p_tenant) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 IF p_enabled THEN
  IF p_user=auth.uid() THEN RAISE EXCEPTION 'Cannot grant financial-report permission to yourself'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners gym WHERE gym.id::text=p_tenant)
   OR NOT EXISTS(SELECT 1 FROM public.iv_user_roles staff
    WHERE staff.user_id=p_user AND staff.tenant_id::text=p_tenant AND staff.role='staff') THEN
   RAISE EXCEPTION 'Target is not a current staff account in this gym';
  END IF;
  INSERT INTO ironvault_private.staff_report_permissions(tenant_id,user_id,permission,granted_by)
   VALUES(p_tenant,p_user,'financial_reports_read',auth.uid())
   ON CONFLICT(tenant_id,user_id,permission) DO UPDATE
    SET granted_by=auth.uid(),granted_at=pg_catalog.now();
 ELSE
  -- Revocation remains possible after the recipient's staff role is removed.
  DELETE FROM ironvault_private.staff_report_permissions permission
   WHERE permission.tenant_id=p_tenant AND permission.user_id=p_user
    AND permission.permission='financial_reports_read';
 END IF;
 -- An audit failure rolls back the permission change, rather than silently granting.
 PERFORM public.iv_log_event(p_tenant,
  CASE WHEN p_enabled THEN 'Financial report access granted' ELSE 'Financial report access revoked' END,
  'Target Auth account: '||p_user::text);
END
$function$;
CREATE FUNCTION public.iv_list_staff_financial_report_access(p_tenant text)
RETURNS TABLE(user_id uuid,email text,financial_reports_read boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF NOT ironvault_private.is_gym_administrator(p_tenant) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 RETURN QUERY SELECT DISTINCT staff.user_id::uuid,account.email::text,
  EXISTS(SELECT 1 FROM ironvault_private.staff_report_permissions permission
   WHERE permission.tenant_id=p_tenant AND permission.user_id=staff.user_id
    AND permission.permission='financial_reports_read')
 FROM public.iv_user_roles staff JOIN auth.users account ON account.id=staff.user_id
 WHERE staff.tenant_id::text=p_tenant AND staff.role='staff';
END
$function$;
ALTER FUNCTION ironvault_private.is_gym_administrator(text) OWNER TO postgres;
ALTER FUNCTION ironvault_private.can_read_financial_reports(text) OWNER TO postgres;
ALTER FUNCTION public.iv_can_read_financial_reports(text) OWNER TO postgres;
ALTER FUNCTION public.iv_set_staff_financial_report_access(text,uuid,boolean) OWNER TO postgres;
ALTER FUNCTION public.iv_list_staff_financial_report_access(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.is_gym_administrator(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ironvault_private.can_read_financial_reports(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.iv_can_read_financial_reports(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.iv_set_staff_financial_report_access(text,uuid,boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.iv_list_staff_financial_report_access(text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION ironvault_private.can_read_financial_reports(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.iv_can_read_financial_reports(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.iv_set_staff_financial_report_access(text,uuid,boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.iv_list_staff_financial_report_access(text) TO authenticated, service_role;
DO $verify$
DECLARE signature text;
BEGIN
 IF has_schema_privilege('anon','ironvault_private','USAGE')
  OR has_schema_privilege('authenticated','ironvault_private','CREATE')
  OR has_function_privilege('authenticated','ironvault_private.is_gym_administrator(text)','EXECUTE')
  OR has_any_column_privilege('authenticated','ironvault_private.staff_report_permissions','SELECT')
  OR has_any_column_privilege('authenticated','ironvault_private.staff_report_permissions','INSERT')
  OR has_any_column_privilege('authenticated','ironvault_private.staff_report_permissions','UPDATE')
  OR has_table_privilege('authenticated','ironvault_private.staff_report_permissions','DELETE') THEN
  RAISE EXCEPTION 'Unexpected inherited private permission access';
 END IF;
 FOREACH signature IN ARRAY ARRAY['ironvault_private.is_gym_administrator(text)',
  'ironvault_private.can_read_financial_reports(text)','public.iv_can_read_financial_reports(text)',
  'public.iv_set_staff_financial_report_access(text,uuid,boolean)',
  'public.iv_list_staff_financial_report_access(text)'] LOOP
  IF has_function_privilege('anon',signature,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous permission API execution remains: %',signature; END IF;
 END LOOP;
END
$verify$;
NOTIFY pgrst,'reload schema';
COMMIT;
-- Metadata-only verification; no grant or list function is invoked in SQL Editor.
SELECT p.oid::regprocedure AS signature,p.prosecdef AS security_definer,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p WHERE p.oid IN (
 'ironvault_private.is_gym_administrator(text)'::regprocedure,
 'ironvault_private.can_read_financial_reports(text)'::regprocedure,
 'public.iv_can_read_financial_reports(text)'::regprocedure,
 'public.iv_set_staff_financial_report_access(text,uuid,boolean)'::regprocedure,
 'public.iv_list_staff_financial_report_access(text)'::regprocedure
) ORDER BY p.oid::regprocedure::text;
