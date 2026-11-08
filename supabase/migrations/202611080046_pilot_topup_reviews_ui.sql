-- MANUAL ONLY after 045. Run the entire transaction once; do not execute both copies.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('ironvault_private.refunds_045_base(text,text,uuid,jsonb,text)') IS NULL THEN RAISE EXCEPTION 'Apply 045 first';END IF;
 IF to_regclass('ironvault_private.topup_reviews') IS NOT NULL THEN RAISE EXCEPTION '046 already installed; do not reapply';END IF;
END; $guard$;
CREATE TABLE ironvault_private.topup_revisions(
 member_id text PRIMARY KEY REFERENCES public.members(id) ON DELETE CASCADE,
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,revision bigint NOT NULL DEFAULT 0
);
CREATE TABLE ironvault_private.topup_reviews(
 request_id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 amount numeric(12,2) NOT NULL CHECK(amount>0),wallet_before numeric NOT NULL,revision bigint NOT NULL,
 expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '10 minutes'
);
ALTER TABLE ironvault_private.topup_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.topup_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.topup_revisions,ironvault_private.topup_reviews FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.iv_topup_review(p_tenant text,p_member text,p_amount numeric,p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;q ironvault_private.topup_reviews%ROWTYPE;revision_value bigint;latest jsonb;
BEGIN
 IF auth.uid() IS NULL OR p_request IS NULL OR p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<=0 OR p_amount>10000000 OR p_amount<>round(p_amount,2) THEN RAISE EXCEPTION 'Choose a valid top-up amount';END IF;
 IF NOT public.iv_can_access(p_tenant) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';END IF;
 PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 SELECT * INTO m FROM public.members WHERE id=p_member AND tenant_id=p_tenant FOR UPDATE;
 IF NOT FOUND OR m.status<>'ACTIVE' THEN RAISE EXCEPTION 'Approved member required';END IF;
 IF coalesce(m.wallet_balance,0)::text IN ('NaN','Infinity','-Infinity') OR coalesce(m.wallet_balance,0)<0 THEN RAISE EXCEPTION 'Wallet needs owner review before a top-up';END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.financial_requests WHERE request_id=p_request) THEN RAISE EXCEPTION 'Payment already submitted; retry the original request to retrieve its receipt';END IF;
 INSERT INTO ironvault_private.topup_revisions(member_id,tenant_id) VALUES(m.id,p_tenant) ON CONFLICT DO NOTHING;
 SELECT revision INTO revision_value FROM ironvault_private.topup_revisions WHERE member_id=m.id AND tenant_id=p_tenant;
 SELECT * INTO q FROM ironvault_private.topup_reviews WHERE request_id=p_request;
 IF FOUND THEN
  IF q.actor_id<>auth.uid() OR q.tenant_id<>p_tenant OR q.member_id<>p_member OR q.amount<>p_amount THEN RAISE EXCEPTION 'Review belongs to another payment';END IF;
 ELSE
  INSERT INTO ironvault_private.topup_reviews(request_id,tenant_id,member_id,actor_id,amount,wallet_before,revision)
  VALUES(p_request,p_tenant,p_member,auth.uid(),p_amount,coalesce(m.wallet_balance,0),revision_value) RETURNING * INTO q;
 END IF;
 IF q.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'Review expired. Open a fresh top-up review';END IF;
 SELECT jsonb_build_object('amount',t.amount,'created_at',t.created_at,'actor',ironvault_private.audit_actor(t.actor_id,p_tenant)->>'name') INTO latest FROM public.iv_financial_transactions t WHERE t.tenant_id=p_tenant AND t.member_id=m.id AND t.kind='topup' ORDER BY t.created_at DESC,t.id DESC LIMIT 1;
 RETURN jsonb_build_object('request_id',q.request_id,'member_id',q.member_id,'amount',q.amount,'wallet_before',q.wallet_before,'wallet_after',q.wallet_before+q.amount,'expires_at',q.expires_at,'latest_topup',latest);
END; $fn$;

ALTER FUNCTION public.iv_financial_transaction(text,text,text,numeric,numeric,uuid) RENAME TO financial_transaction_046_base;
ALTER FUNCTION public.financial_transaction_046_base(text,text,text,numeric,numeric,uuid) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_financial_transaction(p_operation text,p_member_id text,p_plan text,p_amount numeric,p_cash_amount numeric,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;q ironvault_private.topup_reviews%ROWTYPE;current_revision bigint;result jsonb;latest text;
BEGIN
 IF p_operation='topup' THEN
  IF auth.uid() IS NULL OR p_request_id IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
  SELECT * INTO m FROM public.members WHERE id=p_member_id AND public.iv_can_access(tenant_id) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';END IF;
  -- Completed receipts always replay through the existing actor/payload checks FIRST.
  IF EXISTS(SELECT 1 FROM ironvault_private.financial_requests WHERE request_id=p_request_id) THEN
   RETURN ironvault_private.financial_transaction_046_base(p_operation,p_member_id,p_plan,p_amount,p_cash_amount,p_request_id);
  END IF;
  SELECT * INTO q FROM ironvault_private.topup_reviews WHERE request_id=p_request_id;
  SELECT coalesce((SELECT revision FROM ironvault_private.topup_revisions WHERE member_id=m.id AND tenant_id=m.tenant_id),0) INTO current_revision;
  IF q.request_id IS NULL OR q.actor_id<>auth.uid() OR q.tenant_id<>m.tenant_id OR q.member_id<>m.id OR q.amount IS DISTINCT FROM p_amount OR p_plan IS NOT NULL OR p_cash_amount IS DISTINCT FROM 0::numeric THEN RAISE EXCEPTION 'Open a fresh top-up review before confirming' USING ERRCODE='IV004';END IF;
  IF q.revision<>current_revision OR q.wallet_before IS DISTINCT FROM coalesce(m.wallet_balance,0) OR q.expires_at<=clock_timestamp() THEN
   SELECT ' Most recent top-up: PHP '||t.amount||' by '||coalesce(ironvault_private.audit_actor(t.actor_id,m.tenant_id)->>'name','authorized operator')||' at '||to_char(t.created_at AT TIME ZONE 'Asia/Manila','YYYY-MM-DD HH24:MI:SS')||' Philippine time.' INTO latest FROM public.iv_financial_transactions t WHERE t.tenant_id=m.tenant_id AND t.member_id=m.id AND t.kind='topup' ORDER BY t.created_at DESC,t.id DESC LIMIT 1;
   RAISE EXCEPTION 'Top-up review is out of date. Check whether this payment was already recorded. Open a fresh review only for a separate payment.%',coalesce(latest,'') USING ERRCODE='IV004';
  END IF;
  result:=ironvault_private.financial_transaction_046_base(p_operation,p_member_id,p_plan,p_amount,p_cash_amount,p_request_id);
  UPDATE ironvault_private.topup_revisions SET revision=revision+1 WHERE member_id=m.id AND tenant_id=m.tenant_id;
  RETURN result;
 END IF;
 RETURN ironvault_private.financial_transaction_046_base(p_operation,p_member_id,p_plan,p_amount,p_cash_amount,p_request_id);
END; $fn$;

-- Separate grant; it does not grant Reports, exports, or raw financial rows.
ALTER FUNCTION public.iv_staff_access(text,text,uuid,jsonb) RENAME TO staff_access_046_base;
ALTER FUNCTION public.staff_access_046_base(text,text,uuid,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_staff_access(p_tenant text,p_action text DEFAULT 'mine',p_user uuid DEFAULT NULL,p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;revenue boolean:=false;
BEGIN
 IF p_action='permissions' THEN
  IF p_data->'permissions' ? 'revenue_today' THEN
   IF jsonb_typeof(p_data->'permissions'->'revenue_today')<>'boolean' THEN RAISE EXCEPTION 'Choose explicit revenue permission';END IF;
   revenue:=(p_data->'permissions'->>'revenue_today')::boolean;
  END IF;
  result:=ironvault_private.staff_access_046_base(p_tenant,p_action,p_user,jsonb_set(p_data,'{permissions}',(p_data->'permissions')-'revenue_today'));
  UPDATE ironvault_private.staff_access SET permissions=permissions||jsonb_build_object('revenue_today',revenue) WHERE tenant_id=p_tenant AND user_id=p_user;
  PERFORM ironvault_private.write_audit(p_tenant,auth.uid(),'Revenue Today permission changed',p_user::text,jsonb_build_object('target_user',p_user,'allowed',revenue));
  result:=ironvault_private.staff_access_046_base(p_tenant,'list',NULL,'{}');
 ELSE
  result:=ironvault_private.staff_access_046_base(p_tenant,p_action,p_user,p_data);
  IF p_action='mine' AND result->>'role' IN ('owner','super_admin') THEN result:=jsonb_set(result,'{permissions,revenue_today}','true'::jsonb);END IF;
 END IF;
 RETURN result||jsonb_build_object('features',jsonb_build_object('revenue_today',true));
END; $fn$;
CREATE FUNCTION public.iv_revenue_today(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE day date:=ironvault_private.subscription_today();amount numeric;
BEGIN
 PERFORM ironvault_private.staff_require(p_tenant,'revenue_today');
 PERFORM ironvault_private.subscription_require(p_tenant,'read');
 SELECT coalesce(sum(t.amount),0) INTO amount FROM public.iv_financial_transactions t WHERE t.tenant_id=p_tenant AND t.kind IN ('plan_cash','plan_wallet') AND (t.created_at AT TIME ZONE 'Asia/Manila')::date=day;
 IF amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Revenue needs review';END IF;
 RETURN jsonb_build_object('tenant_id',p_tenant,'day',day,'amount',amount);
END; $fn$;

-- Enrich sources with the purchased pass's own immutable receipt snapshot.
ALTER FUNCTION public.iv_refunds(text,text,uuid,jsonb,text) RENAME TO refunds_046_base;
ALTER FUNCTION public.refunds_046_base(text,text,uuid,jsonb,text) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_refunds(p_tenant text,p_action text DEFAULT 'list',p_id uuid DEFAULT NULL,p_payload jsonb DEFAULT '{}',p_review text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;sources jsonb;
BEGIN
 result:=ironvault_private.refunds_046_base(p_tenant,p_action,p_id,p_payload,p_review);
 IF p_action='list' THEN
  SELECT coalesce(jsonb_agg(source||CASE WHEN receipt.request_id IS NOT NULL THEN jsonb_build_object('purchased_plan',receipt.payload->>'plan','purchased_expiry',receipt.result->>'expiration_date') ELSE '{}'::jsonb END ORDER BY source->>'created_at' DESC),'[]') INTO sources
  FROM jsonb_array_elements(result->'sources') source
  LEFT JOIN public.iv_financial_transactions ledger ON ledger.tenant_id=p_tenant AND ledger.id::text=source->>'key'
  LEFT JOIN ironvault_private.financial_requests receipt ON receipt.tenant_id=p_tenant AND receipt.member_id=source->>'member_id' AND receipt.payload->>'operation'='purchase' AND
   receipt.request_id=ledger.request_id;
  result:=jsonb_set(result,'{sources}',sources);
 END IF;
 RETURN result;
END; $fn$;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature,n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
 (n.nspname='ironvault_private' AND p.proname IN ('financial_transaction_046_base','staff_access_046_base','refunds_046_base')) OR
 (n.nspname='public' AND p.proname IN ('iv_topup_review','iv_financial_transaction','iv_staff_access','iv_revenue_today','iv_refunds')) LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f.signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 IF f.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.signature);END IF;
 END LOOP;
END; $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
