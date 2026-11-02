-- Apply only after migrations 001-015. No Auth DML or record deletion.
-- Members may sign in without contact verification. Gym approval remains separate.
BEGIN;
CREATE OR REPLACE FUNCTION public.iv_branch_identity(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id,a.role FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles) AND a.contact_email=lower(btrim(p_email))
  AND (a.contact_verified OR a.role='member') AND r.enabled AND r.tenant_id=a.tenant_id AND r.role=a.role;
$fn$;


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
 INSERT INTO public.iv_user_roles(user_id,tenant_id,role,member_id,enabled) VALUES(p_user,job.tenant_id,job.role,member_id,job.role='member');
 INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id) VALUES(job.tenant_id,job.role,job.contact_email,p_user);
 IF job.role='staff' THEN
  UPDATE public.owners SET staff=coalesce(staff,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('name',job.payload->>'name',
   'email',job.contact_email,'auth_user_id',p_user,'dateCreated',((now() AT TIME ZONE 'Asia/Manila')::date)::text)) WHERE id=job.tenant_id;
 END IF;
 UPDATE ironvault_private.provision_requests SET completed_user=p_user WHERE request_id=p_request;
 RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'member_id',member_id,'user_id',p_user);
END $fn$;


CREATE OR REPLACE FUNCTION public.iv_save_member_profiles(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; m public.members%ROWTYPE; tenant text; operator boolean; owner_access boolean; discount numeric;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>500 THEN RAISE EXCEPTION 'Invalid profile batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO m FROM public.members WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Create member accounts through registration; restore cannot create financial records'; END IF;
  tenant:=m.tenant_id;operator:=public.iv_can_access(tenant);owner_access:=public.iv_can_access(tenant,ARRAY['owner']::text[]);
  IF NOT operator AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
   AND r.role='member' AND r.member_id=m.id AND r.tenant_id=tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=tenant AND g.status='ACTIVE')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF item ? 'tenant_id' AND item->>'tenant_id' IS DISTINCT FROM tenant THEN RAISE EXCEPTION 'Cannot move membership'; END IF;
  IF length(coalesce(item->>'name',m.name)) NOT BETWEEN 1 AND 160 OR length(coalesce(item->>'phone',''))>50
   OR length(coalesce(item->>'avatar',''))>750000 THEN RAISE EXCEPTION 'Invalid profile fields'; END IF;
  IF item ? 'email' AND lower(btrim(item->>'email')) IS DISTINCT FROM lower(btrim(m.email)) THEN
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
   discount_percentage=discount WHERE id=m.id;
  IF owner_access AND item->>'status'='ACTIVE' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id WHERE r.member_id=m.id AND a.tenant_id=tenant AND r.tenant_id=tenant ) THEN
   UPDATE public.iv_user_roles SET enabled=true,disabled_at=NULL WHERE member_id=m.id AND tenant_id=tenant AND role='member';
  END IF;
  INSERT INTO public.iv_activity_logs(tenant_id,actor_id,event,details) VALUES(tenant,auth.uid(),'Member profile updated',m.id);
 END LOOP;
END $fn$;

-- Resume member accounts blocked only by the previous mail gate; preserve explicit
-- revocations (disabled_at) and inactive memberships. Contact remains unverified.
UPDATE public.iv_user_roles r SET enabled=true
FROM ironvault_private.branch_accounts a, public.members m
WHERE r.user_id=a.user_id AND r.role='member' AND a.role='member'
 AND r.tenant_id=a.tenant_id AND m.id=r.member_id AND m.tenant_id=r.tenant_id
 AND m.status IN ('ACTIVE','PENDING') AND NOT r.enabled AND r.disabled_at IS NULL;
COMMIT;
