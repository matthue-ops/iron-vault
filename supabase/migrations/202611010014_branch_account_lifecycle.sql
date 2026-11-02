-- MANUAL ONLY; after 012/013. Additive mappings/jobs/tokens/rate windows.
-- Preserve existing Auth IDs/passwords and all financial history. No Auth tables
-- are created, altered or deleted. Existing contact mappings are backfilled.
BEGIN;
SET LOCAL search_path=pg_catalog;
CREATE TABLE ironvault_private.branch_accounts (
 tenant_id text NOT NULL REFERENCES public.owners(id),
 role text NOT NULL CHECK(role IN ('owner','staff','member')),
 contact_email text NOT NULL CHECK(contact_email=lower(btrim(contact_email))),
 user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id),
 contact_verified boolean NOT NULL DEFAULT false,
 PRIMARY KEY(tenant_id,role,contact_email)
);
INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id,contact_verified)
SELECT r.tenant_id,r.role,lower(btrim(CASE WHEN r.role='member' THEN m.email WHEN r.role='owner' THEN g.email
 ELSE coalesce((SELECT s.value->>'email' FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s
 WHERE s.value->>'auth_user_id'=r.user_id::text LIMIT 1),u.email) END)),r.user_id,u.email_confirmed_at IS NOT NULL
FROM public.iv_user_roles r JOIN auth.users u ON u.id=r.user_id JOIN public.owners g ON g.id=r.tenant_id
LEFT JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
WHERE r.role IN ('owner','staff','member');
CREATE TABLE ironvault_private.provision_requests (
 request_id uuid PRIMARY KEY,
 tenant_id text NOT NULL REFERENCES public.owners(id),
 role text NOT NULL CHECK(role IN ('owner','staff','member')),
 contact_email text NOT NULL,
 alias text NOT NULL UNIQUE,
 actor_id uuid REFERENCES auth.users(id),
 payload jsonb NOT NULL,
 completed_user uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,role,contact_email)
);
CREATE TABLE ironvault_private.email_actions (
 token_hash text PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES auth.users(id),
 kind text NOT NULL CHECK(kind IN ('verify','change_old','change_new','correct_unverified')),
 new_email text,
 base_email text NOT NULL,
 group_id uuid NOT NULL,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '1 hour',
 confirmed_at timestamptz
);
CREATE TABLE ironvault_private.auth_rate_windows (
 bucket text PRIMARY KEY,window_start timestamptz NOT NULL,attempts integer NOT NULL
);
CREATE FUNCTION public.iv_auth_rate_limit(p_bucket text,p_limit integer,p_seconds integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE attempts integer;
BEGIN
 IF p_limit<1 OR p_limit>1000 OR p_seconds<1 OR p_seconds>86400 OR length(p_bucket)>200 THEN RAISE EXCEPTION 'Invalid rate policy'; END IF;
 INSERT INTO ironvault_private.auth_rate_windows AS w(bucket,window_start,attempts) VALUES(p_bucket,now(),1)
 ON CONFLICT(bucket) DO UPDATE SET window_start=CASE WHEN w.window_start<now()-p_seconds*interval '1 second' THEN now() ELSE w.window_start END,
 attempts=CASE WHEN w.window_start<now()-p_seconds*interval '1 second' THEN 1 ELSE w.attempts+1 END RETURNING w.attempts INTO attempts;
 RETURN attempts<=p_limit;
END $fn$;
CREATE FUNCTION public.iv_branch_identity(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id,a.role FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles) AND a.contact_email=lower(btrim(p_email))
  AND a.contact_verified AND r.enabled AND r.tenant_id=a.tenant_id AND r.role=a.role;
$fn$;
CREATE FUNCTION public.iv_prepare_branch_account(p_request uuid,p_actor uuid,p_tenant text,p_role text,p_email text,p_alias text,p_payload jsonb,p_new_gym boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provision_requests%ROWTYPE; actor public.iv_user_roles%ROWTYPE; key text; price numeric; name text;
BEGIN
 IF p_request IS NULL OR p_role NOT IN ('owner','staff','member') OR p_email IS NULL OR p_email<>lower(btrim(p_email))
  OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  OR p_alias !~ '^[a-f0-9]{64}@accounts\.ironvault\.invalid$'
  OR p_payload ? 'password' OR p_payload ? 'service_role' THEN RAISE EXCEPTION 'Invalid account request'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text,1));
 SELECT * INTO job FROM ironvault_private.provision_requests WHERE request_id=p_request;
 IF FOUND THEN
  IF job.actor_id IS DISTINCT FROM p_actor OR job.tenant_id<>p_tenant OR job.role<>p_role OR job.contact_email<>p_email
   OR job.alias<>p_alias OR job.payload<>p_payload THEN RAISE EXCEPTION 'Provision request mismatch'; END IF;
 END IF;
 SELECT * INTO actor FROM public.iv_user_roles WHERE user_id=p_actor AND enabled;
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
CREATE FUNCTION public.iv_find_created_account(p_request uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT u.id FROM ironvault_private.provision_requests p JOIN auth.users u ON u.email=p.alias
 WHERE p.request_id=p_request AND u.raw_app_meta_data->>'iv_provision_request'=p_request::text;
$fn$;
CREATE FUNCTION public.iv_finish_branch_account(p_request uuid,p_user uuid)
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
 INSERT INTO public.iv_user_roles(user_id,tenant_id,role,member_id,enabled) VALUES(p_user,job.tenant_id,job.role,member_id,false);
 INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id) VALUES(job.tenant_id,job.role,job.contact_email,p_user);
 IF job.role='staff' THEN
  UPDATE public.owners SET staff=coalesce(staff,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('name',job.payload->>'name',
   'email',job.contact_email,'auth_user_id',p_user,'dateCreated',((now() AT TIME ZONE 'Asia/Manila')::date)::text)) WHERE id=job.tenant_id;
 END IF;
 UPDATE ironvault_private.provision_requests SET completed_user=p_user WHERE request_id=p_request;
 RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'member_id',member_id,'user_id',p_user);
END $fn$;
CREATE FUNCTION public.iv_queue_email_action(p_user uuid,p_hash text,p_kind text,p_group uuid,p_new_email text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF p_hash !~ '^[a-f0-9]{64}$' OR p_kind NOT IN ('verify','change_old','change_new','correct_unverified') THEN RAISE EXCEPTION 'Invalid verification action'; END IF;
 IF p_kind<>'verify' AND (p_new_email IS NULL OR p_new_email<>lower(btrim(p_new_email))) THEN RAISE EXCEPTION 'Invalid contact email'; END IF;
 INSERT INTO ironvault_private.email_actions(token_hash,user_id,kind,group_id,new_email,base_email)
 SELECT p_hash,p_user,p_kind,p_group,p_new_email,contact_email FROM ironvault_private.branch_accounts WHERE user_id=p_user;
 IF NOT FOUND THEN RAISE EXCEPTION 'Account mapping unavailable'; END IF;
END $fn$;
CREATE FUNCTION public.iv_confirm_email_action(p_hash text)
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
  UPDATE public.iv_user_roles SET enabled=true WHERE user_id=account.user_id AND disabled_at IS NULL;
  IF account.role='owner' THEN UPDATE public.owners SET status='ACTIVE' WHERE id=account.tenant_id AND status='PROVISIONING'; END IF;
 ELSE
  IF action.kind='correct_unverified' THEN
   IF account.contact_verified THEN RAISE EXCEPTION 'Verified contact requires both address proofs'; END IF;
  ELSE
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=action.group_id AND user_id=action.user_id
   AND kind='change_old' AND confirmed_at IS NOT NULL AND expires_at>now())
  OR NOT EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=action.group_id AND user_id=action.user_id
   AND kind='change_new' AND confirmed_at IS NOT NULL AND expires_at>now()) THEN RETURN false; END IF;
  END IF;
  UPDATE ironvault_private.branch_accounts SET contact_email=action.new_email,contact_verified=true WHERE user_id=account.user_id;
  IF account.role='member' THEN UPDATE public.members SET email=action.new_email WHERE id=(SELECT member_id FROM public.iv_user_roles WHERE user_id=account.user_id AND role='member') AND tenant_id=account.tenant_id; END IF;
  IF account.role='staff' THEN
   UPDATE public.owners SET staff=(SELECT jsonb_agg(CASE WHEN s.value->>'auth_user_id'=account.user_id::text THEN s.value||jsonb_build_object('email',action.new_email) ELSE s.value END)
    FROM jsonb_array_elements(staff) s) WHERE id=account.tenant_id;
  END IF;
 END IF;
 UPDATE public.iv_user_roles SET enabled=true WHERE user_id=account.user_id AND disabled_at IS NULL;
 IF account.role='owner' THEN UPDATE public.owners SET status='ACTIVE' WHERE id=account.tenant_id AND status='PROVISIONING'; END IF;
 RETURN true;
END $fn$;
CREATE FUNCTION public.iv_branch_account_details(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('user_id',a.user_id,'tenant_id',a.tenant_id,'role',a.role,'email',a.contact_email,
 'verified',a.contact_verified,'enabled',r.enabled,'gym_name',g.gym_name,'token',g.token,'auth_email',u.email)
 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 JOIN public.owners g ON g.id=a.tenant_id JOIN auth.users u ON u.id=a.user_id WHERE a.user_id=p_user;
$fn$;
CREATE FUNCTION public.iv_lookup_branch_account(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id FROM ironvault_private.branch_accounts a WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles) AND a.contact_email=lower(btrim(p_email));
$fn$;
CREATE FUNCTION public.iv_update_staff_name(p_tenant text,p_user uuid,p_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT public.iv_can_access(p_tenant,ARRAY['owner']::text[]) OR length(p_name) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'Not authorized or invalid name'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=p_user AND tenant_id=p_tenant AND role='staff' AND enabled) THEN RAISE EXCEPTION 'Staff not found'; END IF;
 UPDATE public.owners SET staff=coalesce((SELECT jsonb_agg(CASE WHEN x.value->>'auth_user_id'=p_user::text THEN x.value||jsonb_build_object('name',p_name) ELSE x.value END)
  FROM jsonb_array_elements(staff) x),'[]'::jsonb) WHERE id=p_tenant;
 PERFORM public.iv_log_event(p_tenant,'Staff name updated',p_user::text);
END $fn$;
REVOKE ALL ON FUNCTION public.iv_update_staff_name(text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_update_staff_name(text,uuid,text) TO authenticated,service_role;
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
  IF owner_access AND item->>'status'='ACTIVE' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id WHERE r.member_id=m.id AND a.tenant_id=tenant AND r.tenant_id=tenant AND a.contact_verified) THEN
   UPDATE public.iv_user_roles SET enabled=true,disabled_at=NULL WHERE member_id=m.id AND tenant_id=tenant AND role='member';
  END IF;
  INSERT INTO public.iv_activity_logs(tenant_id,actor_id,event,details) VALUES(tenant,auth.uid(),'Member profile updated',m.id);
 END LOOP;
END $fn$;
CREATE FUNCTION public.iv_contact_status()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('email',a.contact_email,'verified',a.contact_verified)
 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 WHERE a.user_id=auth.uid() AND r.enabled;
$fn$;
REVOKE ALL ON FUNCTION public.iv_contact_status() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_contact_status() TO authenticated,service_role;
-- Close the old metadata-only signup path: private aliases are provisioned by the
-- trusted service with protected app_metadata, not caller-editable user_metadata.
-- Keep the existing trigger attachment, as required. New gateway sets no old flag.
CREATE OR REPLACE FUNCTION public.iv_member_auth_signup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF coalesce(NEW.raw_user_meta_data->>'iv_member_signup','')='true' THEN
  RAISE EXCEPTION 'Use branch-aware member registration'; END IF;
 RETURN NEW;
END $fn$;
-- Reflect verified owner contact, not private alias, in the safe compatibility view.
-- Existing view column order/types stay identical.
CREATE OR REPLACE FUNCTION public.iv_visible_gyms()
RETURNS TABLE(id text,gym_name text,token text,logo text,status text,pricing jsonb,date_created timestamptz,created_at timestamptz,
 owner_name text,email text,password text,staff jsonb,audit_logs jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $visible$

 SELECT g.id,g.gym_name,g.token,g.logo,g.status,jsonb_build_object('day',g.pricing->'day','week',g.pricing->'week','month',g.pricing->'month','studentDiscount',g.pricing->'studentDiscount','seniorDiscount',g.pricing->'seniorDiscount'),g.date_created,g.created_at,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN g.owner_name ELSE NULL END AS owner_name,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN coalesce((SELECT contact_email FROM ironvault_private.branch_accounts a WHERE a.tenant_id=g.id AND a.role='owner'),g.email) ELSE NULL END AS email,
 NULL::text AS password,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN
  coalesce((SELECT jsonb_agg(jsonb_build_object('name',s.value->>'name','email',s.value->>'email','auth_user_id',s.value->>'auth_user_id','dateCreated',s.value->>'dateCreated')) FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s
   WHERE EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.tenant_id=g.id AND r.disabled_at IS NULL AND r.role='staff' AND r.user_id::text=s.value->>'auth_user_id')),'[]'::jsonb)
 ELSE '[]'::jsonb END AS staff,'[]'::jsonb AS audit_logs
 FROM public.owners g WHERE g.status IN ('ACTIVE','PROVISIONING') OR public.iv_can_access(g.id);
$visible$;
CREATE OR REPLACE VIEW public.iv_gyms WITH(security_barrier=true) AS SELECT * FROM public.iv_visible_gyms();
DO $acl$
DECLARE t text; signature text;
BEGIN
 FOREACH t IN ARRAY ARRAY['branch_accounts','provision_requests','email_actions','auth_rate_windows'] LOOP
  EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',t);
  EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['public.iv_auth_rate_limit(text,integer,integer)',
 'public.iv_branch_identity(text,text[],text)','public.iv_prepare_branch_account(uuid,uuid,text,text,text,text,jsonb,boolean)',
 'public.iv_find_created_account(uuid)','public.iv_finish_branch_account(uuid,uuid)',
 'public.iv_queue_email_action(uuid,text,text,uuid,text)','public.iv_confirm_email_action(text)',
 'public.iv_branch_account_details(uuid)','public.iv_lookup_branch_account(text,text[],text)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',signature);
 END LOOP;
END $acl$;
REVOKE ALL ON FUNCTION public.iv_member_auth_signup() FROM PUBLIC,anon,authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT role,count(*) FROM ironvault_private.branch_accounts GROUP BY role;
-- Original snapshot expected 4 member/2 owner; no staff; no Auth account changed.
-- If backfill/uniqueness/role dependencies fail, ROLLBACK, preserve all rows and
-- return the error. Never force success by deleting accounts/history.
