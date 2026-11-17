-- MANUAL ONLY after confirmed 055. No credentials rotate on installation.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_physical_id_action(text,text,jsonb)') IS NULL OR to_regclass('ironvault_private.physical_id_requests') IS NULL THEN RAISE EXCEPTION 'Confirm physical ID migration 055 first';END IF;
 IF to_regprocedure('ironvault_private.physical_ids_056_base(text,text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION '056 already installed; do not reapply';END IF;
END $guard$;
ALTER TABLE ironvault_private.physical_id_requests DROP CONSTRAINT physical_id_requests_status_check;
ALTER TABLE ironvault_private.physical_id_requests ADD CONSTRAINT physical_id_requests_status_check CHECK(status IN ('awaiting_replacement','awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection','issued','rejected','cancelled','obsolete'));
DROP INDEX ironvault_private.physical_id_one_active_request;
CREATE UNIQUE INDEX physical_id_one_active_request ON ironvault_private.physical_id_requests(tenant_id,member_id)
 WHERE status IN ('awaiting_replacement','awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection');
ALTER FUNCTION public.iv_physical_ids(text,text,jsonb) RENAME TO physical_ids_056_base;
ALTER FUNCTION public.physical_ids_056_base(text,text,jsonb) SET SCHEMA ironvault_private;
ALTER FUNCTION public.iv_physical_id_action(text,text,jsonb) RENAME TO physical_id_action_056_base;
ALTER FUNCTION public.physical_id_action_056_base(text,text,jsonb) SET SCHEMA ironvault_private;

CREATE FUNCTION public.iv_physical_ids(p_tenant text,p_action text DEFAULT 'requests',p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;r text;member_key text:=p_data->>'member_id';manage boolean;replace_card boolean;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>20000 THEN RAISE EXCEPTION 'Invalid physical ID query';END IF;
 IF p_action NOT IN ('capabilities','preview','loss') THEN RETURN ironvault_private.physical_ids_056_base(p_tenant,p_action,p_data)||jsonb_build_object('workflow_version',3);END IF;
 r:=ironvault_private.physical_id_authority_055(p_tenant,member_key,NULL,p_action IN ('loss','capabilities'));
 IF p_action='capabilities' THEN RETURN jsonb_build_object('workflow_version',3);END IF;
 IF p_action='loss' AND r NOT IN ('owner','provider') THEN RAISE EXCEPTION 'Owner security access required' USING ERRCODE='42501';END IF;
 manage:=r IN ('owner','provider') OR (r='staff' AND ironvault_private.staff_has_permission(p_tenant,'physical_ids_manage'));
 replace_card:=r='owner' OR (r='staff' AND manage AND ironvault_private.staff_has_permission(p_tenant,'physical_ids_replace'));
 IF EXISTS(SELECT 1 FROM ironvault_private.member_cards WHERE tenant_id=p_tenant AND member_id=member_key AND revoked_at IS NULL) THEN
  result:=ironvault_private.physical_ids_056_base(p_tenant,p_action,p_data);
  RETURN result||jsonb_build_object('workflow_version',3,'card_state','active','permissions',coalesce(result->'permissions','{}')||jsonb_build_object('replace',r='member' OR replace_card,'create_replacement',false));
 END IF;
 SELECT jsonb_build_object('tenant_id',p_tenant,'member_id',m.id,'card_id',c.card_id,'version',c.version,'card_state','awaiting_replacement','workflow_version',3,'role',r,'security_only',p_action='loss',
  'member',jsonb_build_object('id',m.id,'name',m.name,'display_code',m.display_code),'loss_request_id',q.id,'loss_revision',q.revision,
  'permissions',jsonb_build_object('manage',manage,'download',false,'replace',false,'create_replacement',replace_card)) INTO result
 FROM public.members m JOIN ironvault_private.physical_id_requests q ON q.member_id=m.id AND q.tenant_id=m.tenant_id
 JOIN ironvault_private.member_cards c ON c.card_id=q.card_id AND c.tenant_id=q.tenant_id AND c.member_id=q.member_id
 WHERE m.id=member_key AND m.tenant_id=p_tenant AND (m.status IN ('ACTIVE','PENDING') OR (p_action='loss' AND r IN ('owner','provider'))) AND q.status='awaiting_replacement' AND c.revoked_at IS NOT NULL;
 IF result IS NULL THEN RAISE EXCEPTION 'Physical ID unavailable';END IF;
 -- A lost credential is never returned in a preview or pending response.
 RETURN result;
END $fn$;
CREATE FUNCTION public.iv_physical_id_action(p_tenant text,p_action text,p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE r text;action_name text:=p_action;member_key text:=p_data->>'member_id';operation uuid;fingerprint text;op ironvault_private.physical_id_operations%ROWTYPE;
 card ironvault_private.member_cards%ROWTYPE;req ironvault_private.physical_id_requests%ROWTYPE;result jsonb;snapshot jsonb;previous_card uuid;event_id uuid:=gen_random_uuid();
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>20000 OR p_action IS NULL OR p_action NOT IN ('submit','replace','transition','download','report_loss','create_replacement','request_provider','download_direct') THEN RAISE EXCEPTION 'Invalid physical ID action';END IF;
 operation:=(p_data->>'operation_id')::uuid;
 IF operation IS NULL OR member_key IS NULL THEN RAISE EXCEPTION 'Member and retry identity required';END IF;
 PERFORM 1 FROM public.iv_user_roles WHERE user_id=auth.uid() FOR SHARE;
 r:=ironvault_private.physical_id_authority_055(p_tenant,member_key,CASE WHEN p_action IN ('download','download_direct') THEN 'physical_ids_download' WHEN p_action IN ('create_replacement','request_provider','transition') THEN 'physical_ids_manage' ELSE NULL END,p_action IN ('report_loss','create_replacement','replace'));
 IF r='provider' AND p_action IN ('submit','replace','report_loss','create_replacement','request_provider') THEN RAISE EXCEPTION 'Provider card actions are download only' USING ERRCODE='42501';END IF;
 IF p_action='replace' AND r='member' THEN action_name:='report_loss';END IF;
 IF action_name NOT IN ('report_loss','create_replacement','request_provider','download_direct') THEN RETURN ironvault_private.physical_id_action_056_base(p_tenant,p_action,p_data);END IF;
 IF r='staff' AND action_name IN ('report_loss','create_replacement') THEN
  PERFORM ironvault_private.staff_require(p_tenant,'physical_ids_manage');PERFORM ironvault_private.staff_require(p_tenant,'physical_ids_replace');
 END IF;
 IF action_name='request_provider' AND r NOT IN ('owner','staff') THEN RAISE EXCEPTION 'Gym review required' USING ERRCODE='42501';END IF;
 IF action_name='create_replacement' AND r NOT IN ('owner','staff') THEN RAISE EXCEPTION 'Gym replacement permission required' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM public.members WHERE id=member_key AND tenant_id=p_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Member unavailable';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(operation::text,55));
 fingerprint:=md5(p_tenant||p_action||p_data::text);
 SELECT * INTO op FROM ironvault_private.physical_id_operations WHERE id=operation;
 IF FOUND THEN
  IF op.actor_id<>auth.uid() OR op.tenant_id<>p_tenant OR op.member_id<>member_key OR op.action<>p_action OR op.payload_hash<>fingerprint THEN RAISE EXCEPTION 'Retry identity belongs to a different action';END IF;
  IF action_name='download_direct' THEN
   PERFORM ironvault_private.physical_id_production_055(p_tenant);snapshot:=ironvault_private.physical_id_snapshot_055(p_tenant,member_key);
   IF snapshot IS NULL OR snapshot->>'card_id' IS DISTINCT FROM p_data->>'card_id' OR md5(snapshot::text) IS DISTINCT FROM p_data->>'snapshot_hash' THEN RAISE EXCEPTION 'Download is obsolete. Refresh before exporting';END IF;
  END IF;
  RETURN op.result;
 END IF;
 IF action_name='create_replacement' THEN
  SELECT * INTO card FROM ironvault_private.member_cards WHERE tenant_id=p_tenant AND member_id=member_key AND card_id=(p_data->>'card_id')::uuid FOR UPDATE;
  IF NOT FOUND OR card.revoked_at IS NULL OR card.revocation_reason IS DISTINCT FROM 'lost' THEN RAISE EXCEPTION 'Lost card changed. Refresh before replacing';END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.member_cards WHERE tenant_id=p_tenant AND member_id=member_key AND revoked_at IS NULL) THEN RAISE EXCEPTION 'Replacement already exists. Refresh';END IF;
  SELECT * INTO req FROM ironvault_private.physical_id_requests WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant AND member_id=member_key FOR UPDATE;
  IF NOT FOUND OR req.card_id<>card.card_id OR req.status<>'awaiting_replacement' OR req.revision IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Replacement request changed. Refresh';END IF;
  previous_card:=card.card_id;
  INSERT INTO ironvault_private.member_cards(member_id,tenant_id,version,replaces_card_id) VALUES(member_key,p_tenant,(SELECT max(version)+1 FROM ironvault_private.member_cards WHERE member_id=member_key),previous_card) RETURNING * INTO card;
  UPDATE ironvault_private.physical_id_requests SET card_id=card.card_id,status='awaiting_gym_review',revision=revision+1,route=NULL,updated_at=clock_timestamp() WHERE id=req.id RETURNING * INTO req;
  UPDATE ironvault_private.physical_id_notices SET resolved_at=clock_timestamp() WHERE request_id=req.id AND resolved_at IS NULL;
  PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':'||req.revision||':member','Replacement QR available','Your gym created your replacement QR. Your old card remains invalid.','member');
  PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':'||req.revision||':gym','Replacement QR created','The replacement QR is ready. Download the card or arrange provider production.','gym');
 ELSE
  SELECT * INTO card FROM ironvault_private.member_cards WHERE tenant_id=p_tenant AND member_id=member_key AND revoked_at IS NULL FOR UPDATE;
  IF NOT FOUND OR card.card_id IS DISTINCT FROM (p_data->>'card_id')::uuid THEN RAISE EXCEPTION 'Card changed. Refresh the preview';END IF;
  IF action_name='report_loss' THEN
   IF p_data->>'confirm_loss' IS DISTINCT FROM 'true' OR p_data->>'fee_ack' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Confirm card revocation and the possible replacement fee';END IF;
   UPDATE ironvault_private.member_cards SET revoked_at=clock_timestamp(),revoked_by=auth.uid(),revocation_reason='lost' WHERE card_id=card.card_id;
   UPDATE ironvault_private.physical_id_requests SET status='obsolete',revision=revision+1,updated_at=clock_timestamp() WHERE tenant_id=p_tenant AND member_id=member_key AND status IN ('awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection');
   UPDATE ironvault_private.physical_id_notices SET resolved_at=clock_timestamp() WHERE tenant_id=p_tenant AND member_id=member_key AND resolved_at IS NULL;
   INSERT INTO ironvault_private.physical_id_requests(tenant_id,member_id,card_id,kind,status,requested_by) VALUES(p_tenant,member_key,card.card_id,'replacement','awaiting_replacement',auth.uid()) RETURNING * INTO req;
   PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':lost:gym','Lost physical ID reported','The old QR is invalid. An authorized gym user must create the replacement QR.','gym');
   PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':lost:member','Lost card reported','Your old QR is invalid. Awaiting a replacement QR from your gym.','member');
  ELSIF action_name='request_provider' THEN
   PERFORM ironvault_private.physical_id_production_055(p_tenant);
   IF p_data->>'fee_ack' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Acknowledge the possible card fee';END IF;
   IF p_data->>'request_id' IS NOT NULL THEN
    SELECT * INTO req FROM ironvault_private.physical_id_requests WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant AND member_id=member_key FOR UPDATE;
    IF NOT FOUND OR req.card_id<>card.card_id OR req.status<>'awaiting_gym_review' OR req.revision IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Request changed. Refresh before forwarding';END IF;
    UPDATE ironvault_private.physical_id_requests SET status='sent_to_provider',route='provider',revision=revision+1,updated_at=clock_timestamp() WHERE id=req.id RETURNING * INTO req;
   ELSE
    IF EXISTS(SELECT 1 FROM ironvault_private.physical_id_requests WHERE tenant_id=p_tenant AND member_id=member_key AND status IN ('awaiting_replacement','awaiting_gym_review','printing_locally','sent_to_provider','in_production','production_complete','ready_for_collection')) THEN RAISE EXCEPTION 'An active card request already exists';END IF;
    INSERT INTO ironvault_private.physical_id_requests(tenant_id,member_id,card_id,kind,status,route,requested_by) VALUES(p_tenant,member_key,card.card_id,CASE WHEN card.replaces_card_id IS NULL THEN 'initial' ELSE 'replacement' END,'sent_to_provider','provider',auth.uid()) RETURNING * INTO req;
   END IF;
   UPDATE ironvault_private.physical_id_notices SET resolved_at=clock_timestamp() WHERE request_id=req.id AND resolved_at IS NULL;
   PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':'||req.revision||':provider','Physical ID production request','A gym has requested production of this card.','provider');
   PERFORM ironvault_private.physical_id_notify_055(req.id,req.id||':'||req.revision||':member','Physical ID update','Your gym has arranged production of your physical card.','member');
  ELSE
   PERFORM ironvault_private.physical_id_production_055(p_tenant);snapshot:=ironvault_private.physical_id_snapshot_055(p_tenant,member_key);
   IF snapshot IS NULL OR md5(snapshot::text) IS DISTINCT FROM p_data->>'snapshot_hash' THEN RAISE EXCEPTION 'Card details changed. Refresh before downloading';END IF;
   IF btrim(coalesce(snapshot#>>'{member,photo}',''))='' OR btrim(coalesce(snapshot#>>'{gym,logo}',''))='' OR btrim(coalesce(snapshot#>>'{gym,address}',''))='' OR btrim(coalesce(snapshot#>>'{gym,name}',''))='' OR btrim(coalesce(snapshot#>>'{member,name}',''))='' OR btrim(coalesce(snapshot#>>'{member,display_code}',''))='' OR (btrim(coalesce(snapshot#>>'{gym,email}',''))='' AND btrim(coalesce(snapshot#>>'{gym,phone}',''))='') THEN RAISE EXCEPTION 'Complete the card photo, branding and public contact details first';END IF;
   INSERT INTO ironvault_private.physical_id_events(id,tenant_id,member_id,card_id,actor_id,action,data) VALUES(event_id,p_tenant,member_key,card.card_id,auth.uid(),'production_download_authorized',jsonb_build_object('format','CR80-600dpi-v1','version',card.version));
   result:=jsonb_build_object('export_id',event_id,'card_id',card.card_id,'version',card.version);
  END IF;
 END IF;
 IF result IS NULL THEN
  INSERT INTO ironvault_private.physical_id_events(tenant_id,member_id,card_id,request_id,actor_id,action,data) VALUES(p_tenant,member_key,card.card_id,req.id,auth.uid(),action_name,jsonb_strip_nulls(jsonb_build_object('status',req.status,'revision',req.revision,'previous_card_id',previous_card)));
  result:=jsonb_build_object('request_id',req.id,'card_id',card.card_id,'status',req.status,'revision',req.revision);
 END IF;
 INSERT INTO ironvault_private.physical_id_operations(id,actor_id,tenant_id,member_id,action,payload_hash,result) VALUES(operation,auth.uid(),p_tenant,member_key,p_action,fingerprint,result);
 RETURN result;
END $fn$;
DO $acl$ DECLARE obj record;BEGIN
 FOR obj IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
 (n.nspname='ironvault_private' AND p.proname IN ('physical_ids_056_base','physical_id_action_056_base')) OR (n.nspname='public' AND p.proname IN ('iv_physical_ids','iv_physical_id_action')) LOOP
  EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO postgres',obj.nspname,obj.proname,obj.args);
  EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',obj.nspname,obj.proname,obj.args);
  IF obj.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated',obj.nspname,obj.proname,obj.args);END IF;
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
