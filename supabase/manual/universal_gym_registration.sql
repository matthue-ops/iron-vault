-- MANUAL ONLY after 059. No SQL is executed by the agent against a hosted database.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.membership_plans') IS NULL THEN RAISE EXCEPTION 'Confirm migration 059 first';END IF;
 IF to_regclass('ironvault_private.gym_registration_requests') IS NOT NULL THEN RAISE EXCEPTION '060 already installed';END IF;
END $guard$;
CREATE TABLE ironvault_private.gym_registration_requests(id uuid PRIMARY KEY,tenant_id text NOT NULL UNIQUE REFERENCES public.owners(id) ON DELETE CASCADE,kind text NOT NULL CHECK(kind IN ('initial','branch')),payload jsonb NOT NULL,contact_email text NOT NULL,alias text NOT NULL,legal_version uuid NOT NULL REFERENCES ironvault_private.legal_versions(id),accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),actor_id uuid,completed_user uuid,created_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE UNIQUE INDEX iv_initial_registration_email ON ironvault_private.gym_registration_requests(contact_email) WHERE kind='initial' AND completed_user IS NULL;
ALTER TABLE ironvault_private.gym_registration_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.gym_registration_requests FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.iv_gym_registration_documents(p_version uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('version',v.id,'terms',v.terms_text,'privacy',v.privacy_text,'published_at',v.published_at) FROM ironvault_private.legal_settings s JOIN ironvault_private.legal_versions v ON v.id=coalesce(p_version,s.current_version) AND v.scope='platform' WHERE s.scope='platform';
$fn$;
CREATE FUNCTION ironvault_private.prepare_registered_gym_060(p_id uuid,p_email text,p_alias text,p_payload jsonb,p_actor uuid DEFAULT NULL,p_kind text DEFAULT 'initial') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE j ironvault_private.gym_registration_requests%ROWTYPE;t text:='GYM-'||p_id::text;version_id uuid;name text;key text;price numeric;
BEGIN
 IF p_id IS NULL OR p_kind NOT IN ('initial','branch') OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>12000 OR p_payload ? 'password' OR p_payload ? 'service_role' OR p_email IS NULL OR length(p_email)>254 OR p_email<>lower(btrim(p_email)) OR p_email !~ '^[^[:space:]@<>,;:"()\\]+@[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z0-9-]{2,63}$' OR p_alias !~ '^[a-f0-9]{64}@accounts\.ironvault\.invalid$' THEN RAISE EXCEPTION 'Invalid registration';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_id::text,1));
 SELECT * INTO j FROM ironvault_private.gym_registration_requests WHERE id=p_id;
 IF FOUND THEN
  IF j.payload<>p_payload OR j.contact_email<>p_email OR j.alias<>p_alias OR j.actor_id IS DISTINCT FROM p_actor OR j.kind<>p_kind THEN RAISE EXCEPTION 'Registration retry differs from original';END IF;
  RETURN jsonb_build_object('tenant_id',j.tenant_id,'completed_user',j.completed_user,'alias',j.alias);
 END IF;
 IF p_kind='initial' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('registration-email:'||p_email,60));
  IF EXISTS(SELECT 1 FROM ironvault_private.branch_accounts WHERE role='owner' AND contact_email=p_email) THEN RAISE EXCEPTION 'An owner account already uses this email. Use owner sign-in';END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.gym_registration_requests WHERE kind='initial' AND contact_email=p_email AND completed_user IS NULL) THEN RAISE EXCEPTION 'An unfinished registration already exists for this email. Retry the original request';END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.tenant_purge_jobs WHERE tenant_id=t) THEN RAISE EXCEPTION 'This registration was explicitly removed. Start a new registration request';END IF;
 name:=btrim(p_payload->>'gym_name');version_id:=(p_payload->>'legal_version')::uuid;
 IF length(coalesce(name,'')) NOT BETWEEN 1 AND 160 OR length(btrim(coalesce(p_payload->>'name',''))) NOT BETWEEN 1 AND 160 OR length(btrim(coalesce(p_payload->>'address',''))) NOT BETWEEN 3 AND 300 OR length(coalesce(p_payload->>'phone',''))>50 OR p_payload->>'accepted' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Review current published registration terms and complete gym details';END IF;
 IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings s JOIN ironvault_private.legal_versions v ON v.id=s.current_version AND v.scope='platform' WHERE s.scope='platform' AND v.id=version_id AND length(v.terms_text)>0 AND length(v.privacy_text)>0) THEN RETURN jsonb_build_object('needs_legal_review',true);END IF;
 FOREACH key IN ARRAY ARRAY['day','week','month','studentDiscount','seniorDiscount'] LOOP
  price:=(p_payload->'pricing'->>key)::numeric;
  IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<>round(price,2) OR price<0 OR price>(CASE WHEN key LIKE '%Discount' THEN 100 ELSE 10000000 END) OR (key NOT LIKE '%Discount' AND price<=0) THEN RAISE EXCEPTION 'Invalid initial pricing';END IF;
 END LOOP;
 INSERT INTO public.owners(id,gym_name,owner_name,email,password,token,logo,status,pricing,staff,audit_logs) VALUES(t,name,btrim(p_payload->>'name'),p_alias,NULL,gen_random_uuid()::text,'','PROVISIONING',p_payload->'pricing','[]','[]');
 INSERT INTO ironvault_private.provision_requests(request_id,tenant_id,role,contact_email,alias,actor_id,payload) VALUES(p_id,t,'owner',p_email,p_alias,p_actor,p_payload);
 INSERT INTO ironvault_private.gym_registration_requests(id,tenant_id,kind,payload,contact_email,alias,legal_version,actor_id) VALUES(p_id,t,p_kind,p_payload,p_email,p_alias,version_id,p_actor);
 RETURN jsonb_build_object('tenant_id',t,'completed_user',NULL,'alias',p_alias);
END $fn$;
CREATE FUNCTION public.iv_gym_registration_service(p_action text,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE j ironvault_private.gym_registration_requests%ROWTYPE;result jsonb;request_key uuid:=(p_data->>'request_id')::uuid;
BEGIN
 IF p_action='prepare' THEN RETURN ironvault_private.prepare_registered_gym_060(request_key,p_data->>'email',p_data->>'alias',p_data->'payload');END IF;
 IF p_action<>'finish' THEN RAISE EXCEPTION 'Invalid registration action';END IF;
 SELECT * INTO j FROM ironvault_private.gym_registration_requests WHERE gym_registration_requests.id=request_key AND kind='initial';
 IF NOT FOUND THEN RAISE EXCEPTION 'Registration unavailable';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('registration-email:'||j.contact_email,60));
 SELECT * INTO j FROM ironvault_private.gym_registration_requests WHERE gym_registration_requests.id=request_key AND kind='initial' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registration unavailable';END IF;
 IF j.completed_user IS NULL AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts WHERE tenant_id=j.tenant_id AND role='staff' AND contact_email=j.contact_email) THEN RAISE EXCEPTION 'Owner email conflicts with a staff account in this gym';END IF;
 result:=public.iv_finish_branch_account(request_key,(p_data->>'user_id')::uuid);
 UPDATE ironvault_private.gym_registration_requests SET completed_user=(p_data->>'user_id')::uuid WHERE gym_registration_requests.id=request_key;
 -- Draft-only public business details; the owner must still review and publish gym documents.
 UPDATE ironvault_private.legal_settings SET draft=draft||jsonb_build_object('name',j.payload->>'gym_name','address',j.payload->>'address','phone',j.payload->>'phone') WHERE scope=j.tenant_id AND j.completed_user IS NULL;
 -- Live is an administrative label, never a pilot/subscription activation.
 UPDATE ironvault_private.gym_subscriptions SET is_test=false WHERE tenant_id=j.tenant_id AND j.completed_user IS NULL;
 IF j.completed_user IS NULL THEN INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) VALUES('registration:'||j.id,j.tenant_id,'New gym registration','A new Live gym owner can sign in. Review setup and agreements before any pilot activation.') ON CONFLICT DO NOTHING;END IF;
 RETURN result||jsonb_build_object('gym',(SELECT jsonb_build_object('id',g.id,'name',g.gym_name,'token',g.token) FROM public.owners g WHERE g.id=j.tenant_id AND g.status='ACTIVE'));
END $fn$;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='ironvault_private' AND p.proname='prepare_registered_gym_060') OR (n.nspname='public' AND p.proname IN ('iv_gym_registration_documents','iv_gym_registration_service')) LOOP
 EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO postgres',f.nspname,f.proname,f.args);EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',f.nspname,f.proname,f.args);
 IF f.proname='iv_gym_registration_documents' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO anon,authenticated,service_role',f.nspname,f.proname,f.args);ELSIF f.proname='iv_gym_registration_service' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO service_role',f.nspname,f.proname,f.args);END IF;
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';COMMIT;
