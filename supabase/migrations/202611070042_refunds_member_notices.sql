-- 042 MANUAL ONLY after 041. Adds linked adjustments; never rewrites original ledger/history.
BEGIN;
DO $guard$ BEGIN IF to_regclass('ironvault_private.staff_access') IS NULL OR to_regprocedure('ironvault_private.staff_has_permission(text,text)') IS NULL THEN RAISE EXCEPTION 'Apply 041 first';END IF;IF to_regprocedure('ironvault_private.report_snapshot_042_base(text,date,date)') IS NOT NULL THEN RAISE EXCEPTION '042 already installed; do not reapply';END IF;END $guard$;
CREATE TABLE ironvault_private.refund_cases(
 id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
 source_key text NOT NULL,action text NOT NULL CHECK(action IN ('cash','wallet','correct_credit')),amount numeric(12,2) NOT NULL CHECK(amount>0),
 target_member_id text REFERENCES public.members(id) ON DELETE CASCADE,reason_category text NOT NULL,reason text NOT NULL,reference text,
 payload jsonb NOT NULL,source_snapshot jsonb NOT NULL,status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','cancelled')),
 requested_by uuid NOT NULL,requested_actor jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),approved_by uuid,approved_actor jsonb,approved_at timestamptz,
 wallet_before numeric(12,2),wallet_after numeric(12,2),target_wallet_before numeric(12,2),target_wallet_after numeric(12,2),decision_reason text
);
CREATE INDEX iv_refunds_source ON ironvault_private.refund_cases(tenant_id,source_key,status);
CREATE TABLE ironvault_private.member_updates(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
 event_key text NOT NULL,kind text NOT NULL CHECK(kind IN ('financial','status')),state_key text,title text NOT NULL,body text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),read_at timestamptz,resolved_at timestamptz,UNIQUE(tenant_id,member_id,event_key)
);
CREATE OR REPLACE FUNCTION ironvault_private.member_update(p_tenant text,p_member text,p_key text,p_title text,p_body text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS $fn$
 INSERT INTO ironvault_private.member_updates(tenant_id,member_id,event_key,kind,title,body) VALUES(p_tenant,p_member,p_key,'financial',p_title,p_body) ON CONFLICT DO NOTHING;
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.sync_member_status(p_member text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;n ironvault_private.member_updates%ROWTYPE;key text;title text;body text;valid boolean:=false;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member FOR UPDATE;IF NOT FOUND THEN RETURN;END IF;
 IF m.status='ACTIVE' AND m.plan IN ('1-Day Pass','1-Week Pass','1-Month Unlimited') AND m.expiration_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
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
CREATE OR REPLACE FUNCTION ironvault_private.member_status_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN PERFORM ironvault_private.sync_member_status(NEW.id);RETURN NEW;END $fn$;
CREATE TRIGGER iv_member_status_notice AFTER INSERT OR UPDATE OF status,plan,expiration_date ON public.members FOR EACH ROW EXECUTE FUNCTION ironvault_private.member_status_changed();
CREATE OR REPLACE FUNCTION ironvault_private.topup_notice()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE balance numeric;actor jsonb;
BEGIN
 IF NEW.kind='topup' THEN
  SELECT wallet_balance INTO balance FROM public.members WHERE id=NEW.member_id;actor:=ironvault_private.audit_actor(NEW.actor_id,NEW.tenant_id);
  PERFORM ironvault_private.member_update(NEW.tenant_id,NEW.member_id,'topup:'||NEW.id,'Wallet top-up recorded','Amount: PHP '||NEW.amount||E'\nBalance before: PHP '||(balance-NEW.amount)||E'\nBalance after: PHP '||balance||E'\nRecorded by: '||coalesce(actor->>'name','Authorized account')||E'\nReference: '||coalesce(NEW.request_id::text,NEW.id::text));
 END IF;RETURN NEW;
END $fn$;
CREATE TRIGGER iv_topup_notice AFTER INSERT ON public.iv_financial_transactions FOR EACH ROW EXECUTE FUNCTION ironvault_private.topup_notice();
CREATE OR REPLACE FUNCTION ironvault_private.refund_preview(p_tenant text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;target public.members%ROWTYPE;source jsonb;used numeric;available numeric;amount numeric;delta numeric:=0;result jsonb;action text:=p_payload->>'action';chosen_source text:=p_payload->>'source_key';
BEGIN
 PERFORM ironvault_private.staff_require(p_tenant,CASE WHEN ironvault_private.staff_has_permission(p_tenant,'refund_approve') THEN 'refund_approve' ELSE 'refund_request' END);
 PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>20000 OR length(coalesce(p_payload->>'reference',''))>180 THEN RAISE EXCEPTION 'Invalid refund details';END IF;
 amount:=(p_payload->>'amount')::numeric;
 IF amount IS NULL OR amount::text IN ('NaN','Infinity','-Infinity') OR amount<=0 OR amount>10000000 OR amount<>round(amount,2) OR action IS NULL OR action NOT IN ('cash','wallet','correct_credit') OR length(btrim(coalesce(p_payload->>'reason',''))) NOT BETWEEN 3 AND 1000 OR length(coalesce(p_payload->>'reason_category','')) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Enter a valid action, amount and reason';END IF;
 SELECT * INTO m FROM public.members WHERE id=p_payload->>'member_id' AND tenant_id=p_tenant FOR UPDATE;IF NOT FOUND THEN RAISE EXCEPTION 'Member unavailable';END IF;
 SELECT to_jsonb(t) INTO source FROM public.iv_financial_transactions t WHERE t.tenant_id=p_tenant AND t.member_id=m.id AND t.id::text=chosen_source AND t.kind IN ('topup','plan_cash','plan_wallet');
 IF source IS NULL THEN
  SELECT jsonb_build_object('id','refund:'||r.id,'kind','refund_credit','amount',r.amount,'description','Previously approved wallet refund','actor_id',r.approved_by) INTO source FROM ironvault_private.refund_cases r WHERE r.tenant_id=p_tenant AND r.member_id=m.id AND 'refund:'||r.id=chosen_source AND r.status='approved' AND r.action='wallet';
 END IF;
 IF source IS NULL THEN
 SELECT jsonb_build_object('id','correction:'||r.id,'kind','refund_credit','amount',r.amount,'description','Previously corrected incoming wallet credit','actor_id',r.approved_by) INTO source FROM ironvault_private.refund_cases r WHERE r.tenant_id=p_tenant AND r.target_member_id=m.id AND 'correction:'||r.id=chosen_source AND r.status='approved';
 END IF;
 IF source IS NULL THEN RAISE EXCEPTION 'Choose an original eligible transaction';END IF;
 IF (source->>'amount') IS NULL OR source->>'amount' IN ('NaN','Infinity','-Infinity') OR (source->>'amount')::numeric<=0 OR coalesce(m.wallet_balance,0)::text IN ('NaN','Infinity','-Infinity') OR coalesce(m.wallet_balance,0)<0 THEN RAISE EXCEPTION 'Invalid existing financial state; owner review required';END IF;
 SELECT coalesce(sum(r.amount),0) INTO used FROM ironvault_private.refund_cases r WHERE r.tenant_id=p_tenant AND r.source_key=chosen_source AND r.status='approved';
 available:=(source->>'amount')::numeric-used;IF amount>available THEN RAISE EXCEPTION 'Amount exceeds the remaining eligible amount';END IF;
 IF source->>'kind' IN ('topup','refund_credit') THEN
  IF action='wallet' THEN RAISE EXCEPTION 'This credit is already in the wallet; choose cash settlement or credit correction';END IF;delta:=-amount;
 ELSIF action='correct_credit' THEN RAISE EXCEPTION 'Credit corrections must reference an original wallet credit';
 ELSIF action='wallet' THEN delta:=amount;END IF;
 IF delta>0 AND m.status<>'ACTIVE' THEN RAISE EXCEPTION 'Use a cash settlement for an inactive membership';END IF;
 IF coalesce(m.wallet_balance,0)+delta<0 THEN RAISE EXCEPTION 'This correction would create a negative wallet. Owner resolution is required; no deduction was made';END IF;
 IF nullif(p_payload->>'target_member_id','') IS NOT NULL THEN
  IF action<>'correct_credit' OR p_payload->>'target_member_id'=m.id THEN RAISE EXCEPTION 'Choose a different member for this credit correction';END IF;
  SELECT * INTO target FROM public.members WHERE id=p_payload->>'target_member_id' AND tenant_id=p_tenant AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Corrected recipient must be an active member of this gym';END IF;
  IF coalesce(target.wallet_balance,0)::text IN ('NaN','Infinity','-Infinity') OR coalesce(target.wallet_balance,0)<0 THEN RAISE EXCEPTION 'Invalid corrected-recipient balance';END IF;
 END IF;
 result:=jsonb_build_object('member_id',m.id,'member_name',m.name,'source',source,'source_key',chosen_source,'action',action,'amount',amount,'remaining_eligible',available,'wallet_before',coalesce(m.wallet_balance,0),'wallet_after',coalesce(m.wallet_balance,0)+delta,'wallet_delta',delta,'target_member_id',target.id,'target_name',target.name,'target_wallet_before',target.wallet_balance,'target_wallet_after',CASE WHEN target.id IS NOT NULL THEN coalesce(target.wallet_balance,0)+amount END,'cash_payout',CASE WHEN action='cash' THEN amount ELSE 0 END,'reason_category',p_payload->>'reason_category','reason',p_payload->>'reason','reference',p_payload->>'reference','actor',auth.uid());
 RETURN result||jsonb_build_object('review_hash',md5(result::text));
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_refunds(p_tenant text,p_action text DEFAULT 'list',p_id uuid DEFAULT NULL,p_payload jsonb DEFAULT '{}',p_review text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE r ironvault_private.refund_cases%ROWTYPE;preview jsonb;can_approve boolean;member text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('refund:'||p_tenant,0));
 can_approve:=ironvault_private.staff_has_permission(p_tenant,'refund_approve');
 PERFORM ironvault_private.staff_require(p_tenant,CASE WHEN can_approve THEN 'refund_approve' ELSE 'refund_request' END);
 IF p_action='preview' THEN RETURN ironvault_private.refund_preview(p_tenant,p_payload);END IF;
 IF p_action IN ('request','approve','reject','cancel') THEN
  IF p_id IS NULL THEN RAISE EXCEPTION 'Request identity required';END IF;
  SELECT * INTO r FROM ironvault_private.refund_cases WHERE id=p_id FOR UPDATE;
  IF FOUND AND r.tenant_id<>p_tenant THEN RAISE EXCEPTION 'Request belongs to another gym';END IF;
  IF p_action='request' THEN
   PERFORM ironvault_private.staff_require(p_tenant,'refund_request');
   IF r.id IS NOT NULL THEN IF r.payload IS DISTINCT FROM p_payload OR r.requested_by<>auth.uid() THEN RAISE EXCEPTION 'Request ID already used';END IF;RETURN to_jsonb(r);END IF;
   preview:=ironvault_private.refund_preview(p_tenant,p_payload);IF preview->>'review_hash' IS DISTINCT FROM p_review THEN RAISE EXCEPTION 'Review changed. Generate a fresh review before submitting';END IF;
   INSERT INTO ironvault_private.refund_cases(id,tenant_id,member_id,source_key,action,amount,target_member_id,reason_category,reason,reference,payload,source_snapshot,requested_by,requested_actor)
   VALUES(p_id,p_tenant,preview->>'member_id',preview->>'source_key',preview->>'action',(preview->>'amount')::numeric,preview->>'target_member_id',preview->>'reason_category',preview->>'reason',nullif(preview->>'reference',''),p_payload,preview->'source',auth.uid(),ironvault_private.audit_actor(auth.uid(),p_tenant)) RETURNING * INTO r;
  ELSE
   IF r.id IS NULL THEN RAISE EXCEPTION 'Request unavailable';END IF;
   IF p_action='approve' THEN
    IF NOT can_approve THEN RAISE EXCEPTION 'Refund approval permission required';END IF;
    IF r.status='approved' THEN RETURN to_jsonb(r);END IF;
    IF r.status<>'pending' THEN RAISE EXCEPTION 'Request already resolved';END IF;
    preview:=ironvault_private.refund_preview(p_tenant,r.payload);
    IF preview->>'review_hash' IS DISTINCT FROM p_review THEN RAISE EXCEPTION 'Amounts or wallet state changed; review again';END IF;
    IF r.action='cash' AND (p_payload->>'cash_returned' IS DISTINCT FROM 'true' OR length(btrim(coalesce(p_payload->>'payout_reference','')))<3) THEN RAISE EXCEPTION 'Confirm cash was returned and enter its receipt/reference';END IF;
    UPDATE public.members SET wallet_balance=(preview->>'wallet_after')::numeric WHERE id=r.member_id AND tenant_id=p_tenant;
    IF r.target_member_id IS NOT NULL THEN UPDATE public.members SET wallet_balance=(preview->>'target_wallet_after')::numeric WHERE id=r.target_member_id AND tenant_id=p_tenant;END IF;
    UPDATE ironvault_private.refund_cases SET status='approved',approved_by=auth.uid(),approved_actor=ironvault_private.audit_actor(auth.uid(),p_tenant),approved_at=clock_timestamp(),wallet_before=(preview->>'wallet_before')::numeric,wallet_after=(preview->>'wallet_after')::numeric,target_wallet_before=(preview->>'target_wallet_before')::numeric,target_wallet_after=(preview->>'target_wallet_after')::numeric,reference=CASE WHEN r.action='cash' THEN p_payload->>'payout_reference' ELSE reference END WHERE id=p_id RETURNING * INTO r;
    PERFORM ironvault_private.member_update(p_tenant,r.member_id,'refund:'||r.id,CASE r.action WHEN 'cash' THEN 'Cash refund recorded' WHEN 'wallet' THEN 'Refund credited to wallet' ELSE 'Wallet credit correction' END,'Amount: PHP '||r.amount||E'\nAction: '||r.action||E'\nReason: '||r.reason||E'\nBalance before: PHP '||r.wallet_before||E'\nBalance after: PHP '||r.wallet_after||E'\nApproved by: '||coalesce(r.approved_actor->>'name','Authorized account')||E'\nReference: '||coalesce(r.reference,r.id::text));
    IF r.target_member_id IS NOT NULL THEN PERFORM ironvault_private.member_update(p_tenant,r.target_member_id,'correction:'||r.id,'Wallet credit corrected','Amount credited: PHP '||r.amount||E'\nReason: Correction of an incorrectly assigned credit.'||E'\nBalance before: PHP '||r.target_wallet_before||E'\nBalance after: PHP '||r.target_wallet_after||E'\nApproved by: '||coalesce(r.approved_actor->>'name','Authorized account')||E'\nReference: '||r.id);END IF;
   ELSE
    IF r.status<>'pending' THEN RAISE EXCEPTION 'Request already resolved';END IF;
    IF p_action='reject' AND NOT can_approve OR p_action='cancel' AND r.requested_by<>auth.uid() AND NOT can_approve THEN RAISE EXCEPTION 'Not authorized';END IF;
    IF length(btrim(coalesce(p_payload->>'reason','')))<3 THEN RAISE EXCEPTION 'Record a decision reason';END IF;
    UPDATE ironvault_private.refund_cases SET status=CASE WHEN p_action='reject' THEN 'rejected' ELSE 'cancelled' END,decision_reason=p_payload->>'reason' WHERE id=p_id RETURNING * INTO r;
   END IF;
  END IF;
  PERFORM public.iv_log_event(p_tenant,'Refund/correction '||p_action,r.id::text||' · '||r.action||' · PHP '||r.amount);RETURN to_jsonb(r);
 ELSIF p_action<>'list' THEN RAISE EXCEPTION 'Invalid refund action';END IF;
 RETURN jsonb_build_object('can_approve',can_approve,'can_request',ironvault_private.staff_has_permission(p_tenant,'refund_request'),'cases',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at DESC) FROM ironvault_private.refund_cases c WHERE c.tenant_id=p_tenant),'[]'),'members',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'status',m.status,'wallet',m.wallet_balance)) FROM public.members m WHERE m.tenant_id=p_tenant),'[]'),'sources',coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',t.member_id,'key',t.id::text,'kind',t.kind,'amount',t.amount,'created_at',t.created_at,'description',t.description)) FROM public.iv_financial_transactions t WHERE t.tenant_id=p_tenant AND t.kind IN ('topup','plan_cash','plan_wallet')),'[]')||coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',c.member_id,'key','refund:'||c.id,'kind','refund_credit','amount',c.amount,'created_at',c.approved_at,'description','Approved wallet refund')) FROM ironvault_private.refund_cases c WHERE c.tenant_id=p_tenant AND c.status='approved' AND c.action='wallet'),'[]')||coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',c.target_member_id,'key','correction:'||c.id,'kind','refund_credit','amount',c.amount,'created_at',c.approved_at,'description','Corrected incoming wallet credit')) FROM ironvault_private.refund_cases c WHERE c.tenant_id=p_tenant AND c.status='approved' AND c.target_member_id IS NOT NULL),'[]'));
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_staff_access(p_tenant text,p_action text DEFAULT 'mine',p_user uuid DEFAULT NULL,p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE row_access ironvault_private.staff_access%ROWTYPE;actor_role text;key text;perms jsonb;result jsonb;
BEGIN
 SELECT r.role INTO actor_role FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
 ((r.tenant_id=p_tenant AND r.role IN ('owner','staff')) OR (r.role='super_admin' AND r.tenant_id IS NULL)) LIMIT 1;
 IF actor_role IS NULL THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501';END IF;
 IF p_action='mine' THEN
  SELECT * INTO row_access FROM ironvault_private.staff_access WHERE tenant_id=p_tenant AND user_id=auth.uid();
  RETURN jsonb_build_object('role',actor_role,'state',coalesce(row_access.state,'active'),'permissions',CASE WHEN actor_role IN ('owner','super_admin') THEN '{"manual_checkin":true,"reports_read":true,"reports_export":true,"announcements_manage":true,"pricing_manage":true,"subscription_read":true,"refund_request":true,"refund_approve":true}'::jsonb ELSE coalesce(row_access.permissions,'{}') END);
 END IF;
 IF actor_role NOT IN ('owner','super_admin') OR (actor_role='owner' AND NOT ironvault_private.subscription_owner(p_tenant)) THEN RAISE EXCEPTION 'Registered owner required' USING ERRCODE='42501';END IF;
 IF p_action IN ('permissions','suspend','reactivate','remove') THEN
  IF p_user IS NULL OR p_user=auth.uid() THEN RAISE EXCEPTION 'Choose a staff account';END IF;
  PERFORM 1 FROM public.iv_user_roles r WHERE r.tenant_id=p_tenant AND r.user_id=p_user AND r.role='staff' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Staff account unavailable';END IF;
  INSERT INTO ironvault_private.staff_access(tenant_id,user_id) VALUES(p_tenant,p_user) ON CONFLICT DO NOTHING;
  SELECT * INTO STRICT row_access FROM ironvault_private.staff_access WHERE tenant_id=p_tenant AND user_id=p_user FOR UPDATE;
  IF row_access.state='removed' THEN RAISE EXCEPTION 'Staff was removed; create a new authorized engagement instead';END IF;
  IF p_action='permissions' THEN
   perms:=p_data->'permissions';IF perms IS NULL OR jsonb_typeof(perms)<>'object' THEN RAISE EXCEPTION 'Choose explicit permissions';END IF;
   FOR key IN SELECT jsonb_object_keys(perms) LOOP
    IF NOT key=ANY(ARRAY['manual_checkin','reports_read','reports_export','announcements_manage','pricing_manage','subscription_read','refund_request','refund_approve']) OR jsonb_typeof(perms->key)<>'boolean' THEN RAISE EXCEPTION 'Invalid permission';END IF;
   END LOOP;
   IF perms->>'reports_export'='true' AND perms->>'reports_read' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Report export requires report viewing';END IF;
   UPDATE ironvault_private.staff_access SET permissions=perms,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE tenant_id=p_tenant AND user_id=p_user;
   DELETE FROM ironvault_private.staff_report_permissions WHERE tenant_id=p_tenant AND user_id=p_user;
   IF perms->>'reports_read'='true' THEN INSERT INTO ironvault_private.staff_report_permissions(tenant_id,user_id,permission,granted_by) VALUES(p_tenant,p_user,'financial_reports_read',auth.uid());END IF;
  ELSE
   UPDATE ironvault_private.staff_access SET state=CASE p_action WHEN 'suspend' THEN 'suspended' WHEN 'remove' THEN 'removed' ELSE 'active' END,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE tenant_id=p_tenant AND user_id=p_user;
   UPDATE public.iv_user_roles SET enabled=p_action='reactivate',disabled_at=CASE WHEN p_action='reactivate' THEN NULL ELSE clock_timestamp() END WHERE tenant_id=p_tenant AND user_id=p_user AND role='staff';
  END IF;
  PERFORM public.iv_log_event(p_tenant,'Staff access '||p_action,p_user::text);
 ELSIF p_action<>'list' THEN RAISE EXCEPTION 'Invalid staff action';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',r.user_id,'name',coalesce((SELECT x->>'name' FROM public.owners g CROSS JOIN LATERAL jsonb_array_elements(coalesce(g.staff,'[]')) x WHERE g.id=p_tenant AND x->>'auth_user_id'=r.user_id::text LIMIT 1),'Staff account'),'email',b.contact_email,'state',coalesce(a.state,CASE WHEN r.enabled AND r.disabled_at IS NULL THEN 'active' ELSE 'suspended' END),'permissions',coalesce(a.permissions,'{}')) ORDER BY r.user_id),'[]') INTO result
 FROM public.iv_user_roles r LEFT JOIN ironvault_private.staff_access a ON a.user_id=r.user_id AND a.tenant_id=r.tenant_id
 LEFT JOIN ironvault_private.branch_accounts b ON b.user_id=r.user_id AND b.tenant_id=r.tenant_id AND b.role='staff'
 WHERE r.tenant_id=p_tenant AND r.role='staff';
 RETURN jsonb_build_object('staff',result);
END $fn$;

ALTER FUNCTION public.iv_report_snapshot(text,date,date) RENAME TO report_snapshot_042_base;
ALTER FUNCTION public.report_snapshot_042_base(text,date,date) SET SCHEMA ironvault_private;
REVOKE ALL ON FUNCTION ironvault_private.report_snapshot_042_base(text,date,date) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.iv_report_snapshot(p_tenant text,p_start date,p_end date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;adjustments jsonb;
BEGIN
 result:=ironvault_private.report_snapshot_042_base(p_tenant,p_start,p_end);
 SELECT coalesce(jsonb_agg(x),'[]') INTO adjustments FROM (
 SELECT jsonb_build_object('id','refund:'||r.id,'tenant_id',r.tenant_id,'member_id',r.member_id,'kind',CASE r.action WHEN 'cash' THEN 'refund_cash' WHEN 'wallet' THEN 'refund_wallet' ELSE 'wallet_correction' END,'amount',r.amount,'wallet_after',r.wallet_after,'actor_id',r.approved_by,'created_at',r.approved_at,'description',r.action||' · '||r.reason||' · '||coalesce(r.reference,r.id::text)) x
 FROM ironvault_private.refund_cases r WHERE r.tenant_id=p_tenant AND r.status='approved' AND (r.approved_at AT TIME ZONE 'Asia/Manila')::date BETWEEN p_start AND p_end
 UNION ALL
 SELECT jsonb_build_object('id','correction:'||r.id,'tenant_id',r.tenant_id,'member_id',r.target_member_id,'kind','wallet_correction_in','amount',r.amount,'wallet_after',r.target_wallet_after,'actor_id',r.approved_by,'created_at',r.approved_at,'description','Corrected incoming wallet credit · '||r.id)
 FROM ironvault_private.refund_cases r WHERE r.tenant_id=p_tenant AND r.status='approved' AND r.target_member_id IS NOT NULL AND (r.approved_at AT TIME ZONE 'Asia/Manila')::date BETWEEN p_start AND p_end) q;
 RETURN jsonb_set(result,'{financial}',coalesce(result->'financial','[]')||adjustments);
END $fn$;
ALTER FUNCTION public.iv_member_announcements(text,text,jsonb) RENAME TO member_announcements_042_base;
ALTER FUNCTION public.member_announcements_042_base(text,text,jsonb) SET SCHEMA ironvault_private;
REVOKE ALL ON FUNCTION ironvault_private.member_announcements_042_base(text,text,jsonb) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.iv_member_announcements(p_tenant text,p_mode text DEFAULT 'list',p_read jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;result jsonb;updates jsonb;
BEGIN
 IF p_mode IS NULL OR p_mode NOT IN ('list','read','claim') OR p_read IS NULL OR jsonb_typeof(p_read)<>'array' THEN RAISE EXCEPTION 'Invalid notice request';END IF;
 SELECT mem.* INTO m FROM public.members mem JOIN public.iv_user_roles r ON r.member_id=mem.id AND r.tenant_id=mem.tenant_id JOIN public.owners g ON g.id=mem.tenant_id
 WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.role='member' AND r.enabled AND r.disabled_at IS NULL AND mem.status IN ('ACTIVE','PENDING') AND g.status='ACTIVE' FOR UPDATE OF mem FOR SHARE OF r,g;
 IF NOT FOUND THEN RAISE EXCEPTION 'Member notice access denied' USING ERRCODE='42501';END IF;
 PERFORM ironvault_private.sync_member_status(m.id);
 -- General announcements still obey the existing portal and audience rules. Account notices remain accessible.
 IF m.status='ACTIVE' AND coalesce((ironvault_private.subscription_state(p_tenant)->>'portal')::boolean,false) THEN result:=ironvault_private.member_announcements_042_base(p_tenant,p_mode,p_read);
 ELSE result:=jsonb_build_object('server_now',clock_timestamp(),'items','[]'::jsonb);END IF;
 IF p_mode='read' THEN UPDATE ironvault_private.member_updates n SET read_at=coalesce(n.read_at,clock_timestamp()) WHERE n.tenant_id=p_tenant AND n.member_id=m.id AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_read) x WHERE x->>'id'=n.id::text AND x->>'revision'='1');END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',n.id,'tenant_id',n.tenant_id,'revision','1','kind',n.kind,'title',n.title,'body',n.body,'starts_at',n.created_at,'ends_at','9999-12-31T00:00:00Z','resolved_at',n.resolved_at,'unread',n.read_at IS NULL AND (n.kind<>'status' OR n.resolved_at IS NULL),'popup',false) ORDER BY n.created_at DESC),'[]') INTO updates FROM ironvault_private.member_updates n WHERE n.tenant_id=p_tenant AND n.member_id=m.id;
 RETURN jsonb_set(result,'{items}',coalesce(result->'items','[]')||updates)||jsonb_build_object('server_now',clock_timestamp());
END $fn$;
ALTER TABLE ironvault_private.refund_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.member_updates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.refund_cases,ironvault_private.member_updates FROM PUBLIC,anon,authenticated;
DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
 (n.nspname='ironvault_private' AND p.proname IN ('member_update','sync_member_status','member_status_changed','topup_notice','refund_preview','report_snapshot_042_base','member_announcements_042_base')) OR
 (n.nspname='public' AND p.proname IN ('iv_refunds','iv_staff_access','iv_member_announcements','iv_report_snapshot')) LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f.signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_refunds(text,text,uuid,jsonb,text),public.iv_staff_access(text,text,uuid,jsonb),public.iv_member_announcements(text,text,jsonb),public.iv_report_snapshot(text,date,date) TO authenticated;
COMMIT;
