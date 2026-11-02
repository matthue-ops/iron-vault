-- MANUAL ONLY after 018/019. Adds report metadata and canonical purchase receipts.
BEGIN;
CREATE OR REPLACE FUNCTION public.iv_report_snapshot(p_tenant text,p_start date,p_end date)
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
    'display_code',m.display_code,'created_at',m.created_at,'expiration_date',m.expiration_date,'scans_used',m.scans_used,'last_scanned_date',m.last_scanned_date,'plan',m.plan,'wallet_balance',m.wallet_balance,'status',m.status)) FROM public.members m WHERE tenant_id=p_tenant),'[]'::jsonb)) INTO result;
 RETURN result||jsonb_build_object('purchases',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'request_id',r.request_id,'member_id',r.member_id,'plan',r.payload->>'plan','amount',r.payload->'amount',
  'cash',r.payload->'cash','created_at',r.created_at,'renewal',EXISTS(SELECT 1 FROM ironvault_private.financial_requests previous
   WHERE previous.tenant_id=p_tenant AND previous.member_id=r.member_id AND previous.payload->>'operation'='purchase'
    AND (previous.created_at,previous.request_id)<(r.created_at,r.request_id))) ORDER BY r.created_at DESC)
  FROM ironvault_private.financial_requests r WHERE r.tenant_id=p_tenant AND r.payload->>'operation'='purchase'
   AND r.created_at>=start_at AND r.created_at<end_at),'[]'::jsonb));
END $fn$;
NOTIFY pgrst,'reload schema';
COMMIT;
