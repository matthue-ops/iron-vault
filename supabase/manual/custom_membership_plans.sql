-- MANUAL ONLY after confirmed 058. Existing plans, receipts and expiry dates are untouched.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.owner_contact_recoveries') IS NULL OR to_regprocedure('ironvault_private.plan_terms(text,text)') IS NULL THEN RAISE EXCEPTION 'Confirm migration 058 and prerequisites first';END IF;
 IF to_regclass('ironvault_private.membership_plans') IS NOT NULL THEN RAISE EXCEPTION '059 already installed; do not reapply';END IF;
END $guard$;
CREATE TABLE ironvault_private.membership_plans(id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,name text NOT NULL CHECK(length(name) BETWEEN 1 AND 60),price numeric(12,2) NOT NULL CHECK(price>0 AND price<=10000000),duration_days integer NOT NULL CHECK(duration_days BETWEEN 1 AND 3650),archived boolean NOT NULL DEFAULT false,revision bigint NOT NULL DEFAULT 1,updated_by uuid NOT NULL,updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(tenant_id,id));
CREATE UNIQUE INDEX iv_custom_plan_name ON ironvault_private.membership_plans(tenant_id,lower(name));
CREATE TABLE ironvault_private.membership_plan_purchases(request_id uuid PRIMARY KEY REFERENCES ironvault_private.financial_requests(request_id) ON DELETE CASCADE,tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,plan_id uuid NOT NULL,revision bigint NOT NULL,name text NOT NULL,duration_days integer NOT NULL,base_price numeric NOT NULL,charged_price numeric NOT NULL,discount_percentage numeric NOT NULL,expiration_date text NOT NULL,actor_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),FOREIGN KEY(tenant_id,plan_id) REFERENCES ironvault_private.membership_plans(tenant_id,id));
CREATE INDEX iv_custom_plan_entitlement ON ironvault_private.membership_plan_purchases(member_id,tenant_id,name,expiration_date);
ALTER TABLE ironvault_private.membership_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.membership_plan_purchases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.membership_plans,ironvault_private.membership_plan_purchases FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.iv_membership_plans(p_tenant text,p_action text DEFAULT 'list',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE r text;manage boolean;v ironvault_private.membership_plans%ROWTYPE;new_name text;new_price numeric;days integer;plan_key uuid;
BEGIN
 SELECT role INTO r FROM public.iv_user_roles WHERE user_id=auth.uid() AND enabled AND disabled_at IS NULL AND (tenant_id=p_tenant OR (role='super_admin' AND tenant_id IS NULL));
 IF r IS NULL OR NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RAISE EXCEPTION 'Membership plan access denied' USING ERRCODE='42501';END IF;
 IF r='staff' AND NOT EXISTS(SELECT 1 FROM ironvault_private.staff_access WHERE tenant_id=p_tenant AND user_id=auth.uid() AND state='active') THEN RAISE EXCEPTION 'Staff access unavailable' USING ERRCODE='42501';END IF;
 IF r='member' THEN
  IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles u JOIN public.members m ON m.id=u.member_id AND m.tenant_id=u.tenant_id WHERE u.user_id=auth.uid() AND u.tenant_id=p_tenant AND m.status IN ('ACTIVE','PENDING')) THEN RAISE EXCEPTION 'Membership plan access denied' USING ERRCODE='42501';END IF;
  PERFORM ironvault_private.subscription_require(p_tenant,'portal');
 ELSE PERFORM ironvault_private.subscription_require(p_tenant,'read');END IF;
 manage:=r='owner' OR (r='staff' AND ironvault_private.staff_has_permission(p_tenant,'pricing_manage'));
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>10000 THEN RAISE EXCEPTION 'Invalid plan request';END IF;
 IF p_action<>'list' THEN
  IF NOT manage OR r='super_admin' THEN RAISE EXCEPTION 'Gym membership pricing permission required' USING ERRCODE='42501';END IF;
  PERFORM ironvault_private.staff_require(p_tenant,'pricing_manage');PERFORM ironvault_private.subscription_require(p_tenant,'operations');
  plan_key:=(p_data->>'id')::uuid;IF plan_key IS NULL THEN RAISE EXCEPTION 'Plan identity required';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant||':plans',59));
  SELECT * INTO v FROM ironvault_private.membership_plans WHERE membership_plans.id=plan_key AND tenant_id=p_tenant FOR UPDATE;
  IF p_action='save' THEN
   new_name:=btrim(p_data->>'name');new_price:=(p_data->>'price')::numeric;days:=(p_data->>'duration_days')::integer;
   IF new_name IS NULL OR length(new_name) NOT BETWEEN 1 AND 60 OR new_name ~ '[[:cntrl:]]' OR lower(new_name) IN ('1-day pass','1-week pass','1-month unlimited','not selected') OR new_name LIKE 'Custom · %' OR new_price IS NULL OR new_price::text IN ('NaN','Infinity','-Infinity') OR new_price<=0 OR new_price>10000000 OR new_price<>round(new_price,2) OR days IS NULL OR days NOT BETWEEN 1 AND 3650 THEN RAISE EXCEPTION 'Use a unique name, a positive price with at most two decimals, and 1–3650 days';END IF;
   IF v.id IS NOT NULL AND v.name=new_name AND v.price=new_price AND v.duration_days=days AND v.revision=(p_data->>'revision')::bigint+1 THEN NULL;
   ELSE
    IF coalesce(v.revision,0) IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Plan changed. Refresh before saving';END IF;
    IF v.id IS NULL THEN INSERT INTO ironvault_private.membership_plans(id,tenant_id,name,price,duration_days,updated_by) VALUES(plan_key,p_tenant,new_name,new_price,days,auth.uid());ELSE UPDATE ironvault_private.membership_plans SET name=new_name,price=new_price,duration_days=days,revision=revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE membership_plans.id=plan_key AND tenant_id=p_tenant;END IF;
    PERFORM public.iv_log_event(p_tenant,'Custom membership plan saved','Future purchases only; existing memberships are unchanged.');
   END IF;
  ELSIF p_action IN ('archive','restore') THEN
   IF v.id IS NULL THEN RAISE EXCEPTION 'Plan unavailable';END IF;
   IF v.archived IS DISTINCT FROM (p_action='archive') THEN
    IF v.revision IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Plan changed. Refresh before updating';END IF;
    UPDATE ironvault_private.membership_plans SET archived=p_action='archive',revision=revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE membership_plans.id=plan_key AND tenant_id=p_tenant;
    PERFORM public.iv_log_event(p_tenant,'Custom membership plan availability changed','Existing purchased passes retain their original validity.');
   END IF;
  ELSE RAISE EXCEPTION 'Unsupported plan action';END IF;
 END IF;
 RETURN jsonb_build_object('version',6,'can_manage',manage,'items',coalesce((SELECT jsonb_agg((to_jsonb(p)-'updated_by')||jsonb_build_object('purchase_key','Custom · '||p.name||' · '||p.duration_days||' days') ORDER BY p.archived,p.name) FROM ironvault_private.membership_plans p WHERE p.tenant_id=p_tenant AND (NOT p.archived OR manage OR r='super_admin')),'[]'));
END $fn$;
ALTER FUNCTION ironvault_private.plan_terms(text,text) RENAME TO plan_terms_059_base;
CREATE FUNCTION ironvault_private.plan_terms(p_member text,p_plan text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;p ironvault_private.membership_plans%ROWTYPE;cost numeric;discount numeric;
BEGIN
 IF p_plan NOT LIKE 'Custom · %' OR p_plan IS NULL THEN RETURN ironvault_private.plan_terms_059_base(p_member,p_plan);END IF;
 SELECT * INTO STRICT m FROM public.members WHERE id=p_member;
 IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=m.tenant_id AND status='ACTIVE') THEN RAISE EXCEPTION 'Gym inactive';END IF;
 SELECT * INTO p FROM ironvault_private.membership_plans WHERE tenant_id=m.tenant_id AND 'Custom · '||name||' · '||duration_days||' days'=p_plan AND NOT archived FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Custom plan changed or is unavailable. Refresh the plan list';END IF;
 discount:=coalesce(m.discount_percentage,0);cost:=p.price;
 IF discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>=100 THEN RAISE EXCEPTION 'Invalid member discount';END IF;
 IF discount>0 THEN cost:=round(cost*(1-discount/100));END IF;
 IF cost<=0 THEN RAISE EXCEPTION 'Discounted price must be positive';END IF;
 RETURN jsonb_build_object('price',cost,'wallet_balance',coalesce(m.wallet_balance,0),'expiration_date',((now() AT TIME ZONE 'Asia/Manila')::date+p.duration_days-1)::text,'plan_id',p.id,'revision',p.revision,'duration_days',p.duration_days,'base_price',p.price,'discount_percentage',discount);
END $fn$;
ALTER FUNCTION ironvault_private.valid_entitlement(text) RENAME TO valid_entitlement_059_base;
CREATE FUNCTION ironvault_private.valid_entitlement(p_member text) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;expiry date;
BEGIN
 IF ironvault_private.valid_entitlement_059_base(p_member) THEN RETURN true;END IF;
 SELECT * INTO m FROM public.members WHERE id=p_member;
 IF NOT FOUND OR m.status IS DISTINCT FROM 'ACTIVE' OR m.plan NOT LIKE 'Custom · %' OR m.expiration_date IS NULL OR m.expiration_date !~ '^\d{4}-\d{2}-\d{2}$' OR NOT EXISTS(SELECT 1 FROM public.owners WHERE id=m.tenant_id AND status='ACTIVE') THEN RETURN false;END IF;
 BEGIN expiry:=m.expiration_date::date;EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN false;END;
 RETURN expiry>=(now() AT TIME ZONE 'Asia/Manila')::date AND EXISTS(SELECT 1 FROM ironvault_private.membership_plan_purchases p WHERE p.member_id=m.id AND p.tenant_id=m.tenant_id AND p.name=m.plan AND p.expiration_date=m.expiration_date);
END $fn$;
ALTER FUNCTION public.iv_financial_transaction(text,text,text,numeric,numeric,uuid) RENAME TO financial_transaction_059_base;
ALTER FUNCTION public.financial_transaction_059_base(text,text,text,numeric,numeric,uuid) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_financial_transaction(p_operation text,p_member_id text,p_plan text,p_amount numeric,p_cash_amount numeric,p_request_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;terms jsonb;result jsonb;
BEGIN
 IF p_operation IS DISTINCT FROM 'purchase' THEN RETURN ironvault_private.financial_transaction_059_base(p_operation,p_member_id,p_plan,p_amount,p_cash_amount,p_request_id);END IF;
 IF auth.uid() IS NULL OR p_request_id IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501';END IF;
 -- Preserve the existing financial request -> member lock order and full receipt replay checks.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 SELECT * INTO m FROM public.members WHERE id=p_member_id AND (public.iv_can_access(tenant_id) OR (p_cash_amount=0 AND ironvault_private.is_own_membership(id,tenant_id))) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.financial_requests WHERE request_id=p_request_id) THEN RETURN ironvault_private.financial_transaction_059_base(p_operation,p_member_id,p_plan,p_amount,p_cash_amount,p_request_id);END IF;
 IF ironvault_private.valid_entitlement(m.id) THEN RAISE EXCEPTION 'Member already has a valid plan';END IF;
 IF p_plan LIKE 'Custom · %' THEN terms:=ironvault_private.plan_terms(m.id,p_plan);PERFORM set_config('ironvault.custom_plan_pending',m.id,true);END IF;
 result:=ironvault_private.financial_transaction_059_base(p_operation,p_member_id,p_plan,p_amount,p_cash_amount,p_request_id);
 IF terms IS NOT NULL THEN
  PERFORM set_config('ironvault.custom_plan_pending','',true);
  INSERT INTO ironvault_private.membership_plan_purchases(request_id,tenant_id,member_id,plan_id,revision,name,duration_days,base_price,charged_price,discount_percentage,expiration_date,actor_id) VALUES(p_request_id,m.tenant_id,m.id,(terms->>'plan_id')::uuid,(terms->>'revision')::bigint,p_plan,(terms->>'duration_days')::integer,(terms->>'base_price')::numeric,(result->>'price')::numeric,(terms->>'discount_percentage')::numeric,result->>'expiration_date',auth.uid());
  PERFORM ironvault_private.sync_member_status(m.id);
 END IF;
 RETURN result;
END $fn$;

-- Only the recognized-plan predicate changes; verification, isolation and all admission locks stay intact.
CREATE OR REPLACE FUNCTION public.iv_verify_entry_qr(p_payload text,p_tenant text,p_lookup boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE token_id uuid;member_key text;m public.members%ROWTYPE;ticket ironvault_private.daily_passes%ROWTYPE;
 card ironvault_private.member_cards%ROWTYPE;reason text;entered timestamptz;today date:=(now() AT TIME ZONE 'Asia/Manila')::date;
BEGIN
 PERFORM ironvault_private.qr_staff_require_054(p_tenant);
 IF p_lookup IS NULL OR p_payload IS NULL OR p_payload !~* '^(IV1|IVC1)\|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
 RETURN jsonb_build_object('valid',false,'reason','INVALID_QR'); END IF;
 token_id:=split_part(p_payload,'|',2)::uuid;
 IF split_part(p_payload,'|',1)='IVC1' THEN
  SELECT * INTO card FROM ironvault_private.member_cards WHERE token=token_id AND tenant_id=p_tenant;
  IF NOT FOUND THEN RETURN jsonb_build_object('valid',false,'reason','INVALID_CARD_FOR_GYM'); END IF;
  IF card.revoked_at IS NOT NULL THEN RETURN jsonb_build_object('valid',false,'reason','CARD_REVOKED'); END IF;
  member_key:=card.member_id;
 ELSE
  IF p_lookup THEN RETURN jsonb_build_object('valid',false,'reason','PERMANENT_CARD_REQUIRED'); END IF;
  SELECT * INTO ticket FROM ironvault_private.daily_passes WHERE token=token_id AND tenant_id=p_tenant;
  IF NOT FOUND THEN RETURN jsonb_build_object('valid',false,'reason','INVALID_QR'); END IF;
  IF ticket.business_day<>today OR ticket.expires_at<=now() THEN RETURN jsonb_build_object('valid',false,'reason','QR_EXPIRED'); END IF;
  member_key:=ticket.member_id;
 END IF;
 SELECT * INTO m FROM public.members WHERE id=member_key AND tenant_id=p_tenant;
 IF NOT FOUND THEN RETURN jsonb_build_object('valid',false,'reason','INVALID_QR'); END IF;
 SELECT max(created_at) INTO entered FROM public.iv_attendance_logs WHERE member_id=m.id AND tenant_id=p_tenant
 AND created_at >= (today::timestamp AT TIME ZONE 'Asia/Manila') AND created_at < ((today+1)::timestamp AT TIME ZONE 'Asia/Manila');
 reason:=CASE WHEN entered IS NOT NULL OR m.last_scanned_date=today::text OR ticket.used_at IS NOT NULL THEN 'ALREADY_ENTERED'
 WHEN m.status IS DISTINCT FROM 'ACTIVE' THEN 'MEMBER_INACTIVE'
 WHEN m.plan IS NULL OR (m.plan NOT IN ('1-Day Pass','1-Week Pass','1-Month Unlimited') AND NOT EXISTS(SELECT 1 FROM ironvault_private.membership_plan_purchases p WHERE p.member_id=m.id AND p.tenant_id=p_tenant AND p.name=m.plan AND p.expiration_date=m.expiration_date)) THEN 'NO_ACTIVE_PASS'
 WHEN NOT ironvault_private.valid_entitlement(m.id) THEN 'EXPIRED_PASS'
 WHEN NOT ironvault_private.member_legal_current(m.id) THEN 'AGREEMENT_REQUIRED'
 ELSE 'READY' END;
 RETURN jsonb_build_object('valid',true,'eligible',reason='READY','reason',reason,'entered_at',entered,
 'member',jsonb_build_object('id',m.id,'name',m.name,'display_code',m.display_code,'avatar',m.avatar,'plan',m.plan,'expiration_date',m.expiration_date,'status',m.status));
END $fn$;

CREATE OR REPLACE FUNCTION ironvault_private.sync_member_status(p_member text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;n ironvault_private.member_updates%ROWTYPE;key text;title text;body text;valid boolean:=false;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member FOR UPDATE;IF NOT FOUND THEN RETURN;END IF;
 IF m.status='ACTIVE' AND (m.plan IN ('1-Day Pass','1-Week Pass','1-Month Unlimited') OR EXISTS(SELECT 1 FROM ironvault_private.membership_plan_purchases p WHERE p.member_id=m.id AND p.tenant_id=m.tenant_id AND p.name=m.plan AND p.expiration_date=m.expiration_date)) AND m.expiration_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
  BEGIN valid:=m.expiration_date::date>=ironvault_private.subscription_today();EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN valid:=false;END;
 END IF;
 IF m.status='PENDING' THEN key:='pending';title:='Awaiting gym approval';body:='Your account is registered. Wait for gym approval before using member services. Registration and Terms acceptance do not create a valid pass.';
 ELSIF m.status='ACTIVE' AND valid THEN key:='valid:'||m.plan||':'||m.expiration_date;title:='Pass valid until '||m.expiration_date;body:='Your '||m.plan||' is valid through '||m.expiration_date||' in Philippine time. Normal entry and agreement checks still apply.';
 ELSIF m.status='ACTIVE' THEN key:='no-pass';title:='Approved — purchase a pass';body:='Your gym registration is approved. A valid pass is required for entry. Ask the front desk or use the available member purchase options.';
 ELSE UPDATE ironvault_private.member_updates SET resolved_at=coalesce(resolved_at,clock_timestamp()) WHERE member_id=m.id AND kind='status';RETURN;END IF;
 SELECT * INTO n FROM ironvault_private.member_updates WHERE member_id=m.id AND kind='status' AND resolved_at IS NULL ORDER BY created_at DESC LIMIT 1;
 IF n.state_key IS NOT DISTINCT FROM key THEN RETURN;END IF;
 UPDATE ironvault_private.member_updates SET resolved_at=clock_timestamp() WHERE member_id=m.id AND kind='status' AND resolved_at IS NULL;
 INSERT INTO ironvault_private.member_updates(tenant_id,member_id,event_key,kind,state_key,title,body) VALUES(m.tenant_id,m.id,'status:'||gen_random_uuid(),'status',key,title,body);
END $fn$;

CREATE OR REPLACE FUNCTION ironvault_private.member_status_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.plan LIKE 'Custom · %' AND current_setting('ironvault.custom_plan_pending',true)=NEW.id THEN RETURN NEW;END IF;
 PERFORM ironvault_private.sync_member_status(NEW.id);RETURN NEW;
END $fn$;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='ironvault_private' AND p.proname IN ('plan_terms','plan_terms_059_base','valid_entitlement','valid_entitlement_059_base','financial_transaction_059_base','sync_member_status','member_status_changed')) OR (n.nspname='public' AND p.proname IN ('iv_membership_plans','iv_financial_transaction','iv_verify_entry_qr')) LOOP
 EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO postgres',f.nspname,f.proname,f.args);
 EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',f.nspname,f.proname,f.args);
 IF f.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated',f.nspname,f.proname,f.args);END IF;
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
