-- MANUAL ONLY after 047. Review docs/subscriptions/PROVIDER_CONTROL_ROLLOUT.md first.
-- No external payments, emails, automatic refunds or historical approval rewrites.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_profile_images(text,jsonb)') IS NULL OR to_regprocedure('ironvault_private.owner_agreement_valid(text,uuid,uuid)') IS NULL OR to_regprocedure('ironvault_private.subscription_state_043_base(text)') IS NULL THEN RAISE EXCEPTION 'Apply and confirm 047 and its prerequisites first'; END IF;
 IF to_regclass('ironvault_private.subscription_intents') IS NOT NULL THEN RAISE EXCEPTION '048 already installed; do not reapply'; END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.subscription_periods a JOIN ironvault_private.subscription_periods b ON a.tenant_id=b.tenant_id AND a.id<b.id AND daterange(a.start_date,a.end_date,'[]')&&daterange(b.start_date,b.end_date,'[]')) THEN RAISE EXCEPTION 'Existing subscription periods overlap. Review them before 048; no records changed'; END IF;
END $guard$;
ALTER TABLE ironvault_private.subscription_periods ADD COLUMN cancelled_at timestamptz,ADD COLUMN management_revision bigint NOT NULL DEFAULT 0,ADD COLUMN complimentary_days integer NOT NULL DEFAULT 0 CHECK(complimentary_days>=0);
-- Preserve legacy extension days when the original immutable paid quote establishes the base duration.
UPDATE ironvault_private.subscription_periods p SET complimentary_days=(p.end_date-p.start_date)-((r.quote->>'end_date')::date-(r.quote->>'start_date')::date)
FROM ironvault_private.subscription_requests r WHERE r.id=p.id AND r.kind='payment' AND r.quote->>'start_date' IS NOT NULL AND r.quote->>'end_date' IS NOT NULL AND p.kind='paid' AND
 (p.end_date-p.start_date)>=((r.quote->>'end_date')::date-(r.quote->>'start_date')::date);
CREATE TABLE ironvault_private.subscription_payment_methods(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text NOT NULL,account_name text NOT NULL DEFAULT '',account_number text NOT NULL DEFAULT '',instructions text NOT NULL DEFAULT '',image_path text,active boolean NOT NULL DEFAULT true,deleted_at timestamptz,revision bigint NOT NULL DEFAULT 1,updated_by uuid NOT NULL,updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE ironvault_private.subscription_images(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),path text UNIQUE NOT NULL,purpose text NOT NULL CHECK(purpose IN ('method','proof')),tenant_id text REFERENCES public.owners(id) ON DELETE CASCADE,actor_id uuid NOT NULL,mime text NOT NULL CHECK(mime IN ('image/jpeg','image/png','image/webp')),ready boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),CHECK((purpose='method' AND tenant_id IS NULL) OR (purpose='proof' AND tenant_id IS NOT NULL))
);
CREATE TABLE ironvault_private.subscription_intents(
 id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,owner_id uuid NOT NULL,kind text NOT NULL CHECK(kind IN ('payment','upgrade','change','cancel')),target_period uuid REFERENCES ironvault_private.subscription_periods(id),desired jsonb NOT NULL,submission jsonb NOT NULL DEFAULT '{}',quote jsonb NOT NULL,method_snapshot jsonb,proof_path text,reference text,status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','returned','approved','rejected','cancelled')),legacy boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),decided_at timestamptz,decision_note text,revision bigint NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX iv_sub_one_new_pending ON ironvault_private.subscription_intents(tenant_id) WHERE status IN ('pending','returned') AND NOT legacy;
CREATE TABLE ironvault_private.subscription_previews(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,actor_id uuid NOT NULL,input jsonb NOT NULL,quote jsonb NOT NULL,fingerprint text NOT NULL,expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '10 minutes',result jsonb
);
CREATE TABLE ironvault_private.subscription_transactions(
 id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,period_id uuid REFERENCES ironvault_private.subscription_periods(id),request_id uuid REFERENCES ironvault_private.subscription_intents(id),kind text NOT NULL CHECK(kind IN ('payment','upgrade','complimentary','change','cancel','refund')),amount numeric(12,2) NOT NULL CHECK(amount>=0),standard_amount numeric(12,2) NOT NULL DEFAULT 0,reference text,note text NOT NULL DEFAULT '',verified_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),snapshot jsonb NOT NULL,acknowledgment text UNIQUE NOT NULL
);
CREATE UNIQUE INDEX iv_sub_verified_reference ON ironvault_private.subscription_transactions(tenant_id,lower(btrim(reference))) WHERE kind IN ('payment','upgrade','change') AND amount>0 AND nullif(btrim(reference),'') IS NOT NULL;
CREATE INDEX iv_sub_transaction_report ON ironvault_private.subscription_transactions(created_at,tenant_id);
-- Import only unresolved legacy requests, preserving their IDs, original quote and timestamps.
INSERT INTO ironvault_private.subscription_intents(id,tenant_id,owner_id,kind,target_period,desired,quote,reference,legacy,created_at,status)
 SELECT r.id,r.tenant_id,r.owner_id,CASE WHEN r.kind='payment' THEN 'payment' WHEN r.kind='upgrade' THEN 'upgrade' ELSE 'change' END,
 CASE WHEN r.kind='payment' THEN NULL ELSE nullif(r.quote->>'prior_period','')::uuid END,
 jsonb_build_object('plan',r.quote->>'plan','months',1,'legacy_kind',r.kind),r.quote,r.payment_reference,true,r.confirmed_at,
 CASE WHEN v.status='correction' THEN 'returned' ELSE 'pending' END
 FROM ironvault_private.subscription_requests r LEFT JOIN ironvault_private.payment_verifications v ON v.request_id=r.id
 WHERE r.approved_at IS NULL AND r.cancelled_at IS NULL;
-- Import existing verified payments into the report ledger, without creating new access/notices.
INSERT INTO ironvault_private.subscription_transactions(id,tenant_id,period_id,kind,amount,standard_amount,reference,note,verified_by,created_at,snapshot,acknowledgment)
 SELECT r.id,r.tenant_id,p.id,CASE WHEN r.kind='upgrade' THEN 'upgrade' ELSE 'payment' END,(r.quote->>'amount')::numeric,(r.quote->>'amount')::numeric,
 coalesce(r.payment_reference,history.data->>'reference'),
 'Historical approved payment imported; no new collection',r.approved_by,r.approved_at,
 jsonb_build_object('historical_import',true,'legacy_request_id',r.id,'legacy_quote',r.quote,'provider',v.data->>'provider_name','brand',v.data->>'brand','gym',jsonb_build_object('id',g.id,'name',g.gym_name,'owner',g.owner_name),'identity_source','Current display identity; original quote retained','quote',r.quote||jsonb_build_object('action',r.kind,'final_amount',r.quote->'amount','standard_amount',r.quote->'amount','amount_due',r.quote->'amount','days',coverage.end_date-coverage.start_date+1,'start_date',coverage.start_date,'end_date',coverage.end_date,'periods_before','[]'::jsonb,'periods_after','[]'::jsonb),'verification','Imported from recorded provider approval','record','HIST-'||r.id),
 'HIST-'||r.id
 FROM ironvault_private.subscription_requests r JOIN ironvault_private.subscription_periods p ON p.tenant_id=r.tenant_id AND p.id=CASE WHEN r.kind='payment' THEN r.id ELSE nullif(r.quote->>'prior_period','')::uuid END
 JOIN public.owners g ON g.id=r.tenant_id JOIN ironvault_private.service_versions v ON v.id=p.version_id
 LEFT JOIN LATERAL (SELECT e.data FROM ironvault_private.subscription_events e WHERE e.tenant_id=r.tenant_id AND e.data->>'request_id'=r.id::text AND e.action='approve_payment' ORDER BY e.created_at DESC LIMIT 1) history ON true
 CROSS JOIN LATERAL (SELECT coalesce(nullif(history.data->>'start_date','')::date,nullif(r.quote->>'start_date','')::date,p.start_date) AS start_date,coalesce(nullif(history.data->>'end_date','')::date,nullif(r.quote->>'end_date','')::date,p.end_date) AS end_date) coverage
 WHERE r.approved_at IS NOT NULL AND r.approved_by IS NOT NULL AND r.kind IN ('payment','upgrade') AND (r.quote->>'amount')::numeric>0;
-- Stop obsolete verification reminder jobs; the owner/provider in-app reminder system remains.
UPDATE ironvault_private.provider_reminder_jobs SET state='cancelled',lease_until=NULL WHERE state IN ('queued','sending');
UPDATE ironvault_private.verification_intervals SET ended_at=clock_timestamp() WHERE ended_at IS NULL;

-- Ordinary period/grace entitlement only; pending payment claims cannot extend access.
CREATE OR REPLACE FUNCTION ironvault_private.subscription_state(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE t date:=ironvault_private.subscription_today();p ironvault_private.subscription_periods%ROWTYPE;g boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RETURN jsonb_build_object('status','inactive','operations',false,'portal',false,'read',false);END IF;
 SELECT * INTO p FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant AND cancelled_at IS NULL AND access_from<=t ORDER BY access_from DESC,approved_at DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','setup','operations',false,'portal',false,'read',false);END IF;
 g:=p.kind='paid' AND t>p.end_date AND t<=p.end_date+p.grace_days;
 RETURN jsonb_build_object('status',CASE WHEN t<=p.end_date THEN p.kind WHEN g THEN 'grace' ELSE 'suspended' END,'operations',t<=p.end_date OR g,'portal',t<=p.end_date AND p.plan='portal','read',t<=p.end_date OR g OR t<=p.end_date+p.grace_days+coalesce((p.policy->>'export_days')::integer,30),'plan',p.plan,'kind',p.kind,'period_id',p.id,'start_date',p.start_date,'end_date',p.end_date,'grace_end',p.end_date+p.grace_days,'days_remaining',greatest(0,p.end_date-t+1),'retention_review_date',p.end_date+p.grace_days+coalesce((p.policy->>'retention_days')::integer,90));
END $fn$;
CREATE FUNCTION ironvault_private.subscription_overlap_048()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF EXISTS(SELECT 1 FROM ironvault_private.subscription_periods a JOIN ironvault_private.subscription_periods b ON a.tenant_id=b.tenant_id AND a.id<b.id AND a.cancelled_at IS NULL AND b.cancelled_at IS NULL AND daterange(a.start_date,a.end_date,'[]')&&daterange(b.start_date,b.end_date,'[]') WHERE a.tenant_id=NEW.tenant_id) THEN RAISE EXCEPTION 'Subscription coverage overlaps; no approval saved';END IF;RETURN NULL;
END $fn$;
CREATE CONSTRAINT TRIGGER iv_sub_no_overlap AFTER INSERT OR UPDATE ON ironvault_private.subscription_periods DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_overlap_048();

CREATE FUNCTION ironvault_private.subscription_fingerprint_048(p_tenant text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT md5(jsonb_build_object('day',ironvault_private.subscription_today(),'gym',(SELECT jsonb_build_object('id',g.id,'name',g.gym_name,'owner',g.owner_name,'status',g.status) FROM public.owners g WHERE g.id=p_tenant),'subscription',(SELECT to_jsonb(s) FROM ironvault_private.gym_subscriptions s WHERE tenant_id=p_tenant),'periods',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM ironvault_private.subscription_periods p WHERE tenant_id=p_tenant),'requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM ironvault_private.subscription_intents r WHERE tenant_id=p_tenant),'versions',(SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id) FROM ironvault_private.service_versions v),'acceptances',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.version_id) FROM ironvault_private.service_acceptances a WHERE tenant_id=p_tenant),'transactions',(SELECT jsonb_agg(to_jsonb(tx) ORDER BY tx.id) FROM ironvault_private.subscription_transactions tx WHERE tx.tenant_id=p_tenant),'methods',(SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM ironvault_private.subscription_payment_methods m))::text);
$fn$;

CREATE FUNCTION ironvault_private.subscription_quote_048(p_tenant text,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE t date:=ironvault_private.subscription_today();s ironvault_private.gym_subscriptions%ROWTYPE;tail ironvault_private.subscription_periods%ROWTYPE;p ironvault_private.subscription_periods%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;r ironvault_private.subscription_intents%ROWTYPE;
 action text:=p_input->>'action';plan text:=p_input->>'plan';months integer:=coalesce((p_input->>'months')::integer,1);days integer:=coalesce((p_input->>'days')::integer,0);target uuid:=nullif(p_input->>'target_period','')::uuid;startday date;finish date;accessday date;standard numeric:=0;total numeric:=0;charge numeric:=0;offset_days integer:=0;note text:=btrim(coalesce(p_input->>'note',''));before_rows jsonb;after_rows jsonb:='[]';item jsonb;policy jsonb;version uuid;refund_due numeric:=0;request uuid:=nullif(p_input->>'request_id','')::uuid;
BEGIN
 SELECT * INTO STRICT s FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant;
 IF action NOT IN ('payment','upgrade','complimentary','change','cancel','reject','return','refund') OR action IS NULL THEN RAISE EXCEPTION 'Choose a valid subscription action';END IF;
 IF length(note)>2000 OR length(coalesce(p_input->>'reference',''))>180 THEN RAISE EXCEPTION 'Note or reference is too long';END IF;
 IF request IS NOT NULL THEN
  SELECT * INTO STRICT r FROM ironvault_private.subscription_intents WHERE id=request AND tenant_id=p_tenant;
  IF r.status NOT IN ('pending','returned') THEN RAISE EXCEPTION 'This request is already resolved';END IF;
  IF action NOT IN ('reject','return') AND r.kind<>action THEN RAISE EXCEPTION 'Action does not match the request';END IF;
  IF action IN ('change','cancel','upgrade') AND target IS DISTINCT FROM r.target_period THEN RAISE EXCEPTION 'Request targets a different period';END IF;
 ELSIF action IN ('reject','return') THEN RAISE EXCEPTION 'Select a request';
 ELSIF action IN ('payment','upgrade','change','cancel') AND EXISTS(SELECT 1 FROM ironvault_private.subscription_intents WHERE tenant_id=p_tenant AND status IN ('pending','returned')) THEN RAISE EXCEPTION 'Review the existing pending request before direct assignment';
 END IF;
 IF action IN ('return','reject','complimentary','change','cancel','refund') AND length(note)<3 THEN RAISE EXCEPTION 'Enter a reason/note';END IF;
 SELECT * INTO tail FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant AND cancelled_at IS NULL ORDER BY end_date DESC,approved_at DESC LIMIT 1;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.start_date,x.id),'[]') INTO before_rows FROM ironvault_private.subscription_periods x WHERE tenant_id=p_tenant AND cancelled_at IS NULL AND (x.end_date>=t OR x.id=target OR x.id=tail.id);
 IF action='payment' THEN
  IF months<1 OR months>120 THEN RAISE EXCEPTION 'Months must be a whole number from 1 to 120';END IF;
  IF plan NOT IN ('dashboard','portal') OR plan IS NULL THEN RAISE EXCEPTION 'Choose a plan';END IF;
  days:=months*30;
  startday:=CASE WHEN tail.id IS NOT NULL AND (t<=tail.end_date OR tail.kind='paid' AND t<=tail.end_date+tail.grace_days) THEN tail.end_date+1 ELSE t+1 END;
  accessday:=CASE WHEN tail.id IS NOT NULL AND t<=tail.end_date THEN startday ELSE least(t,startday) END;finish:=startday+days-1;
  SELECT * INTO STRICT v FROM ironvault_private.service_versions WHERE NOT retired AND effective_date<=startday ORDER BY effective_date DESC,published_at DESC LIMIT 1;
  policy:=ironvault_private.service_parameters(v.data);version:=v.id;
  IF (policy->>'paid_days')::integer<>30 THEN RAISE EXCEPTION 'The applicable published agreement must specify 30-day months before a new plan can be approved';END IF;
  standard:=(policy->>CASE plan WHEN 'portal' THEN 'portal_price' ELSE 'dashboard_price' END)::numeric*months;
  total:=coalesce((p_input->>'amount')::numeric,standard);charge:=total;
 ELSIF action NOT IN ('reject','return') THEN
  SELECT * INTO STRICT p FROM ironvault_private.subscription_periods WHERE id=target AND tenant_id=p_tenant AND (cancelled_at IS NULL OR action='refund');
  IF p.kind<>'paid' THEN RAISE EXCEPTION 'Select an existing paid subscription, not a pilot';END IF;
  plan:=p.plan;version:=p.version_id;policy:=p.policy;startday:=p.start_date;finish:=p.end_date;accessday:=p.access_from;total:=p.amount;
  IF action='upgrade' THEN
   IF t>p.end_date OR p.access_from>t OR p.plan<>'dashboard' OR EXISTS(SELECT 1 FROM ironvault_private.subscription_periods x WHERE x.tenant_id=p_tenant AND x.cancelled_at IS NULL AND x.start_date>p.start_date) THEN RAISE EXCEPTION 'Upgrade requires an active Dashboard period without queued renewals';END IF;
   plan:='portal';standard:=round(((p.policy->>'portal_price')::numeric-(p.policy->>'dashboard_price')::numeric)*(p.end_date-greatest(t,p.start_date)+1)/30,2);
   charge:=coalesce((p_input->>'amount')::numeric,standard);total:=p.amount+charge;startday:=t;
  ELSIF action='complimentary' THEN
   IF t>p.end_date THEN RAISE EXCEPTION 'Complimentary days require a current or scheduled paid period';END IF;
   IF days<1 OR days>3650 THEN RAISE EXCEPTION 'Enter 1 to 3650 complimentary days';END IF;
   finish:=p.end_date+days;offset_days:=days;
  ELSIF action='change' THEN
   IF p.access_from<=t THEN RAISE EXCEPTION 'An active period cannot be silently edited; use an upgrade, extension or recorded refund';END IF;
   plan:=p_input->>'plan';IF plan NOT IN ('dashboard','portal') OR plan IS NULL OR months<1 OR months>120 THEN RAISE EXCEPTION 'Choose a plan and 1 to 120 whole months';END IF;
   IF (policy->>'paid_days')::integer<>30 THEN RAISE EXCEPTION 'This period uses a different published day policy; review its terms before changing duration';END IF;
   days:=months*30+p.complimentary_days;finish:=p.start_date+days-1;offset_days:=finish-p.end_date;
   standard:=(policy->>CASE plan WHEN 'portal' THEN 'portal_price' ELSE 'dashboard_price' END)::numeric*months;
   total:=coalesce((p_input->>'amount')::numeric,standard);charge:=greatest(0,total-p.amount);refund_due:=greatest(0,p.amount-total);
  ELSIF action='cancel' THEN
   IF p.access_from<=t THEN RAISE EXCEPTION 'Only a scheduled, not-yet-active period may be cancelled';END IF;
   offset_days:=-(p.end_date-p.start_date+1);refund_due:=p.amount;
  ELSIF action='refund' THEN
   charge:=coalesce((p_input->>'amount')::numeric,0);
   IF charge<=0 OR charge<>round(charge,2) OR charge::text IN ('NaN','Infinity','-Infinity') OR charge>(SELECT coalesce(sum(CASE WHEN kind='refund' THEN -amount ELSE amount END),0) FROM ironvault_private.subscription_transactions WHERE period_id=p.id) THEN RAISE EXCEPTION 'Refund exceeds verified unrefunded collections recorded for this period';END IF;
  END IF;
 END IF;
 IF action IN ('payment','upgrade','change') THEN
  IF total IS NULL OR total::text IN ('NaN','Infinity','-Infinity') OR total<=0 OR total>9999999999.99 OR total<>round(total,2) OR charge<0 OR (action='upgrade' AND charge<=0) THEN RAISE EXCEPTION 'Enter a valid positive amount with at most two decimal places';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RAISE EXCEPTION 'Gym must be active';END IF;
  IF NOT ironvault_private.owner_agreement_valid(p_tenant,s.owner_id,version) OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish required documents and have the owner accept the applicable agreement first';END IF;
 ELSIF action='complimentary' AND NOT ironvault_private.owner_agreement_valid(p_tenant,s.owner_id,version) THEN RAISE EXCEPTION 'Owner acceptance of this period agreement is required';END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(before_rows) LOOP
  IF (item->>'id')::uuid=target THEN
   IF action IN ('complimentary','change') THEN item:=item||jsonb_build_object('end_date',finish,'plan',plan,'amount',total,'complimentary_days',p.complimentary_days+CASE WHEN action='complimentary' THEN days ELSE 0 END);
   ELSIF action='upgrade' THEN item:=item||jsonb_build_object('plan','portal','amount',total);
   ELSIF action='cancel' THEN item:=item||jsonb_build_object('cancelled',true);END IF;
  ELSIF offset_days<>0 AND (item->>'start_date')::date>p.start_date THEN
   item:=item||jsonb_build_object('start_date',(item->>'start_date')::date+offset_days,'end_date',(item->>'end_date')::date+offset_days,'access_from',(item->>'access_from')::date+offset_days);
  END IF;
  after_rows:=after_rows||jsonb_build_array(item);
 END LOOP;
 RETURN jsonb_build_object('action',action,'request_id',request,'target_period',target,'plan',plan,'months',CASE WHEN action IN ('payment','change') THEN months ELSE NULL END,'complimentary_days',CASE WHEN action='change' THEN p.complimentary_days ELSE 0 END,'days',CASE WHEN action='upgrade' THEN p.end_date-greatest(t,p.start_date)+1 ELSE days END,'start_date',startday,'end_date',finish,'access_from',accessday,'standard_amount',standard,'final_amount',total,'amount_due',charge,'possible_refund',refund_due,'note',note,'reference',nullif(btrim(p_input->>'reference'),''),'version_id',version,'policy',policy,'periods_before',before_rows,'periods_after',after_rows,'as_of',t,'currency','PHP','source_request',CASE WHEN request IS NULL THEN NULL ELSE to_jsonb(r) END);
END $fn$;

CREATE FUNCTION ironvault_private.subscription_schedule_048(p_period uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE p ironvault_private.subscription_periods%ROWTYPE;prefix text;n integer;t date:=ironvault_private.subscription_today();
BEGIN
 SELECT * INTO STRICT p FROM ironvault_private.subscription_periods WHERE id=p_period;
 UPDATE ironvault_private.owner_notifications SET superseded_at=clock_timestamp() WHERE tenant_id=p.tenant_id AND notice_key LIKE p.id||':%' AND available_at>clock_timestamp() AND notice_key ~ ':(start|reminder:|expiry|suspend|lastgrace|retention)';
 IF p.cancelled_at IS NOT NULL THEN RETURN;END IF;
 prefix:=p.id||':v'||p.management_revision;
 IF p.start_date>=t THEN PERFORM ironvault_private.subscription_notice(p.tenant_id,prefix||':start','Your subscription has started',p.plan||' · '||p.start_date||' through '||p.end_date,p.start_date);END IF;
 FOREACH n IN ARRAY ARRAY[7,3,1] LOOP
  IF p.end_date+1-n>=t THEN PERFORM ironvault_private.subscription_notice(p.tenant_id,prefix||':reminder:'||n,'Subscription renewal reminder','Ends '||p.end_date||'. Renewal starts '||(p.end_date+1)||'. Submit early for Provider approval.',p.end_date+1-n);END IF;
 END LOOP;
 IF p.end_date+1>=t THEN PERFORM ironvault_private.subscription_notice(p.tenant_id,prefix||':expiry','Subscription period ended','Dashboard-only grace ends '||(p.end_date+p.grace_days)||'. Payment requests do not extend access.',p.end_date+1);END IF;
 IF p.end_date+p.grace_days+1>=t THEN PERFORM ironvault_private.subscription_notice(p.tenant_id,prefix||':suspend','Operational access suspended','Reports remain available within the agreed reporting window; Subscription remains available.',p.end_date+p.grace_days+1);END IF;
 IF p.grace_days>0 AND p.end_date+p.grace_days>=t THEN PERFORM ironvault_private.subscription_notice(p.tenant_id,prefix||':lastgrace','Last grace day','Operations stop tomorrow without an approved renewal.',p.end_date+p.grace_days);END IF;
 PERFORM ironvault_private.subscription_notice(p.tenant_id,prefix||':retention','Data retention review approaching','Export records or contact the provider. No automatic deletion.',p.end_date+p.grace_days+coalesce((p.policy->>'retention_days')::integer,90)-7);
END $fn$;

CREATE FUNCTION ironvault_private.subscription_image_read_048(p_path text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM ironvault_private.subscription_images a WHERE a.path=p_path AND a.ready AND
 (ironvault_private.subscription_super() OR (a.purpose='proof' AND ironvault_private.subscription_owner(a.tenant_id)) OR
 (a.purpose='method' AND EXISTS(SELECT 1 FROM ironvault_private.gym_subscriptions s WHERE ironvault_private.subscription_owner(s.tenant_id) AND
 (EXISTS(SELECT 1 FROM ironvault_private.subscription_payment_methods m WHERE m.image_path=a.path AND m.active AND m.deleted_at IS NULL) OR EXISTS(SELECT 1 FROM ironvault_private.subscription_intents r WHERE r.tenant_id=s.tenant_id AND r.method_snapshot->>'image_path'=a.path) OR EXISTS(SELECT 1 FROM ironvault_private.subscription_transactions tx WHERE tx.tenant_id=s.tenant_id AND tx.snapshot->'method'->>'image_path'=a.path))))));
$fn$;
CREATE FUNCTION ironvault_private.subscription_image_write_048(p_path text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM ironvault_private.subscription_images a WHERE a.path=p_path AND a.actor_id=auth.uid() AND NOT a.ready AND a.created_at>clock_timestamp()-interval '1 hour' AND (ironvault_private.subscription_super() OR a.purpose='proof' AND ironvault_private.subscription_owner(a.tenant_id)));
$fn$;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('iv-subscription-images','iv-subscription-images',false,2097152,ARRAY['image/jpeg','image/png','image/webp']);
CREATE POLICY iv_subscription_image_read ON storage.objects FOR SELECT TO authenticated USING(bucket_id='iv-subscription-images' AND ironvault_private.subscription_image_read_048(name));
CREATE POLICY iv_subscription_image_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='iv-subscription-images' AND ironvault_private.subscription_image_write_048(name));
-- Restrictive guards also fence this bucket from unrelated legacy permissive storage policies.
CREATE POLICY iv_sub_guard_read ON storage.objects AS RESTRICTIVE FOR SELECT TO public USING(bucket_id<>'iv-subscription-images' OR ironvault_private.subscription_image_read_048(name));
CREATE POLICY iv_sub_guard_insert ON storage.objects AS RESTRICTIVE FOR INSERT TO public WITH CHECK(bucket_id<>'iv-subscription-images' OR ironvault_private.subscription_image_write_048(name));
CREATE POLICY iv_sub_guard_update ON storage.objects AS RESTRICTIVE FOR UPDATE TO public USING(bucket_id<>'iv-subscription-images') WITH CHECK(bucket_id<>'iv-subscription-images');
CREATE POLICY iv_sub_guard_delete ON storage.objects AS RESTRICTIVE FOR DELETE TO public USING(bucket_id<>'iv-subscription-images');
-- No public URLs, overwrite or delete permission: referenced proof/method snapshots remain immutable.

CREATE FUNCTION public.iv_subscription_manage(p_tenant text DEFAULT NULL,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE provider boolean:=ironvault_private.subscription_super();owner boolean:=false;s ironvault_private.gym_subscriptions%ROWTYPE;r ironvault_private.subscription_intents%ROWTYPE;preview ironvault_private.subscription_previews%ROWTYPE;method ironvault_private.subscription_payment_methods%ROWTYPE;image ironvault_private.subscription_images%ROWTYPE;p ironvault_private.subscription_periods%ROWTYPE;
 v_id uuid;target uuid;v_quote jsonb;item jsonb;old_item jsonb;v_result jsonb;payload jsonb;method_json jsonb;source jsonb;proof text;ref text;reason text;ack text;v_kind text;start_filter date;end_filter date;collected numeric;tx_kind text;before_rows jsonb;amount numeric;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>100000 THEN RAISE EXCEPTION 'Invalid subscription input';END IF;
 IF p_tenant IS NOT NULL THEN
  -- Shared lock order with pilot activation and all new approvals. Identity is rechecked after this lock.
  SELECT * INTO STRICT s FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant FOR UPDATE;
  owner:=ironvault_private.subscription_owner(p_tenant);provider:=ironvault_private.subscription_super();
 END IF;
 IF NOT provider AND NOT owner THEN RAISE EXCEPTION 'Registered owner or enabled Provider required' USING ERRCODE='42501';END IF;
 -- Pin the enabled role and gym identity through this transaction so revocation/suspension cannot race approval.
 PERFORM 1 FROM public.iv_user_roles role_row WHERE role_row.user_id=auth.uid() AND role_row.enabled AND role_row.disabled_at IS NULL AND
 ((provider AND role_row.role='super_admin' AND role_row.tenant_id IS NULL) OR (owner AND role_row.role='owner' AND role_row.tenant_id=p_tenant AND role_row.user_id=s.owner_id)) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Subscription authority revoked' USING ERRCODE='42501';END IF;
 IF p_tenant IS NOT NULL THEN PERFORM 1 FROM public.owners g WHERE g.id=p_tenant FOR SHARE;END IF;
 IF p_action IN ('save_method','delete_method','report','preview','commit','record_refund','queue') AND NOT provider THEN RAISE EXCEPTION 'Provider required' USING ERRCODE='42501';END IF;
 IF p_action='queue' THEN
  RETURN jsonb_build_object('requests',coalesce((SELECT jsonb_agg(x ORDER BY x.expiry NULLS LAST,x.created_at) FROM
   (SELECT r.*,g.gym_name,nullif(ironvault_private.subscription_state(r.tenant_id)->>'end_date','')::date AS expiry FROM ironvault_private.subscription_intents r JOIN public.owners g ON g.id=r.tenant_id WHERE r.status IN ('pending','returned')) x),'[]'));
 ELSIF p_action='methods' THEN
  RETURN jsonb_build_object('methods',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.name,m.id) FROM ironvault_private.subscription_payment_methods m WHERE provider OR m.active AND m.deleted_at IS NULL),'[]'));
 ELSIF p_action IN ('save_method','delete_method') THEN
  v_id:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());PERFORM pg_advisory_xact_lock(hashtextextended('subscription-method:'||v_id::text,48));
  SELECT * INTO method FROM ironvault_private.subscription_payment_methods WHERE subscription_payment_methods.id=v_id FOR UPDATE;
  IF method.id IS NOT NULL AND method.revision IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Payment method changed; reload before editing';END IF;
  IF p_action='delete_method' THEN
   UPDATE ironvault_private.subscription_payment_methods SET active=false,deleted_at=clock_timestamp(),revision=revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE subscription_payment_methods.id=v_id;
  ELSE
   IF length(btrim(coalesce(p_data->>'name',''))) NOT BETWEEN 1 AND 100 OR length(coalesce(p_data->>'account_name',''))>160 OR length(coalesce(p_data->>'account_number',''))>100 OR length(coalesce(p_data->>'instructions',''))>2000 THEN RAISE EXCEPTION 'Enter valid payment details';END IF;
   IF nullif(p_data->>'image_path','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM ironvault_private.subscription_images a WHERE a.path=p_data->>'image_path' AND a.purpose='method' AND a.ready) THEN RAISE EXCEPTION 'Upload and finish the payment QR first';END IF;
   INSERT INTO ironvault_private.subscription_payment_methods(id,name,account_name,account_number,instructions,image_path,active,updated_by)
    VALUES(v_id,btrim(p_data->>'name'),coalesce(p_data->>'account_name',''),coalesce(p_data->>'account_number',''),coalesce(p_data->>'instructions',''),nullif(p_data->>'image_path',''),coalesce((p_data->>'active')::boolean,true),auth.uid())
    ON CONFLICT ON CONSTRAINT subscription_payment_methods_pkey DO UPDATE SET name=excluded.name,account_name=excluded.account_name,account_number=excluded.account_number,instructions=excluded.instructions,image_path=excluded.image_path,active=excluded.active,deleted_at=NULL,updated_by=auth.uid(),updated_at=clock_timestamp(),revision=subscription_payment_methods.revision+1;
  END IF;
  RETURN jsonb_build_object('saved',true,'id',v_id);
 ELSIF p_action='prepare_image' THEN
  IF p_data->>'purpose' NOT IN ('method','proof') OR p_data->>'purpose' IS NULL OR (p_data->>'purpose'='method' AND NOT provider) OR (p_data->>'purpose'='proof' AND p_tenant IS NULL) THEN RAISE EXCEPTION 'Image upload is not authorized';END IF;
  IF p_data->>'mime' NOT IN ('image/jpeg','image/png','image/webp') OR p_data->>'mime' IS NULL THEN RAISE EXCEPTION 'Only JPEG, PNG and WebP images are allowed';END IF;
  IF (SELECT count(*) FROM ironvault_private.subscription_images WHERE actor_id=auth.uid() AND NOT ready AND created_at>clock_timestamp()-interval '1 hour')>=20 THEN RAISE EXCEPTION 'Too many unfinished uploads; retry later';END IF;
  v_id:=gen_random_uuid();proof:=v_id::text||'/image';
  INSERT INTO ironvault_private.subscription_images(id,path,purpose,tenant_id,actor_id,mime) VALUES(v_id,proof,p_data->>'purpose',CASE WHEN p_data->>'purpose'='proof' THEN p_tenant END,auth.uid(),p_data->>'mime');
  RETURN jsonb_build_object('id',v_id,'path',proof);
 ELSIF p_action='finish_image' THEN
  SELECT * INTO STRICT image FROM ironvault_private.subscription_images WHERE subscription_images.id=(p_data->>'id')::uuid AND actor_id=auth.uid() AND (purpose='method' AND provider OR tenant_id=p_tenant) FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM storage.objects o WHERE bucket_id='iv-subscription-images' AND name=image.path AND metadata->>'mimetype'=image.mime AND coalesce((metadata->>'size')::bigint,0) BETWEEN 1 AND 2097152) THEN RAISE EXCEPTION 'Image upload is incomplete or invalid';END IF;
  UPDATE ironvault_private.subscription_images SET ready=true WHERE subscription_images.id=image.id;RETURN jsonb_build_object('path',image.path);
 ELSIF p_action='report' THEN
  start_filter:=coalesce(nullif(p_data->>'from','')::date,'1900-01-01');end_filter:=coalesce(nullif(p_data->>'through','')::date,'9999-12-31');
  IF start_filter>end_filter THEN RAISE EXCEPTION 'Invalid date range';END IF;
  RETURN jsonb_build_object('gyms',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'name',g.gym_name) ORDER BY g.gym_name) FROM public.owners g),'[]'),'transactions',coalesce((SELECT jsonb_agg(x ORDER BY x.created_at DESC,x.id) FROM
   (SELECT tr.*,g.gym_name,(tr.created_at AT TIME ZONE 'Asia/Manila')::date AS verified_date FROM ironvault_private.subscription_transactions tr JOIN public.owners g ON g.id=tr.tenant_id WHERE
    (tr.created_at AT TIME ZONE 'Asia/Manila')::date BETWEEN start_filter AND end_filter AND (p_tenant IS NULL OR tr.tenant_id=p_tenant) AND (nullif(p_data->>'plan','') IS NULL OR tr.snapshot->'quote'->>'plan'=p_data->>'plan') AND (nullif(p_data->>'kind','') IS NULL OR tr.kind=p_data->>'kind')) x),'[]'));
 END IF;
 IF p_tenant IS NULL THEN RAISE EXCEPTION 'Select a gym';END IF;
 IF p_action='get' THEN
  RETURN jsonb_build_object('management_version',48,'today',ironvault_private.subscription_today(),'tenant_id',p_tenant,'provider',provider,'gym',(SELECT jsonb_build_object('id',g.id,'name',g.gym_name,'owner',g.owner_name) FROM public.owners g WHERE g.id=p_tenant),'state',ironvault_private.subscription_state(p_tenant),
   'periods',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.start_date,x.id) FROM ironvault_private.subscription_periods x WHERE tenant_id=p_tenant),'[]'),
   'requests',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id) FROM ironvault_private.subscription_intents x WHERE tenant_id=p_tenant),'[]'),
   'transactions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id) FROM ironvault_private.subscription_transactions x WHERE tenant_id=p_tenant),'[]'),
   'methods',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.name) FROM ironvault_private.subscription_payment_methods m WHERE m.active AND m.deleted_at IS NULL),'[]'),
   'prices',(SELECT jsonb_build_object('dashboard',v.data->'dashboard_price','portal',v.data->'portal_price') FROM ironvault_private.service_versions v WHERE v.id=ironvault_private.service_current()));
 ELSIF p_action IN ('owner_quote','submit') THEN
  IF NOT owner THEN RAISE EXCEPTION 'Only the registered owner can submit this request';END IF;
  v_kind:=p_data->>'kind';IF v_kind NOT IN ('payment','upgrade','change','cancel') OR v_kind IS NULL THEN RAISE EXCEPTION 'Choose a valid request';END IF;
  v_id:=(p_data->>'request_id')::uuid;
  IF p_action='submit' THEN
   IF v_id IS NULL THEN RAISE EXCEPTION 'Request ID required';END IF;
   SELECT * INTO r FROM ironvault_private.subscription_intents WHERE subscription_intents.id=v_id;
   IF FOUND THEN
    IF r.tenant_id<>p_tenant OR r.owner_id<>auth.uid() OR r.submission IS DISTINCT FROM p_data THEN RAISE EXCEPTION 'Request ID belongs to a different request';END IF;
    RETURN jsonb_build_object('request_id',v_id,'status',r.status,'replayed',true);
   END IF;
   IF EXISTS(SELECT 1 FROM ironvault_private.subscription_intents WHERE tenant_id=p_tenant AND status IN ('pending','returned')) THEN RAISE EXCEPTION 'There is already a pending request; review it instead of submitting again';END IF;
  END IF;
  payload:=jsonb_build_object('action',v_kind,'plan',p_data->'desired'->>'plan','months',1,'target_period',p_data->'desired'->>'target_period','note',coalesce(p_data->'desired'->>'note','Owner request'));
  -- Owner quotes cannot set prices/duration or grant complimentary access.
  IF v_kind IN ('change','cancel','upgrade') THEN
   target:=nullif(p_data->'desired'->>'target_period','')::uuid;
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.subscription_periods WHERE subscription_periods.id=target AND tenant_id=p_tenant AND cancelled_at IS NULL) THEN RAISE EXCEPTION 'Select an approved period';END IF;
  END IF;
  -- Existing request checks are handled above; quote helper receives a neutral preview context.
  v_quote:=ironvault_private.subscription_quote_048(p_tenant,payload);
  IF p_action='owner_quote' THEN RETURN v_quote;END IF;
  IF p_data->'quote' IS DISTINCT FROM v_quote OR p_data->>'confirmed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Quote changed; review fresh dates and confirm again';END IF;
  method_json:=NULL;IF nullif(p_data->>'method_id','') IS NOT NULL THEN
   SELECT * INTO STRICT method FROM ironvault_private.subscription_payment_methods WHERE subscription_payment_methods.id=(p_data->>'method_id')::uuid AND active AND deleted_at IS NULL;
   IF method.revision IS DISTINCT FROM (p_data->>'method_revision')::bigint THEN RAISE EXCEPTION 'Payment option changed; reopen Subscription and review the details before submitting';END IF;
   method_json:=to_jsonb(method);
  END IF;
  proof:=nullif(p_data->>'proof_path','');ref:=nullif(btrim(p_data->>'reference'),'');
  IF length(coalesce(ref,''))>180 THEN RAISE EXCEPTION 'Reference is too long';END IF;
  IF proof IS NOT NULL AND NOT EXISTS(SELECT 1 FROM ironvault_private.subscription_images a WHERE a.path=proof AND a.ready AND a.tenant_id=p_tenant AND a.purpose='proof' AND a.actor_id=auth.uid()) THEN RAISE EXCEPTION 'Upload your own receipt image for this gym';END IF;
  INSERT INTO ironvault_private.subscription_intents(id,tenant_id,owner_id,kind,target_period,desired,submission,quote,method_snapshot,proof_path,reference) VALUES(v_id,p_tenant,auth.uid(),v_kind,target,p_data->'desired',p_data,v_quote,method_json,proof,ref);
  INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) VALUES('subscription48:'||v_id,p_tenant,'Subscription request — waiting for approval',v_kind||' · '||coalesce(v_quote->>'plan','')||' · '||coalesce(v_quote->>'start_date','')||' through '||coalesce(v_quote->>'end_date','')||' · Request '||v_id);
  RETURN jsonb_build_object('request_id',v_id,'status','pending');
 ELSIF p_action='revise_request' THEN
  IF NOT owner THEN RAISE EXCEPTION 'Registered owner required';END IF;
  SELECT * INTO STRICT r FROM ironvault_private.subscription_intents WHERE subscription_intents.id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant FOR UPDATE;
  IF r.status NOT IN ('pending','returned') THEN RAISE EXCEPTION 'Request is already resolved';END IF;
  proof:=nullif(p_data->>'proof_path','');IF proof IS NOT NULL AND NOT EXISTS(SELECT 1 FROM ironvault_private.subscription_images a WHERE a.path=proof AND a.ready AND a.tenant_id=p_tenant AND a.purpose='proof' AND a.actor_id=auth.uid()) THEN RAISE EXCEPTION 'Invalid proof image';END IF;
  ref:=nullif(btrim(p_data->>'reference'),'');IF length(coalesce(ref,''))>180 THEN RAISE EXCEPTION 'Reference is too long';END IF;
  INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),'payment_proof_revised',to_jsonb(r));
  UPDATE ironvault_private.subscription_intents SET proof_path=coalesce(proof,proof_path),reference=ref,status='pending',revision=revision+1 WHERE subscription_intents.id=r.id;
  UPDATE ironvault_private.provider_notices SET resolved_at=NULL,available_at=clock_timestamp(),message='Owner supplied updated proof for request '||r.id WHERE notice_key='subscription48:'||r.id;
  RETURN jsonb_build_object('saved',true);
 ELSIF p_action='preview' THEN
  payload:=p_data;
  IF nullif(p_data->'method'->>'id','') IS NOT NULL THEN
   SELECT * INTO method FROM ironvault_private.subscription_payment_methods WHERE subscription_payment_methods.id=(p_data->'method'->>'id')::uuid AND active AND deleted_at IS NULL;
   IF FOUND THEN payload:=payload||jsonb_build_object('method',to_jsonb(method));
   ELSIF nullif(p_data->>'request_id','') IS NOT NULL THEN
    SELECT * INTO STRICT r FROM ironvault_private.subscription_intents WHERE subscription_intents.id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant;
    payload:=payload||jsonb_build_object('method',r.method_snapshot);
   ELSE RAISE EXCEPTION 'Payment option changed; select a current method';END IF;
  END IF;
  v_quote:=ironvault_private.subscription_quote_048(p_tenant,payload);
  INSERT INTO ironvault_private.subscription_previews(tenant_id,actor_id,input,quote,fingerprint) VALUES(p_tenant,auth.uid(),payload,v_quote,ironvault_private.subscription_fingerprint_048(p_tenant)) RETURNING * INTO preview;
  RETURN jsonb_build_object('preview_id',preview.id,'quote',v_quote,'expires_at',preview.expires_at);
 ELSIF p_action='commit' THEN
  SELECT * INTO STRICT preview FROM ironvault_private.subscription_previews WHERE subscription_previews.id=(p_data->>'preview_id')::uuid AND tenant_id=p_tenant AND actor_id=auth.uid() FOR UPDATE;
  -- A completed retry returns its immutable result BEFORE expiry/freshness checks.
  IF preview.result IS NOT NULL THEN RETURN preview.result||jsonb_build_object('replayed',true);END IF;
  IF p_data->>'reviewed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Review all details before approval';END IF;
  IF preview.expires_at<=clock_timestamp() OR preview.fingerprint IS DISTINCT FROM ironvault_private.subscription_fingerprint_048(p_tenant) THEN RAISE EXCEPTION 'Subscription changed or preview expired; open a fresh preview. No approval saved';END IF;
  v_quote:=ironvault_private.subscription_quote_048(p_tenant,preview.input);
  IF v_quote IS DISTINCT FROM preview.quote THEN RAISE EXCEPTION 'Quote changed; preview again';END IF;
  v_kind:=v_quote->>'action';amount:=(v_quote->>'amount_due')::numeric;target:=nullif(v_quote->>'target_period','')::uuid;v_id:=nullif(v_quote->>'request_id','')::uuid;reason:=v_quote->>'note';ref:=v_quote->>'reference';
  IF (v_kind IN ('payment','upgrade','change') AND amount>0) AND p_data->>'payment_verified' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Verify receipt of payment before approval';END IF;
  IF v_kind='refund' AND p_data->>'refund_verified' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Confirm money was actually returned outside the app';END IF;
  IF ref IS NOT NULL AND v_kind IN ('payment','upgrade','change') AND amount>0 AND (EXISTS(SELECT 1 FROM ironvault_private.subscription_transactions WHERE tenant_id=p_tenant AND lower(btrim(reference))=lower(ref) AND subscription_transactions.amount>0 AND subscription_transactions.kind IN ('payment','upgrade','change')) OR EXISTS(SELECT 1 FROM ironvault_private.subscription_events WHERE tenant_id=p_tenant AND action='approve_payment' AND lower(btrim(data->>'reference'))=lower(ref))) THEN RAISE EXCEPTION 'This payment reference was already used for this gym';END IF;
  IF v_kind='payment' THEN
   target:=preview.id;
   INSERT INTO ironvault_private.subscription_periods(id,tenant_id,kind,plan,access_from,start_date,end_date,grace_days,version_id,policy,amount,reference,approved_by)
   VALUES(target,p_tenant,'paid',v_quote->>'plan',(v_quote->>'access_from')::date,(v_quote->>'start_date')::date,(v_quote->>'end_date')::date,(v_quote->'policy'->>'grace_days')::integer,(v_quote->>'version_id')::uuid,v_quote->'policy',(v_quote->>'final_amount')::numeric,ref,auth.uid());
   PERFORM ironvault_private.subscription_schedule_048(target);
  ELSIF v_kind IN ('complimentary','upgrade','change','cancel') THEN
   FOR item IN SELECT value FROM jsonb_array_elements(v_quote->'periods_after') LOOP
    SELECT value INTO old_item FROM jsonb_array_elements(v_quote->'periods_before') WHERE value->>'id'=item->>'id';
    IF item IS DISTINCT FROM old_item THEN
     UPDATE ironvault_private.subscription_periods SET plan=item->>'plan',start_date=(item->>'start_date')::date,end_date=(item->>'end_date')::date,access_from=(item->>'access_from')::date,amount=(item->>'amount')::numeric,complimentary_days=coalesce((item->>'complimentary_days')::integer,0),cancelled_at=CASE WHEN item->>'cancelled'='true' THEN clock_timestamp() END,management_revision=management_revision+1 WHERE subscription_periods.id=(item->>'id')::uuid AND tenant_id=p_tenant;
     PERFORM ironvault_private.subscription_schedule_048((item->>'id')::uuid);
    END IF;
   END LOOP;
  END IF;
  IF v_id IS NOT NULL THEN
   UPDATE ironvault_private.subscription_intents SET status=CASE v_kind WHEN 'reject' THEN 'rejected' WHEN 'return' THEN 'returned' ELSE 'approved' END,decided_at=clock_timestamp(),decision_note=reason,revision=revision+1 WHERE subscription_intents.id=v_id;
   IF v_kind<>'return' THEN UPDATE ironvault_private.payment_verifications SET eligible=false,status=CASE WHEN v_kind='reject' THEN 'rejected' ELSE 'approved' END WHERE request_id=v_id;END IF;
   IF v_kind<>'return' THEN UPDATE ironvault_private.subscription_requests SET approved_at=CASE WHEN v_kind='reject' THEN NULL ELSE clock_timestamp() END,approved_by=CASE WHEN v_kind='reject' THEN NULL ELSE auth.uid() END,cancelled_at=CASE WHEN v_kind='reject' THEN clock_timestamp() ELSE cancelled_at END WHERE subscription_requests.id=v_id AND tenant_id=p_tenant AND approved_at IS NULL;END IF;
   UPDATE ironvault_private.provider_notices SET resolved_at=CASE WHEN v_kind='return' THEN NULL ELSE clock_timestamp() END WHERE notice_key IN ('subscription48:'||v_id,'request:'||v_id,'reference:'||v_id);
  END IF;
  IF v_kind IN ('reject','return') THEN
   ack:='DEC-'||preview.id;v_result:=jsonb_build_object('approved',true,'action',v_kind,'request_id',v_id,'record',ack);
  ELSE
   ack:=CASE WHEN v_kind IN ('payment','upgrade') OR v_kind='change' AND amount>0 THEN 'PA-' WHEN v_kind='complimentary' THEN 'CF-' ELSE 'ADJ-' END||preview.id;
   SELECT jsonb_build_object('provider',coalesce(v.data->>'provider_name','Provider'),'brand',coalesce(v.data->>'brand','Iron Vault'),'billing_contact',v.data->>'billing_contact') INTO source FROM ironvault_private.service_versions v WHERE v.id=coalesce(nullif(v_quote->>'version_id','')::uuid,ironvault_private.service_current());
   source:=coalesce(source,'{}')||jsonb_build_object('gym',(SELECT jsonb_build_object('id',g.id,'name',g.gym_name,'owner',g.owner_name) FROM public.owners g WHERE g.id=p_tenant),'quote',v_quote,'verified_by',auth.uid(),'verification',CASE WHEN v_kind='refund' THEN 'Manual refund confirmed by provider' WHEN v_kind IN ('payment','upgrade','change') AND amount>0 THEN 'Manually verified by provider' ELSE 'No payment collected' END,'method',coalesce(nullif(preview.input->'method','null'::jsonb),v_quote->'source_request'->'method_snapshot'),'record',ack);
   INSERT INTO ironvault_private.subscription_transactions(id,tenant_id,period_id,request_id,kind,amount,standard_amount,reference,note,verified_by,snapshot,acknowledgment)
   VALUES(preview.id,p_tenant,target,v_id,v_kind,CASE WHEN v_kind IN ('payment','upgrade','change','refund') THEN amount ELSE 0 END,CASE WHEN v_kind='change' THEN greatest(0,(v_quote->>'standard_amount')::numeric-coalesce((SELECT (value->>'amount')::numeric FROM jsonb_array_elements(v_quote->'periods_before') WHERE value->>'id'=target::text),0)) ELSE coalesce((v_quote->>'standard_amount')::numeric,0) END,ref,reason,auth.uid(),source,ack);
   v_result:=jsonb_build_object('approved',true,'action',v_kind,'period_id',target,'request_id',v_id,'record',ack,'transaction_id',preview.id);
  END IF;
  INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),'subscription_'||v_kind||'_048',jsonb_build_object('quote',v_quote,'result',v_result));
  PERFORM ironvault_private.subscription_notice(p_tenant,'subscription48:'||preview.id,CASE v_kind WHEN 'complimentary' THEN 'Complimentary days approved' WHEN 'reject' THEN 'Subscription request rejected' WHEN 'return' THEN 'Subscription request needs correction' WHEN 'cancel' THEN 'Scheduled subscription cancelled' WHEN 'refund' THEN 'Refund recorded' ELSE 'Subscription approved' END,
   coalesce(v_quote->>'plan','Request')||' · '||coalesce(v_quote->>'start_date','')||' through '||coalesce(v_quote->>'end_date','')||' · '||CASE WHEN v_kind='complimentary' THEN (v_quote->>'days')||' complimentary days — no charge' WHEN v_kind IN ('reject','return') THEN 'No access change' ELSE 'PHP '||coalesce(amount,0)::text END||' · '||coalesce(reason,'')||CASE WHEN v_kind='complimentary' THEN ' · Expiry: '||coalesce((SELECT value->>'end_date' FROM jsonb_array_elements(v_quote->'periods_before') WHERE value->>'id'=target::text),'')||' → '||(v_quote->>'end_date')||' · Later scheduled coverage: '||coalesce((SELECT string_agg((a.value->>'start_date')||' → '||(b.value->>'start_date'),'; ') FROM jsonb_array_elements(v_quote->'periods_before') a JOIN jsonb_array_elements(v_quote->'periods_after') b ON a.value->>'id'=b.value->>'id' WHERE a.value->>'start_date' IS DISTINCT FROM b.value->>'start_date'),'unchanged') ELSE '' END||' · Record '||ack||'. View Subscription → Payment History for the full dates and record.');
  UPDATE ironvault_private.subscription_previews SET result=v_result WHERE subscription_previews.id=preview.id;
  RETURN v_result;
 ELSE RAISE EXCEPTION 'Unknown subscription management action';END IF;
END $fn$;

-- Retain agreement/pilot/notice APIs; obsolete clients cannot bypass the new review protocol.
ALTER FUNCTION public.iv_subscription_portal(text,text,jsonb) RENAME TO subscription_portal_048_base;
ALTER FUNCTION public.subscription_portal_048_base(text,text,jsonb) SET SCHEMA ironvault_private;
REVOKE ALL ON FUNCTION ironvault_private.subscription_portal_048_base(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE output jsonb;BEGIN
 IF p_action NOT IN ('get','badge','notifications','accept','read_notice','activate_pilot') OR p_action IS NULL THEN RAISE EXCEPTION 'Reload Subscription to use the new preview and approval controls. No transaction recorded';END IF;
 output:=ironvault_private.subscription_portal_048_base(p_tenant,p_action,p_data);
 IF p_action='get' THEN RETURN output||jsonb_build_object('management_version',48,'management',public.iv_subscription_manage(p_tenant,'get','{}'));END IF;
 RETURN output;
END $fn$;
-- Disable the legacy external email-verification worker without sending anything.
CREATE OR REPLACE FUNCTION public.iv_provider_reminder_jobs(p_action text DEFAULT 'claim',p_id uuid DEFAULT NULL,p_token uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN RAISE EXCEPTION 'Service worker required' USING ERRCODE='42501';END IF;
 IF p_action='claim' THEN RETURN '[]'::jsonb;END IF;
 RETURN jsonb_build_object('recorded',false,'retired',true);
END $fn$;
DO $acl$ DECLARE tab text;f record;BEGIN
 FOREACH tab IN ARRAY ARRAY['subscription_payment_methods','subscription_images','subscription_intents','subscription_previews','subscription_transactions'] LOOP
  EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',tab);EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',tab);EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',tab);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
  (n.nspname='ironvault_private' AND (p.proname LIKE '%\_048' ESCAPE '\' OR p.proname='subscription_portal_048_base')) OR (n.nspname='public' AND p.proname IN ('iv_subscription_manage','iv_subscription_portal','iv_provider_reminder_jobs')) LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f.signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_subscription_manage(text,text,jsonb),public.iv_subscription_portal(text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION ironvault_private.subscription_image_read_048(text),ironvault_private.subscription_image_write_048(text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iv_provider_reminder_jobs(text,uuid,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
