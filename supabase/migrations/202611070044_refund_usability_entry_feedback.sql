-- MANUAL ONLY after 043. No history, balances or original ledger entries are rewritten.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.payment_verifications') IS NULL THEN RAISE EXCEPTION 'Apply 043 first';END IF;
 IF to_regclass('ironvault_private.transaction_references') IS NOT NULL THEN RAISE EXCEPTION '044 already installed; do not reapply';END IF;
END $guard$;
CREATE TABLE ironvault_private.transaction_references(
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,kind text NOT NULL CHECK(kind IN ('topup','refund')),record_id uuid NOT NULL,
 reference text NOT NULL CHECK(reference ~ '^[A-HJ-NP-Z2-9]{6}$'),created_by uuid,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),PRIMARY KEY(tenant_id,kind,record_id),UNIQUE(tenant_id,reference)
);
ALTER TABLE ironvault_private.refund_cases ADD COLUMN payout_reference text;
CREATE FUNCTION ironvault_private.transaction_reference(p_tenant text,p_kind text,p_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE ref text;bytes bytea;alphabet constant text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';i integer;tries integer;
BEGIN
 IF p_id IS NULL OR p_kind NOT IN ('topup','refund') THEN RAISE EXCEPTION 'Valid reference identity required';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('reference:'||p_tenant||':'||p_kind||':'||p_id,0));
 SELECT reference INTO ref FROM ironvault_private.transaction_references WHERE tenant_id=p_tenant AND kind=p_kind AND record_id=p_id;IF FOUND THEN RETURN ref;END IF;
 FOR tries IN 1..100 LOOP
  bytes:=decode(replace(gen_random_uuid()::text,'-',''),'hex');ref:='';FOR i IN 0..5 LOOP ref:=ref||substr(alphabet,1+get_byte(bytes,i)%32,1);END LOOP;
  BEGIN
   INSERT INTO ironvault_private.transaction_references(tenant_id,kind,record_id,reference,created_by) VALUES(p_tenant,p_kind,p_id,ref,auth.uid());RETURN ref;
  EXCEPTION WHEN unique_violation THEN NULL;END;
 END LOOP;
 RAISE EXCEPTION 'Could not allocate a unique reference; retry';
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.topup_notice()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE balance numeric;actor jsonb;
BEGIN
 IF NEW.kind='topup' THEN
  SELECT wallet_balance INTO balance FROM public.members WHERE id=NEW.member_id;actor:=ironvault_private.audit_actor(NEW.actor_id,NEW.tenant_id);
  PERFORM ironvault_private.member_update(NEW.tenant_id,NEW.member_id,'topup:'||NEW.id,'Wallet top-up recorded','Amount: PHP '||NEW.amount||E'\nBalance before: PHP '||(balance-NEW.amount)||E'\nBalance after: PHP '||balance||E'\nRecorded by: '||coalesce(actor->>'name','Authorized account')||E'\nReference: '||CASE WHEN NEW.request_id IS NOT NULL THEN ironvault_private.transaction_reference(NEW.tenant_id,'topup',NEW.request_id) ELSE NEW.id::text END);
 END IF;RETURN NEW;
END $fn$;

ALTER FUNCTION public.iv_financial_transaction(text,text,text,numeric,numeric,uuid) RENAME TO financial_transaction_044_base;
ALTER FUNCTION public.financial_transaction_044_base(text,text,text,numeric,numeric,uuid) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_financial_transaction(p_operation text,p_member_id text,p_plan text,p_amount numeric,p_cash_amount numeric,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;tenant text;ref text;
BEGIN
 result:=ironvault_private.financial_transaction_044_base(p_operation,p_member_id,p_plan,p_amount,p_cash_amount,p_request_id);
 IF p_operation='topup' THEN
 SELECT tenant_id INTO STRICT tenant FROM public.members WHERE id=p_member_id;
 ref:=ironvault_private.transaction_reference(tenant,'topup',p_request_id);RETURN result||jsonb_build_object('reference',ref);
 END IF;RETURN result;
END $fn$;
CREATE FUNCTION ironvault_private.require_full_correction(p_review jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF p_review->>'action'='correct_credit' AND p_review->>'reason_category'='Incorrect account selected' THEN
  IF nullif(p_review->>'target_member_id','') IS NULL THEN RAISE EXCEPTION 'Select the intended member for a wrong-account transfer';END IF;
  IF (p_review->>'remaining_eligible')::numeric<>(p_review->'source'->>'amount')::numeric THEN RAISE EXCEPTION 'This credit was previously adjusted. Owner resolution is required before a full transfer';END IF;
  IF (p_review->>'amount')::numeric<>(p_review->>'remaining_eligible')::numeric THEN RAISE EXCEPTION 'Wrong-account corrections must transfer the full eligible credit';END IF;
 END IF;
END $fn$;
CREATE FUNCTION ironvault_private.refund_activity_data(p_case ironvault_private.refund_cases)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('id',p_case.id,'reference',p_case.reference,'source_key',p_case.source_key,'action',p_case.action,'amount',p_case.amount,'status',p_case.status,'reason',p_case.reason,'member',ironvault_private.audit_member(p_case.member_id,p_case.tenant_id),'target',ironvault_private.audit_member(p_case.target_member_id,p_case.tenant_id),'wallet_before',p_case.wallet_before,'wallet_after',p_case.wallet_after,'target_wallet_before',p_case.target_wallet_before,'target_wallet_after',p_case.target_wallet_after,'payout_reference',p_case.payout_reference);
$fn$;
CREATE FUNCTION ironvault_private.refund_activity_text(p_case ironvault_private.refund_cases)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.audit_member_label(p_case.member_id,p_case.tenant_id)||' · PHP '||p_case.amount||' · '||p_case.action||' · '||p_case.reason||' · Reference: '||coalesce(p_case.reference,p_case.id::text)||CASE WHEN p_case.status='pending' THEN ' · Pending approval—no balance change yet' ELSE '' END;
$fn$;
CREATE OR REPLACE FUNCTION public.iv_refunds(p_tenant text,p_action text DEFAULT 'list',p_id uuid DEFAULT NULL,p_payload jsonb DEFAULT '{}',p_review text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE r ironvault_private.refund_cases%ROWTYPE;preview jsonb;can_approve boolean;member text;generated text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('refund:'||p_tenant,0));
 can_approve:=ironvault_private.staff_has_permission(p_tenant,'refund_approve');
 PERFORM ironvault_private.staff_require(p_tenant,CASE WHEN can_approve THEN 'refund_approve' ELSE 'refund_request' END);
 IF p_action='reserve_reference' THEN
  PERFORM ironvault_private.staff_require(p_tenant,'refund_request');
  IF p_id IS NULL THEN RAISE EXCEPTION 'Request identity required';END IF;
  generated:=ironvault_private.transaction_reference(p_tenant,'refund',p_id);
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.transaction_references WHERE tenant_id=p_tenant AND kind='refund' AND record_id=p_id AND created_by=auth.uid()) THEN RAISE EXCEPTION 'Reference belongs to another requester';END IF;
  RETURN jsonb_build_object('reference',generated);
 END IF;
 IF p_action='preview' THEN
  preview:=ironvault_private.refund_preview(p_tenant,p_payload);
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.refund_cases c WHERE c.id=p_id AND c.tenant_id=p_tenant) THEN
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.transaction_references t WHERE t.tenant_id=p_tenant AND t.kind='refund' AND t.record_id=p_id AND t.reference=p_payload->>'reference' AND t.created_by=auth.uid()) THEN RAISE EXCEPTION 'Generate the request reference before review';END IF;
   PERFORM ironvault_private.require_full_correction(preview);
  END IF;
  RETURN preview;
 END IF;
 IF p_action IN ('request','approve','reject','cancel') THEN
  IF p_id IS NULL THEN RAISE EXCEPTION 'Request identity required';END IF;
  SELECT * INTO r FROM ironvault_private.refund_cases WHERE id=p_id FOR UPDATE;
  IF FOUND AND r.tenant_id<>p_tenant THEN RAISE EXCEPTION 'Request belongs to another gym';END IF;
  IF p_action='request' THEN
   PERFORM ironvault_private.staff_require(p_tenant,'refund_request');
   IF r.id IS NOT NULL THEN IF r.payload IS DISTINCT FROM p_payload OR r.requested_by<>auth.uid() THEN RAISE EXCEPTION 'Request ID already used';END IF;RETURN to_jsonb(r);END IF;
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.transaction_references t WHERE t.tenant_id=p_tenant AND t.kind='refund' AND t.record_id=p_id AND t.reference=p_payload->>'reference' AND t.created_by=auth.uid()) THEN RAISE EXCEPTION 'Request reference is missing or changed';END IF;
   preview:=ironvault_private.refund_preview(p_tenant,p_payload);PERFORM ironvault_private.require_full_correction(preview);IF preview->>'review_hash' IS DISTINCT FROM p_review THEN RAISE EXCEPTION 'Review changed. Generate a fresh review before submitting';END IF;
   INSERT INTO ironvault_private.refund_cases(id,tenant_id,member_id,source_key,action,amount,target_member_id,reason_category,reason,reference,payload,source_snapshot,requested_by,requested_actor)
   VALUES(p_id,p_tenant,preview->>'member_id',preview->>'source_key',preview->>'action',(preview->>'amount')::numeric,preview->>'target_member_id',preview->>'reason_category',preview->>'reason',nullif(preview->>'reference',''),p_payload,preview->'source',auth.uid(),ironvault_private.audit_actor(auth.uid(),p_tenant)) RETURNING * INTO r;
  ELSE
   IF r.id IS NULL THEN RAISE EXCEPTION 'Request unavailable';END IF;
   IF p_action='approve' THEN
    IF NOT can_approve THEN RAISE EXCEPTION 'Refund approval permission required';END IF;
    IF r.status='approved' THEN RETURN to_jsonb(r);END IF;
    IF r.status<>'pending' THEN RAISE EXCEPTION 'Request already resolved';END IF;
    preview:=ironvault_private.refund_preview(p_tenant,r.payload);
    IF EXISTS(SELECT 1 FROM ironvault_private.transaction_references t WHERE t.tenant_id=p_tenant AND t.kind='refund' AND t.record_id=r.id) THEN PERFORM ironvault_private.require_full_correction(preview);END IF;
    IF preview->>'review_hash' IS DISTINCT FROM p_review THEN RAISE EXCEPTION 'Amounts or wallet state changed; review again';END IF;
    IF r.action='cash' AND (p_payload->>'cash_returned' IS DISTINCT FROM 'true' OR length(btrim(coalesce(p_payload->>'payout_reference','')))<3) THEN RAISE EXCEPTION 'Confirm cash was returned and enter its receipt/reference';END IF;
    UPDATE public.members SET wallet_balance=(preview->>'wallet_after')::numeric WHERE id=r.member_id AND tenant_id=p_tenant;
    IF r.target_member_id IS NOT NULL THEN UPDATE public.members SET wallet_balance=(preview->>'target_wallet_after')::numeric WHERE id=r.target_member_id AND tenant_id=p_tenant;END IF;
    UPDATE ironvault_private.refund_cases SET status='approved',approved_by=auth.uid(),approved_actor=ironvault_private.audit_actor(auth.uid(),p_tenant),approved_at=clock_timestamp(),wallet_before=(preview->>'wallet_before')::numeric,wallet_after=(preview->>'wallet_after')::numeric,target_wallet_before=(preview->>'target_wallet_before')::numeric,target_wallet_after=(preview->>'target_wallet_after')::numeric,payout_reference=CASE WHEN r.action='cash' THEN p_payload->>'payout_reference' ELSE payout_reference END WHERE id=p_id RETURNING * INTO r;
    PERFORM ironvault_private.member_update(p_tenant,r.member_id,'refund:'||r.id,CASE r.action WHEN 'cash' THEN 'Cash refund recorded' WHEN 'wallet' THEN 'Refund credited to wallet' ELSE 'Wallet credit correction' END,'Amount: PHP '||r.amount||E'\nAction: '||r.action||E'\nReason: '||r.reason||E'\nBalance before: PHP '||r.wallet_before||E'\nBalance after: PHP '||r.wallet_after||E'\nApproved by: '||coalesce(r.approved_actor->>'name','Authorized account')||E'\nReference: '||coalesce(r.reference,r.id::text));
    IF r.target_member_id IS NOT NULL THEN PERFORM ironvault_private.member_update(p_tenant,r.target_member_id,'correction:'||r.id,'Wallet credit corrected','Amount credited: PHP '||r.amount||E'\nReason: Correction of an incorrectly assigned credit.'||E'\nBalance before: PHP '||r.target_wallet_before||E'\nBalance after: PHP '||r.target_wallet_after||E'\nApproved by: '||coalesce(r.approved_actor->>'name','Authorized account')||E'\nReference: '||r.id);END IF;
   ELSE
    IF r.status<>'pending' THEN RAISE EXCEPTION 'Request already resolved';END IF;
    IF p_action='reject' AND NOT can_approve OR p_action='cancel' AND r.requested_by<>auth.uid() AND NOT can_approve THEN RAISE EXCEPTION 'Not authorized';END IF;
    IF length(btrim(coalesce(p_payload->>'reason','')))<3 THEN RAISE EXCEPTION 'Record a decision reason';END IF;
    UPDATE ironvault_private.refund_cases SET status=CASE WHEN p_action='reject' THEN 'rejected' ELSE 'cancelled' END,decision_reason=p_payload->>'reason' WHERE id=p_id RETURNING * INTO r;
   END IF;
  END IF;
  PERFORM ironvault_private.write_audit(p_tenant,auth.uid(),'Refund/correction '||p_action,ironvault_private.refund_activity_text(r),jsonb_build_object('refund',ironvault_private.refund_activity_data(r)));
RETURN to_jsonb(r);
 ELSIF p_action<>'list' THEN RAISE EXCEPTION 'Invalid refund action';END IF;
 RETURN jsonb_build_object('can_approve',can_approve,'can_request',ironvault_private.staff_has_permission(p_tenant,'refund_request'),'cases',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at DESC) FROM ironvault_private.refund_cases c WHERE c.tenant_id=p_tenant),'[]'),'members',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'display_code',m.display_code,'status',m.status,'wallet',m.wallet_balance)) FROM public.members m WHERE m.tenant_id=p_tenant),'[]'),'sources',coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',t.member_id,'key',t.id::text,'kind',t.kind,'reference',(SELECT x.reference FROM ironvault_private.transaction_references x WHERE x.tenant_id=p_tenant AND x.kind='topup' AND x.record_id=t.request_id),'amount',t.amount,'created_at',t.created_at,'description',t.description)) FROM public.iv_financial_transactions t WHERE t.tenant_id=p_tenant AND t.kind IN ('topup','plan_cash','plan_wallet')),'[]')||coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',c.member_id,'key','refund:'||c.id,'kind','refund_credit','amount',c.amount,'created_at',c.approved_at,'description','Approved wallet refund')) FROM ironvault_private.refund_cases c WHERE c.tenant_id=p_tenant AND c.status='approved' AND c.action='wallet'),'[]')||coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',c.target_member_id,'key','correction:'||c.id,'kind','refund_credit','amount',c.amount,'created_at',c.approved_at,'description','Corrected incoming wallet credit')) FROM ironvault_private.refund_cases c WHERE c.tenant_id=p_tenant AND c.status='approved' AND c.target_member_id IS NOT NULL),'[]'));
END $fn$;


ALTER FUNCTION public.iv_report_snapshot(text,date,date) RENAME TO report_snapshot_044_base;
ALTER FUNCTION public.report_snapshot_044_base(text,date,date) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_report_snapshot(p_tenant text,p_start date,p_end date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;activity jsonb;financial jsonb;
BEGIN
 result:=ironvault_private.report_snapshot_044_base(p_tenant,p_start,p_end);
 -- Older refund events are enriched at read time; original audit records are not rewritten.
 SELECT coalesce(jsonb_agg(CASE WHEN log->'audit_data'->'refund' IS NOT NULL THEN log WHEN c.id IS NOT NULL THEN log||jsonb_build_object('audit_data',CASE WHEN jsonb_typeof(log->'audit_data')='object' THEN log->'audit_data' ELSE '{}'::jsonb END||jsonb_build_object('version',1,'tenant_id',p_tenant,'refund',ironvault_private.refund_activity_data(c)||jsonb_build_object('status',CASE WHEN log->>'event'='Refund/correction request' THEN 'pending' ELSE c.status END))) WHEN tr.reference IS NOT NULL THEN log||jsonb_build_object('details',replace(coalesce(log->>'details',''),log->'audit_data'->>'request_id',tr.reference)||' · Reference: '||tr.reference) ELSE log END),'[]') INTO activity
 FROM jsonb_array_elements(result->'activity') log LEFT JOIN ironvault_private.transaction_references tr ON tr.tenant_id=p_tenant AND tr.kind='topup' AND tr.record_id::text=log->'audit_data'->>'request_id' LEFT JOIN ironvault_private.refund_cases c ON c.tenant_id=p_tenant AND log->>'event' LIKE 'Refund/correction %' AND split_part(log->>'details',' · ',1)=c.id::text;
 SELECT coalesce(jsonb_agg(row||CASE WHEN ref.reference IS NOT NULL THEN jsonb_build_object('reference',ref.reference,'description',coalesce(row->>'description','')||' · Reference: '||ref.reference) ELSE '{}'::jsonb END),'[]') INTO financial
 FROM jsonb_array_elements(result->'financial') row LEFT JOIN ironvault_private.transaction_references ref ON ref.tenant_id=p_tenant AND ref.kind='topup' AND row->>'kind'='topup' AND ref.record_id::text=row->>'request_id';
 RETURN result||jsonb_build_object('activity',activity,'financial',financial);
END $fn$;
CREATE FUNCTION ironvault_private.member_latest_entry(p_member text,p_tenant text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('id',a.id,'method',a.method,'created_at',a.created_at,'server_now',now()) FROM public.iv_attendance_logs a WHERE a.member_id=p_member AND a.tenant_id=p_tenant AND ironvault_private.can_read_member(p_member,p_tenant) ORDER BY a.created_at DESC,a.id DESC LIMIT 1;
$fn$;
CREATE OR REPLACE VIEW public.iv_members WITH(security_barrier=true) AS
 SELECT m.id,m.tenant_id,m.tenant_token,m.name,m.email,m.phone,NULL::text AS password,
 m.classification,m.discount_percentage,m.plan,m.card_barcode,m.wallet_balance,
 CASE WHEN ironvault_private.can_read_financial_reports(m.tenant_id) OR EXISTS(
  SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=m.id AND r.tenant_id=m.tenant_id)
 THEN m.amount ELSE NULL END AS amount,
 m.scans_used,m.last_scanned_date,m.expiration_date,m.status,m.date_joined,m.avatar,m.created_at,m.display_code,ironvault_private.member_latest_entry(m.id,m.tenant_id) AS last_entry
 FROM public.members m WHERE ironvault_private.can_read_member(m.id,m.tenant_id);

ALTER TABLE ironvault_private.transaction_references ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.transaction_references FROM PUBLIC,anon,authenticated,service_role;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature,n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
 (n.nspname='ironvault_private' AND p.proname IN ('transaction_reference','require_full_correction','refund_activity_data','refund_activity_text','member_latest_entry','topup_notice','financial_transaction_044_base','report_snapshot_044_base')) OR
 (n.nspname='public' AND p.proname IN ('iv_refunds','iv_financial_transaction','iv_report_snapshot')) LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f.signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 IF f.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.signature);END IF;
 END LOOP;
END $acl$;
-- View callers need EXECUTE; the helper rechecks member/tenant authorization itself.
GRANT EXECUTE ON FUNCTION ironvault_private.member_latest_entry(text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
