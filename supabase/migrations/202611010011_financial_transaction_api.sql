-- MANUAL ONLY. Requires 010 and original reviewed topup/purchase definitions.
-- Behavior-changing: new RPCs, safe topup wrapper, legacy signature validates server outcome.
-- No historical row rewrite. Coordinate app cutover, do NOT deploy independently.
-- Full release also requires owners/members write protection: current broad ALL
-- policies otherwise allow callers to change authoritative prices/member discounts.
-- No migration is assumed applied. Errors abort; ROLLBACK and return error.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.financial_requests') IS NULL THEN RAISE EXCEPTION '010 required'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.iv_topup(text,numeric,uuid)')))
  IS DISTINCT FROM '08e84b7ad3f3a02c34ef083d62715469'
 OR md5(pg_get_functiondef(to_regprocedure('public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)')))
  IS DISTINCT FROM 'e09886b42457a094026b106a7b6af98e' THEN
  RAISE EXCEPTION 'Financial definitions differ from reviewed source';
 END IF;
 IF to_regprocedure('public.iv_financial_transaction(text,text,text,numeric,numeric,uuid)') IS NOT NULL
 OR to_regprocedure('public.iv_quote_plan(text,text)') IS NOT NULL
 OR to_regprocedure('ironvault_private.plan_terms(text,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'Proposed API name already exists; inspect before continuing';
 END IF;
END $guard$;
CREATE FUNCTION ironvault_private.plan_terms(p_member text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; pricing jsonb; price numeric; discount numeric; days integer; key text;
BEGIN
 SELECT * INTO STRICT m FROM public.members WHERE id=p_member;
 SELECT o.pricing INTO STRICT pricing FROM public.owners o WHERE o.id=m.tenant_id AND o.status='ACTIVE';
 CASE p_plan WHEN '1-Day Pass' THEN key:='day';days:=0;
 WHEN '1-Week Pass' THEN key:='week';days:=7;
 WHEN '1-Month Unlimited' THEN key:='month';days:=30;
 ELSE RAISE EXCEPTION 'Unsupported plan'; END CASE;
 price:=(pricing->>key)::numeric;discount:=coalesce(m.discount_percentage,0);
 IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<=0 OR price>10000000
 OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>=100 THEN
  RAISE EXCEPTION 'Invalid configured price or discount';
 END IF;
 -- Preserve existing desk discounted-price whole-peso rounding. Zero-price
 -- entitlements require a separate explicit complimentary-plan workflow.
 IF discount>0 THEN price:=round(price*(1-discount/100)); END IF;
 IF price<=0 OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid configured monetary precision'; END IF;
 RETURN jsonb_build_object('price',price,'expiration_date',
  ((now() AT TIME ZONE 'Asia/Manila')::date+days)::text,'wallet_balance',coalesce(m.wallet_balance,0));
END $fn$;
CREATE FUNCTION public.iv_quote_plan(p_member_id text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.iv_can_access(m.tenant_id)
 OR m.status IS DISTINCT FROM 'ACTIVE' THEN RAISE EXCEPTION 'Not authorized or member inactive'; END IF;
 RETURN ironvault_private.plan_terms(p_member_id,p_plan);
END $fn$;
CREATE FUNCTION public.iv_financial_transaction(p_operation text,p_member_id text,p_plan text,
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
 SELECT * INTO m FROM public.members WHERE id=p_member_id FOR UPDATE;
 IF NOT FOUND OR NOT public.iv_can_access(m.tenant_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
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
CREATE OR REPLACE FUNCTION public.iv_topup(p_member_id text,p_amount numeric,p_request_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN RETURN (public.iv_financial_transaction('topup',p_member_id,NULL,p_amount,0,p_request_id)->>'wallet_balance')::numeric; END $fn$;
CREATE OR REPLACE FUNCTION public.iv_purchase(p_member_id text,p_plan text,p_price numeric,
 p_wallet_amount numeric,p_cash_amount numeric,p_expiration date,p_request_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE outcome jsonb;
BEGIN
 IF p_wallet_amount IS NULL OR p_cash_amount IS NULL OR p_price IS NULL OR p_expiration IS NULL
 OR p_wallet_amount::text IN ('NaN','Infinity','-Infinity') OR p_wallet_amount<0
 OR p_wallet_amount<>round(p_wallet_amount,2) OR p_wallet_amount+p_cash_amount<>p_price THEN
  RAISE EXCEPTION 'Invalid purchase split'; END IF;
 outcome:=public.iv_financial_transaction('purchase',p_member_id,p_plan,p_price,p_cash_amount,p_request_id);
 IF p_expiration::text IS DISTINCT FROM outcome->>'expiration_date' THEN
  RAISE EXCEPTION 'Expiry differs from authoritative membership term'; END IF;
 RETURN (outcome->>'wallet_balance')::numeric;
END $fn$;
ALTER FUNCTION ironvault_private.plan_terms(text,text) OWNER TO postgres;
ALTER FUNCTION public.iv_quote_plan(text,text) OWNER TO postgres;
ALTER FUNCTION public.iv_financial_transaction(text,text,text,numeric,numeric,uuid) OWNER TO postgres;
ALTER FUNCTION public.iv_topup(text,numeric,uuid) OWNER TO postgres;
ALTER FUNCTION public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.plan_terms(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_quote_plan(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_financial_transaction(text,text,text,numeric,numeric,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_topup(text,numeric,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.iv_quote_plan(text,text),public.iv_financial_transaction(text,text,text,numeric,numeric,uuid),
 public.iv_topup(text,numeric,uuid),public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid) TO authenticated,service_role;
DO $verify$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.iv_quote_plan(text,text)',
 'public.iv_financial_transaction(text,text,text,numeric,numeric,uuid)',
 'public.iv_topup(text,numeric,uuid)','public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)'] LOOP
  IF has_function_privilege('anon',signature,'EXECUTE')
   OR NOT has_function_privilege('authenticated',signature,'EXECUTE') THEN
   RAISE EXCEPTION 'Unexpected effective API privilege on %',signature;
  END IF;
 END LOOP;
 IF has_function_privilege('authenticated','ironvault_private.plan_terms(text,text)','EXECUTE') THEN
  RAISE EXCEPTION 'Private pricing helper exposed'; END IF;
END $verify$;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT oid::regprocedure,prosecdef,proconfig,
 has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute
FROM pg_proc WHERE oid IN ('public.iv_quote_plan(text,text)'::regprocedure,
 'public.iv_financial_transaction(text,text,text,numeric,numeric,uuid)'::regprocedure);
-- Expect anon false, authenticated true, empty search path. No RPC invoked.
-- All state changes are one transaction. On compatibility failures use reviewed
-- fix-forward; do not restore original unsafe purchase implementation.
