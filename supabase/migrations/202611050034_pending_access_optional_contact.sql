-- MANUAL ONLY after 033. No historical rows, credentials or balances are changed.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('ironvault_private.write_audit(text,uuid,text,text,jsonb,jsonb)') IS NULL THEN RAISE EXCEPTION 'Apply migration 033 first'; END IF;
END $guard$;
-- Keep contact uniqueness for supplied addresses; multiple members may have no inbox.
-- user_id was already unique and remains the account identity. No foreign keys reference the old contact key.
ALTER TABLE ironvault_private.branch_accounts DROP CONSTRAINT branch_accounts_pkey;
ALTER TABLE ironvault_private.branch_accounts ALTER COLUMN contact_email DROP NOT NULL;
ALTER TABLE ironvault_private.branch_accounts ADD PRIMARY KEY(user_id);
ALTER TABLE ironvault_private.branch_accounts ADD CONSTRAINT iv_branch_contact_unique UNIQUE(tenant_id,role,contact_email);
ALTER TABLE ironvault_private.branch_accounts ADD CONSTRAINT iv_admin_contact_required CHECK(role='member' OR contact_email IS NOT NULL);
ALTER TABLE ironvault_private.provision_requests ALTER COLUMN contact_email DROP NOT NULL;
ALTER TABLE ironvault_private.provision_requests ADD CONSTRAINT iv_provision_contact_required CHECK(role='member' OR contact_email IS NOT NULL);
ALTER TABLE ironvault_private.email_actions ALTER COLUMN base_email DROP NOT NULL;
ALTER TABLE public.members ALTER COLUMN email DROP NOT NULL;
CREATE OR REPLACE FUNCTION public.iv_prepare_branch_account(p_request uuid,p_actor uuid,p_tenant text,p_role text,p_email text,p_alias text,p_payload jsonb,p_new_gym boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provision_requests%ROWTYPE; actor public.iv_user_roles%ROWTYPE; key text; price numeric; name text;
BEGIN
 IF p_request IS NULL OR p_role NOT IN ('owner','staff','member') OR (p_email IS NULL AND (p_role<>'member' OR p_actor IS NULL OR p_new_gym))
  OR (p_email IS NOT NULL AND (p_email='' OR p_email<>lower(btrim(p_email)) OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
  OR p_alias !~ '^[a-f0-9]{64}@accounts\.ironvault\.invalid$'
  OR p_payload ? 'password' OR p_payload ? 'service_role' THEN RAISE EXCEPTION 'Invalid account request'; END IF;
 IF p_role='staff' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.tenant_id=p_tenant AND a.role IN ('owner','staff') AND a.contact_email=p_email) THEN
  -- A same-request retry may find its own already-completed account.
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.provision_requests WHERE request_id=p_request AND tenant_id=p_tenant AND contact_email=p_email AND role=p_role) THEN RAISE EXCEPTION 'Admin portal email already in use'; END IF;
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text,1));
 SELECT * INTO job FROM ironvault_private.provision_requests WHERE request_id=p_request;
 IF FOUND THEN
  IF job.actor_id IS DISTINCT FROM p_actor OR job.tenant_id<>p_tenant OR job.role<>p_role OR job.contact_email IS DISTINCT FROM p_email
   OR job.alias<>p_alias OR job.payload<>p_payload THEN RAISE EXCEPTION 'Provision request mismatch'; END IF;
 END IF;
 SELECT * INTO actor FROM public.iv_user_roles WHERE user_id=p_actor AND enabled AND disabled_at IS NULL;
 IF p_new_gym THEN
  IF actor.role IS DISTINCT FROM 'super_admin' OR actor.tenant_id IS NOT NULL OR p_role<>'owner' THEN RAISE EXCEPTION 'Super Admin required'; END IF;
  name:=p_payload->>'gym_name';IF length(coalesce(name,'')) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'Gym name required'; END IF;
  FOREACH key IN ARRAY ARRAY['day','week','month','studentDiscount','seniorDiscount'] LOOP
   price:=(p_payload->'pricing'->>key)::numeric;
   IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<0
    OR (key NOT LIKE '%Discount' AND price<=0) OR price>(CASE WHEN key LIKE '%Discount' THEN 100 ELSE 10000000 END) OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid gym pricing'; END IF;
  END LOOP;
  -- Globally unique private alias satisfies the existing owners.email uniqueness;
  -- verified contact email lives in branch_accounts, never this login identifier.
  IF job.request_id IS NULL THEN
  INSERT INTO public.owners(id,gym_name,owner_name,email,password,token,logo,status,pricing,staff,audit_logs)
   VALUES(p_tenant,name,p_payload->>'name',p_alias,NULL,gen_random_uuid()::text,
    coalesce(p_payload->>'logo',''),'PROVISIONING',p_payload->'pricing','[]','[]');
  END IF;
 ELSE
  IF p_actor IS NOT NULL AND actor.user_id IS NULL THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND (status='ACTIVE' OR (status='PROVISIONING' AND actor.role='super_admin' AND p_role='staff'))) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
  IF p_actor IS NULL THEN
   IF p_role<>'member' THEN RAISE EXCEPTION 'Member registration only'; END IF;
  ELSIF actor.role IS DISTINCT FROM 'super_admin' THEN
   IF actor.tenant_id IS DISTINCT FROM p_tenant OR actor.role NOT IN ('owner','staff')
    OR (p_role='staff' AND actor.role<>'owner') OR p_role='owner' THEN RAISE EXCEPTION 'Not authorized'; END IF;
  END IF;
 END IF;
 IF length(coalesce(p_payload->>'name','')) NOT BETWEEN 1 AND 160 OR length(coalesce(p_payload->>'phone',''))>50
  OR length(coalesce(p_payload->>'logo',''))>750000 THEN RAISE EXCEPTION 'Invalid profile'; END IF;
 IF job.request_id IS NOT NULL THEN RETURN jsonb_build_object('alias',job.alias,'completed_user',job.completed_user,'tenant_id',job.tenant_id); END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant AND contact_email=p_email
  AND (role=p_role OR (p_role IN ('owner','staff') AND role IN ('owner','staff')))) THEN RAISE EXCEPTION 'Account already registered in this gym'; END IF;
 IF p_role='member' AND EXISTS(SELECT 1 FROM public.members WHERE tenant_id=p_tenant AND lower(btrim(email))=p_email) THEN
  RAISE EXCEPTION 'Membership already exists; ask the gym to restore account access'; END IF;
 INSERT INTO ironvault_private.provision_requests(request_id,tenant_id,role,contact_email,alias,actor_id,payload)
 VALUES(p_request,p_tenant,p_role,p_email,p_alias,p_actor,p_payload);
 RETURN jsonb_build_object('alias',p_alias,'tenant_id',p_tenant);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_finish_branch_account(p_request uuid,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provision_requests%ROWTYPE; member_id text; token text;
BEGIN
 SELECT * INTO STRICT job FROM ironvault_private.provision_requests WHERE request_id=p_request FOR UPDATE;
 IF job.completed_user IS NOT NULL THEN
  IF job.completed_user<>p_user THEN RAISE EXCEPTION 'Different account already completed'; END IF;
  RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'user_id',p_user,'member_id',
   (SELECT r.member_id FROM public.iv_user_roles r WHERE r.user_id=p_user));
 END IF;
 IF job.actor_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=job.actor_id AND r.enabled
  AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.tenant_id=job.tenant_id
   AND ((job.role='member' AND r.role IN ('owner','staff')) OR (job.role='staff' AND r.role='owner'))))) THEN
  RAISE EXCEPTION 'Provisioning authority revoked'; END IF;
 IF job.role='owner' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=job.tenant_id AND status='PROVISIONING') THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF job.role<>'owner' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=job.tenant_id AND (status='ACTIVE' OR (status='PROVISIONING' AND job.role='staff' AND EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=job.actor_id AND enabled AND role='super_admin')))) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user AND email=job.alias AND raw_app_meta_data->>'iv_provision_request'=p_request::text) THEN
  RAISE EXCEPTION 'Auth account does not match protected provisioning metadata'; END IF;
 IF job.role='member' THEN
  member_id:='MEM-'||gen_random_uuid()::text;
  SELECT o.token INTO STRICT token FROM public.owners o WHERE o.id=job.tenant_id;
  INSERT INTO public.members(id,tenant_id,tenant_token,name,email,phone,password,auth_user_id,
   classification,discount_percentage,plan,wallet_balance,amount,scans_used,status,date_joined)
  VALUES(member_id,job.tenant_id,token,job.payload->>'name',job.contact_email,coalesce(job.payload->>'phone',''),NULL,p_user,
   'Regular',0,'Not Selected',0,0,0,CASE WHEN job.actor_id IS NULL THEN 'PENDING' ELSE 'ACTIVE' END,
   ((now() AT TIME ZONE 'Asia/Manila')::date)::text);
 END IF;
 INSERT INTO public.iv_user_roles(user_id,tenant_id,role,member_id,enabled) VALUES(p_user,job.tenant_id,job.role,member_id,true);
 INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id) VALUES(job.tenant_id,job.role,job.contact_email,p_user);
 IF job.role='staff' THEN
  UPDATE public.owners SET staff=coalesce(staff,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('name',job.payload->>'name',
   'email',job.contact_email,'auth_user_id',p_user,'dateCreated',((now() AT TIME ZONE 'Asia/Manila')::date)::text)) WHERE id=job.tenant_id;
 END IF;
 UPDATE ironvault_private.provision_requests SET completed_user=p_user WHERE request_id=p_request;
 IF job.role='owner' THEN UPDATE public.owners SET status='ACTIVE' WHERE id=job.tenant_id AND status='PROVISIONING'; END IF;
 RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'member_id',member_id,'user_id',p_user);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_can_read_live_signal(p_tenant text,p_kind text,p_entity text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
  ((r.role='super_admin' AND r.tenant_id IS NULL) OR
   (r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE') AND
    (r.role IN ('owner','staff') OR (r.role='member' AND (p_kind='gym' OR (p_kind='member' AND p_entity=r.member_id))
     AND EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=p_tenant AND m.status IN ('ACTIVE','PENDING')))))));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_live_cursor(p_tenant text DEFAULT NULL,p_member text DEFAULT NULL,p_cursor text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE allowed boolean; checkpoint text; signals jsonb;
BEGIN
 IF p_tenant IS NULL THEN
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.role='super_admin'
   AND r.tenant_id IS NULL AND r.enabled AND r.disabled_at IS NULL) AND p_member IS NULL INTO allowed;
 ELSIF p_member IS NULL THEN
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL
   AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.role IN ('owner','staff') AND r.tenant_id=p_tenant
    AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE')))) INTO allowed;
 ELSE
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
   JOIN public.owners g ON g.id=r.tenant_id WHERE r.user_id=auth.uid() AND r.role='member'
    AND r.tenant_id=p_tenant AND r.member_id=p_member AND r.enabled AND r.disabled_at IS NULL
    AND m.status IN ('ACTIVE','PENDING') AND g.status='ACTIVE') INTO allowed;
 END IF;
 IF NOT coalesce(allowed,false) THEN RAISE EXCEPTION 'Live update access denied' USING ERRCODE='42501'; END IF;
 SELECT md5(coalesce(string_agg(s.kind||':'||s.entity_id||':'||s.revision::text,'|' ORDER BY s.kind,s.entity_id),'')),
  coalesce(jsonb_agg(jsonb_build_object('kind',s.kind,'entity_id',s.entity_id,'tenant_id',s.tenant_id,'revision',s.revision::text) ORDER BY s.kind,s.entity_id),'[]'::jsonb)
 INTO checkpoint,signals
 FROM public.iv_live_signals s WHERE p_tenant IS NULL OR
  (s.tenant_id=p_tenant AND (p_member IS NULL OR s.kind='gym' OR (s.kind='member' AND s.entity_id=p_member)));
 RETURN jsonb_build_object('cursor',checkpoint,'server_now',now(),'signals',CASE WHEN checkpoint IS DISTINCT FROM p_cursor THEN signals ELSE 'null'::jsonb END);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_member_legal_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE member text; tenant text; p uuid; g uuid; receipt jsonb; agreed boolean;
BEGIN
 SELECT m.id,m.tenant_id INTO member,tenant FROM public.iv_user_roles r JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
 JOIN public.owners o ON o.id=m.tenant_id WHERE r.user_id=auth.uid() AND r.role='member' AND r.enabled AND r.disabled_at IS NULL
 AND m.status IN ('ACTIVE','PENDING') AND o.status='ACTIVE';
 IF member IS NULL THEN RAISE EXCEPTION 'Active member account required' USING ERRCODE='42501'; END IF;
 SELECT current_version INTO p FROM ironvault_private.legal_settings WHERE scope='platform';
 SELECT current_version INTO g FROM ironvault_private.legal_settings WHERE scope=tenant;
 SELECT EXISTS(SELECT 1 FROM ironvault_private.legal_acceptances a WHERE a.user_id=auth.uid() AND a.member_id=member AND a.tenant_id=tenant AND a.platform_version=p AND a.gym_version=g) INTO agreed;
 SELECT jsonb_build_object('accepted_at',a.accepted_at,'platform_version',a.platform_version,'gym_version',a.gym_version) INTO receipt
 FROM ironvault_private.legal_acceptances a WHERE a.user_id=auth.uid() AND a.member_id=member AND a.tenant_id=tenant
 ORDER BY (a.platform_version=p AND a.gym_version=g) DESC NULLS LAST,a.accepted_at DESC LIMIT 1;
 RETURN jsonb_build_object('user_id',auth.uid(),'tenant_id',tenant,'member_id',member,'accepted',agreed,
  'platform_version',p,'gym_version',g,'acceptance',receipt,'server_now',now());
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_member_legal_accept(p_platform uuid,p_gym uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; p uuid; g uuid;
BEGIN
 SELECT member_row.* INTO m FROM public.members member_row JOIN public.iv_user_roles r ON r.member_id=member_row.id AND r.tenant_id=member_row.tenant_id
 JOIN public.owners o ON o.id=member_row.tenant_id WHERE r.user_id=auth.uid() AND r.role='member' AND r.enabled AND r.disabled_at IS NULL
 AND member_row.status IN ('ACTIVE','PENDING') AND o.status='ACTIVE' FOR UPDATE OF member_row;
 IF m.id IS NULL THEN RAISE EXCEPTION 'Active member account required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM ironvault_private.legal_settings WHERE scope IN ('platform',m.tenant_id) ORDER BY scope FOR SHARE;
 SELECT current_version INTO p FROM ironvault_private.legal_settings WHERE scope='platform';
 SELECT current_version INTO g FROM ironvault_private.legal_settings WHERE scope=m.tenant_id;
 IF p IS NULL OR g IS NULL OR p_platform IS DISTINCT FROM p OR p_gym IS DISTINCT FROM g THEN
  RAISE EXCEPTION 'Documents changed or are unavailable. Review the current versions and agree again' USING ERRCODE='IV002';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_acceptances a WHERE a.user_id=auth.uid() AND a.member_id=m.id
  AND a.tenant_id=m.tenant_id AND a.platform_version=p AND a.gym_version=g) THEN
  INSERT INTO ironvault_private.legal_acceptances(request_id,tenant_id,member_id,user_id,platform_version,gym_version,accepted_at)
   VALUES(gen_random_uuid(),m.tenant_id,m.id,auth.uid(),p,g,clock_timestamp());
  PERFORM ironvault_private.emit_live_signal('member',m.id,m.tenant_id);
 END IF;
 RETURN public.iv_member_legal_status();
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_save_member_profiles(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; m public.members%ROWTYPE; tenant text; operator boolean; owner_access boolean; discount numeric; updated_member public.members%ROWTYPE; field text; before_value jsonb; after_value jsonb; label text; operation uuid:=gen_random_uuid(); restored integer;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>500 THEN RAISE EXCEPTION 'Invalid profile batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO m FROM public.members WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Create member accounts through registration; restore cannot create financial records'; END IF;
  tenant:=m.tenant_id;operator:=public.iv_can_access(tenant);owner_access:=public.iv_can_access(tenant,ARRAY['owner']::text[]);
  IF NOT operator AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
   AND r.role='member' AND r.member_id=m.id AND r.tenant_id=tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=tenant AND g.status='ACTIVE')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT operator AND m.status IS DISTINCT FROM 'ACTIVE' THEN RAISE EXCEPTION 'Awaiting gym approval; your profile is read-only'; END IF;
  IF item ? 'tenant_id' AND item->>'tenant_id' IS DISTINCT FROM tenant THEN RAISE EXCEPTION 'Cannot move membership'; END IF;
  IF length(coalesce(item->>'name',m.name)) NOT BETWEEN 1 AND 160 OR length(coalesce(item->>'phone',''))>50
   OR length(coalesce(item->>'avatar',''))>750000 THEN RAISE EXCEPTION 'Invalid profile fields'; END IF;
  IF item ? 'email' AND nullif(lower(btrim(item->>'email')),'') IS DISTINCT FROM nullif(lower(btrim(m.email)),'') THEN
   RAISE EXCEPTION 'Contact email changes require verification'; END IF;
  -- Names/phone/avatar are personal edits. Operators additionally manage approval,
  -- classification and card IDs; only gym administrators change a discount.
  IF operator AND item ? 'status' AND item->>'status' NOT IN ('ACTIVE','PENDING','INACTIVE') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF operator AND item ? 'classification' AND item->>'classification' NOT IN ('Regular','Student','Senior') THEN RAISE EXCEPTION 'Invalid classification'; END IF;
  IF operator AND NOT owner_access AND m.status='INACTIVE' AND item->>'status'='ACTIVE' THEN RAISE EXCEPTION 'Gym administrator required to restore inactive membership'; END IF;
  discount:=coalesce(m.discount_percentage,0);
  IF operator AND item ? 'classification' AND item->>'classification' IS DISTINCT FROM m.classification THEN
   SELECT CASE WHEN item->>'classification'='Student' THEN (g.pricing->>'studentDiscount')::numeric
    WHEN item->>'classification'='Senior' THEN (g.pricing->>'seniorDiscount')::numeric ELSE 0 END
   INTO discount FROM public.owners g WHERE g.id=tenant;
  END IF;
  IF owner_access AND item ? 'discount_percentage' THEN
   discount:=(item->>'discount_percentage')::numeric;
   IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  END IF;
  IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid configured member discount'; END IF;
  UPDATE public.members SET name=coalesce(item->>'name',name),phone=CASE WHEN item ? 'phone' THEN item->>'phone' ELSE phone END,
   avatar=CASE WHEN item ? 'avatar' THEN item->>'avatar' ELSE avatar END,
   status=CASE WHEN operator THEN coalesce(item->>'status',status) ELSE status END,
   classification=CASE WHEN operator THEN coalesce(item->>'classification',classification) ELSE classification END,
   card_barcode=CASE WHEN operator AND item ? 'card_barcode' THEN item->>'card_barcode' ELSE card_barcode END,
   discount_percentage=discount WHERE id=m.id RETURNING * INTO updated_member;
  IF owner_access AND item->>'status'='ACTIVE' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id WHERE r.member_id=m.id AND a.tenant_id=tenant AND r.tenant_id=tenant ) THEN
   UPDATE public.iv_user_roles SET enabled=true,disabled_at=NULL WHERE member_id=m.id AND tenant_id=tenant AND role='member' AND (NOT enabled OR disabled_at IS NOT NULL);
   GET DIAGNOSTICS restored=ROW_COUNT;
   IF restored>0 THEN PERFORM ironvault_private.write_audit(tenant,auth.uid(),'Member access restored',ironvault_private.audit_member_label(m.id,tenant),jsonb_build_object('member',ironvault_private.audit_member(m.id,tenant),'operation_id',operation,'changes',jsonb_build_object('access',jsonb_build_object('before','disabled','after','enabled')))); END IF;
  END IF;
  FOREACH field IN ARRAY ARRAY['name','phone','avatar','classification','card_barcode','discount_percentage','status'] LOOP
   before_value:=to_jsonb(m)->field;after_value:=to_jsonb(updated_member)->field;
   IF before_value IS DISTINCT FROM after_value THEN
    label:=CASE field WHEN 'name' THEN 'name' WHEN 'phone' THEN 'phone' WHEN 'avatar' THEN 'photo' WHEN 'classification' THEN 'classification' WHEN 'card_barcode' THEN 'barcode' WHEN 'discount_percentage' THEN 'discount' ELSE 'status' END;
    IF field='avatar' THEN
     before_value:=to_jsonb(CASE WHEN coalesce(m.avatar,'')='' THEN 'Not set' ELSE 'Photo set' END);
     after_value:=to_jsonb(CASE WHEN coalesce(updated_member.avatar,'')='' THEN 'Not set' ELSE 'Photo set' END);
    END IF;
    PERFORM ironvault_private.write_audit(tenant,auth.uid(),'Member '||label||' changed',
     ironvault_private.audit_member_label(m.id,tenant)||' · '||CASE WHEN field='avatar' THEN 'Profile photo updated (image data excluded)' ELSE initcap(label)||': '||coalesce(before_value#>>'{}','Not set')||' → '||coalesce(after_value#>>'{}','Not set') END,
     jsonb_build_object('member',ironvault_private.audit_member(m.id,tenant),'operation_id',operation,'changes',jsonb_build_object(field,jsonb_build_object('before',before_value,'after',after_value))));
   END IF;
  END LOOP;
 END LOOP;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_queue_contact_change(p_actor uuid,p_user uuid,p_hash text,p_kind text,p_group uuid,p_new_email text,p_base_email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE target ironvault_private.branch_accounts%ROWTYPE; context jsonb; first_request boolean;
BEGIN
 SELECT * INTO STRICT target FROM ironvault_private.branch_accounts WHERE user_id=p_user FOR UPDATE;
 IF p_base_email IS DISTINCT FROM target.contact_email THEN RAISE EXCEPTION 'Contact changed; reload before requesting another change'; END IF;
 IF p_kind NOT IN ('change_old','change_new','correct_unverified') THEN RAISE EXCEPTION 'Invalid contact action'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=p_actor AND r.enabled AND r.disabled_at IS NULL AND
  ((r.user_id=p_user AND r.tenant_id=target.tenant_id AND r.role=target.role)
  OR (r.role='super_admin' AND r.tenant_id IS NULL)
  OR (r.role='owner' AND r.tenant_id=target.tenant_id AND target.role IN ('staff','member') AND EXISTS(SELECT 1 FROM public.owners WHERE id=target.tenant_id AND status='ACTIVE')))) THEN RAISE EXCEPTION 'Contact authority denied'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_group::text,7));
 SELECT audit_context INTO context FROM ironvault_private.email_actions WHERE group_id=p_group AND user_id=p_user LIMIT 1;
 first_request:=NOT FOUND;
 IF EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=p_group AND (user_id<>p_user OR new_email IS DISTINCT FROM p_new_email OR base_email IS DISTINCT FROM target.contact_email)) THEN RAISE EXCEPTION 'Contact group mismatch'; END IF;
 IF NOT first_request AND (context->>'requested_by' IS DISTINCT FROM p_actor::text OR EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=p_group AND (user_id<>p_user OR new_email IS DISTINCT FROM p_new_email OR base_email IS DISTINCT FROM target.contact_email))) THEN RAISE EXCEPTION 'Contact group mismatch'; END IF;
 context:=coalesce(context,jsonb_build_object('requested_by',p_actor,'actor',ironvault_private.audit_actor(p_actor,target.tenant_id),'requested_at',clock_timestamp()));
 PERFORM public.iv_queue_email_action(p_user,p_hash,p_kind,p_group,p_new_email);
 UPDATE ironvault_private.email_actions SET audit_context=context WHERE token_hash=p_hash AND user_id=p_user;
 IF first_request THEN
  PERFORM ironvault_private.write_audit(target.tenant_id,p_actor,CASE target.role WHEN 'member' THEN 'Member email change requested' WHEN 'staff' THEN 'Staff email change requested' ELSE 'Gym owner email change requested' END,
   coalesce(ironvault_private.audit_account(p_user,target.tenant_id)->>'name','Account')||' · Requested email: '||coalesce(target.contact_email,'Not provided')||' → '||p_new_email||' · Awaiting recipient confirmation',
   jsonb_build_object('target',ironvault_private.audit_account(p_user,target.tenant_id),'email_group',p_group,'phase','requested','changes',jsonb_build_object('email',jsonb_build_object('before',target.contact_email,'after',p_new_email))),context->'actor');
 END IF;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_confirm_email_action(p_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE action ironvault_private.email_actions%ROWTYPE; account ironvault_private.branch_accounts%ROWTYPE; requested_by uuid; snapshot jsonb; target jsonb;
BEGIN
 SELECT * INTO STRICT action FROM ironvault_private.email_actions WHERE token_hash=p_hash FOR UPDATE;
 IF action.expires_at<=now() OR action.confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'Verification link expired or used'; END IF;
 SELECT * INTO STRICT account FROM ironvault_private.branch_accounts WHERE user_id=action.user_id FOR UPDATE;
 IF account.contact_email IS DISTINCT FROM action.base_email THEN RAISE EXCEPTION 'Contact changed since this link was issued'; END IF;
 UPDATE ironvault_private.email_actions SET confirmed_at=now() WHERE token_hash=p_hash;
 IF action.kind='verify' THEN
  UPDATE ironvault_private.branch_accounts SET contact_verified=true WHERE user_id=account.user_id;
  UPDATE public.iv_user_roles r SET enabled=true WHERE r.user_id=account.user_id AND r.tenant_id=account.tenant_id AND r.role=account.role AND r.disabled_at IS NULL
   AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=r.tenant_id AND g.status='ACTIVE')
   AND (r.role<>'member' OR EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=r.tenant_id AND m.status IN ('ACTIVE','PENDING')));
 ELSE
  IF action.kind='correct_unverified' THEN
   IF account.contact_verified THEN RAISE EXCEPTION 'Verified contact requires both address proofs'; END IF;
  ELSE
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=action.group_id AND user_id=action.user_id
   AND kind='change_old' AND confirmed_at IS NOT NULL AND expires_at>now())
  OR NOT EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=action.group_id AND user_id=action.user_id
   AND kind='change_new' AND confirmed_at IS NOT NULL AND expires_at>now()) THEN RETURN false; END IF;
  END IF;
  IF account.role IN ('owner','staff') AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.tenant_id=account.tenant_id AND a.role IN ('owner','staff') AND a.user_id<>account.user_id AND a.contact_email=action.new_email) THEN RAISE EXCEPTION 'Admin portal email already in use'; END IF;
  UPDATE ironvault_private.branch_accounts SET contact_email=action.new_email,contact_verified=true WHERE user_id=account.user_id;
  IF account.role='member' THEN UPDATE public.members SET email=action.new_email WHERE id=(SELECT member_id FROM public.iv_user_roles WHERE user_id=account.user_id AND role='member') AND tenant_id=account.tenant_id; END IF;
  IF account.role='staff' THEN
   UPDATE public.owners SET staff=(SELECT jsonb_agg(CASE WHEN s.value->>'auth_user_id'=account.user_id::text THEN s.value||jsonb_build_object('email',action.new_email) ELSE s.value END)
    FROM jsonb_array_elements(staff) s) WHERE id=account.tenant_id;
  END IF;
 END IF;
 UPDATE public.iv_user_roles r SET enabled=true WHERE r.user_id=account.user_id AND r.tenant_id=account.tenant_id AND r.role=account.role AND r.disabled_at IS NULL
   AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=r.tenant_id AND g.status='ACTIVE')
   AND (r.role<>'member' OR EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=r.tenant_id AND m.status IN ('ACTIVE','PENDING')));
 IF action.kind<>'verify' THEN
  requested_by:=nullif(action.audit_context->>'requested_by','')::uuid;snapshot:=action.audit_context->'actor';
  target:=ironvault_private.audit_account(account.user_id,account.tenant_id);
  PERFORM ironvault_private.write_audit(account.tenant_id,requested_by,
   CASE account.role WHEN 'member' THEN 'Member email changed' WHEN 'staff' THEN 'Staff email changed' ELSE 'Gym owner email changed' END,
   coalesce(target->>'name','Account')||coalesce(' ('||(target->>'display_code')||')','')||' · Email: '||coalesce(account.contact_email,'Not provided')||' → '||action.new_email||' · Completed using recipient email proof',
   jsonb_build_object('target',target,'email_group',action.group_id,'confirmation','recipient email proof','changes',jsonb_build_object('email',jsonb_build_object('before',account.contact_email,'after',action.new_email))),
   coalesce(snapshot,jsonb_build_object('id',requested_by,'name','Requester unavailable (older request)','role','unknown')));
 END IF;
 RETURN true;
END $fn$;
NOTIFY pgrst,'reload schema';
COMMIT;
