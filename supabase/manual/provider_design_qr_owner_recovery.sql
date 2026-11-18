-- MANUAL ONLY after confirmed 057. No credentials rotate and no recovery is initiated at installation.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_physical_id_design(text,text,jsonb)') IS NULL OR to_regprocedure('ironvault_private.physical_id_action_057_base(text,text,jsonb)') IS NULL THEN RAISE EXCEPTION 'Confirm migration 057 first';END IF;
 IF to_regclass('ironvault_private.owner_contact_recoveries') IS NOT NULL THEN RAISE EXCEPTION '058 already installed; do not reapply';END IF;
END $guard$;
-- Keep the historical helper signature so existing design and storage checks stay aligned.
CREATE OR REPLACE FUNCTION ironvault_private.card_design_owner_057(t text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.owners WHERE id=t AND status='ACTIVE') AND
 (ironvault_private.subscription_super() OR EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL AND r.tenant_id=t));
$fn$;
CREATE TABLE ironvault_private.physical_id_design_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,revision bigint NOT NULL,actor_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE ironvault_private.physical_id_design_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.physical_id_design_events FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.card_design_audit_058() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF TG_OP='INSERT' OR NEW.revision IS DISTINCT FROM OLD.revision THEN INSERT INTO ironvault_private.physical_id_design_events(tenant_id,revision,actor_id) VALUES(NEW.tenant_id,NEW.revision,NEW.updated_by);END IF;RETURN NEW;
END $fn$;
CREATE TRIGGER iv_card_design_audit_058 AFTER INSERT OR UPDATE ON ironvault_private.physical_id_designs FOR EACH ROW EXECUTE FUNCTION ironvault_private.card_design_audit_058();
ALTER FUNCTION public.iv_physical_id_action(text,text,jsonb) RENAME TO physical_id_action_058_base;
ALTER FUNCTION public.physical_id_action_058_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_physical_id_action(p_tenant text,p_action text,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE c ironvault_private.member_cards%ROWTYPE;o ironvault_private.physical_id_operations%ROWTYPE;operation uuid;member_key text;fingerprint text;result jsonb;
BEGIN
 IF p_action IS DISTINCT FROM 'qr_download' THEN RETURN ironvault_private.physical_id_action_058_base(p_tenant,p_action,p_data);END IF;
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Provider QR download permission required' USING ERRCODE='42501';END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>20000 THEN RAISE EXCEPTION 'Invalid QR export';END IF;
 PERFORM 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND role='super_admin' AND tenant_id IS NULL AND enabled AND disabled_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Provider QR download permission required' USING ERRCODE='42501';END IF;
 PERFORM ironvault_private.physical_id_production_055(p_tenant);
 operation:=(p_data->>'operation_id')::uuid;member_key:=p_data->>'member_id';
 IF operation IS NULL OR member_key IS NULL THEN RAISE EXCEPTION 'Member and retry identity required';END IF;
 PERFORM 1 FROM public.members WHERE id=member_key AND tenant_id=p_tenant AND status IN ('ACTIVE','PENDING') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Member unavailable';END IF;
 SELECT * INTO c FROM ironvault_private.member_cards WHERE tenant_id=p_tenant AND member_id=member_key AND revoked_at IS NULL FOR UPDATE;
 IF NOT FOUND OR c.card_id IS DISTINCT FROM (p_data->>'card_id')::uuid THEN RAISE EXCEPTION 'QR is obsolete. Refresh before downloading';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(operation::text,55));fingerprint:=md5(p_tenant||p_action||p_data::text);
 SELECT * INTO o FROM ironvault_private.physical_id_operations WHERE id=operation;
 IF FOUND THEN
  IF o.actor_id<>auth.uid() OR o.tenant_id<>p_tenant OR o.member_id<>member_key OR o.action<>p_action OR o.payload_hash<>fingerprint THEN RAISE EXCEPTION 'Retry identity belongs to a different action';END IF;
  result:=o.result;
 ELSE
  result:=jsonb_build_object('export_id',gen_random_uuid(),'card_id',c.card_id,'version',c.version);
  INSERT INTO ironvault_private.physical_id_events(id,tenant_id,member_id,card_id,actor_id,action,data) VALUES((result->>'export_id')::uuid,p_tenant,member_key,c.card_id,auth.uid(),'qr_download_authorized',jsonb_build_object('format','SVG-PNG-2048','version',c.version));
  INSERT INTO ironvault_private.physical_id_operations(id,actor_id,tenant_id,member_id,action,payload_hash,result) VALUES(operation,auth.uid(),p_tenant,member_key,p_action,fingerprint,result);
 END IF;
 -- Secrets are returned only to the authorized caller, never put in operation caches or audit data.
 RETURN result||jsonb_build_object('payload','IVC1|'||c.token::text);
END $fn$;
ALTER FUNCTION public.iv_physical_ids(text,text,jsonb) RENAME TO physical_ids_058_base;
ALTER FUNCTION public.physical_ids_058_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_physical_ids(p_tenant text,p_action text DEFAULT 'requests',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;
BEGIN
 result:=ironvault_private.physical_ids_058_base(p_tenant,p_action,p_data);
 IF p_action IN ('preview','loss') THEN result:=result||jsonb_build_object('permissions',coalesce(result->'permissions','{}')||jsonb_build_object('qr_download',ironvault_private.subscription_super() AND result->>'card_state'='active' AND NOT coalesce((result->>'security_only')::boolean,false)));END IF;
 RETURN result;
END $fn$;
CREATE TABLE ironvault_private.owner_contact_recoveries(
 id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,user_id uuid NOT NULL,actor_id uuid NOT NULL,
 base_email text NOT NULL,new_email text NOT NULL,reason text NOT NULL CHECK(length(reason) BETWEEN 8 AND 500),token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','confirmed','cancelled')),created_at timestamptz NOT NULL DEFAULT clock_timestamp(),expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '30 minutes',confirmed_at timestamptz
);
CREATE UNIQUE INDEX iv_owner_contact_one_pending ON ironvault_private.owner_contact_recoveries(user_id) WHERE status='pending';
ALTER TABLE ironvault_private.owner_contact_recoveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.owner_contact_recoveries FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.iv_owner_contact_recovery(p_action text,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE a ironvault_private.branch_accounts%ROWTYPE;r ironvault_private.owner_contact_recoveries%ROWTYPE;provider uuid;tenant text;email text;request_id uuid;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>10000 THEN RAISE EXCEPTION 'Invalid recovery request';END IF;
 IF p_action='prepare' THEN
  provider:=(p_data->>'actor_id')::uuid;tenant:=p_data->>'tenant_id';email:=lower(btrim(p_data->>'new_email'));request_id:=(p_data->>'request_id')::uuid;
  IF request_id IS NULL OR p_data->>'identity_verified' IS DISTINCT FROM 'true' OR length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 8 AND 500 OR email IS NULL OR length(email)>254 OR email !~ '^[^[:space:]@<>,;:"()\\]+@[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z0-9-]{2,63}$' OR coalesce(p_data->>'token_hash','') !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'Invalid recovery request';END IF;
  SELECT * INTO a FROM ironvault_private.branch_accounts WHERE tenant_id=tenant AND role='owner' FOR UPDATE;
  PERFORM 1 FROM public.iv_user_roles WHERE user_id=provider OR (tenant_id=tenant AND role='owner') ORDER BY user_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Owner unavailable';END IF;
  SELECT * INTO r FROM ironvault_private.owner_contact_recoveries WHERE id=request_id;
  IF FOUND AND (r.actor_id<>provider OR r.tenant_id<>tenant OR r.user_id<>a.user_id OR r.new_email<>email OR r.reason<>btrim(p_data->>'reason')) THEN RAISE EXCEPTION 'Retry identity belongs to another request';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=provider AND role='super_admin' AND tenant_id IS NULL AND enabled AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Provider required';END IF;
  IF r.status='confirmed' THEN RETURN jsonb_build_object('status','confirmed');END IF;
  IF r.status='cancelled' THEN RAISE EXCEPTION 'Request superseded; start a new request';END IF;
  IF email=a.contact_email THEN RAISE EXCEPTION 'Use a different working email';END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.branch_accounts WHERE tenant_id=tenant AND role IN ('owner','staff') AND user_id<>a.user_id AND contact_email=email) THEN RAISE EXCEPTION 'Admin portal email already in use';END IF;
  IF r.id IS NOT NULL AND r.base_email IS DISTINCT FROM a.contact_email THEN RAISE EXCEPTION 'Owner email changed; start a new request';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=a.user_id AND tenant_id=tenant AND role='owner' AND enabled AND disabled_at IS NULL) OR NOT EXISTS(SELECT 1 FROM public.owners WHERE id=tenant AND status='ACTIVE') THEN RAISE EXCEPTION 'Owner access unavailable';END IF;
  UPDATE ironvault_private.owner_contact_recoveries SET status='cancelled' WHERE user_id=a.user_id AND status='pending' AND id<>request_id;
  INSERT INTO ironvault_private.owner_contact_recoveries(id,tenant_id,user_id,actor_id,base_email,new_email,reason,token_hash) VALUES(request_id,tenant,a.user_id,provider,a.contact_email,email,btrim(p_data->>'reason'),p_data->>'token_hash')
   ON CONFLICT(id) DO UPDATE SET token_hash=EXCLUDED.token_hash,expires_at=clock_timestamp()+interval '30 minutes';
  RETURN jsonb_build_object('status','pending','user_id',a.user_id,'tenant_id',tenant,'email',email,'gym_token',(SELECT token FROM public.owners WHERE id=tenant));
 END IF;
 IF p_action NOT IN ('inspect','confirm') OR coalesce(p_data->>'token_hash','') !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'Invalid recovery action';END IF;
 SELECT * INTO r FROM ironvault_private.owner_contact_recoveries WHERE token_hash=p_data->>'token_hash';
 IF NOT FOUND THEN RAISE EXCEPTION 'Recovery link unavailable';END IF;
 -- Match ordinary contact confirmation: account first, then role locks; never lock email_actions here.
 SELECT * INTO a FROM ironvault_private.branch_accounts WHERE user_id=r.user_id FOR UPDATE;
 PERFORM 1 FROM public.iv_user_roles WHERE user_id IN (r.actor_id,r.user_id) ORDER BY user_id FOR SHARE;
 SELECT * INTO r FROM ironvault_private.owner_contact_recoveries WHERE id=r.id FOR UPDATE;
 IF r.status='confirmed' THEN RETURN jsonb_build_object('status','confirmed');END IF;
 IF r.status<>'pending' OR r.expires_at<=clock_timestamp() OR a.contact_email IS DISTINCT FROM r.base_email THEN RAISE EXCEPTION 'Recovery expired, superseded or email changed';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=r.actor_id AND role='super_admin' AND tenant_id IS NULL AND enabled AND disabled_at IS NULL) OR NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=r.user_id AND tenant_id=r.tenant_id AND role='owner' AND enabled AND disabled_at IS NULL) OR NOT EXISTS(SELECT 1 FROM public.owners WHERE id=r.tenant_id AND status='ACTIVE') THEN RAISE EXCEPTION 'Recovery authority unavailable';END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.branch_accounts WHERE tenant_id=r.tenant_id AND role IN ('owner','staff') AND user_id<>r.user_id AND contact_email=r.new_email) THEN RAISE EXCEPTION 'Admin portal email already in use';END IF;
 IF p_action='inspect' THEN RETURN jsonb_build_object('status','pending','user_id',r.user_id);END IF;
 UPDATE ironvault_private.branch_accounts SET contact_email=r.new_email,contact_verified=true WHERE user_id=r.user_id;
 -- Existing contact links carry base_email and become invalid when that email changes.
 UPDATE ironvault_private.owner_contact_recoveries SET status='confirmed',confirmed_at=clock_timestamp() WHERE id=r.id;
 RETURN jsonb_build_object('status','confirmed');
END $fn$;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='ironvault_private' AND p.proname IN ('card_design_owner_057','card_design_audit_058','physical_id_action_058_base','physical_ids_058_base')) OR (n.nspname='public' AND p.proname IN ('iv_physical_id_action','iv_physical_ids','iv_owner_contact_recovery')) LOOP
 EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO postgres',f.nspname,f.proname,f.args);
 EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',f.nspname,f.proname,f.args);
 IF f.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO %I',f.nspname,f.proname,f.args,CASE WHEN f.proname='iv_owner_contact_recovery' THEN 'service_role' ELSE 'authenticated' END);END IF;
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
