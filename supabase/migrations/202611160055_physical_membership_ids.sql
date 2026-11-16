-- MANUAL ONLY after 054 and its prerequisites. Install definitions, not live requests.
-- Existing QR tokens, admissions, balances, payments and memberships are preserved.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_approve_entry_qr(text,text)') IS NULL OR to_regclass('ironvault_private.member_cards') IS NULL THEN RAISE EXCEPTION 'Apply and confirm Stage 1 SQL 054 first';END IF;
 IF to_regclass('ironvault_private.physical_id_requests') IS NOT NULL THEN RAISE EXCEPTION '055 already installed; do not reapply';END IF;
END $guard$;
ALTER TABLE ironvault_private.member_cards ADD COLUMN card_id uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE ironvault_private.member_cards ADD COLUMN version integer;
WITH ordered AS (SELECT token,row_number() OVER(PARTITION BY member_id ORDER BY created_at,token)::integer n FROM ironvault_private.member_cards)
 UPDATE ironvault_private.member_cards c SET version=o.n FROM ordered o WHERE o.token=c.token;
ALTER TABLE ironvault_private.member_cards ALTER COLUMN version SET DEFAULT 1;
ALTER TABLE ironvault_private.member_cards ALTER COLUMN version SET NOT NULL;
ALTER TABLE ironvault_private.member_cards ADD CONSTRAINT physical_card_id_unique UNIQUE(card_id);
ALTER TABLE ironvault_private.member_cards ADD CONSTRAINT physical_card_scope_unique UNIQUE(tenant_id,member_id,card_id);
ALTER TABLE ironvault_private.member_cards ADD CONSTRAINT physical_card_version_unique UNIQUE(member_id,version);
ALTER TABLE ironvault_private.member_cards ADD COLUMN replaces_card_id uuid REFERENCES ironvault_private.member_cards(card_id) ON DELETE SET NULL;
ALTER TABLE ironvault_private.member_cards ADD COLUMN revoked_by uuid;
ALTER TABLE ironvault_private.member_cards ADD COLUMN revocation_reason text;
CREATE TABLE ironvault_private.physical_id_requests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,card_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('initial','replacement')),
 status text NOT NULL DEFAULT 'awaiting_gym_review' CHECK(status IN ('awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection','issued','rejected','cancelled','obsolete')),
 route text CHECK(route IN ('local','provider')),revision bigint NOT NULL DEFAULT 1,requested_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),decision_note text NOT NULL DEFAULT '',
 FOREIGN KEY(tenant_id,member_id,card_id) REFERENCES ironvault_private.member_cards(tenant_id,member_id,card_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX physical_id_one_active_request ON ironvault_private.physical_id_requests(tenant_id,member_id)
 WHERE status IN ('awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection');
CREATE INDEX physical_id_queue ON ironvault_private.physical_id_requests(tenant_id,updated_at DESC,id);
CREATE TABLE ironvault_private.physical_id_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,card_id uuid NOT NULL,request_id uuid REFERENCES ironvault_private.physical_id_requests(id) ON DELETE CASCADE,
 actor_id uuid NOT NULL,action text NOT NULL,data jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tenant_id,member_id,card_id) REFERENCES ironvault_private.member_cards(tenant_id,member_id,card_id) ON DELETE CASCADE
);
CREATE TABLE ironvault_private.physical_id_operations(
 id uuid PRIMARY KEY,actor_id uuid NOT NULL,tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,action text NOT NULL,payload_hash text NOT NULL,result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE ironvault_private.physical_id_notices(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,request_id uuid REFERENCES ironvault_private.physical_id_requests(id) ON DELETE CASCADE,
 recipient_id uuid NOT NULL,audience text NOT NULL CHECK(audience IN ('gym','member','provider')),event_key text NOT NULL,
 title text NOT NULL,body text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),read_at timestamptz,resolved_at timestamptz,
 UNIQUE(recipient_id,event_key)
);
CREATE INDEX physical_id_inbox ON ironvault_private.physical_id_notices(recipient_id,created_at DESC);

CREATE FUNCTION ironvault_private.physical_id_authority_055(p_tenant text,p_member text DEFAULT NULL,p_permission text DEFAULT NULL,p_security boolean DEFAULT false)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE r public.iv_user_roles%ROWTYPE;
BEGIN
 IF ironvault_private.subscription_super() THEN RETURN 'provider';END IF;
 SELECT * INTO r FROM public.iv_user_roles WHERE user_id=auth.uid() AND tenant_id=p_tenant AND enabled AND disabled_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Physical ID access denied' USING ERRCODE='42501';END IF;
 IF r.role='member' THEN
  IF p_permission IS NOT NULL OR p_member IS NULL OR r.member_id IS DISTINCT FROM p_member OR NOT ironvault_private.is_own_membership(p_member,p_tenant) THEN RAISE EXCEPTION 'Physical ID access denied' USING ERRCODE='42501';END IF;
  RETURN 'member';
 END IF;
 IF r.role='owner' AND p_security THEN RETURN 'owner';END IF;
 PERFORM ironvault_private.qr_staff_require_054(p_tenant);
 IF p_permission IS NOT NULL AND NOT ironvault_private.staff_has_permission(p_tenant,p_permission) THEN RAISE EXCEPTION 'Permission required: %',p_permission USING ERRCODE='42501';END IF;
 RETURN r.role;
END $fn$;
CREATE FUNCTION ironvault_private.physical_id_production_055(p_tenant text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE')
 OR NOT coalesce((ironvault_private.subscription_state(p_tenant)->>'operations')::boolean,false)
 OR NOT coalesce((ironvault_private.subscription_state(p_tenant)->>'portal')::boolean,false) THEN
 RAISE EXCEPTION 'Current operations and member portal access are required for physical card production' USING ERRCODE='42501';END IF;
END $fn$;
CREATE FUNCTION ironvault_private.physical_id_snapshot_055(p_tenant text,p_member text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('tenant_id',g.id,'member_id',m.id,'card_id',c.card_id,'version',c.version,'payload','IVC1|'||c.token::text,
 'member',jsonb_build_object('id',m.id,'name',m.name,'display_code',m.display_code,'photo',m.avatar,'status',m.status),
 'gym',jsonb_build_object('name',g.gym_name,'logo',g.logo,'accent',g.accent_color,'address',v.data->>'address','email',v.data->>'public_email','phone',v.data->>'phone'))
 FROM public.members m JOIN public.owners g ON g.id=m.tenant_id JOIN ironvault_private.member_cards c ON c.member_id=m.id AND c.tenant_id=m.tenant_id AND c.revoked_at IS NULL
 LEFT JOIN ironvault_private.legal_settings s ON s.scope=g.id LEFT JOIN ironvault_private.legal_versions v ON v.id=s.current_version AND v.scope=g.id
 WHERE m.id=p_member AND m.tenant_id=p_tenant AND m.status IN ('ACTIVE','PENDING');
$fn$;
CREATE FUNCTION public.iv_physical_ids(p_tenant text,p_action text DEFAULT 'requests',p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE role_name text;member_key text:=p_data->>'member_id';result jsonb;page_number integer:=coalesce((p_data->>'page')::integer,0);q text:=lower(btrim(coalesce(p_data->>'search','')));
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>20000 OR page_number<0 OR page_number>100000 OR length(q)>160 THEN RAISE EXCEPTION 'Invalid physical ID query';END IF;
 IF p_action='gyms' THEN
  IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Provider required' USING ERRCODE='42501';END IF;
  RETURN jsonb_build_object('items',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'name',gym_name,'display_code',display_code) ORDER BY gym_name,id) FROM public.owners),'[]'::jsonb));
 END IF;
 role_name:=ironvault_private.physical_id_authority_055(p_tenant,member_key,NULL,(p_action IN ('requests','history','loss') OR (p_action='members' AND p_data->>'security'='true')));
 IF p_action='members' THEN
  IF role_name='member' THEN RAISE EXCEPTION 'Gym account required' USING ERRCODE='42501';END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) INTO result FROM (
   SELECT m.id,m.name,m.display_code,m.status FROM public.members m WHERE m.tenant_id=p_tenant AND m.status IN ('ACTIVE','PENDING')
   AND (q='' OR position(q in lower(m.name))>0 OR position(q in lower(m.display_code))>0)
   ORDER BY m.name,m.id LIMIT 51 OFFSET page_number*50) x;
  RETURN jsonb_build_object('items',result);
 ELSIF p_action='loss' THEN
  IF role_name NOT IN ('owner','provider') THEN RAISE EXCEPTION 'Owner security access required' USING ERRCODE='42501';END IF;
  SELECT jsonb_build_object('tenant_id',p_tenant,'member_id',m.id,'card_id',c.card_id,'version',c.version,'role',role_name,'security_only',true,
   'member',jsonb_build_object('id',m.id,'name',m.name,'display_code',m.display_code),'permissions',jsonb_build_object('replace',true)) INTO result
   FROM public.members m JOIN ironvault_private.member_cards c ON c.member_id=m.id AND c.tenant_id=m.tenant_id AND c.revoked_at IS NULL WHERE m.id=member_key AND m.tenant_id=p_tenant;
  IF result IS NULL THEN RAISE EXCEPTION 'Card unavailable';END IF;RETURN result;
 ELSIF p_action='preview' THEN
  result:=ironvault_private.physical_id_snapshot_055(p_tenant,member_key);
  IF result IS NULL THEN RAISE EXCEPTION 'Physical ID unavailable';END IF;
  RETURN result||jsonb_build_object('snapshot_hash',md5(result::text),'role',role_name,'permissions',jsonb_build_object(
   'manage',role_name IN ('owner','provider') OR (role_name='staff' AND ironvault_private.staff_has_permission(p_tenant,'physical_ids_manage')),
   'download',role_name IN ('owner','provider') OR (role_name='staff' AND ironvault_private.staff_has_permission(p_tenant,'physical_ids_download')),
   'replace',role_name IN ('member','owner','provider') OR (role_name='staff' AND ironvault_private.staff_has_permission(p_tenant,'physical_ids_manage') AND ironvault_private.staff_has_permission(p_tenant,'physical_ids_replace'))));
 ELSIF p_action='requests' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) INTO result FROM (
   SELECT r.*,m.name,m.display_code,c.version,c.revoked_at FROM ironvault_private.physical_id_requests r
   JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id JOIN ironvault_private.member_cards c ON c.card_id=r.card_id
   WHERE r.tenant_id=p_tenant AND (member_key IS NULL OR r.member_id=member_key)
   AND (role_name<>'provider' OR r.route='provider' OR member_key IS NOT NULL)
   AND (role_name<>'staff' OR ironvault_private.staff_has_permission(p_tenant,'physical_ids_manage') OR (ironvault_private.staff_has_permission(p_tenant,'physical_ids_download') AND r.route='local' AND r.status IN ('printing_locally','ready_for_collection','issued'))) ORDER BY r.updated_at DESC,r.id LIMIT 51 OFFSET page_number*50) x;
  RETURN jsonb_build_object('items',result,'role',role_name);
 ELSIF p_action='history' THEN
  IF role_name='member' OR member_key IS NULL THEN RAISE EXCEPTION 'Gym account required' USING ERRCODE='42501';END IF;
  IF role_name='staff' AND NOT ironvault_private.staff_has_permission(p_tenant,'physical_ids_manage') THEN RAISE EXCEPTION 'Physical ID management permission required' USING ERRCODE='42501';END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) INTO result FROM (SELECT e.id,e.card_id,c.version,e.request_id,e.actor_id,e.action,e.data,e.created_at
   FROM ironvault_private.physical_id_events e JOIN ironvault_private.member_cards c ON c.card_id=e.card_id
   WHERE e.tenant_id=p_tenant AND e.member_id=member_key ORDER BY e.created_at DESC,e.id LIMIT 100) x;
  RETURN jsonb_build_object('items',result);
 END IF;
 RAISE EXCEPTION 'Invalid physical ID query';
END $fn$;

CREATE FUNCTION ironvault_private.physical_id_notify_055(p_request uuid,p_key text,p_title text,p_body text,p_audience text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS $fn$
 INSERT INTO ironvault_private.physical_id_notices(tenant_id,member_id,request_id,recipient_id,audience,event_key,title,body)
 SELECT r.tenant_id,r.member_id,r.id,u.user_id,p_audience,p_key,p_title,p_body FROM ironvault_private.physical_id_requests r
 JOIN public.iv_user_roles u ON u.enabled AND u.disabled_at IS NULL AND
 ((p_audience='provider' AND u.role='super_admin' AND u.tenant_id IS NULL)
 OR (p_audience='member' AND u.role='member' AND u.tenant_id=r.tenant_id AND u.member_id=r.member_id)
 OR (p_audience='gym' AND u.tenant_id=r.tenant_id AND (u.role='owner' OR (u.role='staff' AND EXISTS(SELECT 1 FROM ironvault_private.staff_access a WHERE a.tenant_id=u.tenant_id AND a.user_id=u.user_id AND a.state='active' AND a.permissions->>'physical_ids_manage'='true')))))
 WHERE r.id=p_request ON CONFLICT(recipient_id,event_key) DO NOTHING;
$fn$;
CREATE FUNCTION public.iv_physical_id_action(p_tenant text,p_action text,p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE role_name text;member_key text;card ironvault_private.member_cards%ROWTYPE;previous_card uuid;new_card uuid;
 req ironvault_private.physical_id_requests%ROWTYPE;op ironvault_private.physical_id_operations%ROWTYPE;operation uuid;fingerprint text;result jsonb;snapshot jsonb;target text;event_id uuid:=gen_random_uuid();
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>20000 OR p_action IS NULL OR p_action NOT IN ('submit','replace','transition','download') THEN RAISE EXCEPTION 'Invalid physical ID action';END IF;
 operation:=(p_data->>'operation_id')::uuid;member_key:=p_data->>'member_id';
 IF operation IS NULL OR member_key IS NULL THEN RAISE EXCEPTION 'Member and retry identity required';END IF;
 PERFORM 1 FROM public.iv_user_roles WHERE user_id=auth.uid() FOR SHARE;
 role_name:=ironvault_private.physical_id_authority_055(p_tenant,member_key,CASE WHEN p_action='download' THEN 'physical_ids_download' WHEN p_action='transition' THEN 'physical_ids_manage' ELSE NULL END,p_action='replace');
 IF role_name='staff' AND p_action IN ('submit','replace') THEN PERFORM ironvault_private.staff_require(p_tenant,'physical_ids_manage');END IF;
 IF role_name='staff' AND p_action='replace' THEN PERFORM ironvault_private.staff_require(p_tenant,'physical_ids_replace');END IF;
 -- All mutation paths lock member, then card, then request. Admission uses the same order.
 PERFORM 1 FROM public.members WHERE id=member_key AND tenant_id=p_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Member unavailable';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(operation::text,55));
 fingerprint:=md5(p_tenant||p_action||p_data::text);
 SELECT * INTO op FROM ironvault_private.physical_id_operations WHERE id=operation;
 IF FOUND THEN
  IF op.actor_id<>auth.uid() OR op.tenant_id<>p_tenant OR op.member_id<>member_key OR op.action<>p_action OR op.payload_hash<>fingerprint THEN RAISE EXCEPTION 'Retry identity belongs to a different action';END IF;
  IF p_action='download' THEN
   PERFORM ironvault_private.physical_id_production_055(p_tenant);
   snapshot:=ironvault_private.physical_id_snapshot_055(p_tenant,member_key);
   IF snapshot IS NULL OR snapshot->>'card_id' IS DISTINCT FROM p_data->>'card_id' OR md5(snapshot::text) IS DISTINCT FROM p_data->>'snapshot_hash'
    OR NOT EXISTS(SELECT 1 FROM ironvault_private.physical_id_requests WHERE id=(p_data->>'request_id')::uuid AND card_id=(p_data->>'card_id')::uuid AND revision=(p_data->>'revision')::bigint AND status NOT IN ('obsolete','cancelled','rejected')) THEN RAISE EXCEPTION 'Download is obsolete. Refresh before exporting';END IF;
  END IF;
  RETURN op.result;
 END IF;
 SELECT * INTO card FROM ironvault_private.member_cards WHERE tenant_id=p_tenant AND member_id=member_key AND revoked_at IS NULL FOR UPDATE;
 IF NOT FOUND OR card.card_id IS DISTINCT FROM (p_data->>'card_id')::uuid THEN RAISE EXCEPTION 'Card changed. Refresh the preview';END IF;
 IF p_action IN ('submit','replace') THEN
  IF p_data->>'fee_ack' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Acknowledge the possible card fee';END IF;
  IF p_action='replace' THEN
   IF p_data->>'confirm_loss' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Confirm that the current card will stop working';END IF;
   previous_card:=card.card_id;
   UPDATE ironvault_private.member_cards SET revoked_at=clock_timestamp(),revoked_by=auth.uid(),revocation_reason='lost' WHERE card_id=previous_card;
   INSERT INTO ironvault_private.member_cards(member_id,tenant_id,version,replaces_card_id)
    VALUES(member_key,p_tenant,(SELECT max(version)+1 FROM ironvault_private.member_cards WHERE member_id=member_key),previous_card) RETURNING card_id INTO new_card;
   UPDATE ironvault_private.physical_id_requests SET status='obsolete',revision=revision+1,updated_at=clock_timestamp() WHERE tenant_id=p_tenant AND member_id=member_key AND status IN ('awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection');
   UPDATE ironvault_private.physical_id_notices SET resolved_at=clock_timestamp() WHERE tenant_id=p_tenant AND member_id=member_key AND resolved_at IS NULL;
   INSERT INTO ironvault_private.physical_id_events(tenant_id,member_id,card_id,actor_id,action,data) VALUES(p_tenant,member_key,new_card,auth.uid(),'lost_card_replaced',jsonb_build_object('previous_card_id',previous_card));
   SELECT * INTO STRICT card FROM ironvault_private.member_cards WHERE card_id=new_card;
  ELSE
   PERFORM ironvault_private.physical_id_production_055(p_tenant);
   IF EXISTS(SELECT 1 FROM ironvault_private.physical_id_requests WHERE card_id=card.card_id AND status='issued') THEN RAISE EXCEPTION 'Current card already issued; report lost only if a replacement is needed';END IF;
  END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.physical_id_requests WHERE tenant_id=p_tenant AND member_id=member_key AND status IN ('awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection')) THEN RAISE EXCEPTION 'An active card request already exists';END IF;
  INSERT INTO ironvault_private.physical_id_requests(tenant_id,member_id,card_id,kind,requested_by)
   VALUES(p_tenant,member_key,card.card_id,CASE WHEN card.replaces_card_id IS NULL THEN 'initial' ELSE 'replacement' END,auth.uid()) RETURNING * INTO req;
  PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':1:gym','Physical ID request','A member has requested a physical card. Review before production.','gym');
 ELSE
  SELECT * INTO req FROM ironvault_private.physical_id_requests WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant AND member_id=member_key FOR UPDATE;
  IF NOT FOUND OR req.card_id<>card.card_id OR req.revision IS DISTINCT FROM (p_data->>'revision')::bigint OR req.status IN ('obsolete','cancelled','rejected') THEN RAISE EXCEPTION 'Request changed. Refresh before continuing';END IF;
  IF p_action='download' THEN
   PERFORM ironvault_private.physical_id_production_055(p_tenant);
   IF req.status NOT IN ('printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection','issued') OR
    (role_name='provider' AND req.route IS DISTINCT FROM 'provider') OR (role_name<>'provider' AND req.route IS DISTINCT FROM 'local') THEN RAISE EXCEPTION 'Choose and approve the production route first';END IF;
   snapshot:=ironvault_private.physical_id_snapshot_055(p_tenant,member_key);
   IF snapshot IS NULL OR md5(snapshot::text) IS DISTINCT FROM p_data->>'snapshot_hash' THEN RAISE EXCEPTION 'Card details changed. Refresh before downloading';END IF;
   IF coalesce(snapshot#>>'{member,photo}','')='' OR coalesce(snapshot#>>'{gym,logo}','')='' OR btrim(coalesce(snapshot#>>'{gym,address}',''))='' OR btrim(coalesce(snapshot#>>'{gym,name}',''))='' OR btrim(coalesce(snapshot#>>'{member,name}',''))='' OR btrim(coalesce(snapshot#>>'{member,display_code}',''))='' OR (btrim(coalesce(snapshot#>>'{gym,email}',''))='' AND btrim(coalesce(snapshot#>>'{gym,phone}',''))='') THEN RAISE EXCEPTION 'Complete the card photo, branding and public contact details first';END IF;
   INSERT INTO ironvault_private.physical_id_events(id,tenant_id,member_id,card_id,request_id,actor_id,action,data)
    VALUES(event_id,p_tenant,member_key,card.card_id,req.id,auth.uid(),'production_download_authorized',jsonb_build_object('format','CR80-600dpi-v1','revision',req.revision));
   result:=jsonb_build_object('export_id',event_id,'card_id',card.card_id,'revision',req.revision);
  ELSE
   target:=p_data->>'status';
   IF target IS NULL OR req.status IN ('issued','obsolete','cancelled','rejected') THEN RAISE EXCEPTION 'Request is closed';END IF;
   IF role_name='provider' THEN
    IF req.route IS DISTINCT FROM 'provider' OR NOT ((req.status='sent_to_provider' AND target IN ('in_production','rejected','cancelled')) OR (req.status='in_production' AND target IN ('production_complete','cancelled'))) THEN RAISE EXCEPTION 'Invalid provider production transition';END IF;
   ELSIF role_name IN ('owner','staff') THEN
    IF NOT ((req.status='awaiting_gym_review' AND target IN ('printing_locally','sent_to_provider','rejected','cancelled'))
     OR (req.status='printing_locally' AND target IN ('ready_for_collection','cancelled')) OR (req.status='production_complete' AND target IN ('ready_for_collection','cancelled'))
     OR (req.status='ready_for_collection' AND target IN ('issued','cancelled')) OR (req.status IN ('sent_to_provider','in_production') AND target='cancelled')) THEN RAISE EXCEPTION 'Invalid gym production transition';END IF;
   ELSE RAISE EXCEPTION 'Gym review required';END IF;
   IF target NOT IN ('cancelled','rejected') THEN PERFORM ironvault_private.physical_id_production_055(p_tenant);END IF;
   UPDATE ironvault_private.physical_id_requests SET status=target,route=CASE target WHEN 'printing_locally' THEN 'local' WHEN 'sent_to_provider' THEN 'provider' ELSE route END,
    revision=revision+1,updated_at=clock_timestamp(),decision_note=left(coalesce(p_data->>'note',''),500) WHERE id=req.id RETURNING * INTO req;
   UPDATE ironvault_private.physical_id_notices SET resolved_at=clock_timestamp() WHERE request_id=req.id AND resolved_at IS NULL;
   IF target='sent_to_provider' THEN PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':'||req.revision||':provider','Physical ID production request','A gym has forwarded a card request for production.','provider');END IF;
   IF target='production_complete' THEN PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':'||req.revision||':gym','Physical card production complete','Confirm receipt of the card before marking it ready for collection.','gym');END IF;
   PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':'||req.revision||':member','Physical ID update',CASE target WHEN 'printing_locally' THEN 'Your gym is preparing your card.' WHEN 'sent_to_provider' THEN 'Your gym has arranged production of your card.' WHEN 'in_production' THEN 'Your card is being produced.' WHEN 'production_complete' THEN 'Your gym is arranging receipt of your card.' WHEN 'ready_for_collection' THEN 'Your card is ready. Contact your gym to arrange collection.' WHEN 'issued' THEN 'Your gym marked this card as issued.' WHEN 'rejected' THEN 'Your gym could not approve this request. Contact the gym for details.' ELSE 'This card request was cancelled. Contact your gym if you still need a card.' END,'member');
  END IF;
 END IF;
 IF result IS NULL THEN
  INSERT INTO ironvault_private.physical_id_events(tenant_id,member_id,card_id,request_id,actor_id,action,data)
   VALUES(p_tenant,member_key,card.card_id,req.id,auth.uid(),p_action,jsonb_build_object('status',req.status,'revision',req.revision));
  result:=jsonb_build_object('request_id',req.id,'card_id',card.card_id,'status',req.status,'revision',req.revision);
 END IF;
 INSERT INTO ironvault_private.physical_id_operations(id,actor_id,tenant_id,member_id,action,payload_hash,result) VALUES(operation,auth.uid(),p_tenant,member_key,p_action,fingerprint,result);
 RETURN result;
END $fn$;

-- Preserve existing staff-access behavior and grants; extend only the explicit key set.
ALTER FUNCTION public.iv_staff_access(text,text,uuid,jsonb) RENAME TO staff_access_055_base;
ALTER FUNCTION public.staff_access_055_base(text,text,uuid,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_staff_access(p_tenant text,p_action text DEFAULT 'mine',p_user uuid DEFAULT NULL,p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;old_flags jsonb;new_flags jsonb:='{}';key text;keys text[]:=ARRAY['physical_ids_manage','physical_ids_download','physical_ids_replace'];
BEGIN
 IF p_action='permissions' THEN
  -- Match the existing role-before-access-row lock order and serialize partial permission edits.
  IF NOT ironvault_private.subscription_super() AND NOT ironvault_private.subscription_owner(p_tenant) THEN RAISE EXCEPTION 'Registered owner required' USING ERRCODE='42501';END IF;
  PERFORM 1 FROM public.iv_user_roles WHERE tenant_id=p_tenant AND user_id=p_user AND role='staff' FOR UPDATE;
  -- The preserved API validates ownership and all old keys inside this transaction.
  SELECT coalesce(jsonb_object_agg(k,v),'{}') INTO old_flags FROM ironvault_private.staff_access a CROSS JOIN LATERAL jsonb_each(a.permissions) f(k,v)
   WHERE a.tenant_id=p_tenant AND a.user_id=p_user AND k=ANY(keys);
  FOREACH key IN ARRAY keys LOOP
   IF p_data->'permissions' ? key THEN
    IF jsonb_typeof(p_data->'permissions'->key)<>'boolean' THEN RAISE EXCEPTION 'Choose explicit Physical ID permissions';END IF;
    new_flags:=new_flags||jsonb_build_object(key,p_data->'permissions'->key);
   END IF;
  END LOOP;
  new_flags:=coalesce(old_flags,'{}')||new_flags;
  IF new_flags->>'physical_ids_replace'='true' AND new_flags->>'physical_ids_manage' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Lost-card replacement requires Physical ID management';END IF;
  result:=ironvault_private.staff_access_055_base(p_tenant,p_action,p_user,jsonb_set(p_data,'{permissions}',(p_data->'permissions')-keys));
  UPDATE ironvault_private.staff_access SET permissions=permissions||new_flags WHERE tenant_id=p_tenant AND user_id=p_user;
  result:=ironvault_private.staff_access_055_base(p_tenant,'list',NULL,'{}');
 ELSE
  result:=ironvault_private.staff_access_055_base(p_tenant,p_action,p_user,p_data);
  IF p_action='mine' AND result->>'role' IN ('owner','super_admin') THEN result:=jsonb_set(result,'{permissions}',coalesce(result->'permissions','{}')||'{"physical_ids_manage":true,"physical_ids_download":true,"physical_ids_replace":true}');END IF;
 END IF;
 RETURN result;
END $fn$;
CREATE FUNCTION ironvault_private.physical_id_notice_feed_055(p_tenant text,p_mode text,p_read jsonb,p_audience text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE items jsonb;
BEGIN
 IF p_mode NOT IN ('list','read') OR p_read IS NULL OR jsonb_typeof(p_read)<>'array' OR jsonb_array_length(p_read)>5000 THEN RAISE EXCEPTION 'Invalid notice request';END IF;
 IF p_audience='provider' THEN
  IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Provider required' USING ERRCODE='42501';END IF;
 ELSE
  PERFORM 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.enabled AND r.disabled_at IS NULL
   AND ((p_audience='member' AND r.role='member') OR (p_audience='gym' AND (r.role='owner' OR (r.role='staff' AND ironvault_private.staff_has_permission(p_tenant,'physical_ids_manage')))));
  IF NOT FOUND THEN RETURN '[]'::jsonb;END IF;
 END IF;
 IF p_mode='read' THEN UPDATE ironvault_private.physical_id_notices n SET read_at=coalesce(read_at,clock_timestamp())
  WHERE n.recipient_id=auth.uid() AND n.audience=p_audience AND (p_tenant IS NULL OR n.tenant_id=p_tenant)
  AND (p_audience<>'member' OR EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.tenant_id=n.tenant_id AND r.member_id=n.member_id AND r.role='member' AND r.enabled AND r.disabled_at IS NULL))
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_read) x WHERE x->>'id'='physical-id:'||n.id AND x->>'revision'='1');END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id','physical-id:'||id,'revision','1','noticeSource','physical_id','kind','physical_id',
  'tenant_id',tenant_id,'member_id',member_id,'request_id',request_id,'title',title,'body',body,'starts_at',created_at,
  'ends_at','9999-12-31T00:00:00Z','popup',false,'resolved_at',resolved_at,'unread',read_at IS NULL AND resolved_at IS NULL) ORDER BY created_at DESC,id),'[]')
 INTO items FROM ironvault_private.physical_id_notices n WHERE recipient_id=auth.uid() AND audience=p_audience AND (p_tenant IS NULL OR tenant_id=p_tenant)
 AND (p_audience<>'member' OR EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.tenant_id=n.tenant_id AND r.member_id=n.member_id AND r.role='member' AND r.enabled AND r.disabled_at IS NULL));
 RETURN items;
END $fn$;
ALTER FUNCTION public.iv_account_announcements(text,text,jsonb) RENAME TO account_announcements_055_base;
ALTER FUNCTION public.account_announcements_055_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_account_announcements(p_tenant text,p_mode text DEFAULT 'list',p_read jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;items jsonb;
BEGIN
 result:=ironvault_private.account_announcements_055_base(p_tenant,p_mode,p_read);
 items:=ironvault_private.physical_id_notice_feed_055(p_tenant,p_mode,p_read,'gym');
 RETURN jsonb_set(result,'{items}',coalesce(result->'items','[]')||items);
END $fn$;
ALTER FUNCTION public.iv_member_announcements(text,text,jsonb) RENAME TO member_announcements_055_base;
ALTER FUNCTION public.member_announcements_055_base(text,text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_member_announcements(p_tenant text,p_mode text DEFAULT 'list',p_read jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;items jsonb;
BEGIN
 result:=ironvault_private.member_announcements_055_base(p_tenant,p_mode,p_read);
 items:=ironvault_private.physical_id_notice_feed_055(p_tenant,CASE WHEN p_mode='read' THEN 'read' ELSE 'list' END,p_read,'member');
 RETURN jsonb_set(result,'{items}',coalesce(result->'items','[]')||items);
END $fn$;
ALTER FUNCTION public.iv_provider_console(text,jsonb) RENAME TO provider_console_055_base;
ALTER FUNCTION public.provider_console_055_base(text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_provider_console(p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;items jsonb;notices jsonb;
BEGIN
 result:=ironvault_private.provider_console_055_base(p_action,p_data);
 items:=ironvault_private.physical_id_notice_feed_055(NULL,CASE WHEN p_action='read' THEN 'read' ELSE 'list' END,
  CASE WHEN p_action='read' THEN jsonb_build_array(jsonb_build_object('id',p_data->>'key','revision','1')) ELSE '[]'::jsonb END,'provider');
 IF p_action='badge' THEN RETURN jsonb_set(result,'{unread}',to_jsonb(coalesce((result->>'unread')::integer,0)+(SELECT count(*) FROM jsonb_array_elements(items) x WHERE (x->>'unread')::boolean)));END IF;
 SELECT coalesce(jsonb_agg(x||jsonb_build_object('notice_key',x->>'id','message',x->>'body','available_at',x->>'starts_at','read_at',CASE WHEN (x->>'unread')::boolean THEN NULL ELSE x->>'starts_at' END)),'[]') INTO notices FROM jsonb_array_elements(items) x;
 RETURN jsonb_set(result,'{notices}',coalesce(result->'notices','[]')||notices);
END $fn$;
DO $acl$ DECLARE obj record;BEGIN
 FOR obj IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='ironvault_private' AND p.proname IN ('physical_id_authority_055','physical_id_production_055','physical_id_snapshot_055','physical_id_notify_055','physical_id_notice_feed_055','staff_access_055_base','account_announcements_055_base','member_announcements_055_base','provider_console_055_base'))
  OR (n.nspname='public' AND p.proname IN ('iv_physical_ids','iv_physical_id_action','iv_staff_access','iv_account_announcements','iv_member_announcements','iv_provider_console'))
 LOOP
  EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO postgres',obj.nspname,obj.proname,obj.args);
  EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',obj.nspname,obj.proname,obj.args);
  IF obj.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated',obj.nspname,obj.proname,obj.args);END IF;
 END LOOP;
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='ironvault_private' AND tablename IN ('physical_id_requests','physical_id_events','physical_id_operations','physical_id_notices') LOOP
  EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',obj.tablename);
  EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',obj.tablename);
  EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',obj.tablename);
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
