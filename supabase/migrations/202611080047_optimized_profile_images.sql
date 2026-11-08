-- MANUAL ONLY, once after 046. Run the entire file as one transaction.
-- Creates storage and reference/cleanup controls. No historical images or financial rows are rewritten.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_profile_images(text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION '047 already installed; do not reapply'; END IF;
 IF to_regprocedure('public.iv_restore_profiles(jsonb,jsonb)') IS NULL OR to_regprocedure('ironvault_private.subscription_require(text,text,uuid)') IS NULL OR to_regprocedure('public.iv_topup_review(text,text,numeric,uuid)') IS NULL THEN
  RAISE EXCEPTION 'Apply and confirm 046 and its prerequisites first'; END IF;
 IF EXISTS(SELECT 1 FROM storage.buckets WHERE id IN ('iv-gym-images','iv-member-images')) THEN RAISE EXCEPTION 'Image bucket already exists; inspect rather than overwrite'; END IF;
END $guard$;
CREATE TABLE ironvault_private.profile_images(
 id uuid PRIMARY KEY,tenant_id text NOT NULL,member_id text,kind text NOT NULL CHECK(kind IN ('gym','member')),
 actor_id uuid NOT NULL,state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','active','retired','removed')),
 base_hash text NOT NULL,content_hash text NOT NULL CHECK(content_hash ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),committed_at timestamptz,
 CHECK((kind='gym' AND member_id IS NULL) OR (kind='member' AND member_id IS NOT NULL))
);
-- No FK cascade: purge/deletion retires files into a durable cleanup queue instead of orphaning them.
CREATE INDEX iv_profile_image_subject ON ironvault_private.profile_images(tenant_id,member_id,kind,state);
CREATE INDEX iv_profile_image_cleanup ON ironvault_private.profile_images(actor_id,state,created_at);
ALTER TABLE ironvault_private.profile_images ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.profile_images FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES
 ('iv-gym-images','iv-gym-images',true,524288,ARRAY['image/webp','image/png','image/jpeg']),
 ('iv-member-images','iv-member-images',false,65536,ARRAY['image/webp','image/jpeg']);

CREATE FUNCTION ironvault_private.image_reference(p_id uuid,p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $fn$
 SELECT CASE WHEN p_kind='member' THEN 'iv-photo:'||p_id::text ELSE
 'https://uarvhalocgyrikjbrloh.supabase.co/storage/v1/object/public/iv-gym-images/'||p_id::text||'/logo' END;
$fn$;
CREATE FUNCTION ironvault_private.image_access(p_tenant text,p_member text,p_kind text,p_write boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
 ((r.role='super_admin' AND r.tenant_id IS NULL AND EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant)) OR
 (p_kind='member' AND r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') AND
  EXISTS(SELECT 1 FROM public.members m WHERE m.id=p_member AND m.tenant_id=p_tenant AND
   ((r.role='member' AND r.member_id=m.id AND m.status='ACTIVE') OR (NOT p_write AND r.role IN ('owner','staff')))))));
$fn$;
CREATE FUNCTION ironvault_private.image_is_current(p_id uuid,p_tenant text,p_member text,p_kind text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT CASE WHEN p_kind='member' THEN EXISTS(SELECT 1 FROM public.members WHERE id=p_member AND tenant_id=p_tenant AND avatar=ironvault_private.image_reference(p_id,p_kind))
 ELSE EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND logo=ironvault_private.image_reference(p_id,p_kind)) END;
$fn$;
CREATE FUNCTION ironvault_private.image_cleanup_access(p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
 ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.user_id=p_actor AND r.role='member' AND EXISTS(SELECT 1 FROM public.owners WHERE id=r.tenant_id AND status='ACTIVE'))));
$fn$;
CREATE FUNCTION ironvault_private.image_storage_allowed(p_bucket text,p_name text,p_action text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE img ironvault_private.profile_images%ROWTYPE;filename text;
BEGIN
 IF auth.uid() IS NULL OR p_name !~ '^[a-f0-9-]{36}/(photo|logo|icon-192\.png|icon-512\.png|maskable-512\.png)$' THEN RETURN false; END IF;
 SELECT * INTO img FROM ironvault_private.profile_images WHERE id::text=split_part(p_name,'/',1);
 IF NOT FOUND OR p_bucket<>(CASE WHEN img.kind='gym' THEN 'iv-gym-images' ELSE 'iv-member-images' END) THEN RETURN false; END IF;
 filename:=split_part(p_name,'/',2);
 IF (img.kind='member' AND filename<>'photo') OR (img.kind='gym' AND filename NOT IN ('logo','icon-192.png','icon-512.png','maskable-512.png')) THEN RETURN false; END IF;
 IF p_action='insert' THEN RETURN img.state='pending' AND img.actor_id=auth.uid() AND img.created_at>clock_timestamp()-interval '1 hour' AND ironvault_private.image_access(img.tenant_id,img.member_id,img.kind,true); END IF;
 IF p_action='delete' THEN RETURN img.state='retired' AND ironvault_private.image_cleanup_access(img.actor_id) AND NOT ironvault_private.image_is_current(img.id,img.tenant_id,img.member_id,img.kind); END IF;
 IF p_action='select' THEN RETURN
  (img.state='active' AND ironvault_private.image_is_current(img.id,img.tenant_id,img.member_id,img.kind) AND ironvault_private.image_access(img.tenant_id,img.member_id,img.kind,false)) OR
  (img.state IN ('pending','retired') AND ironvault_private.image_cleanup_access(img.actor_id)); END IF;
 RETURN false;
END $fn$;
-- Restrictive boundaries also constrain any existing permissive storage policies.
CREATE POLICY iv_image_select ON storage.objects FOR SELECT TO authenticated USING(bucket_id IN ('iv-gym-images','iv-member-images') AND ironvault_private.image_storage_allowed(bucket_id,name,'select'));
CREATE POLICY iv_image_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id IN ('iv-gym-images','iv-member-images') AND ironvault_private.image_storage_allowed(bucket_id,name,'insert'));
CREATE POLICY iv_image_delete ON storage.objects FOR DELETE TO authenticated USING(bucket_id IN ('iv-gym-images','iv-member-images') AND ironvault_private.image_storage_allowed(bucket_id,name,'delete'));
CREATE POLICY iv_image_read_boundary ON storage.objects AS RESTRICTIVE FOR SELECT TO anon,authenticated USING(bucket_id NOT IN ('iv-gym-images','iv-member-images') OR ironvault_private.image_storage_allowed(bucket_id,name,'select'));
CREATE POLICY iv_image_insert_boundary ON storage.objects AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK(bucket_id NOT IN ('iv-gym-images','iv-member-images') OR ironvault_private.image_storage_allowed(bucket_id,name,'insert'));
CREATE POLICY iv_image_update_boundary ON storage.objects AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING(bucket_id NOT IN ('iv-gym-images','iv-member-images')) WITH CHECK(bucket_id NOT IN ('iv-gym-images','iv-member-images'));
CREATE POLICY iv_image_delete_boundary ON storage.objects AS RESTRICTIVE FOR DELETE TO anon,authenticated USING(bucket_id NOT IN ('iv-gym-images','iv-member-images') OR ironvault_private.image_storage_allowed(bucket_id,name,'delete'));

CREATE FUNCTION ironvault_private.image_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE field text;old_value text;new_value text;subject text;tenant text;img ironvault_private.profile_images%ROWTYPE;
BEGIN
 IF TG_TABLE_NAME='members' THEN field:='avatar';subject:=coalesce(NEW.id,OLD.id);tenant:=coalesce(NEW.tenant_id,OLD.tenant_id);
 ELSE field:='logo';tenant:=coalesce(NEW.id,OLD.id); END IF;
 old_value:=CASE WHEN TG_OP='INSERT' THEN '' ELSE coalesce(to_jsonb(OLD)->>field,'') END;
 new_value:=CASE WHEN TG_OP='DELETE' THEN '' ELSE coalesce(to_jsonb(NEW)->>field,'') END;
 IF TG_OP='UPDATE' AND old_value=new_value THEN RETURN NEW; END IF;
 IF TG_OP<>'DELETE' THEN
  IF new_value LIKE 'iv-photo:%' OR position('/storage/v1/object/public/iv-gym-images/' IN new_value)>0 THEN
   SELECT * INTO img FROM ironvault_private.profile_images WHERE tenant_id=tenant AND member_id IS NOT DISTINCT FROM subject AND state='active' AND ironvault_private.image_reference(id,kind)=new_value;
   IF NOT FOUND THEN RAISE EXCEPTION 'Stored image is unavailable or belongs to another profile'; END IF;
  ELSIF current_setting('ironvault.image_restore',true) IS DISTINCT FROM 'on' AND EXISTS(
   SELECT 1 FROM ironvault_private.profile_images WHERE tenant_id=tenant AND member_id IS NOT DISTINCT FROM subject AND state='active' AND ironvault_private.image_reference(id,kind)=old_value) THEN
   RAISE EXCEPTION 'Photo changed; refresh this profile before saving. Use image replacement or explicit backup restore';
  END IF;
 END IF;
 UPDATE ironvault_private.profile_images SET state='retired' WHERE tenant_id=tenant AND member_id IS NOT DISTINCT FROM subject AND state='active' AND ironvault_private.image_reference(id,kind)=old_value AND old_value<>new_value;
 IF TG_OP='DELETE' AND TG_TABLE_NAME='owners' THEN UPDATE ironvault_private.profile_images SET state='retired' WHERE tenant_id=tenant; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $fn$;
CREATE TRIGGER iv_member_image_guard BEFORE INSERT OR UPDATE OF avatar OR DELETE ON public.members FOR EACH ROW EXECUTE FUNCTION ironvault_private.image_guard();
CREATE TRIGGER iv_gym_image_guard BEFORE INSERT OR UPDATE OF logo OR DELETE ON public.owners FOR EACH ROW EXECUTE FUNCTION ironvault_private.image_guard();

CREATE FUNCTION public.iv_profile_images(p_action text,p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE img ironvault_private.profile_images%ROWTYPE;request uuid;tenant text;member text;kind text;current_value text;expected text;checksum text;filename text;bucket text;obj storage.objects%ROWTYPE;result jsonb;files text[];
BEGIN
 IF auth.uid() IS NULL OR jsonb_typeof(p_payload)<>'object' OR p_action NOT IN ('reserve','commit','status','cancel','cleanup','ack') THEN RAISE EXCEPTION 'Not authorized'; END IF;
 IF p_action='cleanup' THEN
  IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND enabled AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  DELETE FROM ironvault_private.profile_images WHERE state='removed' AND created_at<clock_timestamp()-interval '1 day' AND ironvault_private.image_cleanup_access(actor_id);
  UPDATE ironvault_private.profile_images i SET state='retired' WHERE state='pending' AND created_at<clock_timestamp()-interval '1 hour' AND ironvault_private.image_cleanup_access(actor_id) AND NOT ironvault_private.image_is_current(i.id,i.tenant_id,i.member_id,i.kind);
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',q.id,'kind',q.kind,'bucket',CASE WHEN q.kind='gym' THEN 'iv-gym-images' ELSE 'iv-member-images' END,'files',CASE WHEN q.kind='gym' THEN ARRAY[q.id::text||'/logo',q.id::text||'/icon-192.png',q.id::text||'/icon-512.png',q.id::text||'/maskable-512.png'] ELSE ARRAY[q.id::text||'/photo'] END)),'[]'::jsonb) INTO result FROM
   (SELECT * FROM ironvault_private.profile_images i WHERE state='retired' AND ironvault_private.image_cleanup_access(actor_id) AND NOT ironvault_private.image_is_current(i.id,i.tenant_id,i.member_id,i.kind) ORDER BY created_at LIMIT 20) q;
  RETURN result;
 END IF;
 request:=(p_payload->>'request_id')::uuid;
 IF request IS NULL THEN RAISE EXCEPTION 'Image request required'; END IF;
 IF p_action='reserve' THEN
  tenant:=p_payload->>'tenant_id';member:=nullif(p_payload->>'member_id','');kind:=p_payload->>'kind';expected:=p_payload->>'expected';checksum:=p_payload->>'checksum';
  IF kind IS NULL OR kind NOT IN ('member','gym') OR expected IS NULL OR length(expected)>750000 OR checksum IS NULL OR checksum !~ '^[a-f0-9]{64}$' OR (kind='gym' AND member IS NOT NULL) OR NOT ironvault_private.image_access(tenant,member,kind,true) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(request::text,47));
  SELECT * INTO img FROM ironvault_private.profile_images WHERE id=request;
  IF FOUND THEN
   IF img.actor_id<>auth.uid() OR img.kind<>kind OR img.tenant_id<>tenant OR img.member_id IS DISTINCT FROM member OR img.content_hash<>checksum OR img.base_hash<>md5(expected) THEN RAISE EXCEPTION 'Image request mismatch'; END IF;
   RETURN jsonb_build_object('id',img.id,'state',img.state,'reference',ironvault_private.image_reference(img.id,img.kind));
  END IF;
  IF kind='member' THEN SELECT avatar INTO current_value FROM public.members WHERE id=member AND tenant_id=tenant FOR UPDATE;
  ELSE SELECT logo INTO current_value FROM public.owners WHERE id=tenant FOR UPDATE; END IF;
  IF NOT FOUND OR coalesce(current_value,'')<>expected THEN RAISE EXCEPTION 'Photo changed; refresh before replacing it'; END IF;
  IF kind='member' THEN PERFORM ironvault_private.subscription_require(tenant,'portal'); END IF;
  IF (SELECT count(*) FROM ironvault_private.profile_images WHERE actor_id=auth.uid() AND created_at>clock_timestamp()-interval '10 minutes')>=30 THEN RAISE EXCEPTION 'Too many image uploads; try again later'; END IF;
  INSERT INTO ironvault_private.profile_images(id,tenant_id,member_id,kind,actor_id,base_hash,content_hash) VALUES(request,tenant,member,kind,auth.uid(),md5(expected),checksum) RETURNING * INTO img;
 ELSE
  -- Subject-row-before-job lock order matches image_guard to avoid a commit/restore deadlock.
  SELECT * INTO img FROM ironvault_private.profile_images WHERE id=request;
  IF NOT FOUND THEN RAISE EXCEPTION 'Image request unavailable'; END IF;
  IF p_action='ack' THEN
   IF img.state<>'retired' OR NOT ironvault_private.image_cleanup_access(img.actor_id) OR ironvault_private.image_is_current(img.id,img.tenant_id,img.member_id,img.kind) THEN RAISE EXCEPTION 'Not authorized'; END IF;
   IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id IN ('iv-gym-images','iv-member-images') AND split_part(name,'/',1)=img.id::text) THEN RAISE EXCEPTION 'Image files still require cleanup'; END IF;
   UPDATE ironvault_private.profile_images SET state='removed' WHERE id=img.id AND state='retired';RETURN jsonb_build_object('removed',true);
  END IF;
  IF img.actor_id<>auth.uid() OR NOT ironvault_private.image_access(img.tenant_id,img.member_id,img.kind,true) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF img.kind='member' THEN SELECT avatar INTO current_value FROM public.members WHERE id=img.member_id AND tenant_id=img.tenant_id FOR UPDATE;
  ELSE SELECT logo INTO current_value FROM public.owners WHERE id=img.tenant_id FOR UPDATE; END IF;
  SELECT * INTO STRICT img FROM ironvault_private.profile_images WHERE id=request FOR UPDATE;
  IF p_action='status' THEN RETURN jsonb_build_object('id',img.id,'state',img.state,'reference',ironvault_private.image_reference(img.id,img.kind)); END IF;
  IF p_action='cancel' THEN
   IF img.state='active' THEN RAISE EXCEPTION 'Saved image cannot be cancelled'; END IF;
   UPDATE ironvault_private.profile_images SET state='retired' WHERE id=img.id;RETURN jsonb_build_object('state','retired');
  END IF;
 END IF;
 IF p_action='reserve' THEN RETURN jsonb_build_object('id',img.id,'state',img.state,'reference',ironvault_private.image_reference(img.id,img.kind)); END IF;
 IF img.state='active' AND ironvault_private.image_is_current(img.id,img.tenant_id,img.member_id,img.kind) THEN RETURN jsonb_build_object('state','active','reference',ironvault_private.image_reference(img.id,img.kind)); END IF;
 IF img.state<>'pending' OR img.created_at<clock_timestamp()-interval '1 hour' THEN RAISE EXCEPTION 'Image request expired; refresh and try again'; END IF;
 IF md5(coalesce(current_value,''))<>img.base_hash THEN RAISE EXCEPTION 'Photo changed; refresh before replacing it'; END IF;
 IF img.kind='member' THEN PERFORM ironvault_private.subscription_require(img.tenant_id,'portal'); END IF;
 bucket:=CASE WHEN img.kind='gym' THEN 'iv-gym-images' ELSE 'iv-member-images' END;
 files:=CASE WHEN img.kind='gym' THEN ARRAY['logo','icon-192.png','icon-512.png','maskable-512.png'] ELSE ARRAY['photo'] END;
 FOREACH filename IN ARRAY files LOOP
  SELECT * INTO obj FROM storage.objects WHERE bucket_id=bucket AND name=img.id::text||'/'||filename FOR SHARE;
  IF NOT FOUND OR coalesce(obj.metadata->>'size','') !~ '^[0-9]{1,9}$' THEN RAISE EXCEPTION 'Image upload incomplete'; END IF;
  IF (obj.metadata->>'size')::bigint NOT BETWEEN 1 AND (CASE WHEN img.kind='member' THEN 65536 WHEN filename='logo' THEN 131072 ELSE 524288 END) OR
   (filename LIKE '%.png' AND obj.metadata->>'mimetype' IS DISTINCT FROM 'image/png') OR
   (filename='photo' AND coalesce(obj.metadata->>'mimetype','') NOT IN ('image/webp','image/jpeg')) OR
   (filename='logo' AND coalesce(obj.metadata->>'mimetype','') NOT IN ('image/webp','image/png','image/jpeg')) THEN RAISE EXCEPTION 'Invalid uploaded image'; END IF;
 END LOOP;
 UPDATE ironvault_private.profile_images SET state='active',committed_at=clock_timestamp() WHERE id=img.id;
 IF img.kind='member' THEN PERFORM public.iv_save_member_profiles(jsonb_build_array(jsonb_build_object('id',img.member_id,'tenant_id',img.tenant_id,'avatar',ironvault_private.image_reference(img.id,img.kind))));
 ELSE PERFORM public.iv_save_gym_settings(jsonb_build_array(jsonb_build_object('id',img.tenant_id,'logo',ironvault_private.image_reference(img.id,img.kind)))); END IF;
 RETURN jsonb_build_object('state','active','reference',ironvault_private.image_reference(img.id,img.kind));
END $fn$;
-- Explicit backup restoration can replace a managed image with the embedded legacy image.
-- The original restore engine retains all of its existing authorization and business rules.
ALTER FUNCTION public.iv_restore_profiles(jsonb,jsonb) SET SCHEMA ironvault_private;
ALTER FUNCTION ironvault_private.iv_restore_profiles(jsonb,jsonb) RENAME TO restore_profiles_047_base;
CREATE FUNCTION public.iv_restore_profiles(p_gyms jsonb,p_members jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE prior text:=current_setting('ironvault.image_restore',true);
BEGIN
 PERFORM set_config('ironvault.image_restore','on',true);
 PERFORM ironvault_private.restore_profiles_047_base(p_gyms,p_members);
 PERFORM set_config('ironvault.image_restore',coalesce(prior,''),true);
END $fn$;
ALTER FUNCTION ironvault_private.image_reference(uuid,text) OWNER TO postgres;
ALTER FUNCTION ironvault_private.image_access(text,text,text,boolean) OWNER TO postgres;
ALTER FUNCTION ironvault_private.image_is_current(uuid,text,text,text) OWNER TO postgres;
ALTER FUNCTION ironvault_private.image_cleanup_access(uuid) OWNER TO postgres;
ALTER FUNCTION ironvault_private.image_storage_allowed(text,text,text) OWNER TO postgres;
ALTER FUNCTION ironvault_private.image_guard() OWNER TO postgres;
ALTER FUNCTION public.iv_profile_images(text,jsonb) OWNER TO postgres;
ALTER FUNCTION public.iv_restore_profiles(jsonb,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.image_reference(uuid,text),ironvault_private.image_access(text,text,text,boolean),ironvault_private.image_is_current(uuid,text,text,text),ironvault_private.image_cleanup_access(uuid),ironvault_private.image_storage_allowed(text,text,text),ironvault_private.image_guard(),ironvault_private.restore_profiles_047_base(jsonb,jsonb),public.iv_profile_images(text,jsonb),public.iv_restore_profiles(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA ironvault_private TO authenticated;
GRANT EXECUTE ON FUNCTION ironvault_private.image_storage_allowed(text,text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iv_profile_images(text,jsonb),public.iv_restore_profiles(jsonb,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
