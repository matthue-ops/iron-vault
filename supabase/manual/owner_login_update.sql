-- MANUAL ONLY. Apply directly after installed 001-017; 018-020 are NOT prerequisites.
-- Also compatible after 018-020. If installing those later, reapply this file LAST
-- because 019 replaces the same account functions. Safe to repeat; no SQL run by agent.
-- Only email activation policy changes; existing identities/passwords/history remain.
BEGIN;
CREATE OR REPLACE FUNCTION public.iv_branch_identity(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id,a.role FROM ironvault_private.branch_accounts a
 JOIN public.iv_user_roles r ON r.user_id=a.user_id
 JOIN public.owners g ON g.id=a.tenant_id AND g.status='ACTIVE'
 WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles)
  AND (a.contact_email=lower(btrim(p_email)) OR (a.role='member' AND EXISTS(
   SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=a.tenant_id
    AND (lower(m.id)=lower(btrim(p_email)) OR lower(to_jsonb(m)->>'display_code')=lower(btrim(p_email))))))
  AND r.enabled AND r.disabled_at IS NULL AND r.tenant_id=a.tenant_id AND r.role=a.role
  AND (r.role<>'member' OR EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id
   AND m.tenant_id=r.tenant_id AND m.status IN ('ACTIVE','PENDING')));
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
CREATE OR REPLACE FUNCTION public.iv_confirm_email_action(p_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE action ironvault_private.email_actions%ROWTYPE; account ironvault_private.branch_accounts%ROWTYPE;
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
 RETURN true;
END $fn$;

-- Resume only completed owner provisioning held by unverified contact, never revoked
-- roles, suspended gyms, incomplete jobs, or unrelated PROVISIONING records.
UPDATE public.owners g SET status='ACTIVE'
WHERE g.status='PROVISIONING' AND EXISTS(
 SELECT 1 FROM ironvault_private.branch_accounts a
 JOIN public.iv_user_roles r ON r.user_id=a.user_id AND r.tenant_id=a.tenant_id AND r.role=a.role
 JOIN ironvault_private.provision_requests j ON j.completed_user=a.user_id AND j.tenant_id=a.tenant_id AND j.role=a.role
 JOIN auth.users u ON u.id=a.user_id AND u.raw_app_meta_data->>'iv_provision_request'=j.request_id::text
 WHERE a.tenant_id=g.id AND a.role='owner' AND NOT a.contact_verified AND r.disabled_at IS NULL);

-- Contact remains unverified. Do not change passwords, Auth IDs, member status,
-- approval, or explicit disabled_at markers. Inactive memberships stay disabled.
UPDATE public.iv_user_roles r SET enabled=true
FROM ironvault_private.branch_accounts a, public.owners g
WHERE r.user_id=a.user_id AND r.tenant_id=a.tenant_id AND r.role=a.role
 AND r.role IN ('owner','staff','member') AND NOT a.contact_verified
 AND g.id=r.tenant_id AND g.status='ACTIVE' AND NOT r.enabled AND r.disabled_at IS NULL
 AND (r.role<>'member' OR EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id
  AND m.tenant_id=r.tenant_id AND m.status IN ('ACTIVE','PENDING')));

-- Keep the gateway service-only even if local default grants differ.
REVOKE ALL ON FUNCTION public.iv_branch_identity(text,text[],text), public.iv_finish_branch_account(uuid,uuid), public.iv_confirm_email_action(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iv_branch_identity(text,text[],text), public.iv_finish_branch_account(uuid,uuid), public.iv_confirm_email_action(text) TO service_role;

COMMIT;
