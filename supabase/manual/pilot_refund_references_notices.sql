-- MANUAL ONLY after 044. No SQL has been executed by the agent.
-- Adds generated payout references and member-facing rejection notices.
-- Existing ledger, balances, payouts and notices are not backfilled or rewritten.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.transaction_references') IS NULL OR NOT EXISTS(
  SELECT 1 FROM information_schema.columns WHERE table_schema='ironvault_private' AND table_name='refund_cases' AND column_name='payout_reference'
 ) THEN RAISE EXCEPTION 'Apply 044 first';END IF;
 IF to_regprocedure('ironvault_private.refunds_045_base(text,text,uuid,jsonb,text)') IS NOT NULL THEN RAISE EXCEPTION '045 already installed; do not reapply';END IF;
END; $guard$;

ALTER TABLE ironvault_private.transaction_references DROP CONSTRAINT transaction_references_kind_check;
ALTER TABLE ironvault_private.transaction_references ADD CONSTRAINT transaction_references_kind_check CHECK(kind IN ('topup','refund','payout'));
ALTER TABLE ironvault_private.refund_cases ADD COLUMN member_decision_reason text CHECK(member_decision_reason IS NULL OR length(member_decision_reason)<=500);

CREATE OR REPLACE FUNCTION ironvault_private.transaction_reference(p_tenant text,p_kind text,p_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE ref text;bytes bytea;alphabet constant text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';i integer;tries integer;
BEGIN
 IF p_id IS NULL OR p_kind NOT IN ('topup','refund','payout') THEN RAISE EXCEPTION 'Valid reference identity required';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('reference:'||p_tenant||':'||p_kind||':'||p_id,0));
 SELECT reference INTO ref FROM ironvault_private.transaction_references WHERE tenant_id=p_tenant AND kind=p_kind AND record_id=p_id;IF FOUND THEN RETURN ref;END IF;
 FOR tries IN 1..100 LOOP
  bytes:=decode(replace(gen_random_uuid()::text,'-',''),'hex');ref:='';FOR i IN 0..5 LOOP ref:=ref||substr(alphabet,1+get_byte(bytes,i)%32,1);END LOOP;
  -- Preserve old manually supplied receipts, avoiding them for new payout codes.
  IF p_kind='payout' AND EXISTS(SELECT 1 FROM ironvault_private.refund_cases c WHERE c.tenant_id=p_tenant AND c.payout_reference=ref) THEN CONTINUE;END IF;
  BEGIN
   INSERT INTO ironvault_private.transaction_references(tenant_id,kind,record_id,reference,created_by) VALUES(p_tenant,p_kind,p_id,ref,auth.uid());RETURN ref;
  EXCEPTION WHEN unique_violation THEN NULL;END;
 END LOOP;
 RAISE EXCEPTION 'Could not allocate a unique reference; retry';
END; $fn$;

CREATE FUNCTION ironvault_private.refund_member_notice_045()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF OLD.status<>'pending' OR NEW.status=OLD.status THEN RETURN NEW;END IF;
 IF NEW.status='approved' AND NEW.action='cash' THEN
  -- Insert the final notice before the preserved base emits its same event key.
  -- member_update uses ON CONFLICT DO NOTHING, so there is exactly one notice.
  PERFORM ironvault_private.member_update(NEW.tenant_id,NEW.member_id,'refund:'||NEW.id,'Cash refund recorded',
   'Amount: PHP '||NEW.amount||E'\nDestination: Cash returned outside wallet' ||
   E'\nReason: '||NEW.reason||E'\nBalance before: PHP '||NEW.wallet_before||E'\nBalance after: PHP '||NEW.wallet_after||
   E'\nApproved by: '||coalesce(NEW.approved_actor->>'name','Authorized account')||
   E'\nRequest reference: '||coalesce(NEW.reference,NEW.id::text)||E'\nCash payout reference: '||NEW.payout_reference);
 ELSIF NEW.status='rejected' THEN
  PERFORM ironvault_private.member_update(NEW.tenant_id,NEW.member_id,'refund-rejected:'||NEW.id,'Refund request declined',
   'Amount: PHP '||NEW.amount||E'\nRequest reference: '||coalesce(NEW.reference,NEW.id::text)||
   E'\nThis rejection did not change your wallet balance.\nReason: '||coalesce(nullif(btrim(NEW.member_decision_reason),''),'Contact the gym for details.'));
 END IF;
 RETURN NEW;
END; $fn$;
CREATE TRIGGER iv_refund_member_notice_045 AFTER UPDATE OF status ON ironvault_private.refund_cases FOR EACH ROW EXECUTE FUNCTION ironvault_private.refund_member_notice_045();

ALTER FUNCTION public.iv_refunds(text,text,uuid,jsonb,text) RENAME TO refunds_045_base;
ALTER FUNCTION public.refunds_045_base(text,text,uuid,jsonb,text) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_refunds(p_tenant text,p_action text DEFAULT 'list',p_id uuid DEFAULT NULL,p_payload jsonb DEFAULT '{}',p_review text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE r ironvault_private.refund_cases%ROWTYPE;result jsonb;public_reason text;
BEGIN
 IF p_action IN ('approve','reject') THEN
  PERFORM ironvault_private.staff_require(p_tenant,'refund_approve');
  -- Match the preserved base lock order before reading/annotating the request.
  PERFORM pg_advisory_xact_lock(hashtextextended('refund:'||p_tenant,0));
  SELECT * INTO r FROM ironvault_private.refund_cases WHERE id=p_id FOR UPDATE;
  IF r.id IS NULL OR r.tenant_id<>p_tenant THEN RAISE EXCEPTION 'Request unavailable';END IF;
  IF r.status='pending' THEN
   IF p_action='approve' AND r.action='cash' THEN
    -- The base still validates cash_returned, current eligibility and review hash.
    -- Any failure rolls back allocation; committed retries return the same payout.
    p_payload:=coalesce(p_payload,'{}'::jsonb)||jsonb_build_object('payout_reference',ironvault_private.transaction_reference(p_tenant,'payout',r.id));
   ELSIF p_action='reject' THEN
    public_reason:=nullif(btrim(p_payload->>'member_reason'),'');
    IF length(public_reason)>500 THEN RAISE EXCEPTION 'Member-facing reason must be 500 characters or fewer';END IF;
    UPDATE ironvault_private.refund_cases SET member_decision_reason=public_reason WHERE id=r.id AND tenant_id=p_tenant;
   END IF;
  END IF;
 END IF;
 result:=ironvault_private.refunds_045_base(p_tenant,p_action,p_id,p_payload,p_review);
 IF p_action='list' THEN RETURN result||jsonb_build_object('features',jsonb_build_object('generated_payout_reference',true,'member_rejection_notice',true));END IF;
 RETURN result;
END; $fn$;

ALTER FUNCTION ironvault_private.transaction_reference(text,text,uuid) OWNER TO postgres;
ALTER FUNCTION ironvault_private.refund_member_notice_045() OWNER TO postgres;
ALTER FUNCTION ironvault_private.refunds_045_base(text,text,uuid,jsonb,text) OWNER TO postgres;
ALTER FUNCTION public.iv_refunds(text,text,uuid,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.transaction_reference(text,text,uuid),ironvault_private.refund_member_notice_045(),ironvault_private.refunds_045_base(text,text,uuid,jsonb,text),public.iv_refunds(text,text,uuid,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_refunds(text,text,uuid,jsonb,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
