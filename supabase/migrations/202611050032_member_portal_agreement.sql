-- MANUAL ONLY after 031. Member portal agreement; staff-assisted services remain available.
BEGIN;
DO $prerequisite$
BEGIN
 IF to_regprocedure('ironvault_private.render_full_legal_v2(jsonb,jsonb)') IS NULL OR to_regprocedure('ironvault_private.emit_live_signal(text,text,text)') IS NULL THEN
  RAISE EXCEPTION 'Apply legal migration 031 and live-update migration 027 before 032';
 END IF;
END $prerequisite$;
CREATE INDEX IF NOT EXISTS iv_legal_acceptances_member_versions ON ironvault_private.legal_acceptances(member_id,tenant_id,user_id,platform_version,gym_version,accepted_at DESC);
CREATE OR REPLACE FUNCTION ironvault_private.member_legal_current(p_member text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.members m JOIN public.owners g ON g.id=m.tenant_id
 JOIN public.iv_user_roles r ON r.member_id=m.id AND r.tenant_id=m.tenant_id AND r.role='member'
 JOIN ironvault_private.legal_settings p ON p.scope='platform'
 JOIN ironvault_private.legal_settings t ON t.scope=m.tenant_id
 JOIN ironvault_private.legal_acceptances a ON a.member_id=m.id AND a.tenant_id=m.tenant_id AND a.user_id=r.user_id
  AND a.platform_version=p.current_version AND a.gym_version=t.current_version
 WHERE m.id=p_member AND m.status='ACTIVE' AND g.status='ACTIVE' AND r.enabled AND r.disabled_at IS NULL);
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.require_current_member_legal(p_member text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE tenant text;
BEGIN
 SELECT tenant_id INTO STRICT tenant FROM public.members WHERE id=p_member;
 PERFORM 1 FROM ironvault_private.legal_settings WHERE scope IN ('platform',tenant) ORDER BY scope FOR SHARE;
 IF NOT ironvault_private.member_legal_current(p_member) THEN
  RAISE EXCEPTION 'Review and agree to the current Terms and Privacy Notice before using member QR passes or purchasing a pass' USING ERRCODE='IV002';
 END IF;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_member_legal_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE member text; tenant text; p uuid; g uuid; receipt jsonb; agreed boolean;
BEGIN
 SELECT m.id,m.tenant_id INTO member,tenant FROM public.iv_user_roles r JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
 JOIN public.owners o ON o.id=m.tenant_id WHERE r.user_id=auth.uid() AND r.role='member' AND r.enabled AND r.disabled_at IS NULL
 AND m.status='ACTIVE' AND o.status='ACTIVE';
 IF member IS NULL THEN RAISE EXCEPTION 'Active member account required' USING ERRCODE='42501'; END IF;
 SELECT current_version INTO p FROM ironvault_private.legal_settings WHERE scope='platform';
 SELECT current_version INTO g FROM ironvault_private.legal_settings WHERE scope=tenant;
 agreed:=ironvault_private.member_legal_current(member);
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
 AND member_row.status='ACTIVE' AND o.status='ACTIVE' FOR UPDATE OF member_row;
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
-- Publication is a metadata-only live signal, not disclosure of document/draft payloads.
CREATE OR REPLACE FUNCTION ironvault_private.legal_publication_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.current_version IS DISTINCT FROM OLD.current_version THEN
  IF NEW.scope='platform' THEN PERFORM ironvault_private.emit_live_signal('system','global',NULL);
  ELSE PERFORM ironvault_private.emit_live_signal('gym',NEW.tenant_id,NEW.tenant_id); END IF;
 END IF;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS iv_legal_publication_changed ON ironvault_private.legal_settings;
CREATE TRIGGER iv_legal_publication_changed AFTER UPDATE OF current_version ON ironvault_private.legal_settings
 FOR EACH ROW EXECUTE FUNCTION ironvault_private.legal_publication_changed();
CREATE OR REPLACE FUNCTION public.iv_financial_transaction(p_operation text,p_member_id text,p_plan text,
 p_amount numeric,p_cash_amount numeric,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; receipt ironvault_private.financial_requests%ROWTYPE;
 payload jsonb; result jsonb; terms jsonb; price numeric; wallet numeric; cash numeric; balance numeric; actor uuid:=auth.uid();
BEGIN
 IF actor IS NULL OR p_request_id IS NULL OR p_operation IS NULL OR p_operation NOT IN ('topup','purchase')
 OR p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity')
 OR p_amount<=0 OR p_amount>10000000 OR p_amount<>round(p_amount,2)
 OR p_cash_amount IS NULL OR p_cash_amount::text IN ('NaN','Infinity','-Infinity')
 OR p_cash_amount<0 OR p_cash_amount<>round(p_cash_amount,2) THEN RAISE EXCEPTION 'Invalid financial request'; END IF;
 IF p_operation='topup' AND (p_amount>1000000 OR p_cash_amount<>0 OR p_plan IS NOT NULL) THEN
  RAISE EXCEPTION 'Invalid top-up'; END IF;
 payload:=jsonb_build_object('operation',p_operation,'member_id',p_member_id,'plan',p_plan,'amount',p_amount,'cash',p_cash_amount);
 -- All writers lock request then member. Same-key retries serialize even across
 -- different members; full payload+actor+tenant binding is checked before return.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,0));
 SELECT * INTO m FROM public.members WHERE id=p_member_id AND (public.iv_can_access(tenant_id) OR (p_operation='purchase' AND p_cash_amount=0 AND ironvault_private.is_own_membership(id,tenant_id))) FOR UPDATE;
 IF NOT FOUND OR (NOT public.iv_can_access(m.tenant_id) AND NOT (p_operation='purchase' AND p_cash_amount=0 AND ironvault_private.is_own_membership(m.id,m.tenant_id))) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT * INTO receipt FROM ironvault_private.financial_requests WHERE request_id=p_request_id;
 IF FOUND THEN
  IF receipt.actor_id<>actor OR receipt.tenant_id<>m.tenant_id OR receipt.member_id<>m.id OR receipt.payload<>payload THEN
   RAISE EXCEPTION 'Request key belongs to a different operation'; END IF;
  RETURN receipt.result;
 END IF;
 -- Staff-assisted operations stay available; completed retries above remain read-only.
 IF p_operation='purchase' AND ironvault_private.is_own_membership(m.id,m.tenant_id) AND NOT public.iv_can_access(m.tenant_id) THEN
  PERFORM ironvault_private.require_current_member_legal(m.id);
 END IF;
 IF EXISTS(SELECT 1 FROM public.iv_financial_transactions WHERE request_id=p_request_id) THEN
  RAISE EXCEPTION 'Legacy request key cannot be safely replayed'; END IF;
 IF m.status IS DISTINCT FROM 'ACTIVE' OR NOT EXISTS(SELECT 1 FROM public.owners o WHERE o.id=m.tenant_id AND o.status='ACTIVE') THEN
  RAISE EXCEPTION 'Gym or member inactive'; END IF;
 balance:=coalesce(m.wallet_balance,0);
 IF balance::text IN ('NaN','Infinity','-Infinity') OR balance<0 OR balance<>round(balance,2)
 OR coalesce(m.amount,0)::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Invalid existing financial state'; END IF;
 IF p_operation='topup' THEN
  balance:=balance+p_amount;
  UPDATE public.members SET wallet_balance=balance WHERE id=m.id;
  INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
   VALUES(m.tenant_id,m.id,'topup',p_amount,actor,p_request_id,'Cash wallet top-up');
 ELSE
  -- Stabilize gym pricing against concurrent administrator updates until commit.
  PERFORM 1 FROM public.owners WHERE id=m.tenant_id FOR SHARE;
  IF m.plan IN ('1-Day Pass','1-Week Pass','1-Month Unlimited') AND m.expiration_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
   BEGIN
    IF m.expiration_date::date >= (now() AT TIME ZONE 'Asia/Manila')::date THEN RAISE EXCEPTION 'Member already has a valid plan'; END IF;
   EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN NULL; END;
  END IF;
  terms:=ironvault_private.plan_terms(m.id,p_plan);price:=(terms->>'price')::numeric;
  IF p_amount<>price OR p_cash_amount>price THEN RAISE EXCEPTION 'Price changed or invalid payment split; quote again'; END IF;
  cash:=p_cash_amount;wallet:=price-cash;
  IF wallet>balance THEN RAISE EXCEPTION 'Insufficient wallet funds'; END IF;
  balance:=balance-wallet;
  UPDATE public.members SET wallet_balance=balance,plan=p_plan,
   expiration_date=terms->>'expiration_date',amount=coalesce(amount,0)+price,
   date_joined=(now() AT TIME ZONE 'Asia/Manila')::date::text WHERE id=m.id;
  IF wallet>0 THEN
   INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
    VALUES(m.tenant_id,m.id,'plan_wallet',wallet,actor,p_request_id,p_plan);
  END IF;
  IF cash>0 THEN
   INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
    VALUES(m.tenant_id,m.id,'plan_cash',cash,actor,CASE WHEN wallet=0 THEN p_request_id ELSE NULL END,p_plan);
  END IF;
 END IF;
 result:=jsonb_build_object('request_id',p_request_id,'wallet_balance',balance,'operation',p_operation,
  'price',CASE WHEN p_operation='purchase' THEN price ELSE p_amount END,'expiration_date',terms->>'expiration_date');
 INSERT INTO ironvault_private.financial_requests(request_id,tenant_id,member_id,actor_id,payload,result)
  VALUES(p_request_id,m.tenant_id,m.id,actor,payload,result);
 RETURN result;
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_issue_member_pass(p_member_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; ticket ironvault_private.daily_passes%ROWTYPE; today date:=(now() AT TIME ZONE 'Asia/Manila')::date;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id FOR UPDATE;
 IF NOT FOUND OR NOT ironvault_private.is_own_membership(m.id,m.tenant_id) OR NOT ironvault_private.valid_entitlement(m.id) THEN
  RAISE EXCEPTION 'No valid membership for this pass'; END IF;
 PERFORM ironvault_private.require_current_member_legal(m.id);
 IF m.last_scanned_date=today::text OR EXISTS(SELECT 1 FROM public.iv_attendance_logs WHERE member_id=m.id
  AND (created_at AT TIME ZONE 'Asia/Manila')::date=today) THEN RAISE EXCEPTION 'Already admitted today'; END IF;
 INSERT INTO ironvault_private.daily_passes(member_id,tenant_id,business_day,expires_at)
  VALUES(m.id,m.tenant_id,today,(today+1)::timestamp AT TIME ZONE 'Asia/Manila') ON CONFLICT(member_id,business_day) DO NOTHING;
 SELECT * INTO STRICT ticket FROM ironvault_private.daily_passes WHERE member_id=m.id AND business_day=today;
 IF ticket.used_at IS NOT NULL THEN RAISE EXCEPTION 'Pass already used'; END IF;
 RETURN jsonb_build_object('payload','IV1|'||ticket.token::text,'business_day',today,'expires_at',ticket.expires_at);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_redeem_member_pass(p_token uuid,p_tenant text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE ticket ironvault_private.daily_passes%ROWTYPE; admitted timestamptz;
BEGIN
 -- Lock member in record_admission before touching ticket to match pass issuance;
 -- token lookup itself is read-only, tickets are immutable except used_at.
 SELECT * INTO ticket FROM ironvault_private.daily_passes WHERE token=p_token;
 IF NOT FOUND OR ticket.tenant_id IS DISTINCT FROM p_tenant OR NOT public.iv_can_access(ticket.tenant_id)
  OR ticket.used_at IS NOT NULL OR ticket.expires_at<=now()
  OR ticket.business_day<>(now() AT TIME ZONE 'Asia/Manila')::date THEN RAISE EXCEPTION 'Invalid, expired or used pass'; END IF;
 PERFORM ironvault_private.require_current_member_legal(ticket.member_id);
 admitted:=ironvault_private.record_admission(ticket.member_id,'qr');
 UPDATE ironvault_private.daily_passes SET used_at=admitted WHERE token=p_token AND used_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pass already used'; END IF;
 RETURN jsonb_build_object('member_id',ticket.member_id,'admitted_at',admitted);
END $fn$;

DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['ironvault_private.member_legal_current(text)','ironvault_private.require_current_member_legal(text)',
 'ironvault_private.legal_publication_changed()','public.iv_member_legal_status()','public.iv_member_legal_accept(uuid,uuid)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_member_legal_status(),public.iv_member_legal_accept(uuid,uuid) TO authenticated;
-- Replaced business functions retain their existing ownership and ACLs.
NOTIFY pgrst,'reload schema';
COMMIT;
