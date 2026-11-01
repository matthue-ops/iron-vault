-- MANUAL SQL EDITOR UPDATE: only for a database with migrations 001-017 applied.
-- Installs short display codes, optional account confirmation, and report metadata; applies owner policy LAST.
-- No internal IDs, credentials, tenant links, balances or history are replaced.
-- Select/run the ENTIRE file once. Do not rerun the initial installation package.
BEGIN;

-- 202611010018_short_display_codes.sql
-- MANUAL ONLY after 017. Adds display codes; never changes internal IDs or links.

CREATE SEQUENCE ironvault_private.gym_display_sequence;
CREATE SEQUENCE ironvault_private.member_display_sequence;
REVOKE ALL ON SEQUENCE ironvault_private.gym_display_sequence,ironvault_private.member_display_sequence FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.display_code(p_prefix text,p_number bigint)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $fn$
 SELECT p_prefix||'-'||lpad(p_number::text,greatest(4,length(p_number::text)),'0');
$fn$;
REVOKE ALL ON FUNCTION ironvault_private.display_code(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.owners ADD COLUMN display_code text;
ALTER TABLE public.members ADD COLUMN display_code text;
UPDATE public.owners SET display_code=ironvault_private.display_code('GYM',nextval('ironvault_private.gym_display_sequence'));
UPDATE public.members SET display_code=ironvault_private.display_code('MEM',nextval('ironvault_private.member_display_sequence'));
ALTER TABLE public.owners ALTER COLUMN display_code SET DEFAULT ironvault_private.display_code('GYM',nextval('ironvault_private.gym_display_sequence'));
ALTER TABLE public.members ALTER COLUMN display_code SET DEFAULT ironvault_private.display_code('MEM',nextval('ironvault_private.member_display_sequence'));
ALTER TABLE public.owners ALTER COLUMN display_code SET NOT NULL;
ALTER TABLE public.members ALTER COLUMN display_code SET NOT NULL;
ALTER TABLE public.owners ADD CONSTRAINT iv_gym_display_code_unique UNIQUE(display_code);
ALTER TABLE public.members ADD CONSTRAINT iv_member_display_code_unique UNIQUE(display_code);
CREATE OR REPLACE VIEW public.iv_gyms WITH(security_barrier=true) AS
 SELECT visible.*,g.display_code FROM public.iv_visible_gyms() visible JOIN public.owners g ON g.id=visible.id;
CREATE OR REPLACE VIEW public.iv_members WITH(security_barrier=true) AS
 SELECT m.id,m.tenant_id,m.tenant_token,m.name,m.email,m.phone,NULL::text AS password,
 m.classification,m.discount_percentage,m.plan,m.card_barcode,m.wallet_balance,
 CASE WHEN ironvault_private.can_read_financial_reports(m.tenant_id) OR EXISTS(
  SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=m.id AND r.tenant_id=m.tenant_id)
 THEN m.amount ELSE NULL END AS amount,
 m.scans_used,m.last_scanned_date,m.expiration_date,m.status,m.date_joined,m.avatar,m.created_at,m.display_code
 FROM public.members m WHERE ironvault_private.can_read_member(m.id,m.tenant_id);
NOTIFY pgrst,'reload schema';

-- 202611010019_staff_without_confirmation.sql
-- MANUAL ONLY after 018. Owner-created staff can sign in before email confirmation.

-- Preserve existing contacts: conflicting legacy admin emails abort, never rewrite them.
CREATE UNIQUE INDEX iv_admin_portal_contact_unique ON ironvault_private.branch_accounts(tenant_id,contact_email) WHERE role IN ('owner','staff');
CREATE OR REPLACE FUNCTION public.iv_branch_identity(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id,a.role FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles) AND (a.contact_email=lower(btrim(p_email)) OR (a.role='member' AND EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=a.tenant_id AND (lower(m.id)=lower(btrim(p_email)) OR lower(m.display_code)=lower(btrim(p_email))))))
  AND (a.contact_verified OR a.role IN ('member','staff')) AND r.enabled AND r.tenant_id=a.tenant_id AND r.role=a.role;
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
 INSERT INTO public.iv_user_roles(user_id,tenant_id,role,member_id,enabled) VALUES(p_user,job.tenant_id,job.role,member_id,job.role IN ('member','staff'));
 INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id) VALUES(job.tenant_id,job.role,job.contact_email,p_user);
 IF job.role='staff' THEN
  UPDATE public.owners SET staff=coalesce(staff,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('name',job.payload->>'name',
   'email',job.contact_email,'auth_user_id',p_user,'dateCreated',((now() AT TIME ZONE 'Asia/Manila')::date)::text)) WHERE id=job.tenant_id;
 END IF;
 UPDATE ironvault_private.provision_requests SET completed_user=p_user WHERE request_id=p_request;
 RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'member_id',member_id,'user_id',p_user);
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_prepare_branch_account(p_request uuid,p_actor uuid,p_tenant text,p_role text,p_email text,p_alias text,p_payload jsonb,p_new_gym boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provision_requests%ROWTYPE; actor public.iv_user_roles%ROWTYPE; key text; price numeric; name text;
BEGIN
 IF p_request IS NULL OR p_role NOT IN ('owner','staff','member') OR p_email IS NULL OR p_email<>lower(btrim(p_email))
  OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  OR p_alias !~ '^[a-f0-9]{64}@accounts\.ironvault\.invalid$'
  OR p_payload ? 'password' OR p_payload ? 'service_role' THEN RAISE EXCEPTION 'Invalid account request'; END IF;
 IF p_role='staff' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.tenant_id=p_tenant AND a.role IN ('owner','staff') AND a.contact_email=p_email) THEN
  -- A same-request retry may find its own already-completed account.
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.provision_requests WHERE request_id=p_request AND tenant_id=p_tenant AND contact_email=p_email AND role=p_role) THEN RAISE EXCEPTION 'Admin portal email already in use'; END IF;
 END IF;
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
  IF account.role IN ('owner','staff') AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.tenant_id=account.tenant_id AND a.role IN ('owner','staff') AND a.user_id<>account.user_id AND a.contact_email=action.new_email) THEN RAISE EXCEPTION 'Admin portal email already in use'; END IF;
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
CREATE FUNCTION public.iv_correct_unverified_staff_contact(p_actor uuid,p_user uuid,p_email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE target ironvault_private.branch_accounts%ROWTYPE;
BEGIN
 SELECT * INTO STRICT target FROM ironvault_private.branch_accounts WHERE user_id=p_user AND role='staff' FOR UPDATE;
 IF target.contact_verified OR p_email IS NULL OR p_email<>lower(btrim(p_email)) OR length(p_email)>254
  OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid staff contact correction'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=p_actor AND r.enabled
  AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.role='owner' AND r.tenant_id=target.tenant_id
  AND EXISTS(SELECT 1 FROM public.owners WHERE id=target.tenant_id AND status='ACTIVE')))) THEN RAISE EXCEPTION 'Owner required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=p_user AND tenant_id=target.tenant_id AND role='staff' AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Staff access revoked'; END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.tenant_id=target.tenant_id AND a.role IN ('owner','staff') AND a.user_id<>p_user AND a.contact_email=p_email) THEN RAISE EXCEPTION 'Admin portal email already in use'; END IF;
 UPDATE ironvault_private.branch_accounts SET contact_email=p_email WHERE user_id=p_user;
 DELETE FROM ironvault_private.email_actions WHERE user_id=p_user;
 UPDATE public.owners SET staff=coalesce((SELECT jsonb_agg(CASE WHEN s.value->>'auth_user_id'=p_user::text THEN s.value||jsonb_build_object('email',p_email) ELSE s.value END)
  FROM jsonb_array_elements(coalesce(staff,'[]'::jsonb)) s),'[]'::jsonb) WHERE id=target.tenant_id;
 PERFORM public.iv_log_event(target.tenant_id,'Unverified staff contact corrected',p_user::text);
END $fn$;
REVOKE ALL ON FUNCTION public.iv_correct_unverified_staff_contact(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iv_correct_unverified_staff_contact(uuid,uuid,text) TO service_role;
-- Enable only accounts held by the former email gate; never restore explicit revocations.
UPDATE public.iv_user_roles r SET enabled=true
FROM ironvault_private.branch_accounts a,public.owners g
WHERE r.user_id=a.user_id AND r.tenant_id=a.tenant_id AND r.role='staff' AND a.role='staff'
 AND g.id=r.tenant_id AND g.status='ACTIVE' AND NOT r.enabled AND r.disabled_at IS NULL;


-- 202611010020_clear_report_snapshots.sql
-- MANUAL ONLY after 018/019. Adds report metadata and canonical purchase receipts.

CREATE OR REPLACE FUNCTION public.iv_report_snapshot(p_tenant text,p_start date,p_end date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb; start_at timestamptz; end_at timestamptz;
BEGIN
 IF NOT ironvault_private.can_read_financial_reports(p_tenant) OR p_start IS NULL OR p_end IS NULL OR p_end<p_start THEN
  RAISE EXCEPTION 'Not authorized or invalid report dates'; END IF;
 start_at:=p_start::timestamp AT TIME ZONE 'Asia/Manila';end_at:=(p_end+1)::timestamp AT TIME ZONE 'Asia/Manila';
 SELECT jsonb_build_object(
  'financial',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_financial_transactions x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'attendance',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_attendance_logs x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'activity',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_activity_logs x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'sessions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_staff_sessions x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'members',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'tenant_id',m.tenant_id,'name',m.name,'classification',m.classification,
    'display_code',m.display_code,'created_at',m.created_at,'expiration_date',m.expiration_date,'scans_used',m.scans_used,'last_scanned_date',m.last_scanned_date,'plan',m.plan,'wallet_balance',m.wallet_balance,'status',m.status)) FROM public.members m WHERE tenant_id=p_tenant),'[]'::jsonb)) INTO result;
 RETURN result||jsonb_build_object('purchases',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'request_id',r.request_id,'member_id',r.member_id,'plan',r.payload->>'plan','amount',r.payload->'amount',
  'cash',r.payload->'cash','created_at',r.created_at,'renewal',EXISTS(SELECT 1 FROM ironvault_private.financial_requests previous
   WHERE previous.tenant_id=p_tenant AND previous.member_id=r.member_id AND previous.payload->>'operation'='purchase'
    AND (previous.created_at,previous.request_id)<(r.created_at,r.request_id))) ORDER BY r.created_at DESC)
  FROM ironvault_private.financial_requests r WHERE r.tenant_id=p_tenant AND r.payload->>'operation'='purchase'
   AND r.created_at>=start_at AND r.created_at<end_at),'[]'::jsonb));
END $fn$;
NOTIFY pgrst,'reload schema';

-- 202611020021_owner_without_confirmation.sql
-- MANUAL ONLY. Apply directly after installed 001-017; 018-020 are NOT prerequisites.
-- Also compatible after 018-020. If installing those later, reapply this file LAST
-- because 019 replaces the same account functions. Safe to repeat; no SQL run by agent.
-- Only email activation policy changes; existing identities/passwords/history remain.

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
