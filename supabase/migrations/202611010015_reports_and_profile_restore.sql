-- MANUAL ONLY after 012-014. Scoped report snapshot (no API row truncation)
-- and atomic PROFILE/BRANDING restore. Never restores wallet/ledger/credentials.
BEGIN;
SET LOCAL search_path=pg_catalog;
CREATE FUNCTION public.iv_report_snapshot(p_tenant text,p_start date,p_end date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb; start_at timestamptz; end_at timestamptz;
BEGIN
 IF NOT ironvault_private.can_read_financial_reports(p_tenant) OR p_start IS NULL OR p_end IS NULL OR p_end<p_start THEN
  RAISE EXCEPTION 'Not authorized or invalid report dates'; END IF;
 start_at:=p_start::timestamp AT TIME ZONE 'Asia/Manila';end_at:=(p_end+1)::timestamp AT TIME ZONE 'Asia/Manila';
 SELECT jsonb_build_object(
  'financial',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_financial_transactions x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'attendance',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_attendance_logs x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'activity',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_activity_logs x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'sessions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_staff_sessions x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'members',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'tenant_id',m.tenant_id,'name',m.name,'classification',m.classification,
    'plan',m.plan,'wallet_balance',m.wallet_balance,'status',m.status)) FROM public.members m WHERE tenant_id=p_tenant),'[]'::jsonb)) INTO result;
 RETURN result;
END $fn$;
CREATE FUNCTION public.iv_restore_profiles(p_gyms jsonb,p_members jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 -- Atomic profile/branding-only restore of existing records. Unknown identities,
 -- tenant moves and unauthorized rows abort the whole RPC; no implicit creation.
 PERFORM public.iv_save_gym_settings(p_gyms);
 PERFORM public.iv_save_member_profiles(p_members);
END $fn$;
ALTER POLICY iv_activity_read ON public.iv_activity_logs USING(ironvault_private.can_read_financial_reports(tenant_id));
ALTER POLICY iv_sessions_read ON public.iv_staff_sessions USING(
 ironvault_private.can_read_financial_reports(tenant_id) OR (actor_id=auth.uid() AND public.iv_can_access(tenant_id)));
CREATE OR REPLACE FUNCTION public.iv_list_staff_financial_report_access(p_tenant text)
RETURNS TABLE(user_id uuid,email text,financial_reports_read boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT ironvault_private.is_gym_administrator(p_tenant) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 RETURN QUERY SELECT r.user_id,a.contact_email,EXISTS(SELECT 1 FROM ironvault_private.staff_report_permissions p
  WHERE p.tenant_id=p_tenant AND p.user_id=r.user_id AND p.permission='financial_reports_read')
 FROM public.iv_user_roles r JOIN ironvault_private.branch_accounts a ON a.user_id=r.user_id
 WHERE r.enabled AND r.role='staff' AND r.tenant_id=p_tenant;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_set_staff_financial_report_access(p_tenant text,p_user uuid,p_enabled boolean)
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
    WHERE staff.user_id=p_user AND staff.tenant_id::text=p_tenant AND staff.role='staff' AND staff.enabled) THEN
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
DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.iv_report_snapshot(text,date,date)','public.iv_restore_profiles(jsonb,jsonb)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated,service_role',signature);
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT oid::regprocedure,has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute FROM pg_proc
WHERE oid IN ('public.iv_report_snapshot(text,date,date)'::regprocedure,'public.iv_restore_profiles(jsonb,jsonb)'::regprocedure);
-- Expect anon false/auth true. No report/RPC is executed by this verification.
-- No financial/identity restore, reset, truncation or deletion is included.
