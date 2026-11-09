-- MANUAL ONLY after 050 and all earlier migrations. No financial/attendance rows are changed.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_subscription_manage(text,text,jsonb)') IS NULL OR to_regprocedure('ironvault_private.subscription_portal_040_base(text,text,jsonb)') IS NULL OR to_regprocedure('public.iv_set_gym_preset(text,text)') IS NULL THEN RAISE EXCEPTION 'Apply migrations through 050 first';END IF;
 IF to_regclass('ironvault_private.service_drafts_051') IS NOT NULL THEN RAISE EXCEPTION '051 already installed; do not reapply';END IF;
END $guard$;
CREATE TABLE ironvault_private.service_publications_051(version_id uuid PRIMARY KEY REFERENCES ironvault_private.service_versions(id),publication_order bigint GENERATED ALWAYS AS IDENTITY UNIQUE,published_on date NOT NULL);
INSERT INTO ironvault_private.service_publications_051(version_id,published_on) SELECT id,(published_at AT TIME ZONE 'Asia/Manila')::date FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text' ORDER BY published_at,effective_date,id;
CREATE TABLE ironvault_private.service_drafts_051(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text NOT NULL,version_label text NOT NULL,terms_text text NOT NULL DEFAULT '',privacy_text text NOT NULL DEFAULT '',dpa_text text NOT NULL DEFAULT '',revision bigint NOT NULL DEFAULT 1,updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_by uuid NOT NULL,published_id uuid REFERENCES ironvault_private.service_versions(id),save_request uuid,save_hash text,delete_request uuid,deleted_at timestamptz,legacy_data jsonb);
CREATE TABLE ironvault_private.service_baselines_051(tenant_id text PRIMARY KEY REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,version_id uuid REFERENCES ironvault_private.service_versions(id),assigned_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE ironvault_private.service_transitions_051(tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,version_id uuid NOT NULL REFERENCES ironvault_private.service_versions(id),published_on date NOT NULL,deadline date NOT NULL CHECK(deadline=published_on+30),PRIMARY KEY(tenant_id,version_id));
CREATE TABLE ironvault_private.subscription_settings_control_051(id boolean PRIMARY KEY DEFAULT true CHECK(id),revision bigint NOT NULL DEFAULT 1);
INSERT INTO ironvault_private.subscription_settings_control_051 DEFAULT VALUES;
CREATE TABLE ironvault_private.subscription_settings_051(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),setting_order bigint GENERATED ALWAYS AS IDENTITY,values jsonb NOT NULL,effective_date date NOT NULL,published_at timestamptz NOT NULL DEFAULT clock_timestamp(),published_by uuid NOT NULL,request_id uuid UNIQUE,request_hash text);
-- Preserve the current and previously scheduled configuration, without changing any document.
INSERT INTO ironvault_private.subscription_settings_051(values,effective_date,published_at,published_by) SELECT ironvault_private.service_parameters(data),effective_date,published_at,published_by FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text' ORDER BY effective_date,published_at,id;
INSERT INTO ironvault_private.service_baselines_051(tenant_id,version_id) SELECT s.tenant_id,coalesce((SELECT a.version_id FROM ironvault_private.service_acceptances a JOIN ironvault_private.service_publications_051 p ON p.version_id=a.version_id WHERE a.tenant_id=s.tenant_id AND a.owner_id=s.owner_id AND ironvault_private.owner_agreement_valid(a.tenant_id,a.owner_id,a.version_id) ORDER BY p.publication_order DESC LIMIT 1),ironvault_private.service_current()) FROM ironvault_private.gym_subscriptions s;
CREATE FUNCTION ironvault_private.service_admin_051() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 PERFORM 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND role='super_admin' AND tenant_id IS NULL AND enabled AND disabled_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Enabled Provider required' USING ERRCODE='42501';END IF;
END $fn$;
CREATE FUNCTION ironvault_private.subscription_settings_on_051(p_day date) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT coalesce((SELECT values FROM ironvault_private.subscription_settings_051 WHERE effective_date<=p_day ORDER BY effective_date DESC,setting_order DESC LIMIT 1),(SELECT ironvault_private.service_parameters(draft) FROM ironvault_private.service_settings WHERE id=true));
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.service_current() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT p.version_id FROM ironvault_private.service_publications_051 p JOIN ironvault_private.service_versions v ON v.id=p.version_id WHERE NOT v.retired AND v.document_format='text' ORDER BY p.publication_order DESC LIMIT 1;
$fn$;
CREATE FUNCTION ironvault_private.service_initial_accepted_051(p_tenant text,p_owner uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances a WHERE a.tenant_id=p_tenant AND a.owner_id=p_owner AND ironvault_private.owner_agreement_valid(p_tenant,p_owner,a.version_id));
$fn$;
CREATE FUNCTION ironvault_private.service_current(p_tenant text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT p.version_id FROM ironvault_private.service_publications_051 p JOIN ironvault_private.service_versions v ON v.id=p.version_id JOIN ironvault_private.service_baselines_051 b ON b.tenant_id=p_tenant JOIN ironvault_private.service_publications_051 bp ON bp.version_id=b.version_id JOIN ironvault_private.gym_subscriptions s ON s.tenant_id=b.tenant_id
 WHERE NOT v.retired AND p.publication_order>=bp.publication_order AND (p.version_id=b.version_id OR ironvault_private.owner_agreement_valid(p_tenant,s.owner_id,p.version_id) OR EXISTS(SELECT 1 FROM ironvault_private.service_transitions_051 t WHERE t.tenant_id=p_tenant AND t.version_id=p.version_id AND t.deadline<=ironvault_private.subscription_today() AND ironvault_private.service_initial_accepted_051(p_tenant,s.owner_id))) ORDER BY p.publication_order DESC LIMIT 1;
$fn$;
CREATE FUNCTION ironvault_private.service_satisfied_051(p_tenant text,p_owner uuid,p_version uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.owner_agreement_valid(p_tenant,p_owner,p_version) OR (EXISTS(SELECT 1 FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant AND owner_id=p_owner) AND ironvault_private.service_initial_accepted_051(p_tenant,p_owner) AND EXISTS(SELECT 1 FROM ironvault_private.service_transitions_051 WHERE tenant_id=p_tenant AND version_id=p_version AND deadline<=ironvault_private.subscription_today()));
$fn$;
CREATE FUNCTION ironvault_private.service_register_051() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 PERFORM 1 FROM ironvault_private.service_settings WHERE id=true FOR SHARE;
 INSERT INTO ironvault_private.service_baselines_051(tenant_id,version_id) VALUES(NEW.tenant_id,ironvault_private.service_current()) ON CONFLICT DO NOTHING;
 RETURN NEW;
END $fn$;
CREATE TRIGGER iv_service_register_051 AFTER INSERT ON ironvault_private.gym_subscriptions FOR EACH ROW EXECUTE FUNCTION ironvault_private.service_register_051();
-- Copy the saved legacy draft, including raw source, without publishing or rewriting it.
DO $import$ DECLARE s record;r jsonb;BEGIN
 SELECT * INTO s FROM ironvault_private.service_settings WHERE id=true;
 BEGIN r:=ironvault_private.service_render(s.draft);EXCEPTION WHEN OTHERS THEN SELECT jsonb_build_object('terms_text',terms_text,'privacy_text',privacy_text,'dpa_text',dpa_text) INTO r FROM ironvault_private.service_versions WHERE id=ironvault_private.service_current();END;
 IF s.id IS TRUE THEN INSERT INTO ironvault_private.service_drafts_051(name,version_label,terms_text,privacy_text,dpa_text,updated_by,legacy_data) VALUES('Imported saved draft',coalesce(nullif(s.draft->>'document_version',''),'1.0'),coalesce(r->>'terms_text',''),coalesce(r->>'privacy_text',''),coalesce(r->>'dpa_text',''),coalesce((SELECT published_by FROM ironvault_private.service_versions WHERE id=ironvault_private.service_current()),'00000000-0000-0000-0000-000000000000'::uuid),s.draft);END IF;
END $import$;
CREATE FUNCTION ironvault_private.service_notice_rows_051(p_tenant text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT coalesce(jsonb_agg(to_jsonb(n)||CASE WHEN t.version_id IS NOT NULL THEN jsonb_build_object('kind','status','pinned',NOT done.value,'resolved_at',CASE WHEN done.value THEN coalesce(n.resolved_at,(SELECT min(a.accepted_at) FROM ironvault_private.service_acceptances a JOIN ironvault_private.service_publications_051 ap ON ap.version_id=a.version_id WHERE a.tenant_id=p_tenant AND a.owner_id=s.owner_id AND ap.publication_order>=tp.publication_order AND ironvault_private.owner_agreement_valid(p_tenant,s.owner_id,a.version_id)),(t.deadline::timestamp AT TIME ZONE 'Asia/Manila')) ELSE n.resolved_at END,'transition_deadline',t.deadline,'version_id',t.version_id,'application',CASE WHEN ironvault_private.owner_agreement_valid(p_tenant,s.owner_id,t.version_id) THEN 'accepted' WHEN done.value THEN 'effective_after_notice' ELSE 'pending' END) ELSE '{}'::jsonb END ORDER BY n.available_at DESC,n.notice_key),'[]')
 FROM ironvault_private.owner_notifications n JOIN ironvault_private.gym_subscriptions s ON s.tenant_id=n.tenant_id LEFT JOIN ironvault_private.service_transitions_051 t ON t.tenant_id=n.tenant_id AND n.notice_key='agreement51:'||t.version_id
 LEFT JOIN ironvault_private.service_publications_051 tp ON tp.version_id=t.version_id LEFT JOIN ironvault_private.service_publications_051 cp ON cp.version_id=ironvault_private.service_current(p_tenant)
 CROSS JOIN LATERAL (SELECT coalesce(cp.publication_order>=tp.publication_order,false) AS value) done
 WHERE n.tenant_id=p_tenant AND n.owner_id=auth.uid() AND n.available_at<=clock_timestamp() AND n.superseded_at IS NULL;
$fn$;
CREATE FUNCTION public.iv_service_drafts(p_action text DEFAULT 'list',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE d ironvault_private.service_drafts_051%ROWTYPE;v uuid;rid uuid:=nullif(p_data->>'request_id','')::uuid;payload jsonb;hash text;source jsonb;today date:=ironvault_private.subscription_today();item record;
BEGIN
 PERFORM ironvault_private.service_admin_051();
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>200000 THEN RAISE EXCEPTION 'Invalid document input';END IF;
 IF p_action='list' THEN RETURN jsonb_build_object('workflow_version',51,'today',today,'drafts',coalesce((SELECT jsonb_agg(to_jsonb(x)-'legacy_data' ORDER BY x.updated_at DESC) FROM ironvault_private.service_drafts_051 x WHERE x.deleted_at IS NULL AND x.published_id IS NULL),'[]'),'versions',coalesce((SELECT jsonb_agg(to_jsonb(sv)||jsonb_build_object('published_on',p.published_on) ORDER BY p.publication_order DESC) FROM ironvault_private.service_versions sv JOIN ironvault_private.service_publications_051 p ON p.version_id=sv.id WHERE NOT sv.retired),'[]'));END IF;
 IF p_action NOT IN ('save','preview','publish','delete') THEN RAISE EXCEPTION 'Invalid document action';END IF;
 v:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());PERFORM pg_advisory_xact_lock(hashtextextended('service-draft:'||v::text,51));
 SELECT * INTO d FROM ironvault_private.service_drafts_051 WHERE id=v FOR UPDATE;
 IF p_action='delete' THEN
  IF d.id IS NULL OR d.published_id IS NOT NULL OR p_data->>'confirmed' IS DISTINCT FROM 'true' OR rid IS NULL THEN RAISE EXCEPTION 'Only a confirmed unpublished draft can be deleted';END IF;
  IF d.deleted_at IS NOT NULL AND d.delete_request=rid THEN RETURN jsonb_build_object('deleted',true,'id',d.id);END IF;
  IF d.deleted_at IS NOT NULL OR d.revision IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Draft changed; reload before deleting';END IF;
  UPDATE ironvault_private.service_drafts_051 SET deleted_at=clock_timestamp(),delete_request=rid,revision=revision+1 WHERE id=v;
  RETURN jsonb_build_object('deleted',true,'id',v);
 END IF;
 IF d.deleted_at IS NOT NULL OR d.published_id IS NOT NULL AND p_action<>'publish' THEN RAISE EXCEPTION 'This draft cannot be edited';END IF;
 IF p_action='save' THEN
  payload:=jsonb_build_object('name',btrim(coalesce(p_data->>'name','')),'version_label',btrim(coalesce(p_data->>'version_label','')),'terms_text',coalesce(p_data->>'terms_text',''),'privacy_text',coalesce(p_data->>'privacy_text',''),'dpa_text',coalesce(p_data->>'dpa_text',''));hash:=md5(payload::text);
  IF length(payload->>'name') NOT BETWEEN 1 AND 160 OR length(payload->>'version_label') NOT BETWEEN 1 AND 80 OR length(payload->>'terms_text')>50000 OR length(payload->>'privacy_text')>50000 OR length(payload->>'dpa_text')>50000 OR rid IS NULL THEN RAISE EXCEPTION 'Enter a draft name/version and documents up to 50000 characters each';END IF;
  IF d.save_request=rid THEN IF d.save_hash<>hash THEN RAISE EXCEPTION 'Draft retry changed';END IF;RETURN jsonb_build_object('draft',to_jsonb(d)-'legacy_data','replayed',true);END IF;
  IF (d.id IS NULL AND coalesce((p_data->>'revision')::bigint,0)<>0) OR (d.id IS NOT NULL AND d.revision IS DISTINCT FROM (p_data->>'revision')::bigint) THEN RAISE EXCEPTION 'Draft changed in another session; reopen it';END IF;
  INSERT INTO ironvault_private.service_drafts_051(id,name,version_label,terms_text,privacy_text,dpa_text,updated_by,save_request,save_hash) VALUES(v,payload->>'name',payload->>'version_label',payload->>'terms_text',payload->>'privacy_text',payload->>'dpa_text',auth.uid(),rid,hash)
  ON CONFLICT(id) DO UPDATE SET name=excluded.name,version_label=excluded.version_label,terms_text=excluded.terms_text,privacy_text=excluded.privacy_text,dpa_text=excluded.dpa_text,updated_by=auth.uid(),updated_at=clock_timestamp(),revision=service_drafts_051.revision+1,save_request=rid,save_hash=hash RETURNING * INTO d;
  RETURN jsonb_build_object('draft',to_jsonb(d)-'legacy_data');
 END IF;
 IF d.id IS NULL OR d.revision IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Save/reopen the draft before previewing or publishing';END IF;
 hash:=md5(jsonb_build_object('id',d.id,'revision',d.revision,'name',d.name,'version',d.version_label,'terms',d.terms_text,'privacy',d.privacy_text,'dpa',d.dpa_text,'published_on',today)::text);
 IF p_action='preview' THEN RETURN jsonb_build_object('review_hash',hash,'published_on',today,'transition_deadline',today+30,'draft',to_jsonb(d)-'legacy_data');END IF;
 IF rid IS NULL OR p_data->>'reviewed' IS DISTINCT FROM 'true' OR p_data->>'review_hash' IS DISTINCT FROM hash THEN RAISE EXCEPTION 'Preview and confirm the exact saved draft';END IF;
 IF d.published_id IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE id=d.published_id AND publication_request=rid) THEN RETURN jsonb_build_object('published_id',d.published_id,'replayed',true);END IF;RAISE EXCEPTION 'Draft already published';
 END IF;
 IF btrim(d.terms_text)='' OR btrim(d.privacy_text)='' OR btrim(d.dpa_text)='' OR d.terms_text LIKE '%{{%' OR d.privacy_text LIKE '%{{%' OR d.dpa_text LIKE '%{{%' THEN RAISE EXCEPTION 'Paste all three complete documents without template placeholders';END IF;
 IF d.terms_text !~* E'(^|[\r\n])[[:space:]#]*([0-9]+[.)][[:space:]]*)?FREE[[:space:]]+PILOT' THEN RAISE EXCEPTION 'Include an identifiable Free Pilot Conditions section in Terms of Use';END IF;
 PERFORM 1 FROM ironvault_private.service_settings WHERE id=true FOR UPDATE;
 IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text' AND lower(version_label)=lower(d.version_label)) THEN RAISE EXCEPTION 'Use a new document version label';END IF;
 SELECT coalesce(sv.data,'{}') INTO source FROM ironvault_private.service_versions sv WHERE id=ironvault_private.service_current();
 SELECT coalesce(source,'{}')||coalesce(lv.data,'{}') INTO source FROM (SELECT 1) dummy LEFT JOIN ironvault_private.legal_settings ls ON ls.scope='platform' LEFT JOIN ironvault_private.legal_versions lv ON lv.id=ls.current_version;
 source:=coalesce(source,'{}')||ironvault_private.subscription_settings_on_051(today)||jsonb_build_object('document_version',d.version_label,'provider_name',coalesce(source->>'name',source->>'provider_name'),'support_email',coalesce(source->>'public_email',source->>'support_email'),'plain_documents',true);
 INSERT INTO ironvault_private.service_versions(data,terms_text,privacy_text,dpa_text,effective_date,published_by,version_label,publication_request,source_draft) VALUES(source,d.terms_text,d.privacy_text,d.dpa_text,today,auth.uid(),d.version_label,rid,d.id) RETURNING id INTO v;
 INSERT INTO ironvault_private.service_publications_051(version_id,published_on) VALUES(v,today);
 -- A previously unconfigured gym with no baseline receives its first agreement, not a waiver.
 UPDATE ironvault_private.service_baselines_051 SET version_id=v WHERE version_id IS NULL;
 INSERT INTO ironvault_private.service_transitions_051(tenant_id,version_id,published_on,deadline) SELECT tenant_id,v,today,today+30 FROM ironvault_private.service_baselines_051 WHERE version_id<>v;
 FOR item IN SELECT tenant_id FROM ironvault_private.service_transitions_051 WHERE version_id=v LOOP
  PERFORM ironvault_private.subscription_notice(item.tenant_id,'agreement51:'||v,'New Service Agreement published','Version '||d.version_label||' is available now. Accept to apply it early, or it becomes applicable after the notice period on '||(today+30)||'. Reading this message is not acceptance. Existing approved plan amounts and dates are preserved.');
 END LOOP;
 UPDATE ironvault_private.service_drafts_051 SET published_id=v,updated_at=clock_timestamp() WHERE id=d.id;
 RETURN jsonb_build_object('published_id',v,'published_on',today,'transition_deadline',today+30);
END $fn$;
CREATE FUNCTION public.iv_subscription_settings(p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE rev bigint;values jsonb:='{}';previous jsonb;effective date;today date:=ironvault_private.subscription_today();notice integer;key text;amount numeric;payload jsonb;hash text;review text;rid uuid;existing ironvault_private.subscription_settings_051%ROWTYPE;new_id uuid;g record;
BEGIN
 PERFORM ironvault_private.service_admin_051();
 IF p_action NOT IN ('get','preview','save') OR p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>20000 THEN RAISE EXCEPTION 'Invalid settings request';END IF;
 SELECT revision INTO STRICT rev FROM ironvault_private.subscription_settings_control_051 WHERE id=true FOR UPDATE;
 SELECT greatest(30,coalesce(max((policy->>'price_notice_days')::integer),30)) INTO notice FROM ironvault_private.subscription_periods;
 SELECT greatest(notice,coalesce(max((s.values->>'price_notice_days')::integer),30)) INTO notice FROM ironvault_private.subscription_settings_051 s;
 IF p_action='get' THEN RETURN jsonb_build_object('revision',rev,'settings',ironvault_private.subscription_settings_on_051(today),'today',today,'minimum_price_effective_date',today+notice,'scheduled',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY effective_date,published_at) FROM ironvault_private.subscription_settings_051 s WHERE effective_date>today),'[]'));END IF;
 IF jsonb_typeof(p_data->'values') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Enter settings';END IF;
 FOR key IN SELECT jsonb_object_keys(p_data->'values') LOOP IF key<>ALL(ARRAY['dashboard_price','portal_price','pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days']) THEN RAISE EXCEPTION 'Unknown operational setting';END IF;END LOOP;
 FOREACH key IN ARRAY ARRAY['dashboard_price','portal_price','pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days'] LOOP
  IF coalesce(p_data->'values'->>key,'') !~ '^\d+(\.\d{1,2})?$' THEN RAISE EXCEPTION 'Enter a valid value for %',key;END IF;
  amount:=(p_data->'values'->>key)::numeric;
  IF key IN ('dashboard_price','portal_price') THEN
   IF amount<=0 OR amount>1000000 THEN RAISE EXCEPTION 'Plan prices must be positive and at most PHP 1000000';END IF;
  ELSIF amount<>trunc(amount) OR amount<(CASE WHEN key='grace_days' THEN 0 ELSE 1 END) OR amount>3650 THEN RAISE EXCEPTION 'Invalid day setting: %',key;END IF;
  values:=values||jsonb_build_object(key,amount);
 END LOOP;
 IF (values->>'portal_price')::numeric<(values->>'dashboard_price')::numeric OR (values->>'paid_days')::integer<>30 OR (values->>'grace_days')::integer>30 OR (values->>'price_notice_days')::integer<30 OR (values->>'export_days')::integer>(values->>'retention_days')::integer THEN RAISE EXCEPTION 'Keep 30-day paid months, Portal price at least Dashboard, grace up to 30, notice at least 30 and export within retention';END IF;
 effective:=(p_data->>'effective_date')::date;IF effective IS NULL OR effective<today THEN RAISE EXCEPTION 'Choose today or a future effective date';END IF;
 payload:=jsonb_build_object('values',values,'effective_date',effective);hash:=md5(payload::text);rid:=nullif(p_data->>'request_id','')::uuid;
 IF p_action='save' AND rid IS NOT NULL THEN SELECT * INTO existing FROM ironvault_private.subscription_settings_051 WHERE request_id=rid;IF FOUND THEN IF existing.request_hash<>hash THEN RAISE EXCEPTION 'Settings retry changed';END IF;RETURN jsonb_build_object('saved',true,'id',existing.id,'replayed',true);END IF;END IF;
 IF rev IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Settings changed in another session; reload';END IF;
 previous:=ironvault_private.subscription_settings_on_051(effective);
 IF (previous->>'dashboard_price')::numeric IS DISTINCT FROM (values->>'dashboard_price')::numeric OR (previous->>'portal_price')::numeric IS DISTINCT FROM (values->>'portal_price')::numeric THEN IF effective<today+greatest(notice,(values->>'price_notice_days')::integer) THEN RAISE EXCEPTION 'Price changes require advance notice; earliest date is %',today+greatest(notice,(values->>'price_notice_days')::integer);END IF;END IF;
 review:=md5(jsonb_build_object('payload',payload,'revision',rev,'today',today)::text);
 IF p_action='preview' THEN RETURN payload||jsonb_build_object('revision',rev,'review_hash',review,'previous',previous);END IF;
 IF rid IS NULL OR p_data->>'reviewed' IS DISTINCT FROM 'true' OR p_data->>'review_hash' IS DISTINCT FROM review THEN RAISE EXCEPTION 'Preview and review these exact settings first';END IF;
 INSERT INTO ironvault_private.subscription_settings_051(values,effective_date,published_by,request_id,request_hash) VALUES(values,effective,auth.uid(),rid,hash) RETURNING id INTO new_id;
 UPDATE ironvault_private.subscription_settings_control_051 SET revision=revision+1 WHERE id=true;
 FOR g IN SELECT tenant_id FROM ironvault_private.gym_subscriptions LOOP PERFORM ironvault_private.subscription_notice(g.tenant_id,'settings51:'||new_id,'Subscription settings updated','Effective '||effective||'. Dashboard PHP '||(values->>'dashboard_price')||'; Dashboard + Member Portal PHP '||(values->>'portal_price')||'. This does not publish new terms or change existing approved amounts/dates.');END LOOP;
 RETURN jsonb_build_object('saved',true,'id',new_id,'effective_date',effective,'revision',rev+1);
END $fn$;
-- Keep the tested transaction engines; make narrowly guarded selector substitutions.
CREATE FUNCTION ironvault_private.service_patch_051(sig regprocedure,old_text text,new_text text) RETURNS void LANGUAGE plpgsql SET search_path='' AS $fn$
DECLARE source text;BEGIN SELECT pg_get_functiondef(sig) INTO source;IF position(old_text IN source)=0 THEN RAISE EXCEPTION 'Unexpected function definition for %; no migration applied',sig;END IF;EXECUTE replace(source,old_text,new_text);END $fn$;
DO $patch$ DECLARE sig text;source text;BEGIN
 FOREACH sig IN ARRAY ARRAY['ironvault_private.subscription_portal_038_base(text,text,jsonb)','ironvault_private.subscription_portal_040_base(text,text,jsonb)','ironvault_private.subscription_portal_043_base(text,text,jsonb)'] LOOP
  PERFORM ironvault_private.service_patch_051(sig::regprocedure,'ironvault_private.service_current()','ironvault_private.service_current(p_tenant)');
 END LOOP;
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_portal_038_base(text,text,jsonb)'::regprocedure,'SELECT * INTO v FROM ironvault_private.service_versions WHERE id=current_id;','SELECT * INTO v FROM ironvault_private.service_versions WHERE id=current_id; v.data:=v.data||ironvault_private.subscription_settings_on_051(t);');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_portal_038_base(text,text,jsonb)'::regprocedure,'NOT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=s.owner_id AND version_id=current_id)','NOT ironvault_private.service_satisfied_051(p_tenant,s.owner_id,current_id)');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_portal_043_base(text,text,jsonb)'::regprocedure,'ironvault_private.owner_agreement_valid(p_tenant,subscription.owner_id,ironvault_private.service_current(p_tenant))','ironvault_private.service_satisfied_051(p_tenant,subscription.owner_id,ironvault_private.service_current(p_tenant))');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_quote(text,text,text)'::regprocedure,'ironvault_private.service_current()','ironvault_private.service_current(p_tenant)');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_quote(text,text,text)'::regprocedure,'WHERE NOT retired AND document_format=''text'' AND effective_date<=startday ORDER BY effective_date DESC,published_at DESC LIMIT 1','WHERE id=ironvault_private.service_current(p_tenant)');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_quote(text,text,text)'::regprocedure,'policy:=ironvault_private.service_parameters(v.data)','policy:=ironvault_private.subscription_settings_on_051(startday)');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_quote_048(text,jsonb)'::regprocedure,'WHERE NOT retired AND effective_date<=startday ORDER BY effective_date DESC,published_at DESC LIMIT 1','WHERE id=ironvault_private.service_current(p_tenant)');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_quote_048(text,jsonb)'::regprocedure,'policy:=ironvault_private.service_parameters(v.data)','policy:=ironvault_private.subscription_settings_on_051(startday)');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_quote_048(text,jsonb)'::regprocedure,'ironvault_private.owner_agreement_valid(','ironvault_private.service_satisfied_051(');
 PERFORM ironvault_private.service_patch_051('ironvault_private.subscription_fingerprint_048(text)'::regprocedure,'''day'',','''settings_revision'',(SELECT revision FROM ironvault_private.subscription_settings_control_051 WHERE id=true),''agreement'',ironvault_private.service_current(p_tenant),''day'',');
 PERFORM ironvault_private.service_patch_051('public.iv_subscription_manage(text,text,jsonb)'::regprocedure,'''prices'',(SELECT jsonb_build_object(''dashboard'',v.data->''dashboard_price'',''portal'',v.data->''portal_price'') FROM ironvault_private.service_versions v WHERE v.id=ironvault_private.service_current())','''prices'',jsonb_build_object(''dashboard'',ironvault_private.subscription_settings_on_051(ironvault_private.subscription_today())->''dashboard_price'',''portal'',ironvault_private.subscription_settings_on_051(ironvault_private.subscription_today())->''portal_price'')');
END $patch$;
DROP FUNCTION ironvault_private.service_patch_051(regprocedure,text,text);
-- The legacy publisher cannot be used to bypass independent drafts/settings.
ALTER FUNCTION public.iv_service_documents(text,jsonb,date) RENAME TO service_documents_051_base;
ALTER FUNCTION public.service_documents_051_base(text,jsonb,date) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_service_documents(p_action text,p_data jsonb DEFAULT NULL,p_effective date DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN PERFORM ironvault_private.service_admin_051();IF p_action<>'get' THEN RAISE EXCEPTION 'Reload Service Agreement Settings: use the draft library and separate Subscription settings';END IF;RETURN ironvault_private.service_documents_051_base(p_action,p_data,p_effective)||jsonb_build_object('workflow_version',51);END $fn$;
ALTER FUNCTION public.iv_subscription_portal(text,text,jsonb) RENAME TO subscription_portal_051_base;
ALTER FUNCTION public.subscription_portal_051_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE output jsonb;notices jsonb;cur uuid;latest uuid;own boolean;owner_id_value uuid;documents jsonb;BEGIN
 IF p_action='accept' AND NOT ironvault_private.subscription_owner(p_tenant) THEN RAISE EXCEPTION 'Registered owner required' USING ERRCODE='42501';END IF;
 IF p_action='accept' AND EXISTS(SELECT 1 FROM ironvault_private.service_publications_051 target,ironvault_private.service_publications_051 active WHERE target.version_id=(p_data->>'version_id')::uuid AND active.version_id=ironvault_private.service_current(p_tenant) AND target.publication_order<active.publication_order) THEN RAISE EXCEPTION 'A newer agreement already applies; reopen the latest documents';END IF;
 output:=ironvault_private.subscription_portal_051_base(p_tenant,p_action,p_data);
 cur:=ironvault_private.service_current(p_tenant);latest:=ironvault_private.service_current();own:=ironvault_private.subscription_owner(p_tenant);SELECT owner_id INTO owner_id_value FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant;
 IF p_action IN ('get','badge','notifications') THEN
  output:=output||jsonb_build_object('agreement_workflow',51,'current_version',cur,'latest_version',latest,'initial_agreement_accepted',ironvault_private.service_initial_accepted_051(p_tenant,owner_id_value),'agreement_satisfied',ironvault_private.service_satisfied_051(p_tenant,owner_id_value,cur),'application_mode',CASE WHEN ironvault_private.owner_agreement_valid(p_tenant,owner_id_value,cur) THEN 'accepted' WHEN ironvault_private.service_satisfied_051(p_tenant,owner_id_value,cur) THEN 'effective_after_notice' ELSE 'awaiting_acceptance' END,'transitions',coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('version_label',v.version_label,'accepted',ironvault_private.owner_agreement_valid(p_tenant,owner_id_value,t.version_id)) ORDER BY p.publication_order DESC) FROM ironvault_private.service_transitions_051 t JOIN ironvault_private.service_versions v ON v.id=t.version_id JOIN ironvault_private.service_publications_051 p ON p.version_id=v.id WHERE t.tenant_id=p_tenant),'[]'));
  IF own THEN notices:=ironvault_private.service_notice_rows_051(p_tenant);output:=output||jsonb_build_object('unread_count',(SELECT count(*) FROM jsonb_array_elements(notices) n WHERE n->>'read_at' IS NULL AND n->>'resolved_at' IS NULL AND n->>'superseded_at' IS NULL));IF p_action<>'badge' THEN output:=output||jsonb_build_object('notifications',notices);END IF;END IF;
  IF p_action='get' THEN SELECT coalesce(jsonb_agg(doc.value ORDER BY p.publication_order DESC),'[]') INTO documents FROM jsonb_array_elements(output->'documents') doc JOIN ironvault_private.service_publications_051 p ON p.version_id=(doc.value->>'id')::uuid;output:=output||jsonb_build_object('documents',documents);END IF;
 END IF;
 RETURN output;
END $fn$;
ALTER FUNCTION public.iv_provider_console(text,jsonb) RENAME TO provider_console_051_base;
ALTER FUNCTION public.provider_console_051_base(text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_provider_console(p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE output jsonb;notices jsonb;BEGIN
 output:=ironvault_private.provider_console_051_base(p_action,p_data);
 IF output ? 'notices' THEN
  SELECT coalesce(jsonb_agg(n.value||jsonb_build_object('pinned',coalesce(r.status IN ('pending','returned'),false),'kind',CASE WHEN r.status IN ('pending','returned') THEN 'status' ELSE 'notice' END) ORDER BY n.value->>'available_at' DESC),'[]') INTO notices FROM jsonb_array_elements(output->'notices') n LEFT JOIN ironvault_private.subscription_intents r ON n.value->>'notice_key' IN ('subscription48:'||r.id,'request:'||r.id,'reference:'||r.id);
  output:=output||jsonb_build_object('notices',notices);
 END IF;RETURN output;
END $fn$;
DO $acl$ DECLARE t text;f regprocedure;BEGIN
 FOREACH t IN ARRAY ARRAY['service_publications_051','service_drafts_051','service_baselines_051','service_transitions_051','subscription_settings_control_051','subscription_settings_051'] LOOP EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',t);END LOOP;
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='ironvault_private' AND (p.proname LIKE '%\_051' ESCAPE '\' OR p.proname IN ('service_current','service_documents_051_base','subscription_portal_051_base','provider_console_051_base'))) OR (n.nspname='public' AND p.proname IN ('iv_service_drafts','iv_subscription_settings','iv_service_documents','iv_subscription_portal','iv_provider_console')) LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f);END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_service_drafts(text,jsonb),public.iv_subscription_settings(text,jsonb),public.iv_service_documents(text,jsonb,date),public.iv_subscription_portal(text,text,jsonb),public.iv_provider_console(text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
