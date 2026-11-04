-- MANUAL ONLY after 029. Drafts are private; published versions are immutable.
BEGIN;
CREATE TABLE IF NOT EXISTS ironvault_private.legal_settings (
 scope text PRIMARY KEY, tenant_id text UNIQUE REFERENCES public.owners(id) ON DELETE CASCADE,
 draft jsonb NOT NULL DEFAULT '{}'::jsonb, current_version uuid,
 CHECK((scope='platform' AND tenant_id IS NULL) OR scope=tenant_id)
);
CREATE TABLE IF NOT EXISTS ironvault_private.legal_versions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), scope text NOT NULL REFERENCES ironvault_private.legal_settings(scope) ON DELETE CASCADE,
 data jsonb NOT NULL, terms_text text NOT NULL, privacy_text text NOT NULL,
 published_at timestamptz NOT NULL DEFAULT now(), published_by uuid NOT NULL
);
CREATE TABLE IF NOT EXISTS ironvault_private.legal_acceptances (
 request_id uuid PRIMARY KEY, tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 member_id text NOT NULL, user_id uuid NOT NULL, platform_version uuid NOT NULL, gym_version uuid NOT NULL,
 accepted_at timestamptz NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ironvault_private.legal_settings OWNER TO postgres;
ALTER TABLE ironvault_private.legal_versions OWNER TO postgres;
ALTER TABLE ironvault_private.legal_acceptances OWNER TO postgres;
REVOKE ALL ON ironvault_private.legal_settings,ironvault_private.legal_versions,ironvault_private.legal_acceptances FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE ironvault_private.legal_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.legal_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ironvault_private.legal_acceptances ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION ironvault_private.can_manage_legal(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL
 AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (p_tenant IS NOT NULL AND r.role='owner' AND r.tenant_id=p_tenant
 AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'))));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_legal_manage(p_action text,p_tenant text DEFAULT NULL,p_data jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE scope_key text:=coalesce(p_tenant,'platform'); setting ironvault_private.legal_settings%ROWTYPE;
 clean jsonb:='{}'; document_data jsonb; key text; value text; version_id uuid; terms text; privacy text; entry record;
BEGIN
 IF NOT ironvault_private.can_manage_legal(p_tenant) THEN RAISE EXCEPTION 'Legal settings access denied' USING ERRCODE='42501'; END IF;
 IF p_action NOT IN ('get','save','preview','publish') THEN RAISE EXCEPTION 'Invalid legal action'; END IF;
 IF p_tenant IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF p_action<>'get' THEN
  IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>50000 THEN RAISE EXCEPTION 'Invalid legal details'; END IF;
  FOREACH key IN ARRAY ARRAY['name','address','public_email','phone','privacy_email','retention','providers','membership_policy','refund_policy','age_policy','terms_extra','privacy_extra'] LOOP
   value:=btrim(coalesce(p_data->>key,''));
   IF length(value)>8000 OR (key IN ('name','public_email','privacy_email','phone') AND length(value)>254) THEN RAISE EXCEPTION 'Legal field too long'; END IF;
   clean:=clean||jsonb_build_object(key,value);
  END LOOP;
  IF p_action<>'preview' THEN
  INSERT INTO ironvault_private.legal_settings(scope,tenant_id,draft) VALUES(scope_key,p_tenant,clean)
  ON CONFLICT(scope) DO UPDATE SET draft=excluded.draft;
  END IF;
 END IF;
 SELECT * INTO setting FROM ironvault_private.legal_settings WHERE scope=scope_key FOR UPDATE;
 document_data:=setting.draft;
 IF p_action='preview' THEN document_data:=clean; END IF;
 IF p_action IN ('publish','preview') THEN
 IF p_action='publish' THEN
  FOREACH key IN ARRAY ARRAY['name','address','public_email','privacy_email','retention'] LOOP
   IF coalesce(document_data->>key,'')='' THEN RAISE EXCEPTION 'Complete business name, address, public email, privacy email and retention details before publishing'; END IF;
  END LOOP;
  FOREACH key IN ARRAY ARRAY['public_email','privacy_email'] LOOP
   IF (document_data->>key) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Enter valid public and privacy email addresses'; END IF;
  END LOOP;
  IF p_tenant IS NULL AND coalesce(document_data->>'providers','')='' THEN RAISE EXCEPTION 'List current infrastructure providers and processing locations'; END IF;
  END IF;
  terms:=format('%s — Terms of Service

Business/operator: %s
Address: %s
Contact: %s%s

',CASE WHEN p_tenant IS NULL THEN 'Iron Vault Platform' ELSE document_data->>'name' END,document_data->>'name',document_data->>'address',document_data->>'public_email',CASE WHEN document_data->>'phone'<>'' THEN ' / '||(document_data->>'phone') ELSE '' END);
  privacy:=format('%s — Privacy Notice

Business/operator: %s
Address: %s
Privacy contact: %s

',CASE WHEN p_tenant IS NULL THEN 'Iron Vault Platform' ELSE document_data->>'name' END,document_data->>'name',document_data->>'address',document_data->>'privacy_email');
  IF p_tenant IS NULL THEN
   terms:=terms||$text$Iron Vault provides the software used by participating gyms. Your gym provides its facilities, memberships, staff and training services and is responsible for its prices and payment handling. Both the gym’s published terms and these platform terms apply to use of the member portal.

Keep account credentials and QR passes private. Do not impersonate others, share or alter passes, bypass access controls, disrupt the service, or access another person’s or gym’s information. Report suspected unauthorized access promptly.

The service may be unavailable during maintenance, connectivity problems or interruptions. Your gym may use manual procedures. Report incorrect records to the gym for investigation. Account closure does not automatically erase records that must lawfully be retained.

The gym may restrict access for expiry, security concerns or misuse, subject to its lawful rules. Registration alone does not guarantee entry. Nothing in these terms removes mandatory consumer rights or excludes liability that cannot lawfully be excluded. Philippine law applies, subject to mandatory protections. Raise gym-service concerns with the gym and software-service concerns using the operator contact above.

Published document versions are preserved. Material changes must be communicated through an actual service notification and further acceptance sought where legally required. This signup agreement does not authorize optional marketing.$text$;
   privacy:=privacy||$text$Iron Vault’s legal operator provides software processing services to gyms under their instructions, ordinarily acting as Personal Information Processor for gym-member operations. The gym ordinarily acts as Personal Information Controller. Any independent operator processing must be specifically explained below and reflect the actual contracts and practices.

The service processes registration/contact details, assigned member IDs, authentication and recovery records, optional profile photos, membership/classification and discount information, account-credit and transaction records, attendance and QR-pass records, and support/security records. Do not submit medical records or identification documents unless an appropriate collection process and lawful basis have been explained.

Processing supports accounts, memberships, entry, balances, service notices, reports, error investigation, security and legal obligations. Depending on the activity, the lawful basis may be contract performance, legal obligation, appropriately assessed legitimate interests, or specific consent. Sensitive information requires a valid basis under Philippine law. Acknowledging this notice is not blanket consent or promotional consent.

Access is limited to authorized gym personnel, authorized platform support/security administrators, contracted providers, and lawful recipients. Provider and overseas-processing information is listed below. Appropriate contractual, organizational and technical safeguards must match actual operations. Authentication and role-based controls are used; no system guarantees absolute security.

Retention and deletion criteria are listed below. Deactivation is not immediate erasure. Backups and independently held exports follow their own disclosed disposal cycles. Contact the gym for membership-data requests and the operator for platform-processing concerns.

Subject to Philippine law and applicable exceptions, rights include information, access, correction, objection, erasure/blocking, portability where applicable, and withdrawal of consent where consent is the basis. Identity verification may be required and lawful retention may limit a request. Complaints may be raised with the Philippine National Privacy Commission at privacy.gov.ph. Material notice changes should be communicated through the service’s actual notification process.$text$;
  ELSE
   terms:=terms||$text$Registration requires accurate information. Gym approval, payment and an active membership may be required for entry. Keep contact details updated and protect your account and personal QR pass.

Membership prices, discounts, opening hours and admission rules are set by the gym and must be disclosed before purchase. A day pass is valid only on its assigned date. A weekly pass covers seven consecutive calendar days including the start date. The portal’s monthly pass covers 30 consecutive calendar days including its start date. Missed visits do not pause validity. Access expires at midnight immediately after the final valid date, in Asia/Manila time. QR passes are personal and daily entry restrictions apply. An electronic check-in does not override lawful safety rules.

Payments and top-ups follow the gym’s authorized process. Review amounts and pass details before confirming purchases. Account credits are amounts recorded for use with this gym, not interest-bearing bank deposits. The gym must disclose applicable refund, withdrawal, transfer and expiry rules before accepting funds. Contact the gym about disputed balances, entries or purchases.

Cancellation and refunds follow the gym’s disclosed policy and Philippine consumer law. Where no policy is listed below, ask the gym before purchasing; omission does not remove statutory rights. Account closure does not automatically erase legally retained records.

The gym is responsible for facilities, staff, memberships and payment handling; Iron Vault provides the software. Contact the gym first about membership disputes. Philippine law applies without limiting mandatory consumer protections.$text$;
   privacy:=privacy||$text$This gym determines the purposes and means of its membership operations and ordinarily acts as Personal Information Controller. Iron Vault processes information under the gym’s instructions to operate the software. Roles must match the parties’ actual written agreement and operations.

Information used may include your name, email, phone, member ID, account/security records, optional profile photo, membership and discount classification, payments and account credits, attendance, QR passes, and support correspondence. Required fields enable the stated membership process. Optional information may be omitted without affecting unrelated services.

Purposes include member administration, authentication/recovery, membership and credit management, entry validation, attendance, service announcements, reporting, dispute resolution, security and lawful recordkeeping. Lawful bases depend on the activity and may include contract performance, legal obligations, properly assessed legitimate interests or specific consent. Sensitive information needs an applicable legal basis. Optional marketing consent is separate.

Authorized gym owners/staff and necessary platform administrators/providers may access information for their responsibilities. The accompanying platform notice identifies infrastructure providers and international processing information. Information may also be disclosed where necessary and lawful. Retention criteria are provided below; closing an account does not automatically erase legal, accounting or dispute records. Backups and exports must follow applicable retention procedures.

Contact the privacy email above to exercise applicable rights to information, access, correction, objection, erasure/blocking, portability or consent withdrawal. Identity verification and legal exceptions may apply. You may complain to the Philippine National Privacy Commission through privacy.gov.ph. Minors and guardians should ask the gym about its age and authorization requirements before registration; any published age policy appears in the terms. Material notice changes should be communicated using the gym’s actual notification process.$text$;
  END IF;
  FOR entry IN SELECT * FROM jsonb_each_text(document_data) LOOP
   IF entry.value<>'' AND entry.key IN ('membership_policy','refund_policy','age_policy','terms_extra') THEN terms:=terms||E'\n\n'||replace(initcap(replace(entry.key,'_',' ')),'Extra','Additional Information')||E':\n'||entry.value; END IF;
   IF entry.value<>'' AND entry.key IN ('retention','providers','privacy_extra') THEN privacy:=privacy||E'\n\n'||replace(initcap(replace(entry.key,'_',' ')),'Extra','Additional Information')||E':\n'||entry.value; END IF;
  END LOOP;
  IF p_action='publish' THEN
  INSERT INTO ironvault_private.legal_versions(scope,data,terms_text,privacy_text,published_by)
   VALUES(scope_key,document_data,terms,privacy,auth.uid()) RETURNING id INTO version_id;
  UPDATE ironvault_private.legal_settings SET current_version=version_id WHERE scope=scope_key;
  END IF;
 END IF;
 RETURN jsonb_build_object('preview',CASE WHEN p_action='preview' THEN jsonb_build_object('terms_text',terms,'privacy_text',privacy) ELSE NULL END,'draft',coalesce(document_data,'{}'::jsonb),'current_version',coalesce(version_id,setting.current_version),
  'versions',coalesce((SELECT jsonb_agg(to_jsonb(v)-'published_by' ORDER BY published_at DESC) FROM ironvault_private.legal_versions v WHERE scope=scope_key),'[]'::jsonb));
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_legal_public(p_token text,p_platform uuid DEFAULT NULL,p_gym uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE tenant text; platform_id uuid; gym_id uuid;
BEGIN
 SELECT id INTO tenant FROM public.owners WHERE token=p_token AND status='ACTIVE';
 IF tenant IS NULL THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 SELECT current_version INTO platform_id FROM ironvault_private.legal_settings WHERE scope='platform';
 SELECT current_version INTO gym_id FROM ironvault_private.legal_settings WHERE scope=tenant;
 platform_id:=coalesce(p_platform,platform_id);gym_id:=coalesce(p_gym,gym_id);
 RETURN jsonb_build_object('platform',(SELECT to_jsonb(v)-'published_by' FROM ironvault_private.legal_versions v WHERE id=platform_id AND scope='platform'),
  'gym',(SELECT to_jsonb(v)-'published_by' FROM ironvault_private.legal_versions v WHERE id=gym_id AND scope=tenant));
END $fn$;
-- Freeze the accepted pair at request creation; an in-flight retry keeps its original published pair.
CREATE OR REPLACE FUNCTION ironvault_private.capture_legal_acceptance()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE platform_id uuid; gym_id uuid; member text;
BEGIN
 IF NEW.role<>'member' OR NEW.actor_id IS NOT NULL THEN RETURN NEW; END IF;
 IF TG_OP='INSERT' THEN
  PERFORM 1 FROM ironvault_private.legal_settings WHERE scope IN ('platform',NEW.tenant_id) ORDER BY scope FOR SHARE;
  SELECT current_version INTO platform_id FROM ironvault_private.legal_settings WHERE scope='platform';
  SELECT current_version INTO gym_id FROM ironvault_private.legal_settings WHERE scope=NEW.tenant_id;
  IF platform_id IS NULL OR gym_id IS NULL OR NEW.payload->'legal'->'accepted' IS DISTINCT FROM 'true'::jsonb
   OR NEW.payload->'legal'->>'platform_version' IS DISTINCT FROM platform_id::text
   OR NEW.payload->'legal'->>'gym_version' IS DISTINCT FROM gym_id::text THEN
   RAISE EXCEPTION 'Read and accept the currently published Terms and Privacy Notice' USING ERRCODE='IV001';
  END IF;
 ELSE
  IF NEW.payload IS DISTINCT FROM OLD.payload THEN RAISE EXCEPTION 'Provision payload is immutable'; END IF;
  IF OLD.completed_user IS NULL AND NEW.completed_user IS NOT NULL THEN
   platform_id:=(NEW.payload->'legal'->>'platform_version')::uuid;gym_id:=(NEW.payload->'legal'->>'gym_version')::uuid;
   IF NEW.payload->'legal'->'accepted' IS DISTINCT FROM 'true'::jsonb
    OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_versions WHERE id=platform_id AND scope='platform')
    OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_versions WHERE id=gym_id AND scope=NEW.tenant_id) THEN
    RAISE EXCEPTION 'Legal acceptance is missing';
   END IF;
   SELECT member_id INTO STRICT member FROM public.iv_user_roles WHERE user_id=NEW.completed_user AND tenant_id=NEW.tenant_id AND role='member';
   INSERT INTO ironvault_private.legal_acceptances(request_id,tenant_id,member_id,user_id,platform_version,gym_version,accepted_at)
    VALUES(NEW.request_id,NEW.tenant_id,member,NEW.completed_user,platform_id,gym_id,NEW.created_at);
  END IF;
 END IF;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS iv_capture_legal_acceptance ON ironvault_private.provision_requests;
CREATE TRIGGER iv_capture_legal_acceptance BEFORE INSERT OR UPDATE ON ironvault_private.provision_requests
 FOR EACH ROW EXECUTE FUNCTION ironvault_private.capture_legal_acceptance();
-- Read receipts for authorized legal administrators; no member/contact email is exposed.
CREATE OR REPLACE FUNCTION public.iv_legal_receipts(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT ironvault_private.can_manage_legal(p_tenant) THEN RAISE EXCEPTION 'Legal settings access denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY accepted_at DESC) FROM ironvault_private.legal_acceptances a WHERE tenant_id=p_tenant),'[]'::jsonb);
END $fn$;
DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['ironvault_private.can_manage_legal(text)','ironvault_private.capture_legal_acceptance()',
 'public.iv_legal_manage(text,text,jsonb)','public.iv_legal_public(text,uuid,uuid)','public.iv_legal_receipts(text)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_legal_manage(text,text,jsonb),public.iv_legal_receipts(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iv_legal_public(text,uuid,uuid) TO anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
