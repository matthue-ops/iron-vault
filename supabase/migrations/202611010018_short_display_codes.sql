-- MANUAL ONLY after 017. Adds display codes; never changes internal IDs or links.
BEGIN;
CREATE SEQUENCE ironvault_private.gym_display_sequence;
CREATE SEQUENCE ironvault_private.member_display_sequence;
REVOKE ALL ON SEQUENCE ironvault_private.gym_display_sequence,ironvault_private.member_display_sequence FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.display_code(p_prefix text,p_number bigint)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $fn$
 SELECT p_prefix||'-'||lpad(p_number::text,greatest(4,length(p_number::text)),'0');
$fn$;
REVOKE ALL ON FUNCTION ironvault_private.display_code(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.owners ADD COLUMN display_code text;
ALTER TABLE public.members ADD COLUMN display_code text;
UPDATE public.owners SET display_code=ironvault_private.display_code('GYM',nextval('ironvault_private.gym_display_sequence'));
UPDATE public.members SET display_code=ironvault_private.display_code('MEM',nextval('ironvault_private.member_display_sequence'));
ALTER TABLE public.owners ALTER COLUMN display_code SET DEFAULT ironvault_private.display_code('GYM',nextval('ironvault_private.gym_display_sequence'));
ALTER TABLE public.members ALTER COLUMN display_code SET DEFAULT ironvault_private.display_code('MEM',nextval('ironvault_private.member_display_sequence'));
ALTER TABLE public.owners ALTER COLUMN display_code SET NOT NULL;
ALTER TABLE public.members ALTER COLUMN display_code SET NOT NULL;
ALTER TABLE public.owners ADD CONSTRAINT iv_gym_display_code_unique UNIQUE(display_code);
ALTER TABLE public.members ADD CONSTRAINT iv_member_display_code_unique UNIQUE(display_code);
CREATE OR REPLACE VIEW public.iv_gyms WITH(security_barrier=true) AS
 SELECT visible.*,g.display_code FROM public.iv_visible_gyms() visible JOIN public.owners g ON g.id=visible.id;
CREATE OR REPLACE VIEW public.iv_members WITH(security_barrier=true) AS
 SELECT m.id,m.tenant_id,m.tenant_token,m.name,m.email,m.phone,NULL::text AS password,
 m.classification,m.discount_percentage,m.plan,m.card_barcode,m.wallet_balance,
 CASE WHEN ironvault_private.can_read_financial_reports(m.tenant_id) OR EXISTS(
  SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=m.id AND r.tenant_id=m.tenant_id)
 THEN m.amount ELSE NULL END AS amount,
 m.scans_used,m.last_scanned_date,m.expiration_date,m.status,m.date_joined,m.avatar,m.created_at,m.display_code
 FROM public.members m WHERE ironvault_private.can_read_member(m.id,m.tenant_id);
NOTIFY pgrst,'reload schema';
COMMIT;
