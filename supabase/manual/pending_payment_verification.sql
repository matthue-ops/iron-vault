-- 043 MANUAL ONLY after 042. No clock starts, payments, emails or external calls during installation.
BEGIN;
DO $guard$ BEGIN IF to_regclass('ironvault_private.refund_cases') IS NULL OR to_regclass('ironvault_private.member_updates') IS NULL THEN RAISE EXCEPTION 'Apply 042 first';END IF;IF to_regprocedure('ironvault_private.subscription_portal_043_base(text,text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION '043 already installed; do not reapply';END IF;END $guard$;
CREATE TABLE ironvault_private.payment_verifications(
 request_id uuid PRIMARY KEY REFERENCES ironvault_private.subscription_requests(id) ON DELETE CASCADE,
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 submitted_at timestamptz NOT NULL,policy_version text NOT NULL DEFAULT 'pending-review-v1' CHECK(policy_version='pending-review-v1'),mode text NOT NULL CHECK(mode IN ('timely','grace','late')),
 original_period jsonb,original_quote jsonb NOT NULL,eligible boolean NOT NULL,
 status text NOT NULL CHECK(status IN ('pending','correction','approved','rejected','cancelled')),
 correction_deadline timestamptz,reason text,delay_days integer NOT NULL DEFAULT 0,approved_start date,approved_end date
);
CREATE TABLE ironvault_private.verification_intervals(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,request_id uuid NOT NULL REFERENCES ironvault_private.payment_verifications(request_id) ON DELETE CASCADE,
 responsibility text NOT NULL CHECK(responsibility IN ('provider','owner')),started_at timestamptz NOT NULL DEFAULT clock_timestamp(),ended_at timestamptz,CHECK(ended_at IS NULL OR ended_at>=started_at)
);
CREATE UNIQUE INDEX iv_verification_one_interval ON ironvault_private.verification_intervals(request_id) WHERE ended_at IS NULL;
CREATE TABLE ironvault_private.provider_reminder_jobs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),request_id uuid NOT NULL REFERENCES ironvault_private.payment_verifications(request_id) ON DELETE CASCADE,
 day date NOT NULL,state text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','sending','sent','cancelled','needs_review')),lease_until timestamptz,token uuid,sent_at timestamptz,attempts integer NOT NULL DEFAULT 0,UNIQUE(request_id,day)
);
CREATE FUNCTION ironvault_private.verification_delay_days(p_request uuid,p_at timestamptz)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT count(*)::integer FROM ironvault_private.payment_verifications v CROSS JOIN LATERAL generate_series(((v.original_period->>'end_date')::date+(v.original_period->>'grace_days')::integer+1)::timestamp,(p_at AT TIME ZONE 'Asia/Manila')::date::timestamp,interval '1 day') day
 WHERE v.request_id=p_request AND v.mode='grace'
 AND EXISTS(SELECT 1 FROM ironvault_private.verification_intervals i WHERE i.request_id=v.request_id AND i.responsibility='provider' AND i.started_at<((day+interval '1 day') AT TIME ZONE 'Asia/Manila') AND coalesce(i.ended_at,p_at)>(day AT TIME ZONE 'Asia/Manila'))
 AND NOT EXISTS(SELECT 1 FROM ironvault_private.verification_intervals i WHERE i.request_id=v.request_id AND i.responsibility='owner' AND i.started_at<((day+interval '1 day') AT TIME ZONE 'Asia/Manila') AND coalesce(i.ended_at,p_at)>(day AT TIME ZONE 'Asia/Manila'));
$fn$;
ALTER FUNCTION ironvault_private.subscription_state(text) RENAME TO subscription_state_043_base;
CREATE FUNCTION ironvault_private.subscription_state(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE base jsonb;v ironvault_private.payment_verifications%ROWTYPE;can_continue boolean;
BEGIN
 base:=ironvault_private.subscription_state_043_base(p_tenant);
 IF base->>'status' IN ('inactive','setup') THEN RETURN base;END IF;
 SELECT x.* INTO v FROM ironvault_private.payment_verifications x JOIN ironvault_private.subscription_requests r ON r.id=x.request_id JOIN ironvault_private.gym_subscriptions s ON s.tenant_id=x.tenant_id
 WHERE x.tenant_id=p_tenant AND x.status IN ('pending','correction') AND r.cancelled_at IS NULL AND r.approved_at IS NULL AND x.eligible AND r.owner_id=s.owner_id ORDER BY x.submitted_at LIMIT 1;
 IF NOT FOUND THEN RETURN base;END IF;
 can_continue:=v.status='pending' OR v.status='correction' AND clock_timestamp()<v.correction_deadline;
 IF NOT can_continue THEN RETURN base;END IF;
 RETURN base||jsonb_build_object('status',CASE WHEN coalesce((base->>'operations')::boolean,false) THEN base->>'status' ELSE 'verification' END,'operations',true,'read',true,'portal',coalesce((base->>'portal')::boolean,false) OR (v.mode='timely' AND v.status='pending' AND v.original_period->>'plan'='portal'),'verification',jsonb_build_object('request_id',v.request_id,'mode',v.mode,'status',v.status,'submitted_at',v.submitted_at,'correction_deadline',v.correction_deadline));
END $fn$;
CREATE FUNCTION ironvault_private.verification_quote(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v ironvault_private.payment_verifications%ROWTYPE;tail ironvault_private.subscription_periods%ROWTYPE;startday date;finish date;extra integer:=0;result jsonb;today date:=ironvault_private.subscription_today();
BEGIN
 SELECT * INTO STRICT v FROM ironvault_private.payment_verifications WHERE request_id=p_request;
 SELECT * INTO tail FROM ironvault_private.subscription_periods WHERE tenant_id=v.tenant_id ORDER BY end_date DESC,approved_at DESC LIMIT 1;
 IF v.mode='grace' THEN
  IF tail.id::text IS DISTINCT FROM v.original_period->>'id' OR tail.end_date::text IS DISTINCT FROM v.original_period->>'end_date' THEN RAISE EXCEPTION 'Approved periods changed during review; resolve scheduling before payment approval';END IF;
  startday:=(v.original_period->>'end_date')::date+1;extra:=ironvault_private.verification_delay_days(p_request,clock_timestamp());
 ELSE startday:=greatest(today+1,coalesce(tail.end_date+1,today+1));END IF;
 finish:=startday+(v.original_quote->'policy'->>'paid_days')::integer-1+extra;
 IF finish<today THEN RAISE EXCEPTION 'Owner correction outlasted this paid period; agree a fresh quote and settle this payment before approval';END IF;
 result:=jsonb_build_object('request_id',v.request_id,'start_date',startday,'end_date',finish,'delay_days',extra,'plan',v.original_quote->>'plan','amount',v.original_quote->'amount','reference',(SELECT payment_reference FROM ironvault_private.subscription_requests WHERE id=p_request),'status',v.status,'tail',tail.id,'tail_end',tail.end_date);
 RETURN result||jsonb_build_object('review_hash',md5(result::text));
END $fn$;
ALTER FUNCTION public.iv_subscription_portal(text,text,jsonb) RENAME TO subscription_portal_043_base;
ALTER FUNCTION public.subscription_portal_043_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s ironvault_private.gym_subscriptions%ROWTYPE;r ironvault_private.subscription_requests%ROWTYPE;v ironvault_private.payment_verifications%ROWTYPE;prior ironvault_private.subscription_periods%ROWTYPE;tail ironvault_private.subscription_periods%ROWTYPE;result jsonb;state jsonb;owner boolean;provider boolean;ref text;at_time timestamptz:=clock_timestamp();today date:=ironvault_private.subscription_today();startday date;finish date;accessday date;extra integer:=0;why text;timing text;continue_access boolean;
BEGIN
 SELECT * INTO STRICT s FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant FOR UPDATE;
 owner:=ironvault_private.subscription_owner(p_tenant);provider:=ironvault_private.subscription_super();
 IF NOT owner AND NOT provider THEN RAISE EXCEPTION 'Registered owner or Provider required' USING ERRCODE='42501';END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>200000 THEN RAISE EXCEPTION 'Invalid verification request';END IF;
 IF p_action IN ('submit_reference','resubmit_verification','return_verification','reject_verification','cancel_request','approve_payment','review_verification') THEN
  SELECT * INTO STRICT r FROM ironvault_private.subscription_requests WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant FOR UPDATE;
  SELECT * INTO v FROM ironvault_private.payment_verifications WHERE request_id=r.id FOR UPDATE;
  IF r.kind='payment' AND p_action='submit_reference' AND v.request_id IS NULL THEN
   IF NOT owner OR r.owner_id<>auth.uid() OR p_data->>'verification_policy' IS DISTINCT FROM 'pending-review-v1' THEN RAISE EXCEPTION 'Owner must review the pending-payment date and access policy';END IF;
   IF r.cancelled_at IS NOT NULL OR r.approved_at IS NOT NULL THEN RAISE EXCEPTION 'Request already resolved';END IF;
   IF EXISTS(SELECT 1 FROM ironvault_private.subscription_requests x WHERE x.tenant_id=p_tenant AND x.id<>r.id AND x.approved_at IS NULL AND x.cancelled_at IS NULL) THEN RAISE EXCEPTION 'Resolve the other pending request first';END IF;
   state:=ironvault_private.subscription_state_043_base(p_tenant);
   SELECT * INTO prior FROM ironvault_private.subscription_periods WHERE id=(state->>'period_id')::uuid AND tenant_id=p_tenant;
   timing:=CASE WHEN prior.id IS NOT NULL AND today<=prior.end_date THEN 'timely' WHEN prior.kind='paid' AND today<=prior.end_date+prior.grace_days THEN 'grace' ELSE 'late' END;
   -- A previously submitted reference can be enrolled only by its historical submission date, never by a reset clock.
   IF r.reference_submitted_at IS NOT NULL THEN RAISE EXCEPTION 'Legacy submitted payment requires Provider review; no provisional access was added';END IF;
   result:=ironvault_private.subscription_portal_043_base(p_tenant,p_action,p_data);
   INSERT INTO ironvault_private.payment_verifications(request_id,tenant_id,submitted_at,mode,original_period,original_quote,eligible,status) VALUES(r.id,p_tenant,at_time,timing,to_jsonb(prior),r.quote,timing<>'late','pending');
   INSERT INTO ironvault_private.verification_intervals(request_id,responsibility,started_at) VALUES(r.id,'provider',at_time);
   PERFORM ironvault_private.subscription_notice(p_tenant,'verification:'||r.id,'Payment submitted for verification','The Provider must verify payment. Timely submissions retain existing features; grace submissions retain dashboard-only access. Unapproved upgrades remain unavailable. Late submissions do not restore suspended operations. Counted dates will follow the policy you confirmed.');
  ELSIF v.request_id IS NOT NULL THEN
   IF p_action='review_verification' THEN
    IF NOT provider OR v.status<>'pending' THEN RAISE EXCEPTION 'Provider review requires a pending verification';END IF;RETURN ironvault_private.verification_quote(r.id);
   ELSIF p_action='submit_reference' THEN
    IF NOT owner OR r.owner_id<>auth.uid() OR r.payment_reference IS DISTINCT FROM btrim(p_data->>'reference') THEN RAISE EXCEPTION 'Existing submission must be reviewed; its date cannot be reset';END IF;
   ELSIF p_action IN ('return_verification','reject_verification','cancel_request','resubmit_verification') THEN
    IF v.status NOT IN ('pending','correction') THEN RAISE EXCEPTION 'Verification already resolved';END IF;
    IF p_action='resubmit_verification' THEN
     IF NOT owner OR r.owner_id<>auth.uid() OR v.status<>'correction' THEN RAISE EXCEPTION 'Only the owner can correct a returned submission';END IF;
     ref:=btrim(p_data->>'reference');IF coalesce(length(ref),0) NOT BETWEEN 3 AND 180 THEN RAISE EXCEPTION 'Enter a valid corrected reference';END IF;
     UPDATE ironvault_private.subscription_requests SET payment_reference=ref WHERE id=r.id;
     UPDATE ironvault_private.payment_verifications SET status='pending',eligible=eligible AND at_time<correction_deadline,correction_deadline=NULL WHERE request_id=r.id;
     UPDATE ironvault_private.verification_intervals SET ended_at=at_time WHERE request_id=r.id AND ended_at IS NULL;
     INSERT INTO ironvault_private.verification_intervals(request_id,responsibility,started_at) VALUES(r.id,'provider',at_time);
     INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) VALUES('corrected:'||r.id||':'||gen_random_uuid(),p_tenant,'Corrected payment reference','Review the owner correction; original submission time is preserved.');
    ELSE
     IF p_action<>'cancel_request' AND NOT provider THEN RAISE EXCEPTION 'Provider decision required';END IF;
     why:=btrim(p_data->>'reason');IF coalesce(length(why),0) NOT BETWEEN 3 AND 1000 THEN RAISE EXCEPTION 'Enter a decision reason';END IF;
     UPDATE ironvault_private.verification_intervals SET ended_at=at_time WHERE request_id=r.id AND ended_at IS NULL;
     IF p_action='return_verification' THEN
      IF v.status<>'pending' THEN RAISE EXCEPTION 'Already awaiting owner correction';END IF;
      UPDATE ironvault_private.payment_verifications SET status='correction',reason=why,correction_deadline=at_time+interval '48 hours' WHERE request_id=r.id;
      INSERT INTO ironvault_private.verification_intervals(request_id,responsibility,started_at) VALUES(r.id,'owner',at_time);
     ELSE
      UPDATE ironvault_private.payment_verifications SET status=CASE WHEN p_action='reject_verification' THEN 'rejected' ELSE 'cancelled' END,reason=why,eligible=false WHERE request_id=r.id;
      UPDATE ironvault_private.subscription_requests SET cancelled_at=at_time WHERE id=r.id;
     END IF;
     PERFORM ironvault_private.subscription_notice(p_tenant,'verification-decision:'||r.id||':'||gen_random_uuid(),'Payment verification needs attention',why||CASE WHEN p_action='return_verification' THEN '. Correct within 48 hours. Provisional dashboard access only; owner-correction time is excluded from compensation.' ELSE '. Provisional access ended. Any money received must be settled separately.' END);
    END IF;
    INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),p_action,p_data);
   ELSIF p_action='approve_payment' THEN
    IF NOT provider THEN RAISE EXCEPTION 'Provider approval required';END IF;
    IF v.status='approved' THEN RETURN jsonb_build_object('approved',true,'request_id',r.id,'delay_days',v.delay_days,'start_date',v.approved_start,'end_date',v.approved_end);END IF;
    IF v.status<>'pending' OR r.approved_at IS NOT NULL OR r.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'Payment is not awaiting verification';END IF;
    IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RAISE EXCEPTION 'Gym is inactive';END IF;
    IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish required gym and platform documents before approval';END IF;
    IF NOT ironvault_private.owner_agreement_valid(p_tenant,s.owner_id,(v.original_quote->>'version_id')::uuid) THEN RAISE EXCEPTION 'Valid owner agreement required for the quoted version';END IF;
    ref:=btrim(p_data->>'reference');IF ref IS DISTINCT FROM r.payment_reference OR coalesce(length(ref),0)<3 THEN RAISE EXCEPTION 'Verify the exact submitted reference';END IF;
    SELECT * INTO tail FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant ORDER BY end_date DESC,approved_at DESC LIMIT 1 FOR UPDATE;
    result:=ironvault_private.verification_quote(r.id);
    IF result->>'review_hash' IS DISTINCT FROM p_data->>'review_hash' THEN RAISE EXCEPTION 'Payment dates changed; review the approval again';END IF;
    startday:=(result->>'start_date')::date;finish:=(result->>'end_date')::date;extra:=(result->>'delay_days')::integer;
    accessday:=CASE WHEN tail.id IS NOT NULL AND today<=tail.end_date THEN startday ELSE today END;
    INSERT INTO ironvault_private.subscription_periods(id,tenant_id,kind,plan,access_from,start_date,end_date,grace_days,version_id,policy,amount,reference,approved_by) VALUES(r.id,p_tenant,'paid',v.original_quote->>'plan',least(accessday,startday),startday,finish,(v.original_quote->'policy'->>'grace_days')::integer,(v.original_quote->>'version_id')::uuid,v.original_quote->'policy',(v.original_quote->>'amount')::numeric,ref,auth.uid());
    UPDATE ironvault_private.subscription_requests SET approved_at=at_time,approved_by=auth.uid() WHERE id=r.id;
    UPDATE ironvault_private.payment_verifications SET status='approved',eligible=false,delay_days=extra,approved_start=startday,approved_end=finish WHERE request_id=r.id;
    UPDATE ironvault_private.verification_intervals SET ended_at=at_time WHERE request_id=r.id AND ended_at IS NULL;
    UPDATE ironvault_private.gym_subscriptions SET next_plan=v.original_quote->>'plan' WHERE tenant_id=p_tenant;
    INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),'approve_payment',jsonb_build_object('request_id',r.id,'reference',ref,'quote',v.original_quote,'start_date',startday,'end_date',finish,'delay_days',extra));
    IF extra>0 THEN INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),'automatic_delay_extension',jsonb_build_object('request_id',r.id,'days',extra,'reason','Automatic extension—delayed Provider approval'));END IF;
    UPDATE ironvault_private.owner_notifications SET superseded_at=at_time WHERE tenant_id=p_tenant AND available_at>now() AND notice_key ~ ':(reminder:|expiry|suspend|lastgrace|retention)' AND notice_key NOT LIKE r.id||':%';
    UPDATE ironvault_private.owner_notifications SET resolved_at=at_time WHERE tenant_id=p_tenant AND notice_key LIKE (v.original_period->>'id')||':%' AND notice_key ~ ':(reminder:|expiry|suspend|lastgrace|retention)';
    PERFORM ironvault_private.subscription_schedule(r.id);
    PERFORM ironvault_private.subscription_notice(p_tenant,r.id||':approved','Payment approved','Counted period: '||startday||' through '||finish||'. '||extra||' days added. Reason: Automatic extension—delayed Provider approval. Owner-correction days are excluded. Reference: '||ref);
   END IF;
  ELSE
   IF p_action IN ('return_verification','reject_verification','resubmit_verification','review_verification') THEN RAISE EXCEPTION 'No tracked verification for this request';END IF;
   RETURN ironvault_private.subscription_portal_043_base(p_tenant,p_action,p_data);
  END IF;
  UPDATE ironvault_private.provider_notices SET resolved_at=at_time WHERE tenant_id=p_tenant AND (notice_key IN ('request:'||r.id,'reference:'||r.id) OR notice_key LIKE 'corrected:'||r.id||':%') AND EXISTS(SELECT 1 FROM ironvault_private.payment_verifications WHERE request_id=r.id AND status IN ('approved','rejected','cancelled','correction'));
  UPDATE ironvault_private.provider_reminder_jobs SET state='cancelled' WHERE request_id=r.id AND state='queued' AND EXISTS(SELECT 1 FROM ironvault_private.payment_verifications WHERE request_id=r.id AND status<>'pending');
 ELSE
  result:=ironvault_private.subscription_portal_043_base(p_tenant,p_action,p_data);
  IF p_action IN ('quote','confirm_plan') THEN RETURN result;END IF;
  RETURN result||jsonb_build_object('verifications',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM ironvault_private.payment_verifications x WHERE x.tenant_id=p_tenant),'[]'));
 END IF;
 result:=ironvault_private.subscription_portal_043_base(p_tenant,'get','{}');
 RETURN result||jsonb_build_object('verifications',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM ironvault_private.payment_verifications x WHERE x.tenant_id=p_tenant),'[]'));
END $fn$;
-- The scheduler is a service-only worker. No browser, page view or email success controls access.
CREATE FUNCTION public.iv_provider_reminder_jobs(p_action text DEFAULT 'claim',p_id uuid DEFAULT NULL,p_token uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provider_reminder_jobs%ROWTYPE;v ironvault_private.payment_verifications%ROWTYPE;result jsonb:='[]';today date:=ironvault_private.subscription_today();
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN RAISE EXCEPTION 'Service worker required' USING ERRCODE='42501';END IF;
 IF p_action='claim' THEN
  IF (clock_timestamp() AT TIME ZONE 'Asia/Manila')::time>=time '09:00' THEN
   INSERT INTO ironvault_private.provider_reminder_jobs(request_id,day)
   SELECT x.request_id,today FROM ironvault_private.payment_verifications x JOIN ironvault_private.subscription_requests r ON r.id=x.request_id
   WHERE x.status='pending' AND x.submitted_at<=clock_timestamp()-interval '24 hours' AND r.approved_at IS NULL AND r.cancelled_at IS NULL ON CONFLICT DO NOTHING;
  END IF;
  UPDATE ironvault_private.provider_reminder_jobs j SET state='cancelled' WHERE j.state IN ('queued','sending') AND (j.day<today OR NOT EXISTS(SELECT 1 FROM ironvault_private.payment_verifications x WHERE x.request_id=j.request_id AND x.status='pending'));
  WITH stale AS (UPDATE ironvault_private.provider_reminder_jobs SET state='needs_review' WHERE state='sending' AND lease_until<clock_timestamp() RETURNING id,request_id)
  INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) SELECT 'mail-uncertain:'||stale.id,pv.tenant_id,'Reminder delivery needs review','A reminder worker stopped before delivery was confirmed. Inspect the mail provider before retrying. Access is unchanged.' FROM stale JOIN ironvault_private.payment_verifications pv ON pv.request_id=stale.request_id ON CONFLICT DO NOTHING;
  FOR job IN SELECT * FROM ironvault_private.provider_reminder_jobs WHERE day=today AND state='queued' AND attempts=0 ORDER BY day,id LIMIT 20 FOR UPDATE SKIP LOCKED LOOP
   UPDATE ironvault_private.provider_reminder_jobs SET state='sending',token=gen_random_uuid(),lease_until=clock_timestamp()+interval '10 minutes',attempts=attempts+1 WHERE id=job.id RETURNING * INTO job;
   SELECT * INTO v FROM ironvault_private.payment_verifications WHERE request_id=job.request_id;
   result:=result||jsonb_build_array(jsonb_build_object('id',job.id,'token',job.token,'request_id',job.request_id,'tenant_id',v.tenant_id,'submitted_at',v.submitted_at,'day',job.day));
  END LOOP;
  RETURN result;
 ELSIF p_action IN ('complete','uncertain') THEN
  UPDATE ironvault_private.provider_reminder_jobs SET state=CASE WHEN p_action='complete' THEN 'sent' ELSE 'needs_review' END,sent_at=CASE WHEN p_action='complete' THEN clock_timestamp() END,lease_until=NULL WHERE id=p_id AND token=p_token AND state='sending';
  IF FOUND AND p_action='uncertain' THEN
   INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) SELECT 'mail-uncertain:'||j.id,pv.tenant_id,'Reminder delivery needs review','Email delivery was not confirmed. Inspect the mail provider before retrying; access is unchanged.' FROM ironvault_private.provider_reminder_jobs j JOIN ironvault_private.payment_verifications pv ON pv.request_id=j.request_id WHERE j.id=p_id ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('recorded',true);
 ELSE RAISE EXCEPTION 'Invalid reminder action';END IF;
END $fn$;
ALTER TABLE ironvault_private.payment_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.verification_intervals ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.provider_reminder_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.payment_verifications,ironvault_private.verification_intervals,ironvault_private.provider_reminder_jobs FROM PUBLIC,anon,authenticated;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
 (n.nspname='ironvault_private' AND p.proname IN ('verification_delay_days','verification_quote','subscription_state','subscription_state_043_base','subscription_portal_043_base')) OR (n.nspname='public' AND p.proname IN ('iv_subscription_portal','iv_provider_reminder_jobs')) LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f.signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_subscription_portal(text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iv_provider_reminder_jobs(text,uuid,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
