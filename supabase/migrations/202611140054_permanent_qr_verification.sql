-- MANUAL ONLY: apply once after 053 and prerequisites, before deploying Stage 1.
-- Adds credentials and verification APIs. No payments, memberships or history are rewritten.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_gym_usage(text)') IS NULL OR to_regprocedure('ironvault_private.record_admission(text,text)') IS NULL
 OR to_regprocedure('ironvault_private.member_legal_current(text)') IS NULL THEN RAISE EXCEPTION 'Apply 053 and its prerequisites first'; END IF;
 IF to_regclass('ironvault_private.member_cards') IS NOT NULL THEN RAISE EXCEPTION '054 already installed; inspect rather than reapply'; END IF;
END $guard$;
CREATE TABLE ironvault_private.member_cards (
 token uuid PRIMARY KEY DEFAULT gen_random_uuid(), member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz
);
CREATE UNIQUE INDEX iv_one_active_member_card ON ironvault_private.member_cards(member_id) WHERE revoked_at IS NULL;
ALTER TABLE ironvault_private.member_cards ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.member_cards FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.create_member_card_054()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 INSERT INTO ironvault_private.member_cards(member_id,tenant_id) VALUES(NEW.id,NEW.tenant_id);
 RETURN NEW;
END $fn$;
CREATE TRIGGER iv_create_member_card_054 AFTER INSERT ON public.members FOR EACH ROW EXECUTE FUNCTION ironvault_private.create_member_card_054();
INSERT INTO ironvault_private.member_cards(member_id,tenant_id) SELECT id,tenant_id FROM public.members;

-- QR scanning keeps existing active owner/staff access; it does not grant manual-checkin or financial permissions.
CREATE FUNCTION ironvault_private.qr_staff_require_054(p_tenant text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles r JOIN public.owners g ON g.id=r.tenant_id
 LEFT JOIN ironvault_private.staff_access a ON a.tenant_id=r.tenant_id AND a.user_id=r.user_id
 WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.role IN ('owner','staff') AND r.enabled AND r.disabled_at IS NULL
 AND g.status='ACTIVE' AND (r.role='owner' OR coalesce(a.state,'active')='active')) THEN
 RAISE EXCEPTION 'Gym staff access required' USING ERRCODE='42501'; END IF;
 PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 PERFORM ironvault_private.subscription_require(p_tenant,'portal');
END $fn$;
CREATE FUNCTION public.iv_member_card(p_member text,p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE card ironvault_private.member_cards%ROWTYPE;
BEGIN
 IF NOT ironvault_private.is_own_membership(p_member,p_tenant) THEN PERFORM ironvault_private.qr_staff_require_054(p_tenant); END IF;
 SELECT c.* INTO card FROM ironvault_private.member_cards c JOIN public.members m ON m.id=c.member_id AND m.tenant_id=c.tenant_id
 WHERE c.member_id=p_member AND c.tenant_id=p_tenant AND c.revoked_at IS NULL AND m.status IN ('ACTIVE','PENDING');
 IF NOT FOUND THEN RAISE EXCEPTION 'Member card unavailable'; END IF;
 RETURN jsonb_build_object('payload','IVC1|'||card.token::text);
END $fn$;

-- Read-only, scoped preflight. Never records attendance, uses a ticket, or changes a wallet.
CREATE FUNCTION public.iv_verify_entry_qr(p_payload text,p_tenant text,p_lookup boolean DEFAULT false)
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
 WHEN m.plan IS NULL OR m.plan NOT IN ('1-Day Pass','1-Week Pass','1-Month Unlimited') THEN 'NO_ACTIVE_PASS'
 WHEN NOT ironvault_private.valid_entitlement(m.id) THEN 'EXPIRED_PASS'
 WHEN NOT ironvault_private.member_legal_current(m.id) THEN 'AGREEMENT_REQUIRED'
 ELSE 'READY' END;
 RETURN jsonb_build_object('valid',true,'eligible',reason='READY','reason',reason,'entered_at',entered,
 'member',jsonb_build_object('id',m.id,'name',m.name,'display_code',m.display_code,'avatar',m.avatar,'plan',m.plan,'expiration_date',m.expiration_date,'status',m.status));
END $fn$;

CREATE FUNCTION public.iv_approve_entry_qr(p_payload text,p_tenant text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE member_key text;token_id uuid;result jsonb;admitted timestamptz;
BEGIN
 PERFORM ironvault_private.qr_staff_require_054(p_tenant);
 IF p_payload IS NULL OR p_payload !~* '^(IV1|IVC1)\|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RAISE EXCEPTION 'Invalid QR'; END IF;
 token_id:=split_part(p_payload,'|',2)::uuid;
 IF split_part(p_payload,'|',1)='IVC1' THEN SELECT member_id INTO member_key FROM ironvault_private.member_cards WHERE token=token_id AND tenant_id=p_tenant;
 ELSE SELECT member_id INTO member_key FROM ironvault_private.daily_passes WHERE token=token_id AND tenant_id=p_tenant; END IF;
 -- Same member-first lock order as daily issuance and manual admission.
 PERFORM 1 FROM public.members WHERE id=member_key AND tenant_id=p_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invalid QR for this gym'; END IF;
 IF split_part(p_payload,'|',1)='IVC1' THEN PERFORM 1 FROM ironvault_private.member_cards WHERE token=token_id AND tenant_id=p_tenant AND revoked_at IS NULL FOR SHARE;
 ELSE PERFORM 1 FROM ironvault_private.daily_passes WHERE token=token_id AND tenant_id=p_tenant AND used_at IS NULL AND expires_at>now() AND business_day=(now() AT TIME ZONE 'Asia/Manila')::date FOR UPDATE; END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'QR no longer valid; scan again'; END IF;
 result:=public.iv_verify_entry_qr(p_payload,p_tenant,false);
 IF NOT coalesce((result->>'eligible')::boolean,false) THEN RAISE EXCEPTION 'Entry not approved: %',result->>'reason'; END IF;
 PERFORM ironvault_private.require_current_member_legal(member_key);
 admitted:=ironvault_private.record_admission(member_key,'qr');
 -- Consume any issued daily ticket too: card, generated QR and manual entry share one allowance.
 UPDATE ironvault_private.daily_passes SET used_at=admitted WHERE member_id=member_key AND tenant_id=p_tenant AND business_day=(now() AT TIME ZONE 'Asia/Manila')::date AND used_at IS NULL;
 RETURN jsonb_build_object('member_id',member_key,'admitted_at',admitted);
END $fn$;
-- Old browser tabs must not silently bypass the new verification flow.
CREATE OR REPLACE FUNCTION public.iv_redeem_member_pass(p_token uuid,p_tenant text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN RAISE EXCEPTION 'Refresh the reception app to verify and approve entry'; END $fn$;
DO $acl$ DECLARE signature text; BEGIN
 FOREACH signature IN ARRAY ARRAY['ironvault_private.create_member_card_054()','ironvault_private.qr_staff_require_054(text)',
 'public.iv_member_card(text,text)','public.iv_verify_entry_qr(text,text,boolean)','public.iv_approve_entry_qr(text,text)'] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_member_card(text,text),public.iv_verify_entry_qr(text,text,boolean),public.iv_approve_entry_qr(text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
