-- MANUAL ONLY after 036. Add private PDF publishing; preserve legacy documents/receipts/periods.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.service_versions') IS NULL THEN RAISE EXCEPTION 'Apply 035 and 036 first'; END IF;
 IF position('request_id_value' IN pg_get_functiondef('public.iv_subscription_portal(text,text,jsonb)'::regprocedure))=0 THEN RAISE EXCEPTION 'Apply migration 036 before 037'; END IF;
 IF to_regclass('ironvault_private.service_pdf_files') IS NOT NULL OR EXISTS(SELECT 1 FROM storage.buckets WHERE id='iv-service-documents') THEN RAISE EXCEPTION 'PDF installation/bucket already exists; review rather than reapply'; END IF;
END $guard$;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('iv-service-documents','iv-service-documents',false,5242880,ARRAY['application/pdf']);
CREATE TABLE ironvault_private.service_pdf_files(id uuid PRIMARY KEY,object_path text NOT NULL UNIQUE,display_name text NOT NULL,sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),size_bytes integer NOT NULL CHECK(size_bytes BETWEEN 1 AND 5242880),pages integer NOT NULL CHECK(pages BETWEEN 1 AND 100),uploaded_by uuid NOT NULL,uploaded_at timestamptz NOT NULL DEFAULT clock_timestamp(),CHECK(object_path='documents/'||id::text||'.pdf'));
CREATE TABLE ironvault_private.service_pdf_draft(id boolean PRIMARY KEY DEFAULT true CHECK(id),revision uuid NOT NULL DEFAULT gen_random_uuid(),files jsonb NOT NULL DEFAULT '{}'::jsonb,settings_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,version_label text NOT NULL DEFAULT '',effective_date date NOT NULL DEFAULT (now() AT TIME ZONE 'Asia/Manila')::date,updated_by uuid,updated_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO ironvault_private.service_pdf_draft(id) VALUES(true);
ALTER TABLE ironvault_private.service_versions ADD COLUMN document_format text NOT NULL DEFAULT 'text' CHECK(document_format IN ('text','pdf'));
ALTER TABLE ironvault_private.service_versions ADD COLUMN version_label text;
ALTER TABLE ironvault_private.service_versions ADD COLUMN pdf_files jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE ironvault_private.service_versions ADD COLUMN publication_request uuid UNIQUE;
ALTER TABLE ironvault_private.service_versions ADD COLUMN source_draft uuid;
CREATE UNIQUE INDEX iv_service_pdf_version_label ON ironvault_private.service_versions(lower(btrim(version_label))) WHERE document_format='pdf';
CREATE OR REPLACE FUNCTION ironvault_private.service_pdf_allowed(p_path text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM ironvault_private.service_pdf_files f WHERE f.object_path=p_path AND
 (ironvault_private.subscription_super() OR
 (EXISTS(SELECT 1 FROM ironvault_private.gym_subscriptions s WHERE ironvault_private.subscription_owner(s.tenant_id))
 AND EXISTS(SELECT 1 FROM ironvault_private.service_versions v CROSS JOIN LATERAL jsonb_each(v.pdf_files) j WHERE v.document_format='pdf' AND j.value->>'id'=f.id::text))));
$fn$;
-- Counter broad legacy Storage policies without changing their behavior for other buckets.
CREATE POLICY iv_service_pdf_select ON storage.objects FOR SELECT TO authenticated USING(bucket_id='iv-service-documents' AND ironvault_private.service_pdf_allowed(name));
CREATE POLICY iv_service_pdf_read_boundary ON storage.objects AS RESTRICTIVE FOR SELECT TO anon,authenticated USING(bucket_id<>'iv-service-documents' OR (auth.uid() IS NOT NULL AND ironvault_private.service_pdf_allowed(name)));
CREATE POLICY iv_service_pdf_insert_boundary ON storage.objects AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK(bucket_id<>'iv-service-documents');
CREATE POLICY iv_service_pdf_update_boundary ON storage.objects AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING(bucket_id<>'iv-service-documents') WITH CHECK(bucket_id<>'iv-service-documents');
CREATE POLICY iv_service_pdf_delete_boundary ON storage.objects AS RESTRICTIVE FOR DELETE TO anon,authenticated USING(bucket_id<>'iv-service-documents');
CREATE OR REPLACE FUNCTION public.iv_service_pdf_register(p_actor uuid,p_id uuid,p_name text,p_hash text,p_size integer,p_pages integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE prior ironvault_private.service_pdf_files%ROWTYPE;path text:='documents/'||p_id::text||'.pdf';
BEGIN
 IF NOT ironvault_private.subscription_super(p_actor) THEN RAISE EXCEPTION 'Service Provider administrator required' USING ERRCODE='42501'; END IF;
 IF p_id IS NULL OR coalesce(length(p_name),0) NOT BETWEEN 1 AND 180 OR p_hash IS NULL OR p_hash !~ '^[a-f0-9]{64}$' OR p_size NOT BETWEEN 1 AND 5242880 OR p_pages NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Invalid PDF metadata'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,37));
 SELECT * INTO prior FROM ironvault_private.service_pdf_files WHERE id=p_id;
 IF FOUND THEN
  IF prior.uploaded_by<>p_actor OR prior.sha256<>p_hash OR prior.size_bytes<>p_size OR prior.pages<>p_pages THEN RAISE EXCEPTION 'PDF upload ID already belongs to different contents'; END IF;
  RETURN to_jsonb(prior);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='iv-service-documents' AND name=path) THEN RAISE EXCEPTION 'Private uploaded PDF not found'; END IF;
 INSERT INTO ironvault_private.service_pdf_files(id,object_path,display_name,sha256,size_bytes,pages,uploaded_by) VALUES(p_id,path,p_name,p_hash,p_size,p_pages,p_actor) RETURNING * INTO prior;
 RETURN to_jsonb(prior);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_service_pdf_settings(p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE setting ironvault_private.service_settings%ROWTYPE;draft ironvault_private.service_pdf_draft%ROWTYPE;current_document ironvault_private.service_versions%ROWTYPE;existing ironvault_private.service_versions%ROWTYPE;k text;settings jsonb;manifest jsonb:='{}';file ironvault_private.service_pdf_files%ROWTYPE;published_version uuid;request_uuid uuid;notice integer;effective date;label text;
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Service Provider administrator required' USING ERRCODE='42501'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('get','save','publish') OR p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>10000 THEN RAISE EXCEPTION 'Invalid PDF settings request'; END IF;
 SELECT * INTO STRICT setting FROM ironvault_private.service_settings WHERE id=true FOR UPDATE;
 SELECT * INTO STRICT draft FROM ironvault_private.service_pdf_draft WHERE id=true FOR UPDATE;
 SELECT * INTO current_document FROM ironvault_private.service_versions WHERE id=ironvault_private.service_current();
 notice:=greatest(30,coalesce((current_document.data->>'price_notice_days')::integer,30),coalesce((SELECT max((v.data->>'price_notice_days')::integer) FROM ironvault_private.service_versions v WHERE v.id IN (SELECT DISTINCT ON (a.tenant_id,a.owner_id) a.version_id FROM ironvault_private.service_acceptances a ORDER BY a.tenant_id,a.owner_id,a.accepted_at DESC)),30));
 IF p_action='publish' THEN
  request_uuid:=(p_data->>'request_id')::uuid;
  IF request_uuid IS NULL THEN RAISE EXCEPTION 'Publication request ID required'; END IF;
  SELECT * INTO existing FROM ironvault_private.service_versions WHERE publication_request=request_uuid;
  IF FOUND THEN IF existing.source_draft IS DISTINCT FROM (p_data->>'revision')::uuid THEN RAISE EXCEPTION 'Publication request belongs to another draft'; END IF;RETURN jsonb_build_object('published_id',existing.id,'replayed',true); END IF;
 END IF;
 IF p_action<>'get' AND (p_data->>'revision')::uuid IS DISTINCT FROM draft.revision THEN RAISE EXCEPTION 'Draft changed in another session. Reload before continuing'; END IF;
 IF p_action='save' THEN
  settings:=setting.draft;
  FOREACH k IN ARRAY ARRAY['dashboard_price','portal_price','pilot_days','paid_days','grace_days','price_notice_days'] LOOP
   IF p_data->'settings'->k IS NULL OR jsonb_typeof(p_data->'settings'->k)<>'number' THEN RAISE EXCEPTION 'Enter a numeric value: %',k; END IF;
   settings:=settings||jsonb_build_object(k,p_data->'settings'->k);
  END LOOP;
  IF (settings->>'dashboard_price')::numeric<=0 OR (settings->>'portal_price')::numeric<(settings->>'dashboard_price')::numeric OR (settings->>'portal_price')::numeric>1000000 OR (settings->>'dashboard_price')::numeric<>round((settings->>'dashboard_price')::numeric,2) OR (settings->>'portal_price')::numeric<>round((settings->>'portal_price')::numeric,2) THEN RAISE EXCEPTION 'Invalid prices'; END IF;
  FOREACH k IN ARRAY ARRAY['pilot_days','paid_days','grace_days','price_notice_days'] LOOP IF (settings->>k)::numeric<>(settings->>k)::integer OR (settings->>k)::integer NOT BETWEEN 1 AND 3650 THEN RAISE EXCEPTION 'Invalid duration: %',k; END IF; END LOOP;
  IF (settings->>'grace_days')::integer>30 OR (settings->>'price_notice_days')::integer<30 THEN RAISE EXCEPTION 'Grace cannot exceed 30 days; price notice must be at least 30 days'; END IF;
  IF jsonb_typeof(p_data->'files') IS DISTINCT FROM 'object' OR octet_length((p_data->'files')::text)>500 THEN RAISE EXCEPTION 'Invalid PDF selection'; END IF;
  FOREACH k IN ARRAY ARRAY['terms','privacy','dpa'] LOOP
   IF nullif(p_data->'files'->>k,'') IS NOT NULL THEN
    SELECT * INTO STRICT file FROM ironvault_private.service_pdf_files WHERE id=(p_data->'files'->>k)::uuid;
    manifest:=manifest||jsonb_build_object(k,jsonb_build_object('id',file.id,'sha256',file.sha256,'name',file.display_name,'pages',file.pages,'size_bytes',file.size_bytes));
   END IF;
  END LOOP;
  label:=btrim(coalesce(p_data->>'version_label',''));IF length(label)>80 THEN RAISE EXCEPTION 'Version label must be at most 80 characters'; END IF;
  effective:=coalesce(nullif(p_data->>'effective_date','')::date,ironvault_private.subscription_today());
  UPDATE ironvault_private.service_settings SET draft=settings,updated_at=clock_timestamp() WHERE id=true;
  UPDATE ironvault_private.service_pdf_draft SET files=manifest,version_label=label,settings_snapshot=ironvault_private.service_parameters(settings),effective_date=effective,revision=gen_random_uuid(),updated_by=auth.uid(),updated_at=clock_timestamp() WHERE id=true RETURNING * INTO draft;
 ELSIF p_action='publish' THEN
  IF draft.settings_snapshot IS DISTINCT FROM ironvault_private.service_parameters(setting.draft) THEN RAISE EXCEPTION 'Settings changed outside this PDF draft. Save and review again'; END IF;
  IF p_data->>'reviewed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Confirm that all PDFs match the saved settings'; END IF;
  IF length(draft.version_label)<2 OR NOT (draft.files ?& ARRAY['terms','privacy','dpa']) THEN RAISE EXCEPTION 'Provide a version label and all three verified PDFs'; END IF;
  FOREACH k IN ARRAY ARRAY['terms','privacy','dpa'] LOOP
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.service_pdf_files f JOIN storage.objects o ON o.bucket_id='iv-service-documents' AND o.name=f.object_path WHERE f.id=(draft.files->k->>'id')::uuid AND f.sha256=draft.files->k->>'sha256') THEN RAISE EXCEPTION 'A verified PDF file is missing'; END IF;
  END LOOP;
  notice:=greatest(30,coalesce((current_document.data->>'price_notice_days')::integer,30),coalesce((SELECT max((v.data->>'price_notice_days')::integer) FROM ironvault_private.service_versions v WHERE v.id IN (SELECT DISTINCT ON (a.tenant_id,a.owner_id) a.version_id FROM ironvault_private.service_acceptances a ORDER BY a.tenant_id,a.owner_id,a.accepted_at DESC)),30));
  IF draft.effective_date<ironvault_private.subscription_today() OR (EXISTS(SELECT 1 FROM ironvault_private.service_versions) AND draft.effective_date<ironvault_private.subscription_today()+notice) THEN RAISE EXCEPTION 'Allow at least % days notice for a new publication; existing approved periods are protected',notice; END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE effective_date>=draft.effective_date) THEN RAISE EXCEPTION 'A publication already exists on or after this date. Choose a later effective date'; END IF;
  INSERT INTO ironvault_private.service_versions(data,terms_text,privacy_text,dpa_text,effective_date,published_by,document_format,version_label,pdf_files,publication_request,source_draft)
  VALUES(ironvault_private.service_parameters(setting.draft),'Published PDF Terms of Use','Published PDF Privacy Notice','Published PDF Data Processing Agreement',draft.effective_date,auth.uid(),'pdf',draft.version_label,draft.files,request_uuid,draft.revision) RETURNING id INTO published_version;
  PERFORM ironvault_private.subscription_notice(s.tenant_id,'documents:'||published_version,'Service documents and settings update',
   'Effective '||draft.effective_date||'. Dashboard PHP '||coalesce(current_document.data->>'dashboard_price','not previously published')||' → '||(setting.draft->>'dashboard_price')||'; Portal PHP '||coalesce(current_document.data->>'portal_price','not previously published')||' → '||(setting.draft->>'portal_price')||'; pilot days '||coalesce(current_document.data->>'pilot_days','not previously published')||' → '||(setting.draft->>'pilot_days')||'; paid days '||coalesce(current_document.data->>'paid_days','not previously published')||' → '||(setting.draft->>'paid_days')||'; grace days '||coalesce(current_document.data->>'grace_days','not previously published')||' → '||(setting.draft->>'grace_days')||'; price notice days '||coalesce(current_document.data->>'price_notice_days','not previously published')||' → '||(setting.draft->>'price_notice_days')||'; export days '||coalesce(current_document.data->>'export_days','not previously published')||' → '||(setting.draft->>'export_days')||'; retention review days '||coalesce(current_document.data->>'retention_days','not previously published')||' → '||(setting.draft->>'retention_days')||'. Read the PDFs and accept the applicable version. You may continue, change plans or decline renewal. Approved periods keep their recorded dates and prices.') FROM ironvault_private.gym_subscriptions s;
  PERFORM ironvault_private.subscription_notice(s.tenant_id,'documents-effective:'||published_version,'Updated documents and settings are effective','The notified service documents and settings are effective today. Existing approved subscription periods remain unchanged; review any required acceptance before a future activation or renewal.',draft.effective_date) FROM ironvault_private.gym_subscriptions s;
 END IF;
 RETURN jsonb_build_object('minimum_effective_date',CASE WHEN EXISTS(SELECT 1 FROM ironvault_private.service_versions) THEN greatest(ironvault_private.subscription_today()+notice,(SELECT max(effective_date)+1 FROM ironvault_private.service_versions)) ELSE ironvault_private.subscription_today() END,'revision',draft.revision,'draft',jsonb_build_object('settings',ironvault_private.service_parameters(CASE WHEN p_action='save' THEN settings ELSE setting.draft END),'files',draft.files,'version_label',draft.version_label,'effective_date',draft.effective_date),'current',to_jsonb(current_document),'scheduled',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY effective_date) FROM ironvault_private.service_versions v WHERE effective_date>ironvault_private.subscription_today()),'[]'::jsonb),'versions',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY effective_date DESC,published_at DESC) FROM ironvault_private.service_versions v),'[]'::jsonb),'published_id',published_version);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_service_documents(p_action text,p_data jsonb DEFAULT NULL,p_effective date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s ironvault_private.service_settings%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;k text;clean jsonb:='{}';rendered jsonb;effective date:=coalesce(p_effective,ironvault_private.subscription_today());published_version_id uuid;
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Super Admin required' USING ERRCODE='42501'; END IF;
 SELECT * INTO STRICT s FROM ironvault_private.service_settings settings_row WHERE settings_row.id=true FOR UPDATE;
 IF p_action='publish' AND EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE document_format='pdf') THEN RAISE EXCEPTION 'Publish the new version through PDF documents; legacy drafts and history remain available'; END IF;
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
DO $acl$ DECLARE tab text;signature text; BEGIN
 FOREACH tab IN ARRAY ARRAY['service_pdf_files','service_pdf_draft'] LOOP EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',tab);EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',tab);EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',tab);END LOOP;
 FOREACH signature IN ARRAY ARRAY['ironvault_private.service_pdf_allowed(text)','public.iv_service_pdf_register(uuid,uuid,text,text,integer,integer)','public.iv_service_pdf_settings(text,jsonb)'] LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION ironvault_private.service_pdf_allowed(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iv_service_pdf_register(uuid,uuid,text,text,integer,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.iv_service_pdf_settings(text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
