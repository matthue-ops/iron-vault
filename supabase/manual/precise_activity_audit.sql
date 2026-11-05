-- MANUAL ONLY after 032. Precise audit events; preserve all historical records and business safeguards.
BEGIN;
DO $prerequisite$ BEGIN
 IF to_regprocedure('public.iv_member_legal_status()') IS NULL THEN RAISE EXCEPTION 'Apply 032 before the activity audit migration'; END IF;
END $prerequisite$;
ALTER TABLE public.iv_activity_logs ADD COLUMN IF NOT EXISTS audit_data jsonb;
ALTER TABLE ironvault_private.email_actions ADD COLUMN IF NOT EXISTS audit_context jsonb;
-- Match the existing Reports permission even for direct table reads of financial/contact audit details.
DROP POLICY IF EXISTS iv_audit_report_read_scope ON public.iv_activity_logs;
CREATE POLICY iv_audit_report_read_scope ON public.iv_activity_logs AS RESTRICTIVE FOR SELECT TO authenticated USING (ironvault_private.can_read_financial_reports(tenant_id));
CREATE OR REPLACE FUNCTION ironvault_private.audit_actor(p_actor uuid,p_tenant text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT coalesce((SELECT jsonb_build_object('id',r.user_id,'role',r.role,'name',coalesce(
 CASE r.role WHEN 'owner' THEN nullif(g.owner_name,'') WHEN 'member' THEN nullif(m.name,'')
 WHEN 'staff' THEN nullif((SELECT s.value->>'name' FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s WHERE s.value->>'auth_user_id'=r.user_id::text LIMIT 1),'')
 WHEN 'super_admin' THEN coalesce(nullif(u.raw_user_meta_data->>'name',''),nullif(u.raw_user_meta_data->>'full_name',''),'Platform administrator') END,
 (SELECT nullif(j.payload->>'name','') FROM ironvault_private.provision_requests j WHERE j.tenant_id=p_tenant AND j.completed_user=r.user_id ORDER BY j.created_at DESC LIMIT 1),'Name unavailable'))
 FROM public.iv_user_roles r JOIN public.owners g ON g.id=p_tenant LEFT JOIN public.members m ON m.id=r.member_id AND m.tenant_id=p_tenant
 LEFT JOIN auth.users u ON u.id=r.user_id WHERE r.user_id=p_actor AND (r.tenant_id=p_tenant OR (r.role='super_admin' AND r.tenant_id IS NULL))),
 jsonb_build_object('id',p_actor,'name','Actor unavailable','role','unknown'));
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.audit_member(p_member text,p_tenant text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('id',id,'name',name,'display_code',display_code,'type','member') FROM public.members WHERE id=p_member AND tenant_id=p_tenant;
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.audit_member_label(p_member text,p_tenant text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT coalesce(name,'Member')||' ('||coalesce(display_code,id)||')' FROM public.members WHERE id=p_member AND tenant_id=p_tenant;
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.audit_account(p_user uuid,p_tenant text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT CASE WHEN r.role='member' THEN ironvault_private.audit_member(r.member_id,p_tenant)
 ELSE ironvault_private.audit_actor(p_user,p_tenant)||jsonb_build_object('type',r.role) END
 FROM public.iv_user_roles r WHERE r.user_id=p_user AND r.tenant_id=p_tenant;
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.write_audit(p_tenant text,p_actor uuid,p_event text,p_details text,p_data jsonb,p_snapshot jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 INSERT INTO public.iv_activity_logs(tenant_id,actor_id,event,details,audit_data,created_at)
 VALUES(p_tenant,CASE WHEN EXISTS(SELECT 1 FROM auth.users WHERE id=p_actor) THEN p_actor ELSE NULL END,p_event,p_details,
 coalesce(p_data,'{}'::jsonb)||jsonb_build_object('version',1,'tenant_id',p_tenant,'actor',coalesce(p_snapshot,ironvault_private.audit_actor(p_actor,p_tenant))),clock_timestamp());
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.audit_financial_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE op text:=NEW.payload->>'operation'; amount numeric; cash numeric; after_balance numeric; before_balance numeric; detail text;
BEGIN
 IF op NOT IN ('topup','purchase') THEN RETURN NEW; END IF;
 IF NEW.result->>'request_id' IS DISTINCT FROM NEW.request_id::text OR NEW.result->>'operation' IS DISTINCT FROM op THEN RAISE EXCEPTION 'Invalid financial receipt for audit'; END IF;
 amount:=(NEW.payload->>'amount')::numeric;cash:=(NEW.payload->>'cash')::numeric;after_balance:=(NEW.result->>'wallet_balance')::numeric;
 before_balance:=CASE WHEN op='topup' THEN after_balance-amount ELSE after_balance+amount-cash END;
 detail:=ironvault_private.audit_member_label(NEW.member_id,NEW.tenant_id)||' · '||CASE WHEN op='topup' THEN 'Added ₱'||round(amount,2)::text ELSE (NEW.payload->>'plan')||' · Total ₱'||round(amount,2)::text||' · Wallet used ₱'||round(amount-cash,2)::text||' · Cash collected ₱'||round(cash,2)::text END
 ||' · Wallet ₱'||round(before_balance,2)::text||' → ₱'||round(after_balance,2)::text;
 PERFORM ironvault_private.write_audit(NEW.tenant_id,NEW.actor_id,CASE WHEN op='topup' THEN 'Wallet top-up' ELSE 'Membership purchased' END,detail,
 jsonb_build_object('source','financial_receipt','request_id',NEW.request_id,'member',ironvault_private.audit_member(NEW.member_id,NEW.tenant_id),
 'operation',op,'amount',amount,'plan',NEW.payload->>'plan','wallet_used',CASE WHEN op='purchase' THEN amount-cash ELSE 0 END,'cash_collected',CASE WHEN op='purchase' THEN cash ELSE NULL END,'wallet_before',before_balance,'wallet_after',after_balance));
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS iv_audit_financial_receipt ON ironvault_private.financial_requests;
CREATE TRIGGER iv_audit_financial_receipt AFTER INSERT ON ironvault_private.financial_requests FOR EACH ROW EXECUTE FUNCTION ironvault_private.audit_financial_receipt();
CREATE OR REPLACE FUNCTION ironvault_private.audit_admission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 PERFORM ironvault_private.write_audit(NEW.tenant_id,NEW.actor_id,CASE NEW.method WHEN 'qr' THEN 'QR check-in' WHEN 'manual' THEN 'Manual check-in' ELSE 'Gym check-in' END,
 ironvault_private.audit_member_label(NEW.member_id,NEW.tenant_id)||' · '||CASE NEW.method WHEN 'qr' THEN 'Entry recorded by QR scan' WHEN 'manual' THEN 'Entry recorded manually' ELSE 'Entry method: '||NEW.method END,
 jsonb_build_object('source','attendance','attendance_id',NEW.id,'member',ironvault_private.audit_member(NEW.member_id,NEW.tenant_id),'method',NEW.method));
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS iv_audit_admission ON public.iv_attendance_logs;
CREATE TRIGGER iv_audit_admission AFTER INSERT ON public.iv_attendance_logs FOR EACH ROW EXECUTE FUNCTION ironvault_private.audit_admission();
CREATE OR REPLACE FUNCTION public.iv_save_member_profiles(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; m public.members%ROWTYPE; tenant text; operator boolean; owner_access boolean; discount numeric; updated_member public.members%ROWTYPE; field text; before_value jsonb; after_value jsonb; label text; operation uuid:=gen_random_uuid(); restored integer;
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
   discount_percentage=discount WHERE id=m.id RETURNING * INTO updated_member;
  IF owner_access AND item->>'status'='ACTIVE' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id WHERE r.member_id=m.id AND a.tenant_id=tenant AND r.tenant_id=tenant ) THEN
   UPDATE public.iv_user_roles SET enabled=true,disabled_at=NULL WHERE member_id=m.id AND tenant_id=tenant AND role='member' AND (NOT enabled OR disabled_at IS NOT NULL);
   GET DIAGNOSTICS restored=ROW_COUNT;
   IF restored>0 THEN PERFORM ironvault_private.write_audit(tenant,auth.uid(),'Member access restored',ironvault_private.audit_member_label(m.id,tenant),jsonb_build_object('member',ironvault_private.audit_member(m.id,tenant),'operation_id',operation,'changes',jsonb_build_object('access',jsonb_build_object('before','disabled','after','enabled')))); END IF;
  END IF;
  FOREACH field IN ARRAY ARRAY['name','phone','avatar','classification','card_barcode','discount_percentage','status'] LOOP
   before_value:=to_jsonb(m)->field;after_value:=to_jsonb(updated_member)->field;
   IF before_value IS DISTINCT FROM after_value THEN
    label:=CASE field WHEN 'name' THEN 'name' WHEN 'phone' THEN 'phone' WHEN 'avatar' THEN 'photo' WHEN 'classification' THEN 'classification' WHEN 'card_barcode' THEN 'barcode' WHEN 'discount_percentage' THEN 'discount' ELSE 'status' END;
    IF field='avatar' THEN
     before_value:=to_jsonb(CASE WHEN coalesce(m.avatar,'')='' THEN 'Not set' ELSE 'Photo set' END);
     after_value:=to_jsonb(CASE WHEN coalesce(updated_member.avatar,'')='' THEN 'Not set' ELSE 'Photo set' END);
    END IF;
    PERFORM ironvault_private.write_audit(tenant,auth.uid(),'Member '||label||' changed',
     ironvault_private.audit_member_label(m.id,tenant)||' · '||CASE WHEN field='avatar' THEN 'Profile photo updated (image data excluded)' ELSE initcap(label)||': '||coalesce(before_value#>>'{}','Not set')||' → '||coalesce(after_value#>>'{}','Not set') END,
     jsonb_build_object('member',ironvault_private.audit_member(m.id,tenant),'operation_id',operation,'changes',jsonb_build_object(field,jsonb_build_object('before',before_value,'after',after_value))));
   END IF;
  END LOOP;
 END LOOP;
END $fn$;


CREATE OR REPLACE FUNCTION public.iv_queue_contact_change(p_actor uuid,p_user uuid,p_hash text,p_kind text,p_group uuid,p_new_email text,p_base_email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE target ironvault_private.branch_accounts%ROWTYPE; context jsonb; first_request boolean;
BEGIN
 SELECT * INTO STRICT target FROM ironvault_private.branch_accounts WHERE user_id=p_user FOR UPDATE;
 IF p_base_email IS DISTINCT FROM target.contact_email THEN RAISE EXCEPTION 'Contact changed; reload before requesting another change'; END IF;
 IF p_kind NOT IN ('change_old','change_new','correct_unverified') THEN RAISE EXCEPTION 'Invalid contact action'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=p_actor AND r.enabled AND r.disabled_at IS NULL AND
  ((r.user_id=p_user AND r.tenant_id=target.tenant_id AND r.role=target.role)
  OR (r.role='super_admin' AND r.tenant_id IS NULL)
  OR (r.role='owner' AND r.tenant_id=target.tenant_id AND target.role IN ('staff','member') AND EXISTS(SELECT 1 FROM public.owners WHERE id=target.tenant_id AND status='ACTIVE')))) THEN RAISE EXCEPTION 'Contact authority denied'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_group::text,7));
 SELECT audit_context INTO context FROM ironvault_private.email_actions WHERE group_id=p_group AND user_id=p_user LIMIT 1;
 first_request:=NOT FOUND;
 IF EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=p_group AND (user_id<>p_user OR new_email IS DISTINCT FROM p_new_email OR base_email IS DISTINCT FROM target.contact_email)) THEN RAISE EXCEPTION 'Contact group mismatch'; END IF;
 IF NOT first_request AND (context->>'requested_by' IS DISTINCT FROM p_actor::text OR EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=p_group AND (user_id<>p_user OR new_email IS DISTINCT FROM p_new_email OR base_email IS DISTINCT FROM target.contact_email))) THEN RAISE EXCEPTION 'Contact group mismatch'; END IF;
 context:=coalesce(context,jsonb_build_object('requested_by',p_actor,'actor',ironvault_private.audit_actor(p_actor,target.tenant_id),'requested_at',clock_timestamp()));
 PERFORM public.iv_queue_email_action(p_user,p_hash,p_kind,p_group,p_new_email);
 UPDATE ironvault_private.email_actions SET audit_context=context WHERE token_hash=p_hash AND user_id=p_user;
 IF first_request THEN
  PERFORM ironvault_private.write_audit(target.tenant_id,p_actor,CASE target.role WHEN 'member' THEN 'Member email change requested' WHEN 'staff' THEN 'Staff email change requested' ELSE 'Gym owner email change requested' END,
   coalesce(ironvault_private.audit_account(p_user,target.tenant_id)->>'name','Account')||' · Requested email: '||target.contact_email||' → '||p_new_email||' · Awaiting recipient confirmation',
   jsonb_build_object('target',ironvault_private.audit_account(p_user,target.tenant_id),'email_group',p_group,'phase','requested','changes',jsonb_build_object('email',jsonb_build_object('before',target.contact_email,'after',p_new_email))),context->'actor');
 END IF;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_confirm_email_action(p_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE action ironvault_private.email_actions%ROWTYPE; account ironvault_private.branch_accounts%ROWTYPE; requested_by uuid; snapshot jsonb; target jsonb;
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
 IF action.kind<>'verify' THEN
  requested_by:=nullif(action.audit_context->>'requested_by','')::uuid;snapshot:=action.audit_context->'actor';
  target:=ironvault_private.audit_account(account.user_id,account.tenant_id);
  PERFORM ironvault_private.write_audit(account.tenant_id,requested_by,
   CASE account.role WHEN 'member' THEN 'Member email changed' WHEN 'staff' THEN 'Staff email changed' ELSE 'Gym owner email changed' END,
   coalesce(target->>'name','Account')||coalesce(' ('||(target->>'display_code')||')','')||' · Email: '||account.contact_email||' → '||action.new_email||' · Completed using recipient email proof',
   jsonb_build_object('target',target,'email_group',action.group_id,'confirmation','recipient email proof','changes',jsonb_build_object('email',jsonb_build_object('before',account.contact_email,'after',action.new_email))),
   coalesce(snapshot,jsonb_build_object('id',requested_by,'name','Requester unavailable (older request)','role','unknown')));
 END IF;
 RETURN true;
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_correct_unverified_staff_contact(p_actor uuid,p_user uuid,p_email text)
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
 IF target.contact_email=p_email THEN RETURN; END IF;
 UPDATE ironvault_private.branch_accounts SET contact_email=p_email WHERE user_id=p_user;
 DELETE FROM ironvault_private.email_actions WHERE user_id=p_user;
 UPDATE public.owners SET staff=coalesce((SELECT jsonb_agg(CASE WHEN s.value->>'auth_user_id'=p_user::text THEN s.value||jsonb_build_object('email',p_email) ELSE s.value END)
  FROM jsonb_array_elements(coalesce(staff,'[]'::jsonb)) s),'[]'::jsonb) WHERE id=target.tenant_id;
 PERFORM ironvault_private.write_audit(target.tenant_id,p_actor,'Staff email corrected',coalesce(ironvault_private.audit_account(p_user,target.tenant_id)->>'name','Staff')||' · Email: '||target.contact_email||' → '||p_email||' · Contact remains unverified',jsonb_build_object('target',ironvault_private.audit_account(p_user,target.tenant_id),'verified',false,'changes',jsonb_build_object('email',jsonb_build_object('before',target.contact_email,'after',p_email))));
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_update_staff_name(p_tenant text,p_user uuid,p_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE before_name text;
BEGIN
 IF NOT public.iv_can_access(p_tenant,ARRAY['owner']::text[]) OR length(p_name) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'Not authorized or invalid name'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=p_user AND tenant_id=p_tenant AND role='staff' AND enabled) THEN RAISE EXCEPTION 'Staff not found'; END IF;
 PERFORM 1 FROM public.owners WHERE id=p_tenant FOR UPDATE;
 SELECT s.value->>'name' INTO before_name FROM public.owners g CROSS JOIN LATERAL jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s WHERE g.id=p_tenant AND s.value->>'auth_user_id'=p_user::text;
 IF before_name IS NOT DISTINCT FROM p_name THEN RETURN; END IF;
 UPDATE public.owners SET staff=coalesce((SELECT jsonb_agg(CASE WHEN x.value->>'auth_user_id'=p_user::text THEN x.value||jsonb_build_object('name',p_name) ELSE x.value END)
  FROM jsonb_array_elements(staff) x),'[]'::jsonb) WHERE id=p_tenant;
 PERFORM ironvault_private.write_audit(p_tenant,auth.uid(),'Staff name changed',coalesce(before_name,'Not set')||' → '||p_name,jsonb_build_object('target',ironvault_private.audit_account(p_user,p_tenant),'changes',jsonb_build_object('name',jsonb_build_object('before',before_name,'after',p_name))));
END $fn$;

DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['ironvault_private.audit_actor(uuid,text)','ironvault_private.audit_member(text,text)',
 'ironvault_private.audit_member_label(text,text)','ironvault_private.audit_account(uuid,text)',
 'ironvault_private.write_audit(text,uuid,text,text,jsonb,jsonb)','ironvault_private.audit_financial_receipt()',
 'ironvault_private.audit_admission()','public.iv_queue_contact_change(uuid,uuid,text,text,uuid,text,text)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_queue_contact_change(uuid,uuid,text,text,uuid,text,text) TO service_role;
-- Replaced application functions retain their existing owner/ACL and authorization checks.
NOTIFY pgrst,'reload schema';
COMMIT;
