-- MANUAL ONLY after confirmed 056. No card credentials or business records are rewritten.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('ironvault_private.physical_ids_056_base(text,text,jsonb)') IS NULL THEN RAISE EXCEPTION 'Confirm migration 056 first'; END IF;
 IF to_regclass('ironvault_private.physical_id_designs') IS NOT NULL OR EXISTS(SELECT 1 FROM storage.buckets WHERE id='iv-card-backgrounds') THEN RAISE EXCEPTION '057 already installed or bucket exists; inspect rather than overwrite'; END IF;
END $guard$;
CREATE TABLE ironvault_private.physical_id_designs(tenant_id text PRIMARY KEY REFERENCES public.owners(id) ON DELETE CASCADE,revision bigint NOT NULL DEFAULT 0,design jsonb NOT NULL DEFAULT '{}',updated_by uuid,updated_at timestamptz NOT NULL DEFAULT clock_timestamp());
-- Durable retirement records permit safe cleanup after replacement or gym purge.
CREATE TABLE ironvault_private.physical_id_backgrounds(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id text NOT NULL,actor_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE ironvault_private.physical_id_designs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.physical_id_backgrounds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.physical_id_designs,ironvault_private.physical_id_backgrounds FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('iv-card-backgrounds','iv-card-backgrounds',false,4194304,ARRAY['image/webp','image/png','image/jpeg']);
CREATE FUNCTION ironvault_private.card_design_owner_057(t text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r JOIN public.owners g ON g.id=r.tenant_id WHERE r.user_id=auth.uid() AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL AND r.tenant_id=t AND g.status='ACTIVE');
$fn$;
CREATE FUNCTION ironvault_private.card_background_access_057(n text,a text) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE b ironvault_private.physical_id_backgrounds%ROWTYPE;current_file boolean;
BEGIN
 IF auth.uid() IS NULL OR n !~ '^[a-f0-9-]{36}/background$' THEN RETURN false;END IF;
 SELECT * INTO b FROM ironvault_private.physical_id_backgrounds WHERE id::text=split_part(n,'/',1);IF NOT FOUND THEN RETURN false;END IF;
 IF a='delete' THEN PERFORM pg_advisory_xact_lock(hashtextextended(b.tenant_id,57));END IF;
 SELECT EXISTS(SELECT 1 FROM ironvault_private.physical_id_designs d WHERE d.tenant_id=b.tenant_id AND (d.design->>'front_background'=b.id::text OR d.design->>'back_background'=b.id::text)) INTO current_file;
 IF a='insert' THEN RETURN b.actor_id=auth.uid() AND b.created_at>clock_timestamp()-interval '1 hour' AND ironvault_private.card_design_owner_057(b.tenant_id);END IF;
 IF a='delete' THEN RETURN NOT current_file AND (ironvault_private.card_design_owner_057(b.tenant_id) OR ironvault_private.subscription_super());END IF;
 IF a='select' THEN RETURN (b.actor_id=auth.uid() AND ironvault_private.card_design_owner_057(b.tenant_id)) OR (current_file AND EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.tenant_id=b.tenant_id AND r.role IN ('member','owner','staff')))));END IF;
 RETURN false;
END $fn$;
CREATE POLICY iv_card_background_read ON storage.objects FOR SELECT TO authenticated USING(bucket_id='iv-card-backgrounds' AND ironvault_private.card_background_access_057(name,'select'));
CREATE POLICY iv_card_background_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='iv-card-backgrounds' AND ironvault_private.card_background_access_057(name,'insert'));
CREATE POLICY iv_card_background_delete ON storage.objects FOR DELETE TO authenticated USING(bucket_id='iv-card-backgrounds' AND ironvault_private.card_background_access_057(name,'delete'));
CREATE POLICY iv_card_background_read_boundary ON storage.objects AS RESTRICTIVE FOR SELECT TO anon,authenticated USING(bucket_id<>'iv-card-backgrounds' OR ironvault_private.card_background_access_057(name,'select'));
CREATE POLICY iv_card_background_insert_boundary ON storage.objects AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK(bucket_id<>'iv-card-backgrounds' OR ironvault_private.card_background_access_057(name,'insert'));
CREATE POLICY iv_card_background_delete_boundary ON storage.objects AS RESTRICTIVE FOR DELETE TO anon,authenticated USING(bucket_id<>'iv-card-backgrounds' OR ironvault_private.card_background_access_057(name,'delete'));
CREATE POLICY iv_card_background_update_boundary ON storage.objects AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING(bucket_id<>'iv-card-backgrounds') WITH CHECK(bucket_id<>'iv-card-backgrounds');
CREATE FUNCTION public.iv_physical_id_design(p_tenant text,p_action text,p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE d ironvault_private.physical_id_designs%ROWTYPE;v jsonb;k text;b uuid;answer jsonb;
BEGIN
 IF NOT ironvault_private.card_design_owner_057(p_tenant) THEN RAISE EXCEPTION 'Gym owner design permission required' USING ERRCODE='42501';END IF;
 PERFORM ironvault_private.physical_id_production_055(p_tenant);
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>10000 THEN RAISE EXCEPTION 'Invalid design';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant,57));
 SELECT * INTO d FROM ironvault_private.physical_id_designs WHERE tenant_id=p_tenant;
 IF p_action='get' THEN RETURN jsonb_build_object('revision',coalesce(d.revision,0),'design',coalesce(d.design,'{}'));END IF;
 IF p_action='reserve' THEN INSERT INTO ironvault_private.physical_id_backgrounds(tenant_id,actor_id) VALUES(p_tenant,auth.uid()) RETURNING id INTO b;RETURN jsonb_build_object('id',b);END IF;
 IF p_action='cleanup' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'path',x.id||'/background')),'[]') INTO answer FROM (SELECT b.id FROM ironvault_private.physical_id_backgrounds b WHERE b.tenant_id=p_tenant AND b.created_at<clock_timestamp()-interval '1 hour' AND NOT EXISTS(SELECT 1 FROM ironvault_private.physical_id_designs z WHERE z.tenant_id=b.tenant_id AND (z.design->>'front_background'=b.id::text OR z.design->>'back_background'=b.id::text)) LIMIT 20) x;RETURN answer;
 END IF;
 IF p_action='ack' THEN DELETE FROM ironvault_private.physical_id_backgrounds b WHERE b.id::text=p_data->>'id' AND b.tenant_id=p_tenant AND b.created_at<clock_timestamp()-interval '1 hour' AND NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='iv-card-backgrounds' AND o.name=b.id::text||'/background') AND NOT EXISTS(SELECT 1 FROM ironvault_private.physical_id_designs z WHERE z.tenant_id=b.tenant_id AND (z.design->>'front_background'=b.id::text OR z.design->>'back_background'=b.id::text));RETURN '{}';END IF;
 IF p_action<>'save' THEN RAISE EXCEPTION 'Invalid design action';END IF;
 v:=p_data->'design';IF v IS NULL OR jsonb_typeof(v)<>'object' THEN RAISE EXCEPTION 'Design required';END IF;
 IF v->>'template' NOT IN ('classic','modern','premium') OR v->>'template' IS NULL OR v->>'tone' NOT IN ('light','dark') OR v->>'tone' IS NULL THEN RAISE EXCEPTION 'Choose a supported template and background';END IF;
 FOR k IN SELECT jsonb_object_keys(v) LOOP
  IF k IN ('primary','accent') THEN IF coalesce(v->>k,'') !~ '^#[a-fA-F0-9]{6}$' THEN RAISE EXCEPTION 'Invalid colour';END IF;
  ELSIF k IN ('front_background','back_background') THEN
   SELECT id INTO b FROM ironvault_private.physical_id_backgrounds WHERE id::text=v->>k AND tenant_id=p_tenant;
   IF b IS NULL OR NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='iv-card-backgrounds' AND name=b::text||'/background') THEN RAISE EXCEPTION 'Background unavailable or belongs to another gym';END IF;
  ELSIF k IN ('front_x','front_y','back_x','back_y','front_overlay','back_overlay') THEN
   IF jsonb_typeof(v->k)<>'number' OR (v->>k)::numeric<0 OR (v->>k)::numeric>100 THEN RAISE EXCEPTION 'Invalid background position';END IF;
  ELSIF k NOT IN ('template','tone') THEN RAISE EXCEPTION 'Unsupported design setting';END IF;
 END LOOP;
 -- An identical retry after a lost response succeeds; different stale saves cannot overwrite.
 IF d.design=v AND d.revision=(p_data->>'revision')::bigint+1 THEN RETURN jsonb_build_object('revision',d.revision,'design',d.design);END IF;
 IF coalesce(d.revision,0) IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Design changed. Refresh before saving';END IF;
 INSERT INTO ironvault_private.physical_id_designs(tenant_id,revision,design,updated_by) VALUES(p_tenant,1,v,auth.uid()) ON CONFLICT(tenant_id) DO UPDATE SET revision=physical_id_designs.revision+1,design=v,updated_by=auth.uid(),updated_at=clock_timestamp() RETURNING * INTO d;
 RETURN jsonb_build_object('revision',d.revision,'design',d.design);
END $fn$;
-- Both existing export paths already hash this shared snapshot. Extend it without changing card tokens.
ALTER FUNCTION ironvault_private.physical_id_snapshot_055(text,text) RENAME TO physical_id_snapshot_057_base;
CREATE FUNCTION ironvault_private.physical_id_snapshot_055(p_tenant text,p_member text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.physical_id_snapshot_057_base(p_tenant,p_member)||jsonb_build_object('design',coalesce(d.design,'{}'),'design_revision',coalesce(d.revision,0)) FROM (SELECT 1) x LEFT JOIN ironvault_private.physical_id_designs d ON d.tenant_id=p_tenant;
$fn$;
ALTER FUNCTION public.iv_physical_ids(text,text,jsonb) RENAME TO physical_ids_057_base;
ALTER FUNCTION public.physical_ids_057_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_physical_ids(p_tenant text,p_action text DEFAULT 'requests',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;
BEGIN
 result:=ironvault_private.physical_ids_057_base(p_tenant,p_action,p_data);
 IF p_action IN ('preview','loss') THEN result:=result||jsonb_build_object('appearance_version',4,'permissions',coalesce(result->'permissions','{}')||jsonb_build_object('design',ironvault_private.card_design_owner_057(p_tenant) AND NOT coalesce((result->>'security_only')::boolean,false)));END IF;
 RETURN result;
END $fn$;
ALTER FUNCTION public.iv_physical_id_action(text,text,jsonb) RENAME TO physical_id_action_057_base;
ALTER FUNCTION public.physical_id_action_057_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_physical_id_action(p_tenant text,p_action text,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 -- Serialize design saves and production authorization; underlying admission/member locks stay unchanged.
 IF p_action IN ('download','download_direct') THEN IF p_data->>'appearance_version' IS DISTINCT FROM '4' THEN RAISE EXCEPTION 'Refresh the Physical ID screen before downloading the current design';END IF;PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant,57));END IF;
 RETURN ironvault_private.physical_id_action_057_base(p_tenant,p_action,p_data);
END $fn$;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='ironvault_private' AND p.proname IN ('card_design_owner_057','card_background_access_057','physical_id_snapshot_057_base','physical_id_snapshot_055','physical_ids_057_base','physical_id_action_057_base')) OR (n.nspname='public' AND p.proname IN ('iv_physical_id_design','iv_physical_ids','iv_physical_id_action')) LOOP
 EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO postgres',f.nspname,f.proname,f.args);
 EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',f.nspname,f.proname,f.args);
 IF f.nspname='public' OR f.proname='card_background_access_057' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated',f.nspname,f.proname,f.args);END IF;
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
