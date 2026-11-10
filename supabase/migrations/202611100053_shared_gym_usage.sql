-- MANUAL ONLY after 052. Read-only aggregates; no record, status, billing or existing-function changes.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('ironvault_private.subscription_portal_052_base(text,text,jsonb)') IS NULL THEN RAISE EXCEPTION 'Apply migrations through 052 first';END IF;
 IF to_regprocedure('public.iv_gym_usage(text)') IS NOT NULL THEN RAISE EXCEPTION '053 already installed; do not reapply';END IF;
END $guard$;
CREATE FUNCTION public.iv_gym_usage(p_tenant text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE stamp timestamptz:=statement_timestamp();today date;month_start date;result jsonb;BEGIN
 IF NOT (ironvault_private.subscription_super() OR ironvault_private.subscription_owner(p_tenant)) THEN RAISE EXCEPTION 'Enabled Provider or registered gym owner required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant) THEN RAISE EXCEPTION 'Gym not found';END IF;
 today:=(stamp AT TIME ZONE 'Asia/Manila')::date;month_start:=date_trunc('month',today::timestamp)::date;
 WITH attendance AS MATERIALIZED (
  SELECT member_id,(created_at AT TIME ZONE 'Asia/Manila')::date AS report_day FROM public.iv_attendance_logs
  WHERE tenant_id=p_tenant AND created_at>=(least(today-60,(month_start-interval '3 months')::date)::timestamp AT TIME ZONE 'Asia/Manila') AND created_at<(today::timestamp AT TIME ZONE 'Asia/Manila')
 ),months AS (SELECT (month_start-make_interval(months=>number))::date AS start,(month_start-make_interval(months=>number-1))::date-1 AS finish FROM generate_series(3,1,-1) number)
 SELECT jsonb_build_object('tenant_id',p_tenant,'snapshot_at',stamp,'timezone','Asia/Manila',
  'period',jsonb_build_object('start',today-30,'end',today-1,'days',30),
  'totals',jsonb_build_object('unique_visitors',count(DISTINCT member_id) FILTER(WHERE report_day>=today-30),'checkins',count(*) FILTER(WHERE report_day>=today-30)),
  'previous',jsonb_build_object('start',today-60,'end',today-31,'unique_visitors',count(DISTINCT member_id) FILTER(WHERE report_day BETWEEN today-60 AND today-31),'checkins',count(*) FILTER(WHERE report_day BETWEEN today-60 AND today-31)),
  'months',(SELECT jsonb_agg(jsonb_build_object('start',m.start,'end',m.finish,'unique_visitors',(SELECT count(DISTINCT member_id) FROM attendance a WHERE a.report_day BETWEEN m.start AND m.finish),'checkins',(SELECT count(*) FROM attendance a WHERE a.report_day BETWEEN m.start AND m.finish)) ORDER BY m.start) FROM months m)) INTO result FROM attendance;
 RETURN result;
END $fn$;
ALTER FUNCTION public.iv_gym_usage(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.iv_gym_usage(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_gym_usage(text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
