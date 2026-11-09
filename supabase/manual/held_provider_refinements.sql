-- MANUAL ONLY after 051. No financial records, receipts or subscription periods are rewritten.
BEGIN;
DO $guard$ DECLARE source text;old text;replacement text;BEGIN
 IF to_regclass('ironvault_private.service_publications_051') IS NULL THEN RAISE EXCEPTION 'Apply 051 first';END IF;
 IF to_regprocedure('ironvault_private.subscription_portal_052_base(text,text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION '052 already installed';END IF;
 source:=pg_get_functiondef('public.iv_subscription_manage(text,text,jsonb)'::regprocedure);
 old:='SELECT r.*,g.gym_name,nullif(ironvault_private.subscription_state(r.tenant_id)->>''end_date'','''')::date AS expiry FROM ironvault_private.subscription_intents r JOIN public.owners g ON g.id=r.tenant_id WHERE r.status IN (''pending'',''returned'')';
 replacement:='SELECT queue_row.*,g.gym_name,nullif(ironvault_private.subscription_state(queue_row.tenant_id)->>''end_date'','''')::date AS expiry FROM ironvault_private.subscription_intents queue_row JOIN public.owners g ON g.id=queue_row.tenant_id WHERE queue_row.status IN (''pending'',''returned'')';
 IF position(old IN source)=0 THEN RAISE EXCEPTION 'Unexpected pending-list function; review before applying';END IF;
 EXECUTE replace(source,old,replacement);
END $guard$;
ALTER FUNCTION public.iv_subscription_portal(text,text,jsonb) RENAME TO subscription_portal_052_base;
ALTER FUNCTION public.subscription_portal_052_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE output jsonb;latest uuid;owner_id_value uuid;BEGIN
 IF p_action='accept' THEN
  IF NOT ironvault_private.subscription_owner(p_tenant) THEN RAISE EXCEPTION 'Registered owner required' USING ERRCODE='42501';END IF;
  -- Serialize publication with acceptance, so an old selection cannot race a new publication.
  PERFORM 1 FROM ironvault_private.service_settings WHERE id=true FOR SHARE;
  latest:=ironvault_private.service_current();
  IF (p_data->>'version_id')::uuid IS DISTINCT FROM latest THEN RAISE EXCEPTION 'Only the latest published agreement can be accepted. Reopen the documents.';END IF;
 END IF;
 output:=ironvault_private.subscription_portal_052_base(p_tenant,p_action,p_data);
 IF p_action='get' AND ironvault_private.subscription_owner(p_tenant) THEN
  latest:=ironvault_private.service_current();SELECT owner_id INTO owner_id_value FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant;
  output:=output||jsonb_build_object('acceptance_version',latest,'documents',coalesce((SELECT jsonb_agg(doc.value ORDER BY (doc.value->>'id'=latest::text) DESC,publication.publication_order DESC) FROM jsonb_array_elements(output->'documents') doc JOIN ironvault_private.service_publications_051 publication ON publication.version_id=(doc.value->>'id')::uuid WHERE publication.version_id=latest OR ironvault_private.owner_agreement_valid(p_tenant,owner_id_value,publication.version_id)),'[]'));
 END IF;RETURN output;
END $fn$;
-- Cleanup only unused, explicitly selected test publications. No cascade deletion.
CREATE TABLE ironvault_private.service_cleanup_audit_052(request_id uuid PRIMARY KEY,version_id uuid NOT NULL,version_label text,provider_id uuid NOT NULL,deleted_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE ironvault_private.service_cleanup_audit_052 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.service_cleanup_audit_052 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.service_cleanup_preview_052(p_version uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v ironvault_private.service_versions%ROWTYPE;c record;amount bigint;refs jsonb:='[]';latest uuid;gyms jsonb;BEGIN
 SELECT * INTO STRICT v FROM ironvault_private.service_versions WHERE id=p_version;
 latest:=ironvault_private.service_current();
 -- Discover FK dependencies as well as known JSON snapshots. Unknown new dependencies block deletion.
 FOR c IN SELECT ns.nspname,cl.relname,att.attname FROM pg_constraint fk JOIN pg_class cl ON cl.oid=fk.conrelid JOIN pg_namespace ns ON ns.oid=cl.relnamespace JOIN pg_attribute att ON att.attrelid=fk.conrelid AND att.attnum=fk.conkey[1] WHERE fk.contype='f' AND fk.confrelid='ironvault_private.service_versions'::regclass AND NOT (ns.nspname='ironvault_private' AND cl.relname IN ('service_publications_051','service_drafts_051')) LOOP
  EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I=$1',c.nspname,c.relname,c.attname) INTO amount USING p_version;
  IF amount>0 THEN refs:=refs||jsonb_build_array(jsonb_build_object('source',c.relname,'count',amount));END IF;
 END LOOP;
 FOR c IN SELECT table_name,column_name FROM information_schema.columns WHERE table_schema='ironvault_private' AND data_type='jsonb' AND table_name IN ('subscription_requests','subscription_intents','subscription_transactions','subscription_previews','subscription_events') LOOP
  EXECUTE format('SELECT count(*) FROM ironvault_private.%I WHERE %I::text LIKE $1',c.table_name,c.column_name) INTO amount USING '%'||p_version::text||'%';
  IF amount>0 THEN refs:=refs||jsonb_build_array(jsonb_build_object('source',c.table_name||'.'||c.column_name,'count',amount));END IF;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',g.id,'name',g.gym_name,'is_test',subscription.is_test) ORDER BY g.gym_name),'[]') INTO gyms FROM public.owners g JOIN ironvault_private.gym_subscriptions subscription ON subscription.tenant_id=g.id WHERE
 EXISTS(SELECT 1 FROM ironvault_private.service_acceptances a WHERE a.tenant_id=g.id AND a.version_id=p_version) OR
 EXISTS(SELECT 1 FROM ironvault_private.service_baselines_051 b WHERE b.tenant_id=g.id AND b.version_id=p_version) OR
 EXISTS(SELECT 1 FROM ironvault_private.service_transitions_051 t WHERE t.tenant_id=g.id AND t.version_id=p_version) OR
 EXISTS(SELECT 1 FROM ironvault_private.subscription_periods p WHERE p.tenant_id=g.id AND p.version_id=p_version) OR
 EXISTS(SELECT 1 FROM ironvault_private.subscription_requests r WHERE r.tenant_id=g.id AND r.quote::text LIKE '%'||p_version::text||'%') OR
 EXISTS(SELECT 1 FROM ironvault_private.subscription_intents r WHERE r.tenant_id=g.id AND r.quote::text LIKE '%'||p_version::text||'%') OR
 EXISTS(SELECT 1 FROM ironvault_private.subscription_transactions t WHERE t.tenant_id=g.id AND t.snapshot::text LIKE '%'||p_version::text||'%');
 RETURN jsonb_build_object('id',v.id,'version_label',v.version_label,'published_at',v.published_at,'latest',v.id=latest,'references',refs,'gyms',gyms,'eligible',v.id<>latest AND jsonb_array_length(refs)=0,'review_hash',md5(to_jsonb(v)::text||refs::text||coalesce(latest::text,'')));
END $fn$;
CREATE FUNCTION public.iv_service_cleanup(p_action text DEFAULT 'list',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;v uuid;rid uuid;old ironvault_private.service_cleanup_audit_052%ROWTYPE;BEGIN
 PERFORM ironvault_private.service_admin_051();
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>5000 THEN RAISE EXCEPTION 'Invalid cleanup input';END IF;
 IF p_action='list' THEN RETURN jsonb_build_object('versions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',sv.id,'version_label',sv.version_label,'published_at',sv.published_at) ORDER BY publication.publication_order DESC) FROM ironvault_private.service_versions sv JOIN ironvault_private.service_publications_051 publication ON publication.version_id=sv.id),'[]'));END IF;
 IF p_action NOT IN ('preview','delete') THEN RAISE EXCEPTION 'Invalid cleanup action';END IF;
 v:=(p_data->>'id')::uuid;rid:=nullif(p_data->>'request_id','')::uuid;
 IF p_action='delete' THEN
  IF rid IS NULL OR p_data->>'confirmed' IS DISTINCT FROM 'true' OR p_data->>'test_publication' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Explicit test publication and deletion confirmation required';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('service-cleanup:'||rid::text,52));
  SELECT * INTO old FROM ironvault_private.service_cleanup_audit_052 WHERE request_id=rid;
  IF FOUND THEN IF old.version_id<>v THEN RAISE EXCEPTION 'Cleanup retry changed';END IF;RETURN jsonb_build_object('deleted',true,'id',v,'replayed',true);END IF;
  -- Lock referenced tables in a consistent order. Prevent approval/publication/registration racing preview/deletion.
  LOCK TABLE ironvault_private.service_settings IN SHARE ROW EXCLUSIVE MODE;
  PERFORM 1 FROM ironvault_private.service_versions WHERE id=v FOR UPDATE;
 END IF;
 result:=ironvault_private.service_cleanup_preview_052(v);
 IF p_action='preview' THEN RETURN result;END IF;
 IF result->>'eligible' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Protected publication: latest or referenced records cannot be deleted. Test-gym references require a separately approved cleanup.';END IF;
 IF result->>'review_hash' IS DISTINCT FROM p_data->>'review_hash' THEN RAISE EXCEPTION 'Publication changed; preview again';END IF;
 -- Retain the private source draft, hidden from normal editing, and the non-content cleanup audit.
 UPDATE ironvault_private.service_drafts_051 SET legacy_data=coalesce(legacy_data,'{}')||jsonb_build_object('deleted_test_publication',v),published_id=NULL,deleted_at=coalesce(deleted_at,clock_timestamp()) WHERE published_id=v;
 INSERT INTO ironvault_private.service_cleanup_audit_052(request_id,version_id,version_label,provider_id) VALUES(rid,v,result->>'version_label',auth.uid());
 DELETE FROM ironvault_private.service_publications_051 WHERE version_id=v;
 DELETE FROM ironvault_private.service_versions WHERE id=v;
 RETURN jsonb_build_object('deleted',true,'id',v);
END $fn$;
ALTER FUNCTION ironvault_private.subscription_portal_052_base(text,text,jsonb) OWNER TO postgres;
ALTER FUNCTION ironvault_private.service_cleanup_preview_052(uuid) OWNER TO postgres;
ALTER FUNCTION public.iv_service_cleanup(text,jsonb) OWNER TO postgres;
ALTER FUNCTION public.iv_subscription_portal(text,text,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.subscription_portal_052_base(text,text,jsonb),ironvault_private.service_cleanup_preview_052(uuid),public.iv_service_cleanup(text,jsonb),public.iv_subscription_portal(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_service_cleanup(text,jsonb),public.iv_subscription_portal(text,text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
