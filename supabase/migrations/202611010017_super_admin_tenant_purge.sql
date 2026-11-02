-- MANUAL INSTALL ONLY, after 016. Defines a destructive API; does not purge data.
-- Application data is deleted atomically; Auth deletion uses the supported Admin API.
BEGIN;
CREATE TABLE ironvault_private.tenant_purge_jobs (
 request_id uuid PRIMARY KEY,
 tenant_id text NOT NULL UNIQUE,
 actor_id uuid NOT NULL,
 pending_users uuid[] NOT NULL,
 summary jsonb NOT NULL,
 retained_accounts integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ironvault_private.tenant_purge_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.tenant_purge_jobs FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.tenant_purge_summary(p_tenant text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('tenant_id',g.id,'gym_name',g.gym_name,
 'members',(SELECT count(*) FROM public.members WHERE tenant_id=g.id),
 'accounts',(SELECT count(*) FROM ironvault_private.branch_accounts WHERE tenant_id=g.id),
 'transactions',(SELECT count(*) FROM public.iv_financial_transactions WHERE tenant_id=g.id),
 'attendance',(SELECT count(*) FROM public.iv_attendance_logs WHERE tenant_id=g.id),
 'activity',(SELECT count(*) FROM public.iv_activity_logs WHERE tenant_id=g.id),
 'sessions',(SELECT count(*) FROM public.iv_staff_sessions WHERE tenant_id=g.id),
 'wallet_credit',(SELECT coalesce(sum(wallet_balance),0)::text FROM public.members WHERE tenant_id=g.id),
 'wallet_accounts',(SELECT count(*) FROM public.members WHERE tenant_id=g.id AND coalesce(wallet_balance,0)<>0))
 FROM public.owners g WHERE g.id=p_tenant;
$fn$;
REVOKE ALL ON FUNCTION ironvault_private.tenant_purge_summary(text) FROM PUBLIC,anon,authenticated,service_role;
-- Preserve identities still referenced by another gym or another application table.
CREATE FUNCTION ironvault_private.purge_auth_is_shared(p_user uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE link record; present boolean;
BEGIN
 IF EXISTS(SELECT 1 FROM public.members WHERE auth_user_id=p_user) THEN RETURN true; END IF;
 FOR link IN SELECT c.conrelid::regclass AS relation,a.attname AS column_name
  FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_class t ON t.oid=c.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
  WHERE c.contype='f' AND c.confrelid='auth.users'::regclass
   AND cardinality(c.conkey)=1 AND n.nspname IN ('public','ironvault_private')
 LOOP
  EXECUTE pg_catalog.format('SELECT EXISTS(SELECT 1 FROM %s WHERE %I=$1)',link.relation,link.column_name)
   INTO present USING p_user;
  IF present THEN RETURN true; END IF;
 END LOOP;
 RETURN false;
END $fn$;
REVOKE ALL ON FUNCTION ironvault_private.purge_auth_is_shared(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.iv_tenant_purge_control(p_actor uuid,p_action text,p_tenant text DEFAULT NULL,
 p_request uuid DEFAULT NULL,p_review jsonb DEFAULT NULL,p_confirmation text DEFAULT NULL,p_user uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.tenant_purge_jobs%ROWTYPE; users uuid[]; review jsonb;
BEGIN
 -- Only service_role can call this API. The Edge function supplies its verified actor.
 PERFORM 1 FROM public.iv_user_roles WHERE user_id=p_actor AND role='super_admin' AND tenant_id IS NULL AND enabled FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Super Admin required'; END IF;
 IF p_action='list' THEN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('request_id',request_id,'tenant_id',tenant_id,
   'remaining',cardinality(pending_users))) FROM ironvault_private.tenant_purge_jobs),'[]'::jsonb);
 END IF;
 IF p_action='preview' THEN
  review:=ironvault_private.tenant_purge_summary(p_tenant);
  IF review IS NULL THEN RAISE EXCEPTION 'Gym not found'; END IF;
  RETURN review;
 END IF;
 IF p_request IS NULL OR p_tenant IS NULL THEN RAISE EXCEPTION 'Invalid purge request'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant,17));
 SELECT * INTO job FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request FOR UPDATE;
 IF FOUND AND job.tenant_id<>p_tenant THEN RAISE EXCEPTION 'Purge request belongs to another gym'; END IF;
 IF p_action='start' AND job.request_id IS NULL THEN
  IF p_confirmation IS DISTINCT FROM 'PURGE '||p_tenant THEN RAISE EXCEPTION 'Exact tenant confirmation required'; END IF;
  PERFORM 1 FROM public.owners WHERE id=p_tenant FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Gym not found'; END IF;
  review:=ironvault_private.tenant_purge_summary(p_tenant);
  IF p_review IS DISTINCT FROM review THEN RAISE EXCEPTION 'Gym changed; review the purge again'; END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.tenant_purge_jobs WHERE tenant_id=p_tenant) THEN RAISE EXCEPTION 'Resume the existing purge'; END IF;
  SELECT coalesce(array_agg(DISTINCT id),'{}'::uuid[]) INTO users FROM (
   SELECT user_id AS id FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant
   UNION SELECT user_id FROM public.iv_user_roles WHERE tenant_id=p_tenant
   UNION SELECT auth_user_id FROM public.members WHERE tenant_id=p_tenant AND auth_user_id IS NOT NULL
   UNION SELECT completed_user FROM ironvault_private.provision_requests WHERE tenant_id=p_tenant AND completed_user IS NOT NULL
   UNION SELECT u.id FROM auth.users u JOIN ironvault_private.provision_requests p
    ON u.raw_app_meta_data->>'iv_provision_request'=p.request_id::text WHERE p.tenant_id=p_tenant
  ) candidates WHERE candidates.id<>p_actor AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=candidates.id AND r.role='super_admin')
   AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=candidates.id AND r.tenant_id IS DISTINCT FROM p_tenant)
   AND NOT EXISTS(SELECT 1 FROM public.members m WHERE m.auth_user_id=candidates.id AND m.tenant_id<>p_tenant)
   AND NOT EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.user_id=candidates.id AND a.tenant_id<>p_tenant);
  INSERT INTO ironvault_private.tenant_purge_jobs(request_id,tenant_id,actor_id,pending_users,summary)
   VALUES(p_request,p_tenant,p_actor,users,review);
  DELETE FROM ironvault_private.email_actions WHERE user_id IN (SELECT user_id FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant);
  DELETE FROM ironvault_private.staff_report_permissions WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.daily_passes WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.financial_requests WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_staff_sessions WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_attendance_logs WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_financial_transactions WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_activity_logs WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.provision_requests WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_user_roles WHERE tenant_id=p_tenant;
  DELETE FROM public.members WHERE tenant_id=p_tenant;
  DELETE FROM public.owners WHERE id=p_tenant;
  SELECT * INTO STRICT job FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request;
 END IF;
 IF job.request_id IS NULL THEN
  IF p_action='next' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant) THEN RETURN jsonb_build_object('complete',true); END IF;
  RAISE EXCEPTION 'Purge job not found';
 END IF;
 IF p_action='check' THEN
  IF p_user IS NULL OR NOT p_user=ANY(job.pending_users) THEN RAISE EXCEPTION 'Account not in purge job'; END IF;
  RETURN jsonb_build_object('eligible',p_user<>p_actor AND NOT ironvault_private.purge_auth_is_shared(p_user),
   'shared',p_user=p_actor OR ironvault_private.purge_auth_is_shared(p_user));
 END IF;
 IF p_action='retain' THEN
  IF p_user IS NULL OR NOT p_user=ANY(job.pending_users)
   OR (p_user<>p_actor AND NOT ironvault_private.purge_auth_is_shared(p_user)) THEN RAISE EXCEPTION 'Account is not shared'; END IF;
  UPDATE ironvault_private.tenant_purge_jobs SET pending_users=array_remove(pending_users,p_user),
   retained_accounts=retained_accounts+1 WHERE request_id=p_request;
 ELSIF p_action='ack' THEN
  IF p_user IS NULL OR NOT p_user=ANY(job.pending_users) THEN RAISE EXCEPTION 'Account not in purge job'; END IF;
  -- Only acknowledge confirmed Admin API deletion, never delete auth.users in SQL.
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=p_user) THEN RAISE EXCEPTION 'Auth account still exists'; END IF;
  UPDATE ironvault_private.tenant_purge_jobs SET pending_users=array_remove(pending_users,p_user) WHERE request_id=p_request;
 ELSIF p_action='finish' THEN
  IF cardinality(job.pending_users)<>0 THEN RAISE EXCEPTION 'Auth cleanup incomplete'; END IF;
  DELETE FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request;
  RETURN jsonb_build_object('complete',true,'retained_accounts',job.retained_accounts);
 ELSIF p_action NOT IN ('start','next') THEN RAISE EXCEPTION 'Unknown purge action'; END IF;
 SELECT * INTO STRICT job FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request;
 RETURN jsonb_build_object('request_id',job.request_id,'tenant_id',job.tenant_id,'pending_users',job.pending_users,
  'remaining',cardinality(job.pending_users),'retained_accounts',job.retained_accounts);
END $fn$;
REVOKE ALL ON FUNCTION public.iv_tenant_purge_control(uuid,text,text,uuid,jsonb,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iv_tenant_purge_control(uuid,text,text,uuid,jsonb,text,uuid) TO service_role;
COMMIT;
