-- MANUAL ONLY. After 012. Member wallet-only purchases plus server-issued,
-- unguessable, expiring, tenant-bound daily pass tickets. No legacy row rewrite.
-- Unsigned member-ID/date QR codes intentionally cease to authorize admission.
-- No persistent signing secret is sent to browsers. An opaque server ticket
-- provides forgery resistance; it is not a cryptographically signed offline QR.
BEGIN;
SET LOCAL search_path=pg_catalog;
CREATE FUNCTION ironvault_private.is_own_membership(p_member text,p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
  AND r.role='member' AND r.member_id=p_member AND r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_quote_plan(p_member_id text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id;
 IF NOT FOUND OR auth.uid() IS NULL OR (NOT public.iv_can_access(m.tenant_id) AND NOT ironvault_private.is_own_membership(m.id,m.tenant_id))
 OR m.status IS DISTINCT FROM 'ACTIVE' THEN RAISE EXCEPTION 'Not authorized or member inactive'; END IF;
 RETURN ironvault_private.plan_terms(p_member_id,p_plan);
END $fn$;
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

CREATE TABLE ironvault_private.daily_passes (
 token uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 member_id text NOT NULL REFERENCES public.members(id),
 tenant_id text NOT NULL REFERENCES public.owners(id),
 business_day date NOT NULL,
 expires_at timestamptz NOT NULL,
 used_at timestamptz,
 UNIQUE(member_id,business_day)
);
ALTER TABLE ironvault_private.daily_passes OWNER TO postgres;
ALTER TABLE ironvault_private.daily_passes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.daily_passes FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.valid_entitlement(p_member text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; expiry date;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member;
 IF NOT FOUND OR m.status IS DISTINCT FROM 'ACTIVE'
  OR m.plan IS NULL OR m.plan NOT IN ('1-Day Pass','1-Week Pass','1-Month Unlimited')
  OR m.expiration_date IS NULL OR m.expiration_date !~ '^\d{4}-\d{2}-\d{2}$'
  OR NOT EXISTS(SELECT 1 FROM public.owners WHERE id=m.tenant_id AND status='ACTIVE') THEN RETURN false; END IF;
 BEGIN expiry:=m.expiration_date::date; EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN false; END;
 RETURN expiry >= (now() AT TIME ZONE 'Asia/Manila')::date;
END $fn$;
CREATE FUNCTION public.iv_issue_member_pass(p_member_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; ticket ironvault_private.daily_passes%ROWTYPE; today date:=(now() AT TIME ZONE 'Asia/Manila')::date;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id FOR UPDATE;
 IF NOT FOUND OR NOT ironvault_private.is_own_membership(m.id,m.tenant_id) OR NOT ironvault_private.valid_entitlement(m.id) THEN
  RAISE EXCEPTION 'No valid membership for this pass'; END IF;
 IF m.last_scanned_date=today::text OR EXISTS(SELECT 1 FROM public.iv_attendance_logs WHERE member_id=m.id
  AND (created_at AT TIME ZONE 'Asia/Manila')::date=today) THEN RAISE EXCEPTION 'Already admitted today'; END IF;
 INSERT INTO ironvault_private.daily_passes(member_id,tenant_id,business_day,expires_at)
  VALUES(m.id,m.tenant_id,today,(today+1)::timestamp AT TIME ZONE 'Asia/Manila') ON CONFLICT(member_id,business_day) DO NOTHING;
 SELECT * INTO STRICT ticket FROM ironvault_private.daily_passes WHERE member_id=m.id AND business_day=today;
 IF ticket.used_at IS NOT NULL THEN RAISE EXCEPTION 'Pass already used'; END IF;
 RETURN jsonb_build_object('payload','IV1|'||ticket.token::text,'business_day',today,'expires_at',ticket.expires_at);
END $fn$;
CREATE FUNCTION ironvault_private.record_admission(p_member text,p_method text)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; today text:=((now() AT TIME ZONE 'Asia/Manila')::date)::text; admitted timestamptz:=now();
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.iv_can_access(m.tenant_id) OR NOT ironvault_private.valid_entitlement(m.id) THEN RAISE EXCEPTION 'Not authorized or membership invalid'; END IF;
 IF m.last_scanned_date=today OR EXISTS(SELECT 1 FROM public.iv_attendance_logs WHERE member_id=m.id
  AND (created_at AT TIME ZONE 'Asia/Manila')::date=today::date) THEN RAISE EXCEPTION 'Already admitted today'; END IF;
 UPDATE public.members SET scans_used=coalesce(scans_used,0)+1,last_scanned_date=today WHERE id=m.id;
 INSERT INTO public.iv_attendance_logs(tenant_id,member_id,method,actor_id,created_at) VALUES(m.tenant_id,m.id,p_method,auth.uid(),admitted);
 RETURN admitted;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_checkin(p_member_id text,p_method text)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF p_method IS DISTINCT FROM 'manual' THEN RAISE EXCEPTION 'QR admission requires a server-issued pass'; END IF;
 RETURN ironvault_private.record_admission(p_member_id,'manual');
END $fn$;
CREATE FUNCTION public.iv_redeem_member_pass(p_token uuid,p_tenant text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE ticket ironvault_private.daily_passes%ROWTYPE; admitted timestamptz;
BEGIN
 -- Lock member in record_admission before touching ticket to match pass issuance;
 -- token lookup itself is read-only, tickets are immutable except used_at.
 SELECT * INTO ticket FROM ironvault_private.daily_passes WHERE token=p_token;
 IF NOT FOUND OR ticket.tenant_id IS DISTINCT FROM p_tenant OR NOT public.iv_can_access(ticket.tenant_id)
  OR ticket.used_at IS NOT NULL OR ticket.expires_at<=now()
  OR ticket.business_day<>(now() AT TIME ZONE 'Asia/Manila')::date THEN RAISE EXCEPTION 'Invalid, expired or used pass'; END IF;
 admitted:=ironvault_private.record_admission(ticket.member_id,'qr');
 UPDATE ironvault_private.daily_passes SET used_at=admitted WHERE token=p_token AND used_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pass already used'; END IF;
 RETURN jsonb_build_object('member_id',ticket.member_id,'admitted_at',admitted);
END $fn$;
DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['ironvault_private.is_own_membership(text,text)',
 'ironvault_private.valid_entitlement(text)','ironvault_private.record_admission(text,text)',
 'public.iv_issue_member_pass(text)','public.iv_redeem_member_pass(uuid,text)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_issue_member_pass(text),public.iv_redeem_member_pass(uuid,text) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_checkin(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.iv_checkin(text,text) TO authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT oid::regprocedure,has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute FROM pg_proc
WHERE oid IN ('public.iv_issue_member_pass(text)'::regprocedure,'public.iv_redeem_member_pass(uuid,text)'::regprocedure);
-- Expect anon false/authenticated true. No account/financial/history deletion.
-- On error ROLLBACK; fix forward, never re-enable unsigned QR authorization.
