-- MANUAL ONLY after 035. Replace two function bodies; preserve all tables, records and ACLs.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.service_settings') IS NULL THEN RAISE EXCEPTION 'Apply migration 035 first'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.iv_service_documents(p_action text,p_data jsonb DEFAULT NULL,p_effective date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s ironvault_private.service_settings%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;k text;clean jsonb:='{}';rendered jsonb;effective date:=coalesce(p_effective,ironvault_private.subscription_today());published_version_id uuid;
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Super Admin required' USING ERRCODE='42501'; END IF;
 SELECT * INTO STRICT s FROM ironvault_private.service_settings settings_row WHERE settings_row.id=true FOR UPDATE;
 IF p_action NOT IN ('get','save','preview','publish') THEN RAISE EXCEPTION 'Invalid service document action'; END IF;
 IF p_action<>'get' THEN
  IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>150000 THEN RAISE EXCEPTION 'Invalid service details'; END IF;
  FOR k IN SELECT jsonb_object_keys(s.draft) LOOP
   clean:=clean||jsonb_build_object(k,coalesce(p_data->k,s.draft->k));
   IF length(clean->>k)>50000 THEN RAISE EXCEPTION 'Field too long: %',k; END IF;
  END LOOP;
  IF (clean->>'dashboard_price')::numeric<=0 OR (clean->>'portal_price')::numeric<(clean->>'dashboard_price')::numeric OR (clean->>'portal_price')::numeric>1000000 OR (clean->>'dashboard_price')::numeric<>round((clean->>'dashboard_price')::numeric,2) OR (clean->>'portal_price')::numeric<>round((clean->>'portal_price')::numeric,2) THEN RAISE EXCEPTION 'Invalid plan prices'; END IF;
  FOREACH k IN ARRAY ARRAY['pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days'] LOOP
   IF (clean->>k)::integer<1 OR (clean->>k)::integer>3650 OR (clean->>k)::numeric<>(clean->>k)::integer THEN RAISE EXCEPTION 'Invalid day setting: %',k; END IF;
  END LOOP;
  IF (clean->>'grace_days')::integer>30 OR (clean->>'price_notice_days')::integer<30 OR (clean->>'export_days')::integer>(clean->>'retention_days')::integer THEN RAISE EXCEPTION 'Grace must be at most 30 days, price notice at least 30 days, export no longer than retention'; END IF;
  IF p_action IN ('save','publish') THEN UPDATE ironvault_private.service_settings SET draft=clean,updated_at=clock_timestamp() WHERE service_settings.id=true; END IF;
  rendered:=ironvault_private.service_render(clean);
 END IF;
 IF p_action='publish' THEN
  FOR k IN SELECT jsonb_object_keys(clean) LOOP IF k<>'contract_extra' AND btrim(coalesce(clean->>k,''))='' THEN RAISE EXCEPTION 'Complete field before publication: %',k; END IF; END LOOP;
  FOREACH k IN ARRAY ARRAY['support_email','privacy_email'] LOOP IF clean->>k !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid contact email'; END IF; END LOOP;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions) AND effective<ironvault_private.subscription_today()+30 THEN RAISE EXCEPTION 'New service terms require 30 days advance notice'; END IF;
  IF effective<ironvault_private.subscription_today() THEN RAISE EXCEPTION 'Cannot backdate publication'; END IF;
  SELECT * INTO v FROM ironvault_private.service_versions version_row WHERE version_row.id=ironvault_private.service_current();
  IF v.id IS NOT NULL AND (v.data->>'dashboard_price' IS DISTINCT FROM clean->>'dashboard_price' OR v.data->>'portal_price' IS DISTINCT FROM clean->>'portal_price') AND effective<ironvault_private.subscription_today()+greatest(30,(v.data->>'price_notice_days')::integer) THEN RAISE EXCEPTION 'Price changes require the published advance notice period'; END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE effective_date>=effective) THEN RAISE EXCEPTION 'A publication already exists on or after this date; choose a later effective date'; END IF;
  INSERT INTO ironvault_private.service_versions(data,terms_text,privacy_text,dpa_text,effective_date,published_by) VALUES(clean,rendered->>'terms_text',rendered->>'privacy_text',rendered->>'dpa_text',effective,auth.uid()) RETURNING service_versions.id INTO published_version_id;
  PERFORM ironvault_private.subscription_notice(g.tenant_id,'documents:'||published_version_id,'Service documents published','Effective '||effective||'. Dashboard PHP '||coalesce(v.data->>'dashboard_price','not previously published')||' → '||(clean->>'dashboard_price')||'; Portal PHP '||coalesce(v.data->>'portal_price','not previously published')||' → '||(clean->>'portal_price')||'. Review documents and choose to continue, change plans or decline renewal. Approved paid periods are preserved.') FROM ironvault_private.gym_subscriptions g;
 END IF;
 RETURN jsonb_build_object('draft',CASE WHEN p_action='get' THEN s.draft ELSE clean END,'preview',rendered,'published_id',published_version_id,'versions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY effective_date DESC,published_at DESC) FROM ironvault_private.service_versions x),'[]'::jsonb));
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE t date:=ironvault_private.subscription_today();s ironvault_private.gym_subscriptions%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;req ironvault_private.subscription_requests%ROWTYPE;p ironvault_private.subscription_periods%ROWTYPE;quote jsonb;request_id_value uuid;reason text;days integer;result jsonb;super boolean:=ironvault_private.subscription_super();owner boolean;reference text;current_id uuid;
BEGIN
 SELECT * INTO STRICT s FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant FOR UPDATE;
 owner:=ironvault_private.subscription_owner(p_tenant);
 IF NOT super AND NOT owner THEN RAISE EXCEPTION 'Registered owner or Super Admin required' USING ERRCODE='42501'; END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>200000 THEN RAISE EXCEPTION 'Invalid subscription request'; END IF;
 current_id:=ironvault_private.service_current();
 SELECT * INTO v FROM ironvault_private.service_versions WHERE id=current_id;
 IF p_action='accept' THEN
  IF NOT owner THEN RAISE EXCEPTION 'Only the registered owner may accept'; END IF;
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish gym legal details before acceptance so the gym identity is recorded'; END IF;
  SELECT * INTO STRICT v FROM ironvault_private.service_versions WHERE id=(p_data->>'version_id')::uuid;
  IF p_data->>'accepted' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Explicit agreement is required'; END IF;
  INSERT INTO ironvault_private.service_acceptances(tenant_id,owner_id,version_id,gym_snapshot,owner_snapshot)
  SELECT p_tenant,auth.uid(),v.id,jsonb_build_object('id',g.id,'name',g.gym_name,'member_document_version',l.current_version,'legal_details',(SELECT jsonb_build_object('name',data->>'name','address',data->>'address','public_email',data->>'public_email') FROM ironvault_private.legal_versions WHERE legal_versions.id=l.current_version)),jsonb_build_object('id',auth.uid(),'name',g.owner_name,'email',a.contact_email)
  FROM public.owners g JOIN ironvault_private.branch_accounts a ON a.tenant_id=g.id AND a.user_id=auth.uid() AND a.role='owner' LEFT JOIN ironvault_private.legal_settings l ON l.scope=g.id WHERE g.id=p_tenant ON CONFLICT DO NOTHING;
 ELSIF p_action='quote' THEN RETURN ironvault_private.subscription_quote(p_tenant,p_data->>'kind',p_data->>'plan');
 ELSIF p_action='confirm_plan' THEN
  IF NOT owner OR p_data->>'confirmed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Registered owner must explicitly confirm the plan'; END IF;
  request_id_value:=(p_data->>'request_id')::uuid;SELECT * INTO req FROM ironvault_private.subscription_requests WHERE subscription_requests.id=request_id_value;
  IF FOUND THEN IF req.tenant_id<>p_tenant OR req.owner_id<>auth.uid() OR req.quote IS DISTINCT FROM p_data->'quote' THEN RAISE EXCEPTION 'Request ID already used with different details'; END IF;RETURN to_jsonb(req);END IF;
  quote:=ironvault_private.subscription_quote(p_tenant,p_data->'quote'->>'kind',p_data->'quote'->>'plan');
  IF quote IS DISTINCT FROM p_data->'quote' THEN RAISE EXCEPTION 'Quote changed; review exact amount and dates again'; END IF;
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND version_id=(quote->>'version_id')::uuid) THEN RAISE EXCEPTION 'Accept the quoted service documents first'; END IF;
  INSERT INTO ironvault_private.subscription_requests(id,tenant_id,owner_id,kind,quote) VALUES(request_id_value,p_tenant,auth.uid(),quote->>'kind',quote);
 ELSIF p_action IN ('activate_pilot','approve_payment','approve_downgrade','extend') THEN
  IF NOT super THEN RAISE EXCEPTION 'Super Admin required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RAISE EXCEPTION 'Gym is not active'; END IF;
  IF s.owner_id IS NULL THEN RAISE EXCEPTION 'Registered owner binding unavailable; review account ownership first'; END IF;
  IF p_action='activate_pilot' THEN
   IF EXISTS(SELECT 1 FROM ironvault_private.subscription_periods WHERE subscription_periods.id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant AND kind='pilot') THEN RETURN jsonb_build_object('approved',true,'request_id',p_data->>'request_id'); END IF;
   IF p_data->>'reviewed_business' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Review first-pilot business eligibility'; END IF;
   IF s.pilot_used OR EXISTS(SELECT 1 FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant) THEN RAISE EXCEPTION 'This gym has already used its pilot or subscription'; END IF;
   IF current_id IS NULL OR NOT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=s.owner_id AND version_id=current_id) THEN RAISE EXCEPTION 'Registered owner must accept current service documents first'; END IF;
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish gym and platform member documents first'; END IF;
   request_id_value:=(p_data->>'request_id')::uuid;
   INSERT INTO ironvault_private.subscription_periods(id,tenant_id,kind,plan,access_from,start_date,end_date,grace_days,version_id,policy,amount,approved_by) VALUES(request_id_value,p_tenant,'pilot','portal',t,t+1,t+(v.data->>'pilot_days')::integer,0,v.id,ironvault_private.service_parameters(v.data),0,auth.uid());
   UPDATE ironvault_private.gym_subscriptions SET pilot_used=true WHERE tenant_id=p_tenant;
   PERFORM ironvault_private.subscription_schedule(request_id_value);
   PERFORM ironvault_private.subscription_notice(p_tenant,request_id_value||':welcome','Welcome to your free pilot','Full access is available now. Counted pilot days begin tomorrow and end '||(t+(v.data->>'pilot_days')::integer)||'. No automatic charges.');
  ELSIF p_action='extend' THEN
   IF EXISTS(SELECT 1 FROM ironvault_private.subscription_events WHERE tenant_id=p_tenant AND action='extend' AND data->>'request_id'=p_data->>'request_id') THEN RETURN jsonb_build_object('approved',true); END IF;
   IF nullif(p_data->>'request_id','')::uuid IS NULL THEN RAISE EXCEPTION 'Request ID required'; END IF;
   reason:=btrim(p_data->>'reason');days:=(p_data->>'days')::integer;
   IF coalesce(length(reason),0)<5 OR days NOT BETWEEN 1 AND 365 THEN RAISE EXCEPTION 'Enter an extension of 1–365 days and a recorded reason'; END IF;
   SELECT * INTO STRICT p FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant ORDER BY end_date DESC LIMIT 1 FOR UPDATE;
   IF p.access_from>t OR p.end_date<t THEN RAISE EXCEPTION 'Only a current final period can be extended'; END IF;
   UPDATE ironvault_private.subscription_periods SET end_date=end_date+days WHERE subscription_periods.id=p.id;
   UPDATE ironvault_private.owner_notifications SET superseded_at=clock_timestamp() WHERE tenant_id=p_tenant AND notice_key LIKE p.id||':%' AND available_at>now();
   PERFORM ironvault_private.subscription_schedule(p.id);
   -- Existing notice keys are preserved; replace only future schedule dates on a documented extension.
   UPDATE ironvault_private.owner_notifications n SET available_at=(CASE WHEN notice_key LIKE '%:reminder:%' THEN p.end_date+days+1-split_part(notice_key,':',3)::integer WHEN notice_key LIKE '%:expiry' THEN p.end_date+days+1 WHEN notice_key LIKE '%:suspend' THEN p.end_date+days+p.grace_days+1 WHEN notice_key LIKE '%:lastgrace' THEN p.end_date+days+p.grace_days ELSE p.end_date+days+p.grace_days+coalesce((p.policy->>'retention_days')::integer,90)-7 END)::timestamp AT TIME ZONE 'Asia/Manila',superseded_at=NULL,message=replace(message,p.end_date::text,(p.end_date+days)::text) WHERE tenant_id=p_tenant AND notice_key LIKE p.id||':%' AND superseded_at IS NOT NULL;
   PERFORM ironvault_private.subscription_notice(p_tenant,'extension:'||(p_data->>'request_id'),'Subscription extension approved',days||' days added. Reason: '||reason);
  ELSE
   SELECT * INTO STRICT req FROM ironvault_private.subscription_requests WHERE subscription_requests.id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant FOR UPDATE;
   IF req.approved_at IS NOT NULL THEN RETURN jsonb_build_object('approved',true,'request_id',req.id); END IF;
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish gym and platform member documents before paid activation'; END IF;
   IF (p_action='approve_downgrade') IS DISTINCT FROM (req.kind='downgrade') THEN RAISE EXCEPTION 'Approval action does not match request'; END IF;
   quote:=ironvault_private.subscription_quote(p_tenant,req.kind,req.quote->>'plan');
   IF quote IS DISTINCT FROM req.quote THEN RAISE EXCEPTION 'Quote dates or amount changed. Owner must confirm a fresh request; no payment is recorded'; END IF;
   reference:=btrim(p_data->>'reference');IF req.kind<>'downgrade' AND coalesce(length(reference),0)<3 THEN RAISE EXCEPTION 'Record a payment reference or cash receipt'; END IF;
   SELECT * INTO p FROM ironvault_private.subscription_periods WHERE subscription_periods.id=(quote->>'prior_period')::uuid;
   IF req.kind='upgrade' THEN
    UPDATE ironvault_private.subscription_periods SET plan='portal',amount=amount+(quote->>'amount')::numeric WHERE subscription_periods.id=(quote->>'prior_period')::uuid;
   ELSIF req.kind='payment' THEN
    INSERT INTO ironvault_private.subscription_periods(id,tenant_id,kind,plan,access_from,start_date,end_date,grace_days,version_id,policy,amount,reference,approved_by) VALUES(req.id,p_tenant,'paid',quote->>'plan',(quote->>'access_from')::date,(quote->>'start_date')::date,(quote->>'end_date')::date,(quote->'policy'->>'grace_days')::integer,(quote->>'version_id')::uuid,quote->'policy',(quote->>'amount')::numeric,reference,auth.uid());
    UPDATE ironvault_private.owner_notifications SET superseded_at=clock_timestamp() WHERE tenant_id=p_tenant AND available_at>now() AND notice_key ~ ':(reminder:|expiry|suspend|lastgrace|retention)' AND notice_key NOT LIKE req.id||':%';
    PERFORM ironvault_private.subscription_schedule(req.id);
   END IF;
   UPDATE ironvault_private.gym_subscriptions SET next_plan=quote->>'plan' WHERE tenant_id=p_tenant;
   UPDATE ironvault_private.subscription_requests SET approved_at=clock_timestamp(),approved_by=auth.uid() WHERE subscription_requests.id=req.id;
   PERFORM ironvault_private.subscription_notice(p_tenant,req.id||':approved',CASE WHEN req.kind='downgrade' THEN 'Downgrade scheduled' ELSE 'Payment approved' END,req.quote->>'plan'||' plan. Starts '||(req.quote->>'start_date')||'; ends '||(req.quote->>'end_date')||'. PHP '||(req.quote->>'amount')||'. Reference: '||coalesce(reference,'Not applicable')||CASE WHEN req.kind='downgrade' THEN '. Renewal payment is still required; this does not create a free paid period.' ELSE '' END);
  END IF;
  INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),p_action,p_data||jsonb_build_object('date',t,'quote',quote,'previous_period',to_jsonb(p)));
 ELSIF p_action='read_notice' THEN
  IF NOT owner THEN RAISE EXCEPTION 'Registered owner required'; END IF;
  UPDATE ironvault_private.owner_notifications SET read_at=coalesce(read_at,clock_timestamp()) WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND notice_key=p_data->>'key' AND available_at<=now();
 ELSIF p_action<>'get' THEN RAISE EXCEPTION 'Invalid subscription action'; END IF;
 RETURN jsonb_build_object('tenant_id',p_tenant,'owner_id',s.owner_id,'is_owner',owner,'pilot_used',s.pilot_used,'next_plan',(SELECT next_plan FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant),'state',ironvault_private.subscription_state(p_tenant),'current_version',current_id,'gym_documents_ready',EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL),'platform_documents_ready',EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL),'accepted',EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=s.owner_id AND version_id=current_id),'documents',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY effective_date DESC) FROM ironvault_private.service_versions x),'[]'::jsonb),'acceptances',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY accepted_at DESC) FROM ironvault_private.service_acceptances a WHERE tenant_id=p_tenant),'[]'::jsonb),'periods',coalesce((SELECT jsonb_agg(to_jsonb(period_row) ORDER BY period_row.start_date DESC) FROM ironvault_private.subscription_periods period_row WHERE tenant_id=p_tenant),'[]'::jsonb),'requests',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY confirmed_at DESC) FROM ironvault_private.subscription_requests r WHERE tenant_id=p_tenant),'[]'::jsonb),'events',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY created_at DESC) FROM ironvault_private.subscription_events e WHERE tenant_id=p_tenant),'[]'::jsonb),'notifications',CASE WHEN owner THEN coalesce((SELECT jsonb_agg(to_jsonb(n) ORDER BY available_at DESC) FROM ironvault_private.owner_notifications n WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND available_at<=now() AND superseded_at IS NULL),'[]'::jsonb) ELSE '[]'::jsonb END);
END $fn$;
NOTIFY pgrst,'reload schema';
COMMIT;
