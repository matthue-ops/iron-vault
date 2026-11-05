-- MANUAL ONLY after 034. Existing gyms become setup-only; no clocks start until explicit activation.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_queue_contact_change(uuid,uuid,text,text,uuid,text,text)') IS NULL OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='iv_admin_contact_required' AND conrelid='ironvault_private.branch_accounts'::regclass) THEN RAISE EXCEPTION 'Apply migrations 033 and 034 first'; END IF;
 IF to_regclass('ironvault_private.service_settings') IS NOT NULL THEN RAISE EXCEPTION 'Subscription installation already exists; do not reapply'; END IF;
END $guard$;
CREATE TABLE ironvault_private.service_settings(id boolean PRIMARY KEY DEFAULT true CHECK(id),draft jsonb NOT NULL,updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE ironvault_private.service_versions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),data jsonb NOT NULL,terms_text text NOT NULL,privacy_text text NOT NULL,dpa_text text NOT NULL,effective_date date NOT NULL,published_at timestamptz NOT NULL DEFAULT now(),published_by uuid NOT NULL);
CREATE TABLE ironvault_private.gym_subscriptions(tenant_id text PRIMARY KEY REFERENCES public.owners(id) ON DELETE CASCADE,owner_id uuid REFERENCES auth.users(id),pilot_used boolean NOT NULL DEFAULT false,next_plan text CHECK(next_plan IN ('dashboard','portal')),created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE ironvault_private.service_acceptances(tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,owner_id uuid NOT NULL,version_id uuid NOT NULL REFERENCES ironvault_private.service_versions(id),gym_snapshot jsonb NOT NULL,owner_snapshot jsonb NOT NULL,accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),PRIMARY KEY(tenant_id,owner_id,version_id));
CREATE TABLE ironvault_private.subscription_requests(id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,owner_id uuid NOT NULL,kind text NOT NULL CHECK(kind IN ('payment','upgrade','downgrade')),quote jsonb NOT NULL,confirmed_at timestamptz NOT NULL DEFAULT clock_timestamp(),approved_at timestamptz,approved_by uuid);
CREATE TABLE ironvault_private.subscription_periods(id uuid PRIMARY KEY,tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,kind text NOT NULL CHECK(kind IN ('pilot','paid')),plan text NOT NULL CHECK(plan IN ('dashboard','portal')),access_from date NOT NULL,start_date date NOT NULL,end_date date NOT NULL,grace_days integer NOT NULL CHECK(grace_days BETWEEN 0 AND 30),version_id uuid NOT NULL REFERENCES ironvault_private.service_versions(id),policy jsonb NOT NULL,amount numeric(12,2) NOT NULL CHECK(amount>=0),reference text,approved_by uuid NOT NULL,approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),CHECK(end_date>=start_date),CHECK(access_from<=start_date));
CREATE UNIQUE INDEX iv_one_pilot_per_gym ON ironvault_private.subscription_periods(tenant_id) WHERE kind='pilot';
CREATE TABLE ironvault_private.subscription_events(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,actor_id uuid NOT NULL,action text NOT NULL,data jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE ironvault_private.owner_notifications(tenant_id text NOT NULL REFERENCES ironvault_private.gym_subscriptions(tenant_id) ON DELETE CASCADE,owner_id uuid NOT NULL,notice_key text NOT NULL,title text NOT NULL,message text NOT NULL,available_at timestamptz NOT NULL,read_at timestamptz,PRIMARY KEY(tenant_id,notice_key));
CREATE UNIQUE INDEX iv_subscription_payment_reference_unique ON ironvault_private.subscription_events(tenant_id,lower(btrim(data->>'reference'))) WHERE action='approve_payment' AND nullif(btrim(data->>'reference'),'') IS NOT NULL;
CREATE INDEX iv_owner_notifications_due ON ironvault_private.owner_notifications(owner_id,available_at DESC);
CREATE OR REPLACE FUNCTION ironvault_private.subscription_today()
RETURNS date LANGUAGE sql STABLE SET search_path='' AS $fn$ SELECT (now() AT TIME ZONE 'Asia/Manila')::date $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_super(p_actor uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=p_actor AND role='super_admin' AND tenant_id IS NULL AND enabled AND disabled_at IS NULL);
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_owner(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM ironvault_private.gym_subscriptions s JOIN public.iv_user_roles r ON r.user_id=s.owner_id AND r.tenant_id=s.tenant_id WHERE s.tenant_id=p_tenant AND s.owner_id=auth.uid() AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL);
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.service_current()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT id FROM ironvault_private.service_versions WHERE effective_date<=ironvault_private.subscription_today() ORDER BY effective_date DESC,published_at DESC LIMIT 1;
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_state(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE t date:=ironvault_private.subscription_today();p ironvault_private.subscription_periods%ROWTYPE;g boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RETURN jsonb_build_object('status','inactive','operations',false,'portal',false,'read',false);END IF;
 SELECT * INTO p FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant AND access_from<=t ORDER BY access_from DESC,approved_at DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','setup','operations',false,'portal',false,'read',false); END IF;
 g:=p.kind='paid' AND t>p.end_date AND t<=p.end_date+p.grace_days;
 RETURN jsonb_build_object('status',CASE WHEN t<=p.end_date THEN p.kind WHEN g THEN 'grace' ELSE 'suspended' END,'operations',t<=p.end_date OR g,'portal',t<=p.end_date AND p.plan='portal','read',t<=p.end_date OR g OR t<=p.end_date+p.grace_days+coalesce((p.policy->>'export_days')::integer,30),'plan',p.plan,'kind',p.kind,'period_id',p.id,'start_date',p.start_date,'end_date',p.end_date,'grace_end',p.end_date+p.grace_days,'days_remaining',greatest(0,p.end_date-t+1),'retention_review_date',p.end_date+p.grace_days+coalesce((p.policy->>'retention_days')::integer,90));
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_require(p_tenant text,p_feature text,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF ironvault_private.subscription_super(p_actor) THEN RETURN; END IF;
 IF p_actor IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=p_actor AND tenant_id=p_tenant AND enabled AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Account access revoked' USING ERRCODE='42501'; END IF;
 IF p_feature NOT IN ('operations','portal','read') OR NOT coalesce((ironvault_private.subscription_state(p_tenant)->>p_feature)::boolean,false) THEN RAISE EXCEPTION 'Gym subscription does not currently include this service. Contact the registered gym owner.' USING ERRCODE='IV003'; END IF;
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_notice(p_tenant text,p_key text,p_title text,p_message text,p_date date DEFAULT ironvault_private.subscription_today())
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 INSERT INTO ironvault_private.owner_notifications(tenant_id,owner_id,notice_key,title,message,available_at)
 SELECT tenant_id,owner_id,p_key,p_title,p_message,p_date::timestamp AT TIME ZONE 'Asia/Manila' FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant AND owner_id IS NOT NULL ON CONFLICT DO NOTHING;
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_enrol()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.role='owner' THEN
  INSERT INTO ironvault_private.gym_subscriptions(tenant_id,owner_id) VALUES(NEW.tenant_id,NEW.user_id) ON CONFLICT DO NOTHING;
  PERFORM ironvault_private.subscription_notice(NEW.tenant_id,'setup','Complete your pilot setup','Publish your gym documents and accept the service agreement. Your pilot is awaiting Super Admin activation.');
  IF ironvault_private.service_current() IS NOT NULL THEN PERFORM ironvault_private.subscription_notice(NEW.tenant_id,'documents:'||ironvault_private.service_current(),'Review and accept service documents','Only the registered owner can accept the Iron Vault Service Agreement and DPA and acknowledge the Privacy Notice before pilot activation.'); END IF;
 END IF;RETURN NEW;
END $fn$;
CREATE TRIGGER iv_subscription_enrol AFTER INSERT ON ironvault_private.branch_accounts FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_enrol();
INSERT INTO ironvault_private.gym_subscriptions(tenant_id,owner_id) SELECT g.id,(SELECT a.user_id FROM ironvault_private.branch_accounts a WHERE a.tenant_id=g.id AND a.role='owner' LIMIT 1) FROM public.owners g;
DO $seed$ DECLARE s record; BEGIN FOR s IN SELECT tenant_id FROM ironvault_private.gym_subscriptions LOOP PERFORM ironvault_private.subscription_notice(s.tenant_id,'setup','Complete your pilot setup','Existing records are preserved. Complete setup and request pilot activation.'); END LOOP; END $seed$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_schedule(p_period uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE p ironvault_private.subscription_periods%ROWTYPE;n integer;
BEGIN
 SELECT * INTO STRICT p FROM ironvault_private.subscription_periods WHERE id=p_period;
 PERFORM ironvault_private.subscription_notice(p.tenant_id,p.id||':start',CASE WHEN p.kind='pilot' THEN 'Your free pilot has started' ELSE 'Your subscription has started' END,p.plan||' access. Counted period: '||p.start_date||' through '||p.end_date||' (Philippine time). Amount recorded: PHP '||p.amount,p.start_date);
 FOREACH n IN ARRAY ARRAY[7,3,1] LOOP
  PERFORM ironvault_private.subscription_notice(p.tenant_id,p.id||':reminder:'||n,CASE WHEN p.kind='pilot' THEN 'Free pilot nearing expiry' ELSE 'Subscription renewal reminder' END,'Period ends '||p.end_date||'. Renewal due '||(p.end_date+1)||'. Review Subscription & Billing.',p.end_date+1-n);
 END LOOP;
 PERFORM ironvault_private.subscription_notice(p.tenant_id,p.id||':expiry','Subscription period ended',CASE WHEN p.kind='paid' THEN 'Dashboard-only grace lasts through '||(p.end_date+p.grace_days)||'. Member portal access is unavailable.' ELSE 'Your free pilot has ended. Choose a paid plan to continue operations. There is no automatic pilot grace period.' END,p.end_date+1);
 PERFORM ironvault_private.subscription_notice(p.tenant_id,p.id||':suspend','Operational access suspended','Unpaid operational access has ended. Owner billing, eligible read-only reports and exports remain available.',p.end_date+p.grace_days+1);
 IF p.grace_days>0 THEN PERFORM ironvault_private.subscription_notice(p.tenant_id,p.id||':lastgrace','Last grace day','Operational access ends tomorrow unless renewal is approved.',p.end_date+p.grace_days); END IF;
 PERFORM ironvault_private.subscription_notice(p.tenant_id,p.id||':retention','Data retention review approaching','Your records may be due for retention review. Export your records or contact the privacy contact. No automatic deletion is performed by this installation.',p.end_date+p.grace_days+coalesce((p.policy->>'retention_days')::integer,90)-7);
END $fn$;

INSERT INTO ironvault_private.service_settings(id,draft) VALUES(true,$defaults${"provider_name": "Matt Hue", "brand": "Iron Vault", "address": "", "support_email": "ironvault@gmail.com", "billing_contact": "0992-634-8656", "privacy_contact": "Matt Hue / Iron Vault Privacy Contact", "privacy_email": "ironvault@gmail.com", "support_hours": "9 AM\u20135 PM, Philippine time", "dashboard_price": 999, "portal_price": 1800, "pilot_days": 14, "paid_days": 30, "grace_days": 7, "price_notice_days": 30, "export_days": 30, "retention_days": 90, "late_payment_policy": "During grace, renewal continues from the original due date. After suspension, access resumes on approval and counted days start the following day.", "upgrade_policy": "Upgrades charge the plan-price difference proportionally for remaining days and retain expiry. Downgrades take effect after the current paid period.", "refund_policy": "", "outage_policy": "", "billing_complaints": "", "backup_policy": "", "security_retention": "", "payment_retention": "Retain for applicable Philippine accounting and tax requirements.", "providers": "", "privacy_purposes": "Owner identity and contacts, account/security records, agreement acceptances, subscription/payment references, support and service communications; used to deliver, secure and administer the service.", "marketing_policy": "Do not sell personal information or use gym/member data for third-party advertising. Promotional emails require separate optional opt-in and unsubscribe. Service/security/billing notices are separate.", "sensitive_data_policy": "Standard registration does not request medical records, health information or government ID images.", "deletion_process": "", "breach_process": "Report suspected incidents promptly to the privacy contact. The parties assess and respond without undue delay, observing applicable NPC notification rules, including the 72-hour requirement where its conditions apply.", "liability_policy": "", "dispute_policy": "Philippine law applies. First attempt good-faith resolution through the support contact. Competent Philippine courts and authorities retain jurisdiction under applicable law. Complaints to the NPC are not restricted.", "contract_extra": "", "support_days": "", "tax_policy": "", "billing_instructions": "", "_terms_template": "# {{brand}} \u2014 Gym Subscription Service Agreement\n\n1. PARTIES AND AUTHORITY\n{{provider_name}}, operating {{brand}}, at {{address}} provides this software service. The accepting registered gym owner confirms authority to bind the identified gym. The gym identity and accepting owner are recorded with this version in its acceptance receipt. A brand is not represented as a separate legal entity merely by its use.\n\n2. ELECTRONIC ACCEPTANCE\nExplicit checkbox and acceptance-button actions record the gym, owner account, version and Philippine timestamp. Opening a notification is not agreement. Electronic records may have legal effect under the Civil Code and Electronic Commerce Act (RA 8792).\n\n3. SERVICE AND GYM RESPONSIBILITY\nSoftware supports member records, attendance, credits, purchases, staff and reports. The gym operates its business and is responsible for permits, personnel, pricing, member policies, safety and lawful handling of information. This is not medical advice or a guarantee of member conduct.\n\n4. PLANS AND PRICES\nDashboard Only: PHP {{dashboard_price}} total per gym for {{paid_days}} days. Dashboard + Member Portal: PHP {{portal_price}} total for the same period, not an additional fee. Dashboard includes staff-assisted registration, entry, transactions and reports. Member Portal adds member login, profiles, QR and supported self-service. One tenant is covered; additional tenants require their own subscriptions. Tax treatment: {{tax_policy}}. Configured prices are final quoted totals.\n\n5. ONBOARDING\nBefore operations, the registered owner must complete required gym details, publish the gym's member Terms and Privacy documents, and accept these service documents. Super Admin separately approves pilot activation. Publication does not certify the gym's compliance with all laws. Setup-only access remains available before approval.\n\n6. FREE PILOT\nOne {{pilot_days}}-day full-feature pilot per gym business, subject to Super Admin approval. Access opens immediately on approval; counted days start the following calendar day. All dates use Philippine time (UTC+8), ending at 11:59:59 PM on the final day. No automatic charge or automatic paid conversion. Extensions require a recorded reason. No paid grace period automatically follows the pilot.\n\n7. PAID PERIODS AND EARLY PAYMENT\nEach paid period lasts {{paid_days}} consecutive counted days. For a new activation outside an existing period, access begins on approval and counting starts the next day. Early payment during a pilot schedules the paid period for the day after the pilot's final day. Early renewal adds days after the existing paid-through date. Billing confirmation discloses the exact plan, amount and dates.\n\n8. PAYMENTS\nPay only through the instructions shown in billing. Payment is effective after verification and approval by Super Admin. Submission of a reference is not proof of approval. Required invoices/payment documentation must be provided under applicable rules. No automatic recurring debit is authorized by this agreement. Billing contact: {{billing_contact}}. Instructions: {{billing_instructions}}.\n\n9. OVERDUE ACCESS\nPaid subscriptions receive {{grace_days}} dashboard-only grace days after expiry. Portal access is unavailable during grace. Operational access is suspended afterward; the owner retains billing and eligible read-only/export access. Temporary restrictions do not automatically change the chosen plan or price. {{late_payment_policy}}\n\n10. PLAN CHANGES\n{{upgrade_policy}} Exact amounts and dates must be explicitly confirmed before approval. Existing records and credentials are retained when portal access changes. Existing member sessions lose protected access when entitlement ends.\n\n11. NOTIFICATIONS\nOnboarding, agreement, billing and subscription notices go only to the registered owner account. Staff cannot accept this agreement or approve charges. Keep owner credentials and contacts current. Service communications are separate from optional marketing. Scheduled notifications remain available when the owner next signs in.\n\n12. MEMBERS AND MANUAL SERVICE\nPortal signups accept member documents and may await gym approval. Staff-registered walk-ins may have no email and are pre-approved; they may later sign in by Member ID and password. Member approval, member legal acceptance and gym subscription entitlement are independent. Staff-assisted entry does not itself establish acceptance of app terms. Membership and balance rules remain applicable.\n\n13. LAWFUL COLLECTION\nThe gym must provide accurate notices, establish lawful bases, minimise collection and protect member/staff information under RA 10173 and applicable NPC rules. Physical presence and previous collection are not blanket consent. App agreement does not authorize unrelated marketing or sensitive-data collection.\n\n14. DATA ROLES AND PROCESSING\nThe gym generally controls member processing for its operations. The provider processes it on documented instructions and may separately control account, billing and security processing described in its Privacy Notice. Actual activities determine roles. The accompanying Data Processing Agreement applies to processor services.\n\n15. SECURITY AND INCIDENTS\nMaintain reasonable organisational, physical and technical safeguards, restrict staff access and report suspected misuse. {{breach_process}} The provider and gym retain their respective statutory obligations.\n\n16. SERVICE PROVIDERS\n{{providers}} Appropriate safeguards and accountability must accompany cross-border processing; location alone does not establish compliance. Material provider changes must be communicated through the disclosed process.\n\n17. TRANSACTIONS\nDisplayed balances record the gym's obligations; the provider does not hold member funds merely because a balance appears. The gym collects funds, reconciles records, authorizes changes and issues required documents. Reports do not replace accounting or tax obligations.\n\n18. ACCEPTABLE USE\nDo not access other gyms, falsify financial/attendance/audit records, upload unlawful information, share credentials to defeat accountability, bypass access restrictions or compromise service security. Proportionate protective restrictions may be applied.\n\n19. AVAILABILITY AND SUPPORT\nSupport: {{support_email}}; {{support_hours}}, {{support_days}}. Exercise reasonable care, but no unagreed uptime guarantee is given. Maintain an outage contingency. {{outage_policy}}\n\n20. CANCELLATION AND REFUNDS\n{{refund_policy}} {{billing_complaints}} Mandatory legal rights and remedies are not waived.\n\n21. SUSPENSION AND TERMINATION\nNonpayment follows the grace rules. Security threats, material misuse or legal requirements may require restrictions; provide notice and an opportunity to remedy where appropriate. Suspension does not automatically erase records. Termination and data handling remain subject to applicable law and the DPA.\n\n22. RETENTION AND EXPORT\nOwner export access lasts {{export_days}} days after final operational entitlement ends. Operational records are due for retention review within {{retention_days}} days after that endpoint, subject to lawful holds. {{deletion_process}} Backup handling: {{backup_policy}} Security history: {{security_retention}} Payment records: {{payment_retention}} Do not promise immediate removal from every backup.\n\n23. INTELLECTUAL PROPERTY\nProvider/licensor rights in software and branding remain theirs. The gym receives service-use rights during authorised access and retains rights in its own content. Use gym identity and records only as needed for the service and other expressly agreed lawful purposes. Individuals retain privacy rights.\n\n24. LIABILITY\n{{liability_policy}} Nothing waives future fraud, non-waivable remedies or statutory privacy duties.\n\n25. AGREEMENT AND PRICE CHANGES\nPublish immutable versions and notify the owner of material changes. Obtain renewed explicit acceptance where required; reading a notification is insufficient. Price changes require at least {{price_notice_days}} calendar days' notice stating old/new price, affected plan, effective date and options. Existing paid and approved future periods are protected. New prices apply to unapproved periods starting on/after the effective date. Owners may decline renewal without an extra cancellation penalty. No automatic payment authorization is implied.\n\n26. LAW, CONTACTS AND ADDITIONAL CONDITIONS\n{{dispute_policy}} Privacy: {{privacy_contact}}, {{privacy_email}}. Address: {{address}}. {{contract_extra}}\n", "_privacy_template": "# {{brand}} \u2014 Tenant Privacy Notice\n\n1. RESPONSIBLE PROVIDER\n{{provider_name}}, operating {{brand}}, {{address}}. Privacy contact: {{privacy_contact}}, {{privacy_email}}.\n\n2. SCOPE AND ROLES\nThis notice covers owner/staff account administration, billing, security, acceptance history, support and communications controlled by the provider. Member processing on the gym's instructions is separately described by the gym's notice and the DPA. Roles follow actual processing.\n\n3. DATA AND PURPOSES\n{{privacy_purposes}} Do not collect more than reasonably necessary.\n\n4. LAWFUL BASIS\nIdentify and document applicable bases under RA 10173 for the actual activity, such as contractual necessity, legal duties or properly assessed legitimate interests. Obtain specific consent where required. Agreement acceptance is not blanket privacy consent.\n\n5. RECIPIENTS AND LOCATIONS\n{{providers}} Disclose actual recipients, processing locations and appropriate cross-border safeguards. Do not invent a region or an email delivery provider.\n\n6. MARKETING\n{{marketing_policy}} Declining promotions does not block service. Owners cannot opt members into unrelated advertising on their behalf.\n\n7. SENSITIVE INFORMATION\n{{sensitive_data_policy}} New collection requires a specific assessment, lawful basis, safeguards and notice before use.\n\n8. RETENTION\nExport access: {{export_days}} days after final access. Operational records: retention review within {{retention_days}} days, with lawful exceptions. {{backup_policy}} Security/audit: {{security_retention}} Subscription/payment: {{payment_retention}}\n\n9. REQUESTS AND RIGHTS\nSubject to applicable law, individuals may seek information, access, correction, objection, erasure/blocking, portability and other available remedies. Contact {{privacy_email}}. {{deletion_process}} Verify identity proportionately and coordinate gym-controlled records with the gym. NPC complaint rights remain available.\n\n10. SECURITY AND INCIDENTS\nApply appropriate organisational, physical and technical controls. {{breach_process}} No system can promise absolute security.\n\n11. REQUIRED AND OPTIONAL INFORMATION\nExplain required account/billing fields and consequences of omission. Promotional consent is optional. A working owner contact is necessary for administration; walk-in members need no email for staff-assisted services.\n\n12. VERSIONS AND CONTACT\nPreserve published versions, announce material processing changes and obtain new consent where required. Support: {{support_email}}; privacy: {{privacy_email}}. This notice does not replace the provider's underlying legal obligations.\n", "_dpa_template": "# {{brand}} \u2014 Data Processing Agreement\n\n1. PARTIES AND SCOPE\n{{provider_name}}, operating {{brand}} (processor for the covered activities), and the accepting gym (controller) agree to the following processing of member/staff records for gym management. Separate provider-controlled billing/account processing is covered by its Privacy Notice.\n\n2. SUBJECT MATTER, DURATION AND INSTRUCTIONS\nProcess membership/contact records, attendance, credits, purchases, staff permissions and related service records solely to provide the agreed gym software on documented lawful instructions. Processing lasts for the service and defined retention/return periods. Notify the gym if an instruction appears unlawful; do not follow it merely because it is requested.\n\n3. CONTROLLER DUTIES\nThe gym establishes purposes and lawful bases, issues accurate notices, minimises collection, authorizes users, maintains accurate data, and responds to requests with processor assistance. Physical presence is not blanket consent.\n\n4. CONFIDENTIALITY AND ACCESS\nLimit access to authorised persons with confidentiality duties and need-to-know roles. Protect credentials and maintain accountable access controls. Do not sell or independently advertise using covered data.\n\n5. SECURITY\nMaintain appropriate organisational, physical and technical measures proportionate to risk, including access control, secure transmission, logging, recovery and review processes as actually provided. No unsupported certification or absolute-security claim is made.\n\n6. SUBPROCESSORS AND TRANSFERS\nCurrent providers/locations: {{providers}} Use appropriate contractual safeguards, maintain accountability, and notify the gym of material changes with a reasonable opportunity to raise data-protection concerns. Follow applicable Philippine transfer rules.\n\n7. DATA-SUBJECT REQUESTS\nHelp the gym locate, correct, export, restrict or delete covered data as appropriate. Refer gym-controlled requests to the gym without obstructing statutory rights. Contact: {{privacy_email}}.\n\n8. INCIDENTS\n{{breach_process}} Provide available details, containment and remediation assistance without undue delay. Each party assesses applicable NPC/data-subject notifications; no contract postpones a mandatory deadline.\n\n9. ASSURANCE AND COMPLIANCE\nProvide reasonable information about processing and safeguards and cooperate with proportionate lawful review requests, protecting other customers' data and confidential security information. Cooperate with competent authorities as required.\n\n10. RETURN, DELETION AND BACKUPS\nOwner export window: {{export_days}} days after final access. Operational retention review: {{retention_days}} days. {{deletion_process}} Backup cycle: {{backup_policy}} Security: {{security_retention}} Payment/legal records: {{payment_retention}} Document lawful exceptions and deletion/return actions.\n\n11. LIMITS OF INSTRUCTIONS\n{{sensitive_data_policy}} New sensitive-data uses require prior assessment and appropriate written instructions/safeguards. The processor does not acquire ownership of member personal information.\n\n12. CONFLICTS AND CONTACT\nMandatory RA 10173 and applicable NPC rules prevail over conflicting terms. The Service Agreement governs commercial matters without removing statutory processing duties. Privacy contact: {{privacy_contact}}, {{privacy_email}}, {{address}}. {{dispute_policy}}\n"}$defaults$::jsonb);
ALTER TABLE ironvault_private.owner_notifications ADD COLUMN superseded_at timestamptz;
CREATE OR REPLACE FUNCTION ironvault_private.service_render(p_data jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('terms_text',ironvault_private.fill_legal_tokens_v2(p_data->>'_terms_template',p_data),'privacy_text',ironvault_private.fill_legal_tokens_v2(p_data->>'_privacy_template',p_data),'dpa_text',ironvault_private.fill_legal_tokens_v2(p_data->>'_dpa_template',p_data));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_service_documents(p_action text,p_data jsonb DEFAULT NULL,p_effective date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s ironvault_private.service_settings%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;k text;clean jsonb:='{}';rendered jsonb;effective date:=coalesce(p_effective,ironvault_private.subscription_today());published_version_id uuid;
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Super Admin required' USING ERRCODE='42501'; END IF;
 SELECT * INTO STRICT s FROM ironvault_private.service_settings settings_row WHERE settings_row.id=true FOR UPDATE;
 IF p_action NOT IN ('get','save','preview','publish') THEN RAISE EXCEPTION 'Invalid service document action'; END IF;
 IF p_action<>'get' THEN
  IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>150000 THEN RAISE EXCEPTION 'Invalid service details'; END IF;
  FOR k IN SELECT jsonb_object_keys(s.draft) LOOP
   clean:=clean||jsonb_build_object(k,coalesce(p_data->k,s.draft->k));
   IF length(clean->>k)>50000 THEN RAISE EXCEPTION 'Field too long: %',k; END IF;
  END LOOP;
  IF (clean->>'dashboard_price')::numeric<=0 OR (clean->>'portal_price')::numeric<(clean->>'dashboard_price')::numeric OR (clean->>'portal_price')::numeric>1000000 OR (clean->>'dashboard_price')::numeric<>round((clean->>'dashboard_price')::numeric,2) OR (clean->>'portal_price')::numeric<>round((clean->>'portal_price')::numeric,2) THEN RAISE EXCEPTION 'Invalid plan prices'; END IF;
  FOREACH k IN ARRAY ARRAY['pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days'] LOOP
   IF (clean->>k)::integer<1 OR (clean->>k)::integer>3650 OR (clean->>k)::numeric<>(clean->>k)::integer THEN RAISE EXCEPTION 'Invalid day setting: %',k; END IF;
  END LOOP;
  IF (clean->>'grace_days')::integer>30 OR (clean->>'price_notice_days')::integer<30 OR (clean->>'export_days')::integer>(clean->>'retention_days')::integer THEN RAISE EXCEPTION 'Grace must be at most 30 days, price notice at least 30 days, export no longer than retention'; END IF;
  IF p_action IN ('save','publish') THEN UPDATE ironvault_private.service_settings SET draft=clean,updated_at=clock_timestamp() WHERE service_settings.id=true; END IF;
  rendered:=ironvault_private.service_render(clean);
 END IF;
 IF p_action='publish' THEN
  FOR k IN SELECT jsonb_object_keys(clean) LOOP IF k<>'contract_extra' AND btrim(coalesce(clean->>k,''))='' THEN RAISE EXCEPTION 'Complete field before publication: %',k; END IF; END LOOP;
  FOREACH k IN ARRAY ARRAY['support_email','privacy_email'] LOOP IF clean->>k !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid contact email'; END IF; END LOOP;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions) AND effective<ironvault_private.subscription_today()+30 THEN RAISE EXCEPTION 'New service terms require 30 days advance notice'; END IF;
  IF effective<ironvault_private.subscription_today() THEN RAISE EXCEPTION 'Cannot backdate publication'; END IF;
  SELECT * INTO v FROM ironvault_private.service_versions version_row WHERE version_row.id=ironvault_private.service_current();
  IF v.id IS NOT NULL AND (v.data->>'dashboard_price' IS DISTINCT FROM clean->>'dashboard_price' OR v.data->>'portal_price' IS DISTINCT FROM clean->>'portal_price') AND effective<ironvault_private.subscription_today()+greatest(30,(v.data->>'price_notice_days')::integer) THEN RAISE EXCEPTION 'Price changes require the published advance notice period'; END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE effective_date>=effective) THEN RAISE EXCEPTION 'A publication already exists on or after this date; choose a later effective date'; END IF;
  INSERT INTO ironvault_private.service_versions(data,terms_text,privacy_text,dpa_text,effective_date,published_by) VALUES(clean,rendered->>'terms_text',rendered->>'privacy_text',rendered->>'dpa_text',effective,auth.uid()) RETURNING service_versions.id INTO published_version_id;
  PERFORM ironvault_private.subscription_notice(g.tenant_id,'documents:'||published_version_id,'Service documents published','Effective '||effective||'. Dashboard PHP '||coalesce(v.data->>'dashboard_price','not previously published')||' → '||(clean->>'dashboard_price')||'; Portal PHP '||coalesce(v.data->>'portal_price','not previously published')||' → '||(clean->>'portal_price')||'. Review documents and choose to continue, change plans or decline renewal. Approved paid periods are preserved.') FROM ironvault_private.gym_subscriptions g;
 END IF;
 RETURN jsonb_build_object('draft',CASE WHEN p_action='get' THEN s.draft ELSE clean END,'preview',rendered,'published_id',published_version_id,'versions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY effective_date DESC,published_at DESC) FROM ironvault_private.service_versions x),'[]'::jsonb));
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.service_parameters(p_data jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_object_agg(key,value) FROM jsonb_each(p_data) WHERE key=ANY(ARRAY['dashboard_price','portal_price','pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days']);
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_quote(p_tenant text,p_kind text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE t date:=ironvault_private.subscription_today();tail ironvault_private.subscription_periods%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;startday date;accessday date;finish date;amount numeric;state jsonb;policy jsonb;version_id uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RAISE EXCEPTION 'Gym is not active'; END IF;
 IF p_plan NOT IN ('dashboard','portal') OR p_kind NOT IN ('payment','upgrade','downgrade') THEN RAISE EXCEPTION 'Choose a valid action and plan'; END IF;
 SELECT * INTO tail FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant ORDER BY end_date DESC,approved_at DESC LIMIT 1;
 state:=ironvault_private.subscription_state(p_tenant);
 IF p_kind='upgrade' THEN
  IF state->>'status'<>'paid' OR state->>'plan'<>'dashboard' OR p_plan<>'portal' OR EXISTS(SELECT 1 FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant AND access_from>t) THEN RAISE EXCEPTION 'Upgrade requires a current dashboard paid period without queued renewals'; END IF;
  SELECT * INTO tail FROM ironvault_private.subscription_periods WHERE id=(state->>'period_id')::uuid;
  startday:=t;finish:=tail.end_date;accessday:=t;policy:=tail.policy;
  amount:=round(((policy->>'portal_price')::numeric-(policy->>'dashboard_price')::numeric)*(finish-t+1)/(policy->>'paid_days')::numeric,2);
  version_id:=tail.version_id;
 ELSE
  startday:=CASE WHEN tail.id IS NOT NULL AND t<=tail.end_date THEN tail.end_date+1 WHEN tail.kind='paid' AND t<=tail.end_date+tail.grace_days THEN tail.end_date+1 ELSE t+1 END;
  SELECT * INTO v FROM ironvault_private.service_versions WHERE effective_date<=startday ORDER BY effective_date DESC,published_at DESC LIMIT 1;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Service documents must be published first'; END IF;
  version_id:=v.id;policy:=ironvault_private.service_parameters(v.data);finish:=startday+(policy->>'paid_days')::integer-1;
  accessday:=CASE WHEN startday>t AND (tail.id IS NULL OR t>tail.end_date+tail.grace_days) THEN t ELSE startday END;
  -- During a pilot/current period, an approved future period starts only after that period.
  IF tail.id IS NOT NULL AND t<=tail.end_date THEN accessday:=startday; END IF;
  amount:=(policy->>CASE p_plan WHEN 'dashboard' THEN 'dashboard_price' ELSE 'portal_price' END)::numeric;
  IF p_kind='downgrade' THEN IF tail.id IS NULL OR tail.plan<>'portal' OR t>tail.end_date OR p_plan<>'dashboard' THEN RAISE EXCEPTION 'Downgrade requires a current portal period'; END IF;amount:=0;END IF;
 END IF;
 RETURN jsonb_build_object('kind',p_kind,'plan',p_plan,'amount',amount,'start_date',startday,'end_date',finish,'access_from',accessday,'version_id',version_id,'policy',policy,'prior_period',tail.id,'currency','PHP');
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE t date:=ironvault_private.subscription_today();s ironvault_private.gym_subscriptions%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;req ironvault_private.subscription_requests%ROWTYPE;p ironvault_private.subscription_periods%ROWTYPE;quote jsonb;request_id_value uuid;reason text;days integer;result jsonb;super boolean:=ironvault_private.subscription_super();owner boolean;reference text;current_id uuid;
BEGIN
 SELECT * INTO STRICT s FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant FOR UPDATE;
 owner:=ironvault_private.subscription_owner(p_tenant);
 IF NOT super AND NOT owner THEN RAISE EXCEPTION 'Registered owner or Super Admin required' USING ERRCODE='42501'; END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>200000 THEN RAISE EXCEPTION 'Invalid subscription request'; END IF;
 current_id:=ironvault_private.service_current();
 SELECT * INTO v FROM ironvault_private.service_versions WHERE id=current_id;
 IF p_action='accept' THEN
  IF NOT owner THEN RAISE EXCEPTION 'Only the registered owner may accept'; END IF;
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish gym legal details before acceptance so the gym identity is recorded'; END IF;
  SELECT * INTO STRICT v FROM ironvault_private.service_versions WHERE id=(p_data->>'version_id')::uuid;
  IF p_data->>'accepted' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Explicit agreement is required'; END IF;
  INSERT INTO ironvault_private.service_acceptances(tenant_id,owner_id,version_id,gym_snapshot,owner_snapshot)
  SELECT p_tenant,auth.uid(),v.id,jsonb_build_object('id',g.id,'name',g.gym_name,'member_document_version',l.current_version,'legal_details',(SELECT jsonb_build_object('name',data->>'name','address',data->>'address','public_email',data->>'public_email') FROM ironvault_private.legal_versions WHERE legal_versions.id=l.current_version)),jsonb_build_object('id',auth.uid(),'name',g.owner_name,'email',a.contact_email)
  FROM public.owners g JOIN ironvault_private.branch_accounts a ON a.tenant_id=g.id AND a.user_id=auth.uid() AND a.role='owner' LEFT JOIN ironvault_private.legal_settings l ON l.scope=g.id WHERE g.id=p_tenant ON CONFLICT DO NOTHING;
 ELSIF p_action='quote' THEN RETURN ironvault_private.subscription_quote(p_tenant,p_data->>'kind',p_data->>'plan');
 ELSIF p_action='confirm_plan' THEN
  IF NOT owner OR p_data->>'confirmed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Registered owner must explicitly confirm the plan'; END IF;
  request_id_value:=(p_data->>'request_id')::uuid;SELECT * INTO req FROM ironvault_private.subscription_requests WHERE subscription_requests.id=request_id_value;
  IF FOUND THEN IF req.tenant_id<>p_tenant OR req.owner_id<>auth.uid() OR req.quote IS DISTINCT FROM p_data->'quote' THEN RAISE EXCEPTION 'Request ID already used with different details'; END IF;RETURN to_jsonb(req);END IF;
  quote:=ironvault_private.subscription_quote(p_tenant,p_data->'quote'->>'kind',p_data->'quote'->>'plan');
  IF quote IS DISTINCT FROM p_data->'quote' THEN RAISE EXCEPTION 'Quote changed; review exact amount and dates again'; END IF;
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND version_id=(quote->>'version_id')::uuid) THEN RAISE EXCEPTION 'Accept the quoted service documents first'; END IF;
  INSERT INTO ironvault_private.subscription_requests(id,tenant_id,owner_id,kind,quote) VALUES(request_id_value,p_tenant,auth.uid(),quote->>'kind',quote);
 ELSIF p_action IN ('activate_pilot','approve_payment','approve_downgrade','extend') THEN
  IF NOT super THEN RAISE EXCEPTION 'Super Admin required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND status='ACTIVE') THEN RAISE EXCEPTION 'Gym is not active'; END IF;
  IF s.owner_id IS NULL THEN RAISE EXCEPTION 'Registered owner binding unavailable; review account ownership first'; END IF;
  IF p_action='activate_pilot' THEN
   IF EXISTS(SELECT 1 FROM ironvault_private.subscription_periods WHERE subscription_periods.id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant AND kind='pilot') THEN RETURN jsonb_build_object('approved',true,'request_id',p_data->>'request_id'); END IF;
   IF p_data->>'reviewed_business' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Review first-pilot business eligibility'; END IF;
   IF s.pilot_used OR EXISTS(SELECT 1 FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant) THEN RAISE EXCEPTION 'This gym has already used its pilot or subscription'; END IF;
   IF current_id IS NULL OR NOT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=s.owner_id AND version_id=current_id) THEN RAISE EXCEPTION 'Registered owner must accept current service documents first'; END IF;
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish gym and platform member documents first'; END IF;
   request_id_value:=(p_data->>'request_id')::uuid;
   INSERT INTO ironvault_private.subscription_periods(id,tenant_id,kind,plan,access_from,start_date,end_date,grace_days,version_id,policy,amount,approved_by) VALUES(request_id_value,p_tenant,'pilot','portal',t,t+1,t+(v.data->>'pilot_days')::integer,0,v.id,ironvault_private.service_parameters(v.data),0,auth.uid());
   UPDATE ironvault_private.gym_subscriptions SET pilot_used=true WHERE tenant_id=p_tenant;
   PERFORM ironvault_private.subscription_schedule(request_id_value);
   PERFORM ironvault_private.subscription_notice(p_tenant,request_id_value||':welcome','Welcome to your free pilot','Full access is available now. Counted pilot days begin tomorrow and end '||(t+(v.data->>'pilot_days')::integer)||'. No automatic charges.');
  ELSIF p_action='extend' THEN
   IF EXISTS(SELECT 1 FROM ironvault_private.subscription_events WHERE tenant_id=p_tenant AND action='extend' AND data->>'request_id'=p_data->>'request_id') THEN RETURN jsonb_build_object('approved',true); END IF;
   IF nullif(p_data->>'request_id','')::uuid IS NULL THEN RAISE EXCEPTION 'Request ID required'; END IF;
   reason:=btrim(p_data->>'reason');days:=(p_data->>'days')::integer;
   IF coalesce(length(reason),0)<5 OR days NOT BETWEEN 1 AND 365 THEN RAISE EXCEPTION 'Enter an extension of 1–365 days and a recorded reason'; END IF;
   SELECT * INTO STRICT p FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant ORDER BY end_date DESC LIMIT 1 FOR UPDATE;
   IF p.access_from>t OR p.end_date<t THEN RAISE EXCEPTION 'Only a current final period can be extended'; END IF;
   UPDATE ironvault_private.subscription_periods SET end_date=end_date+days WHERE subscription_periods.id=p.id;
   UPDATE ironvault_private.owner_notifications SET superseded_at=clock_timestamp() WHERE tenant_id=p_tenant AND notice_key LIKE p.id||':%' AND available_at>now();
   PERFORM ironvault_private.subscription_schedule(p.id);
   -- Existing notice keys are preserved; replace only future schedule dates on a documented extension.
   UPDATE ironvault_private.owner_notifications n SET available_at=(CASE WHEN notice_key LIKE '%:reminder:%' THEN p.end_date+days+1-split_part(notice_key,':',3)::integer WHEN notice_key LIKE '%:expiry' THEN p.end_date+days+1 WHEN notice_key LIKE '%:suspend' THEN p.end_date+days+p.grace_days+1 WHEN notice_key LIKE '%:lastgrace' THEN p.end_date+days+p.grace_days ELSE p.end_date+days+p.grace_days+coalesce((p.policy->>'retention_days')::integer,90)-7 END)::timestamp AT TIME ZONE 'Asia/Manila',superseded_at=NULL,message=replace(message,p.end_date::text,(p.end_date+days)::text) WHERE tenant_id=p_tenant AND notice_key LIKE p.id||':%' AND superseded_at IS NOT NULL;
   PERFORM ironvault_private.subscription_notice(p_tenant,'extension:'||(p_data->>'request_id'),'Subscription extension approved',days||' days added. Reason: '||reason);
  ELSE
   SELECT * INTO STRICT req FROM ironvault_private.subscription_requests WHERE subscription_requests.id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant FOR UPDATE;
   IF req.approved_at IS NOT NULL THEN RETURN jsonb_build_object('approved',true,'request_id',req.id); END IF;
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL) THEN RAISE EXCEPTION 'Publish gym and platform member documents before paid activation'; END IF;
   IF (p_action='approve_downgrade') IS DISTINCT FROM (req.kind='downgrade') THEN RAISE EXCEPTION 'Approval action does not match request'; END IF;
   quote:=ironvault_private.subscription_quote(p_tenant,req.kind,req.quote->>'plan');
   IF quote IS DISTINCT FROM req.quote THEN RAISE EXCEPTION 'Quote dates or amount changed. Owner must confirm a fresh request; no payment is recorded'; END IF;
   reference:=btrim(p_data->>'reference');IF req.kind<>'downgrade' AND coalesce(length(reference),0)<3 THEN RAISE EXCEPTION 'Record a payment reference or cash receipt'; END IF;
   SELECT * INTO p FROM ironvault_private.subscription_periods WHERE subscription_periods.id=(quote->>'prior_period')::uuid;
   IF req.kind='upgrade' THEN
    UPDATE ironvault_private.subscription_periods SET plan='portal',amount=amount+(quote->>'amount')::numeric WHERE subscription_periods.id=(quote->>'prior_period')::uuid;
   ELSIF req.kind='payment' THEN
    INSERT INTO ironvault_private.subscription_periods(id,tenant_id,kind,plan,access_from,start_date,end_date,grace_days,version_id,policy,amount,reference,approved_by) VALUES(req.id,p_tenant,'paid',quote->>'plan',(quote->>'access_from')::date,(quote->>'start_date')::date,(quote->>'end_date')::date,(quote->'policy'->>'grace_days')::integer,(quote->>'version_id')::uuid,quote->'policy',(quote->>'amount')::numeric,reference,auth.uid());
    UPDATE ironvault_private.owner_notifications SET superseded_at=clock_timestamp() WHERE tenant_id=p_tenant AND available_at>now() AND notice_key ~ ':(reminder:|expiry|suspend|lastgrace|retention)' AND notice_key NOT LIKE req.id||':%';
    PERFORM ironvault_private.subscription_schedule(req.id);
   END IF;
   UPDATE ironvault_private.gym_subscriptions SET next_plan=quote->>'plan' WHERE tenant_id=p_tenant;
   UPDATE ironvault_private.subscription_requests SET approved_at=clock_timestamp(),approved_by=auth.uid() WHERE subscription_requests.id=req.id;
   PERFORM ironvault_private.subscription_notice(p_tenant,req.id||':approved',CASE WHEN req.kind='downgrade' THEN 'Downgrade scheduled' ELSE 'Payment approved' END,req.quote->>'plan'||' plan. Starts '||(req.quote->>'start_date')||'; ends '||(req.quote->>'end_date')||'. PHP '||(req.quote->>'amount')||'. Reference: '||coalesce(reference,'Not applicable')||CASE WHEN req.kind='downgrade' THEN '. Renewal payment is still required; this does not create a free paid period.' ELSE '' END);
  END IF;
  INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),p_action,p_data||jsonb_build_object('date',t,'quote',quote,'previous_period',to_jsonb(p)));
 ELSIF p_action='read_notice' THEN
  IF NOT owner THEN RAISE EXCEPTION 'Registered owner required'; END IF;
  UPDATE ironvault_private.owner_notifications SET read_at=coalesce(read_at,clock_timestamp()) WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND notice_key=p_data->>'key' AND available_at<=now();
 ELSIF p_action<>'get' THEN RAISE EXCEPTION 'Invalid subscription action'; END IF;
 RETURN jsonb_build_object('tenant_id',p_tenant,'owner_id',s.owner_id,'is_owner',owner,'pilot_used',s.pilot_used,'next_plan',(SELECT next_plan FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant),'state',ironvault_private.subscription_state(p_tenant),'current_version',current_id,'gym_documents_ready',EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL),'platform_documents_ready',EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL),'accepted',EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=s.owner_id AND version_id=current_id),'documents',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY effective_date DESC) FROM ironvault_private.service_versions x),'[]'::jsonb),'acceptances',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY accepted_at DESC) FROM ironvault_private.service_acceptances a WHERE tenant_id=p_tenant),'[]'::jsonb),'periods',coalesce((SELECT jsonb_agg(to_jsonb(period_row) ORDER BY period_row.start_date DESC) FROM ironvault_private.subscription_periods period_row WHERE tenant_id=p_tenant),'[]'::jsonb),'requests',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY confirmed_at DESC) FROM ironvault_private.subscription_requests r WHERE tenant_id=p_tenant),'[]'::jsonb),'events',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY created_at DESC) FROM ironvault_private.subscription_events e WHERE tenant_id=p_tenant),'[]'::jsonb),'notifications',CASE WHEN owner THEN coalesce((SELECT jsonb_agg(to_jsonb(n) ORDER BY available_at DESC) FROM ironvault_private.owner_notifications n WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND available_at<=now() AND superseded_at IS NULL),'[]'::jsonb) ELSE '[]'::jsonb END);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_subscription_directory()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Super Admin required' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('tenant_id',s.tenant_id,'gym_name',g.gym_name,'owner_name',g.owner_name,'owner_id',s.owner_id,'pilot_used',s.pilot_used,'state',ironvault_private.subscription_state(s.tenant_id),'accepted',EXISTS(SELECT 1 FROM ironvault_private.service_acceptances a WHERE a.tenant_id=s.tenant_id AND a.owner_id=s.owner_id AND a.version_id=ironvault_private.service_current()),'gym_documents_ready',EXISTS(SELECT 1 FROM ironvault_private.legal_settings l WHERE l.scope=s.tenant_id AND current_version IS NOT NULL)) ORDER BY g.gym_name) FROM ironvault_private.gym_subscriptions s JOIN public.owners g ON g.id=s.tenant_id),'[]'::jsonb);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_subscription_access(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT ironvault_private.subscription_super() AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND tenant_id=p_tenant AND enabled AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Gym access denied' USING ERRCODE='42501'; END IF;
 RETURN ironvault_private.subscription_state(p_tenant)||jsonb_build_object('is_owner',ironvault_private.subscription_owner(p_tenant),'super',ironvault_private.subscription_super());
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_subscription_public(p_token text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('portal',coalesce((ironvault_private.subscription_state(g.id)->>'portal')::boolean,false),'message','Member portal access is currently unavailable. Please contact gym staff.') FROM public.owners g WHERE g.token=p_token AND g.status='ACTIVE';
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.subscription_write_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE rowdata jsonb:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;tenant text:=rowdata->>'tenant_id';
BEGIN
 IF TG_TABLE_NAME='owners' THEN tenant:=rowdata->>'id';IF NEW.staff IS NOT DISTINCT FROM OLD.staff AND NEW.pricing IS NOT DISTINCT FROM OLD.pricing THEN RETURN NEW; END IF; END IF;
 -- Service-side account creation has explicit actor-aware guards in prepare/finish below.
 IF auth.uid() IS NOT NULL THEN
  PERFORM ironvault_private.subscription_require(tenant,'operations');
  IF EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND tenant_id=tenant AND role='member') THEN PERFORM ironvault_private.subscription_require(tenant,'portal');END IF;
 END IF;
 IF TG_TABLE_NAME='iv_attendance_logs' AND rowdata->>'method'='qr' THEN PERFORM ironvault_private.subscription_require(tenant,'portal');END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END $fn$;
CREATE TRIGGER iv_subscription_members BEFORE INSERT OR UPDATE OR DELETE ON public.members FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_write_guard();
CREATE TRIGGER iv_subscription_money BEFORE INSERT ON public.iv_financial_transactions FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_write_guard();
CREATE TRIGGER iv_subscription_attendance BEFORE INSERT ON public.iv_attendance_logs FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_write_guard();
CREATE TRIGGER iv_subscription_staff BEFORE UPDATE OF staff,pricing ON public.owners FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_write_guard();
CREATE TRIGGER iv_subscription_announcements BEFORE INSERT OR UPDATE OR DELETE ON public.iv_announcements FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_write_guard();
CREATE TRIGGER iv_subscription_report_permissions BEFORE INSERT OR UPDATE OR DELETE ON ironvault_private.staff_report_permissions FOR EACH ROW EXECUTE FUNCTION ironvault_private.subscription_write_guard();
CREATE OR REPLACE FUNCTION ironvault_private.subscription_can_read(p_tenant text,p_member text DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.subscription_super() OR EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.enabled AND r.disabled_at IS NULL AND
 ((r.role='owner' AND ironvault_private.subscription_owner(p_tenant) AND (ironvault_private.subscription_state(p_tenant)->>'read')::boolean)
 OR (r.role='staff' AND (ironvault_private.subscription_state(p_tenant)->>'operations')::boolean)
 OR (r.role='member' AND r.member_id=p_member AND (ironvault_private.subscription_state(p_tenant)->>'portal')::boolean)));
$fn$;
CREATE POLICY iv_subscription_role_scope ON public.iv_user_roles AS RESTRICTIVE FOR SELECT TO authenticated USING(ironvault_private.subscription_can_read(tenant_id,member_id) OR (user_id=auth.uid() AND role IN ('owner','super_admin')));
CREATE POLICY iv_subscription_member_read ON public.members AS RESTRICTIVE FOR SELECT TO authenticated USING(ironvault_private.subscription_can_read(tenant_id,id));

CREATE OR REPLACE FUNCTION public.iv_prepare_branch_account(p_request uuid,p_actor uuid,p_tenant text,p_role text,p_email text,p_alias text,p_payload jsonb,p_new_gym boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provision_requests%ROWTYPE; actor public.iv_user_roles%ROWTYPE; key text; price numeric; name text;
BEGIN
 IF p_request IS NULL OR p_role NOT IN ('owner','staff','member') OR (p_email IS NULL AND (p_role<>'member' OR p_actor IS NULL OR p_new_gym))
  OR (p_email IS NOT NULL AND (p_email='' OR p_email<>lower(btrim(p_email)) OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
  OR p_alias !~ '^[a-f0-9]{64}@accounts\.ironvault\.invalid$'
  OR p_payload ? 'password' OR p_payload ? 'service_role' THEN RAISE EXCEPTION 'Invalid account request'; END IF;
 IF p_role='staff' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.tenant_id=p_tenant AND a.role IN ('owner','staff') AND a.contact_email=p_email) THEN
  -- A same-request retry may find its own already-completed account.
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.provision_requests WHERE request_id=p_request AND tenant_id=p_tenant AND contact_email=p_email AND role=p_role) THEN RAISE EXCEPTION 'Admin portal email already in use'; END IF;
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text,1));
 SELECT * INTO job FROM ironvault_private.provision_requests WHERE request_id=p_request;
 IF FOUND THEN
  IF job.actor_id IS DISTINCT FROM p_actor OR job.tenant_id<>p_tenant OR job.role<>p_role OR job.contact_email IS DISTINCT FROM p_email
   OR job.alias<>p_alias OR job.payload<>p_payload THEN RAISE EXCEPTION 'Provision request mismatch'; END IF;
 END IF;
 SELECT * INTO actor FROM public.iv_user_roles WHERE user_id=p_actor AND enabled AND disabled_at IS NULL;
 IF p_new_gym THEN
  IF actor.role IS DISTINCT FROM 'super_admin' OR actor.tenant_id IS NOT NULL OR p_role<>'owner' THEN RAISE EXCEPTION 'Super Admin required'; END IF;
  name:=p_payload->>'gym_name';IF length(coalesce(name,'')) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'Gym name required'; END IF;
  FOREACH key IN ARRAY ARRAY['day','week','month','studentDiscount','seniorDiscount'] LOOP
   price:=(p_payload->'pricing'->>key)::numeric;
   IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<0
    OR (key NOT LIKE '%Discount' AND price<=0) OR price>(CASE WHEN key LIKE '%Discount' THEN 100 ELSE 10000000 END) OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid gym pricing'; END IF;
  END LOOP;
  -- Globally unique private alias satisfies the existing owners.email uniqueness;
  -- verified contact email lives in branch_accounts, never this login identifier.
  IF job.request_id IS NULL THEN
  INSERT INTO public.owners(id,gym_name,owner_name,email,password,token,logo,status,pricing,staff,audit_logs)
   VALUES(p_tenant,name,p_payload->>'name',p_alias,NULL,gen_random_uuid()::text,
    coalesce(p_payload->>'logo',''),'PROVISIONING',p_payload->'pricing','[]','[]');
  END IF;
 ELSE
  IF p_actor IS NOT NULL AND actor.user_id IS NULL THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND (status='ACTIVE' OR (status='PROVISIONING' AND actor.role='super_admin' AND p_role='staff'))) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
  IF p_actor IS NULL THEN
   IF p_role<>'member' THEN RAISE EXCEPTION 'Member registration only'; END IF;
  ELSIF actor.role IS DISTINCT FROM 'super_admin' THEN
   IF actor.tenant_id IS DISTINCT FROM p_tenant OR actor.role NOT IN ('owner','staff')
    OR (p_role='staff' AND actor.role<>'owner') OR p_role='owner' THEN RAISE EXCEPTION 'Not authorized'; END IF;
  END IF;
 END IF;
 IF NOT p_new_gym THEN PERFORM ironvault_private.subscription_require(p_tenant,CASE WHEN p_actor IS NULL THEN 'portal' ELSE 'operations' END,p_actor); END IF;
 IF length(coalesce(p_payload->>'name','')) NOT BETWEEN 1 AND 160 OR length(coalesce(p_payload->>'phone',''))>50
  OR length(coalesce(p_payload->>'logo',''))>750000 THEN RAISE EXCEPTION 'Invalid profile'; END IF;
 IF job.request_id IS NOT NULL THEN RETURN jsonb_build_object('alias',job.alias,'completed_user',job.completed_user,'tenant_id',job.tenant_id); END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant AND contact_email=p_email
  AND (role=p_role OR (p_role IN ('owner','staff') AND role IN ('owner','staff')))) THEN RAISE EXCEPTION 'Account already registered in this gym'; END IF;
 IF p_role='member' AND EXISTS(SELECT 1 FROM public.members WHERE tenant_id=p_tenant AND lower(btrim(email))=p_email) THEN
  RAISE EXCEPTION 'Membership already exists; ask the gym to restore account access'; END IF;
 INSERT INTO ironvault_private.provision_requests(request_id,tenant_id,role,contact_email,alias,actor_id,payload)
 VALUES(p_request,p_tenant,p_role,p_email,p_alias,p_actor,p_payload);
 RETURN jsonb_build_object('alias',p_alias,'tenant_id',p_tenant);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_finish_branch_account(p_request uuid,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provision_requests%ROWTYPE; member_id text; token text;
BEGIN
 SELECT * INTO STRICT job FROM ironvault_private.provision_requests WHERE request_id=p_request FOR UPDATE;
 IF job.completed_user IS NOT NULL THEN
  IF job.completed_user<>p_user THEN RAISE EXCEPTION 'Different account already completed'; END IF;
  RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'user_id',p_user,'member_id',
   (SELECT r.member_id FROM public.iv_user_roles r WHERE r.user_id=p_user));
 END IF;
 IF job.actor_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=job.actor_id AND r.enabled
  AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.tenant_id=job.tenant_id
   AND ((job.role='member' AND r.role IN ('owner','staff')) OR (job.role='staff' AND r.role='owner'))))) THEN
  RAISE EXCEPTION 'Provisioning authority revoked'; END IF;
 IF job.role='owner' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=job.tenant_id AND status='PROVISIONING') THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF job.role<>'owner' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=job.tenant_id AND (status='ACTIVE' OR (status='PROVISIONING' AND job.role='staff' AND EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=job.actor_id AND enabled AND role='super_admin')))) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user AND email=job.alias AND raw_app_meta_data->>'iv_provision_request'=p_request::text) THEN
  RAISE EXCEPTION 'Auth account does not match protected provisioning metadata'; END IF;
 IF job.role<>'owner' THEN PERFORM ironvault_private.subscription_require(job.tenant_id,CASE WHEN job.actor_id IS NULL THEN 'portal' ELSE 'operations' END,job.actor_id); END IF;
 IF job.role='member' THEN
  member_id:='MEM-'||gen_random_uuid()::text;
  SELECT o.token INTO STRICT token FROM public.owners o WHERE o.id=job.tenant_id;
  INSERT INTO public.members(id,tenant_id,tenant_token,name,email,phone,password,auth_user_id,
   classification,discount_percentage,plan,wallet_balance,amount,scans_used,status,date_joined)
  VALUES(member_id,job.tenant_id,token,job.payload->>'name',job.contact_email,coalesce(job.payload->>'phone',''),NULL,p_user,
   'Regular',0,'Not Selected',0,0,0,CASE WHEN job.actor_id IS NULL THEN 'PENDING' ELSE 'ACTIVE' END,
   ((now() AT TIME ZONE 'Asia/Manila')::date)::text);
 END IF;
 INSERT INTO public.iv_user_roles(user_id,tenant_id,role,member_id,enabled) VALUES(p_user,job.tenant_id,job.role,member_id,true);
 INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id) VALUES(job.tenant_id,job.role,job.contact_email,p_user);
 IF job.role='staff' THEN
  UPDATE public.owners SET staff=coalesce(staff,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('name',job.payload->>'name',
   'email',job.contact_email,'auth_user_id',p_user,'dateCreated',((now() AT TIME ZONE 'Asia/Manila')::date)::text)) WHERE id=job.tenant_id;
 END IF;
 UPDATE ironvault_private.provision_requests SET completed_user=p_user WHERE request_id=p_request;
 IF job.role='owner' THEN UPDATE public.owners SET status='ACTIVE' WHERE id=job.tenant_id AND status='PROVISIONING'; END IF;
 RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'member_id',member_id,'user_id',p_user);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_branch_identity(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id,a.role FROM ironvault_private.branch_accounts a
 JOIN public.iv_user_roles r ON r.user_id=a.user_id
 JOIN public.owners g ON g.id=a.tenant_id AND g.status='ACTIVE'
 WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles)
  AND (a.contact_email=lower(btrim(p_email)) OR (a.role='member' AND EXISTS(
   SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=a.tenant_id
    AND (lower(m.id)=lower(btrim(p_email)) OR lower(to_jsonb(m)->>'display_code')=lower(btrim(p_email))))))
  AND (a.role='owner' OR (a.role='staff' AND (ironvault_private.subscription_state(a.tenant_id)->>'operations')::boolean) OR (a.role='member' AND (ironvault_private.subscription_state(a.tenant_id)->>'portal')::boolean))
  AND r.enabled AND r.disabled_at IS NULL AND r.tenant_id=a.tenant_id AND r.role=a.role
  AND (r.role<>'member' OR EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id
   AND m.tenant_id=r.tenant_id AND m.status IN ('ACTIVE','PENDING')));
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.can_read_member(p_id text,p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.members m WHERE m.id=p_id AND m.tenant_id IS NOT DISTINCT FROM p_tenant)
 AND ironvault_private.subscription_can_read(p_tenant,p_id)
 AND (public.iv_can_access(p_tenant) OR EXISTS(SELECT 1 FROM public.iv_user_roles r
 WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=p_id AND r.tenant_id=p_tenant
 AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE')));
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.subscription_super() OR ((ironvault_private.subscription_state(p_tenant)->>'read')::boolean AND ironvault_private.subscription_owner(p_tenant)) OR ((ironvault_private.subscription_state(p_tenant)->>'operations')::boolean AND EXISTS(
  SELECT 1 FROM public.iv_user_roles r JOIN ironvault_private.staff_report_permissions p ON p.user_id=r.user_id AND p.tenant_id=r.tenant_id
  WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND r.role='staff' AND r.tenant_id=p_tenant
   AND p.permission='financial_reports_read' AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE')));
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.is_own_membership(p_member text,p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT (ironvault_private.subscription_state(p_tenant)->>'portal')::boolean AND EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL
  AND r.role='member' AND r.member_id=p_member AND r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_issue_member_pass(p_member_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; ticket ironvault_private.daily_passes%ROWTYPE; today date:=(now() AT TIME ZONE 'Asia/Manila')::date;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id FOR UPDATE;
 IF NOT FOUND OR NOT ironvault_private.is_own_membership(m.id,m.tenant_id) OR NOT ironvault_private.valid_entitlement(m.id) THEN
  RAISE EXCEPTION 'No valid membership for this pass'; END IF;
 PERFORM ironvault_private.subscription_require(m.tenant_id,'portal');
 PERFORM ironvault_private.require_current_member_legal(m.id);
 IF m.last_scanned_date=today::text OR EXISTS(SELECT 1 FROM public.iv_attendance_logs WHERE member_id=m.id
  AND (created_at AT TIME ZONE 'Asia/Manila')::date=today) THEN RAISE EXCEPTION 'Already admitted today'; END IF;
 INSERT INTO ironvault_private.daily_passes(member_id,tenant_id,business_day,expires_at)
  VALUES(m.id,m.tenant_id,today,(today+1)::timestamp AT TIME ZONE 'Asia/Manila') ON CONFLICT(member_id,business_day) DO NOTHING;
 SELECT * INTO STRICT ticket FROM ironvault_private.daily_passes WHERE member_id=m.id AND business_day=today;
 IF ticket.used_at IS NOT NULL THEN RAISE EXCEPTION 'Pass already used'; END IF;
 RETURN jsonb_build_object('payload','IV1|'||ticket.token::text,'business_day',today,'expires_at',ticket.expires_at);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_can_read_live_signal(p_tenant text,p_kind text,p_entity text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
  ((r.role='super_admin' AND r.tenant_id IS NULL) OR
   (r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE') AND
    (r.role IN ('owner','staff') OR (r.role='member' AND (p_kind='gym' OR (p_kind='member' AND p_entity=r.member_id))
     AND EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=p_tenant AND m.status IN ('ACTIVE','PENDING') AND (ironvault_private.subscription_state(m.tenant_id)->>'portal')::boolean))))));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_live_cursor(p_tenant text DEFAULT NULL,p_member text DEFAULT NULL,p_cursor text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE allowed boolean; checkpoint text; signals jsonb;
BEGIN
 IF p_tenant IS NULL THEN
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.role='super_admin'
   AND r.tenant_id IS NULL AND r.enabled AND r.disabled_at IS NULL) AND p_member IS NULL INTO allowed;
 ELSIF p_member IS NULL THEN
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL
   AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.role IN ('owner','staff') AND r.tenant_id=p_tenant
    AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE')))) INTO allowed;
 ELSE
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
   JOIN public.owners g ON g.id=r.tenant_id WHERE r.user_id=auth.uid() AND r.role='member'
    AND r.tenant_id=p_tenant AND r.member_id=p_member AND r.enabled AND r.disabled_at IS NULL
    AND m.status IN ('ACTIVE','PENDING') AND (ironvault_private.subscription_state(m.tenant_id)->>'portal')::boolean AND g.status='ACTIVE') INTO allowed;
 END IF;
 IF NOT coalesce(allowed,false) THEN RAISE EXCEPTION 'Live update access denied' USING ERRCODE='42501'; END IF;
 SELECT md5(coalesce(string_agg(s.kind||':'||s.entity_id||':'||s.revision::text,'|' ORDER BY s.kind,s.entity_id),'')),
  coalesce(jsonb_agg(jsonb_build_object('kind',s.kind,'entity_id',s.entity_id,'tenant_id',s.tenant_id,'revision',s.revision::text) ORDER BY s.kind,s.entity_id),'[]'::jsonb)
 INTO checkpoint,signals
 FROM public.iv_live_signals s WHERE p_tenant IS NULL OR
  (s.tenant_id=p_tenant AND (p_member IS NULL OR s.kind='gym' OR (s.kind='member' AND s.entity_id=p_member)));
 RETURN jsonb_build_object('cursor',checkpoint,'server_now',now(),'signals',CASE WHEN checkpoint IS DISTINCT FROM p_cursor THEN signals ELSE 'null'::jsonb END);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_revoke_staff(p_tenant text,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 IF NOT public.iv_can_access(p_tenant,ARRAY['owner']::text[]) OR auth.uid()=p_user THEN RAISE EXCEPTION 'Not authorized'; END IF;
 UPDATE public.iv_user_roles SET enabled=false,disabled_at=now() WHERE user_id=p_user AND tenant_id=p_tenant AND role='staff';
 IF NOT FOUND THEN RAISE EXCEPTION 'Staff link not found'; END IF;
 PERFORM public.iv_log_event(p_tenant,'Staff access revoked',p_user::text);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_member_announcements(p_tenant text,p_mode text DEFAULT 'list',p_read jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_member text; a record; v_revision text; was_read boolean; claimed boolean; result jsonb:='[]'::jsonb;
BEGIN
 PERFORM ironvault_private.subscription_require(p_tenant,'portal');
 IF p_mode IS NULL OR p_mode NOT IN ('list','claim','read') OR p_read IS NULL
  OR jsonb_typeof(p_read)<>'array' THEN RAISE EXCEPTION 'Invalid announcement request'; END IF;
 -- Locks keep account/gym revocation from racing this operation.
 SELECT m.id INTO v_member FROM public.iv_user_roles r JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
 JOIN public.owners g ON g.id=r.tenant_id
 WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.role='member'
  AND r.enabled AND r.disabled_at IS NULL AND m.status='ACTIVE' AND g.status='ACTIVE'
 FOR SHARE OF r,m,g;
 IF NOT FOUND THEN RAISE EXCEPTION 'Member announcement access denied'; END IF;
 FOR a IN SELECT n.* FROM public.iv_announcements n WHERE n.tenant_id=p_tenant
  AND n.archived_at IS NULL AND n.starts_at<=now() AND n.ends_at>now()
  ORDER BY n.pinned DESC,n.starts_at DESC,n.id FOR SHARE OF n
 LOOP
  -- Pin changes are cosmetic. Text/schedule changes constitute a significant update.
  v_revision:=a.content_revision::text;
  SELECT EXISTS(SELECT 1 FROM public.iv_announcement_reads r WHERE r.announcement_id=a.id
   AND r.member_id=v_member AND r.revision=v_revision) INTO was_read;
  claimed:=false;
  IF (p_mode='claim' AND NOT was_read) OR (p_mode='read' AND EXISTS(
   SELECT 1 FROM jsonb_array_elements(p_read) x WHERE x->>'id'=a.id::text AND x->>'revision'=v_revision)) THEN
   INSERT INTO public.iv_announcement_reads(tenant_id,announcement_id,member_id,revision)
    VALUES(p_tenant,a.id,v_member,v_revision) ON CONFLICT DO NOTHING;
   claimed:=FOUND;
   was_read:=true;
  END IF;
  result:=result||jsonb_build_array(jsonb_build_object('id',a.id,'tenant_id',a.tenant_id,'title',a.title,
   'body',a.body,'starts_at',a.starts_at,'ends_at',a.ends_at,'pinned',a.pinned,'revision',v_revision,
   'unread',NOT was_read,'popup',p_mode='claim' AND claimed));
 END LOOP;
 RETURN jsonb_build_object('items',result,'server_now',now());
END $fn$;
-- Explicit per-object ownership, RLS and ACLs. No browser or service-role direct table writes.
DO $acl$
DECLARE tab text;f record;
BEGIN
 FOREACH tab IN ARRAY ARRAY['service_settings','service_versions','gym_subscriptions','service_acceptances','subscription_requests','subscription_periods','subscription_events','owner_notifications'] LOOP
  EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',tab);
  EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',tab);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='ironvault_private' AND (p.proname LIKE 'subscription_%' OR p.proname IN ('service_current','service_render','service_parameters')) LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f.signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $acl$;
REVOKE ALL ON FUNCTION public.iv_service_documents(text,jsonb,date),public.iv_subscription_portal(text,text,jsonb),public.iv_subscription_directory(),public.iv_subscription_access(text),public.iv_subscription_public(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_service_documents(text,jsonb,date),public.iv_subscription_portal(text,text,jsonb),public.iv_subscription_directory(),public.iv_subscription_access(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iv_subscription_public(text) TO anon,authenticated;
-- RLS policies call only these read helpers. They reveal entitlements, never payments/owner notices.
GRANT EXECUTE ON FUNCTION ironvault_private.subscription_can_read(text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
