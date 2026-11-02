-- MANUAL ONLY after installed 020/021. Activity names and roles; safe to repeat.
-- Replaces only the report snapshot function. No record writes or new API permissions.
-- Names/roles are resolved from current tenant-bound accounts, not claimed historical identity.
BEGIN;
CREATE OR REPLACE FUNCTION public.iv_report_snapshot(p_tenant text,p_start date,p_end date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb; identities jsonb; start_at timestamptz; end_at timestamptz;
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
    'display_code',m.display_code,'created_at',m.created_at,'expiration_date',m.expiration_date,'scans_used',m.scans_used,'last_scanned_date',m.last_scanned_date,'plan',m.plan,'wallet_balance',m.wallet_balance,'status',m.status)) FROM public.members m WHERE tenant_id=p_tenant),'[]'::jsonb)) INTO result;
 result:=result||jsonb_build_object('purchases',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'request_id',r.request_id,'member_id',r.member_id,'plan',r.payload->>'plan','amount',r.payload->'amount',
  'cash',r.payload->'cash','created_at',r.created_at,'renewal',EXISTS(SELECT 1 FROM ironvault_private.financial_requests previous
   WHERE previous.tenant_id=p_tenant AND previous.member_id=r.member_id AND previous.payload->>'operation'='purchase'
    AND (previous.created_at,previous.request_id)<(r.created_at,r.request_id))) ORDER BY r.created_at DESC)
  FROM ironvault_private.financial_requests r WHERE r.tenant_id=p_tenant AND r.payload->>'operation'='purchase'
   AND r.created_at>=start_at AND r.created_at<end_at),'[]'::jsonb));
 -- Resolve only identities referenced by this tenant's selected report rows.
 -- Disabled/revoked roles remain eligible for attribution, never authorization.
 WITH referenced AS (
  SELECT DISTINCT ids.user_id::uuid AS user_id
  FROM jsonb_array_elements((result->'activity')||(result->'sessions')) log
  CROSS JOIN LATERAL (
   SELECT log->>'actor_id' AS user_id
   UNION ALL
   SELECT match[1] FROM regexp_matches(coalesce(log->>'details',''),
    '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})','g') AS match
  ) ids WHERE ids.user_id IS NOT NULL
 ), named AS (
  SELECT r.user_id,r.role,coalesce(
   CASE r.role
    WHEN 'owner' THEN nullif(btrim(g.owner_name),'')
    WHEN 'staff' THEN nullif(btrim(staff.name),'')
    WHEN 'member' THEN nullif(btrim(m.name),'')
    WHEN 'super_admin' THEN coalesce(nullif(btrim(u.raw_user_meta_data->>'name'),''),nullif(btrim(u.raw_user_meta_data->>'full_name'),''),'Platform administrator')
   END,
   CASE WHEN r.role IN ('owner','staff') THEN nullif(btrim(job.name),'') END,
   'Name unavailable') AS name
  FROM referenced ref
  JOIN public.iv_user_roles r ON r.user_id=ref.user_id
   AND (r.tenant_id=p_tenant OR (r.role='super_admin' AND r.tenant_id IS NULL))
  JOIN public.owners g ON g.id=p_tenant
  LEFT JOIN public.members m ON m.id=r.member_id AND m.tenant_id=p_tenant AND r.role='member'
  LEFT JOIN auth.users u ON u.id=r.user_id AND r.role='super_admin'
  LEFT JOIN LATERAL (
   SELECT s.value->>'name' AS name FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s
   WHERE r.role='staff' AND s.value->>'auth_user_id'=r.user_id::text LIMIT 1
  ) staff ON true
  LEFT JOIN LATERAL (
   SELECT p.payload->>'name' AS name FROM ironvault_private.provision_requests p
   WHERE p.tenant_id=p_tenant AND p.completed_user=r.user_id AND p.role=r.role
   ORDER BY p.created_at DESC,p.request_id LIMIT 1
  ) job ON true
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'name',name,'role',role)
  ORDER BY user_id,role),'[]'::jsonb) INTO identities FROM named;
 RETURN result||jsonb_build_object('actors',identities);
END $fn$;
NOTIFY pgrst,'reload schema';
COMMIT;
