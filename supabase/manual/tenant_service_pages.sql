-- MANUAL ONLY: apply after 037. No tenant is purged. Existing tenants are labelled Test.
-- PDF file/record removal is a separate explicit cleanup after installation (see rollout).
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.service_pdf_files') IS NULL THEN RAISE EXCEPTION 'Apply 037 first'; END IF;
 IF to_regclass('ironvault_private.provider_notices') IS NOT NULL THEN RAISE EXCEPTION '038 already installed; do not reapply'; END IF;
END $guard$;
ALTER TABLE ironvault_private.gym_subscriptions ADD COLUMN is_test boolean NOT NULL DEFAULT false;
UPDATE ironvault_private.gym_subscriptions SET is_test=true;
ALTER TABLE ironvault_private.service_versions ADD COLUMN retired boolean NOT NULL DEFAULT false;
ALTER TABLE ironvault_private.service_settings ADD COLUMN revision uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE ironvault_private.service_acceptances ADD COLUMN accepted_documents jsonb;
ALTER TABLE ironvault_private.subscription_requests ADD COLUMN payment_reference text;
ALTER TABLE ironvault_private.subscription_requests ADD COLUMN reference_submitted_at timestamptz;
ALTER TABLE ironvault_private.subscription_requests ADD COLUMN cancelled_at timestamptz;
ALTER TABLE ironvault_private.owner_notifications ADD COLUMN resolved_at timestamptz;
ALTER TABLE ironvault_private.owner_notifications ADD COLUMN destination text NOT NULL DEFAULT 'subscription';
CREATE TABLE ironvault_private.provider_notices(notice_key text PRIMARY KEY,tenant_id text REFERENCES public.owners(id) ON DELETE CASCADE,title text NOT NULL,message text NOT NULL,available_at timestamptz NOT NULL DEFAULT clock_timestamp(),resolved_at timestamptz);
CREATE TABLE ironvault_private.provider_notice_reads(notice_key text NOT NULL REFERENCES ironvault_private.provider_notices(notice_key) ON DELETE CASCADE,user_id uuid NOT NULL,read_at timestamptz NOT NULL DEFAULT clock_timestamp(),PRIMARY KEY(notice_key,user_id));
CREATE TABLE ironvault_private.provider_announcements(id uuid PRIMARY KEY,title text NOT NULL,message text NOT NULL,published_by uuid NOT NULL,audience text NOT NULL,requested_targets jsonb NOT NULL,published_at timestamptz NOT NULL DEFAULT clock_timestamp(),available_at timestamptz NOT NULL);
CREATE TABLE ironvault_private.provider_announcement_targets(announcement_id uuid REFERENCES ironvault_private.provider_announcements(id) ON DELETE CASCADE,tenant_id text REFERENCES public.owners(id) ON DELETE CASCADE,owner_id uuid NOT NULL,PRIMARY KEY(announcement_id,tenant_id));
CREATE OR REPLACE FUNCTION ironvault_private.service_current()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT id FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text' AND effective_date<=ironvault_private.subscription_today() ORDER BY effective_date DESC,published_at DESC LIMIT 1;
$fn$;
-- Stop the retired upload/publish APIs even if an old browser tab remains open.
REVOKE EXECUTE ON FUNCTION public.iv_service_pdf_settings(text,jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.iv_service_pdf_register(uuid,uuid,text,text,integer,integer) FROM service_role;
CREATE OR REPLACE FUNCTION ironvault_private.service_pdf_allowed(p_path text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$ SELECT false $fn$;
-- Draft seed is inserted below by the reproducible build; existing real contact/policy values survive.

UPDATE ironvault_private.service_settings SET draft=(SELECT jsonb_object_agg(j.key,CASE WHEN j.key LIKE '\_%' ESCAPE '\' OR j.key='document_version' THEN j.value WHEN nullif(btrim(draft->>j.key),'') IS NOT NULL THEN draft->j.key ELSE j.value END) FROM jsonb_each($defaults${"provider_name": "Matt Hue", "brand": "Iron Vault", "address": "Poblacion 2, Tagbilaran City, Bohol, Philippines", "support_email": "ironvault@gmail.com", "billing_contact": "0992-634-8656", "privacy_contact": "Matt Hue / Iron Vault Privacy Contact", "privacy_email": "ironvault@gmail.com", "support_hours": "9 AM–5 PM, Philippine time", "dashboard_price": 999, "portal_price": 1800, "pilot_days": 14, "paid_days": 30, "grace_days": 7, "price_notice_days": 30, "export_days": 30, "retention_days": 90, "late_payment_policy": "During paid grace, renewal continues from the original renewal date. After suspension, access returns on approval and counted days start the following day.", "upgrade_policy": "Upgrades charge the plan-price difference proportionally for remaining days and retain the expiry date. Downgrades take effect after the current paid period and require the applicable renewal payment.", "refund_policy": "Cancellation before a scheduled paid period begins qualifies for a full refund. After activation, unused days are generally non-refundable, except where required by law or where a service failure or exceptional circumstance justifies another remedy. Duplicate or incorrect payments will be reviewed and corrected. Credit may replace a refund only with the owner’s agreement.", "outage_policy": "Report service problems promptly. A confirmed interruption preventing core operations for four continuous hours qualifies for review. Depending on the circumstances, remedies may include correction, an extension, credit, or a refund where appropriate or legally required.", "billing_complaints": "Report billing issues promptly, preferably within 30 days of discovering them. The Service Provider aims to initiate approved refunds within 7–14 business days; payment providers may require additional settlement time. Statutory rights remain unaffected.", "backup_policy": "", "security_retention": "Security/audit records are generally kept for up to 12 months where reasonably necessary.", "payment_retention": "Retain for applicable Philippine accounting and tax requirements.", "providers": "", "privacy_purposes": "Depending on features used: names, contact details, Member IDs, optional photos, membership details, attendance, account credits, transactions, staff permissions, subscription/payment references, agreement acceptances, support and necessary security logs. Use these to deliver, secure and administer the service, provide support, investigate problems and meet legal obligations.", "marketing_policy": "Do not sell personal information or use gym/member information for third-party advertising. Promotional emails require separate optional opt-in and an unsubscribe method. Billing, security and necessary service notices are separate.", "sensitive_data_policy": "Standard registration does not request medical records, health information or government ID images. Do not enter these into general-purpose fields. New sensitive-information uses require an appropriate assessment and safeguards before collection.", "deletion_process": "Deletion is reviewed manually; expiry does not automatically erase records. Operational records are reviewed for deletion or anonymisation within the stated review period after final operational access ends, subject to lawful preservation needs. Coordinate gym-controlled requests with the registered owner. On backup restoration, reapply previously approved deletion or restriction instructions where appropriate.", "breach_process": "Protect passwords and limit staff access. Report suspected misuse promptly to the privacy/security contact. Assess and handle incidents without undue delay. Legally required notifications, including the applicable 72-hour requirement where its conditions apply, must not be delayed by normal support hours.", "liability_policy": "The Service Provider exercises reasonable care but does not promise uninterrupted or error-free service or absolute security. Maintain a practical alternative for essential gym operations during an outage. Nothing removes rights or remedies that cannot lawfully be waived.", "dispute_policy": "Philippine law applies. Contact the Service Provider first to address concerns in good faith. Competent courts and authorities retain jurisdiction under applicable law. Complaints to the National Privacy Commission are not restricted.", "contract_extra": "", "support_days": "Monday to Friday, excluding Philippine public holidays.", "tax_policy": "The quoted subscription amount is the total payable. Any additional charges require prior disclosure and agreement.", "billing_instructions": "", "_terms_template": "# {{brand}} — Terms of Use\n\nService Provider: {{provider_name}}, operating {{brand}}\nAddress: {{address}}\nSupport: {{support_email}} · Billing: {{billing_contact}}\nPrivacy/security: {{privacy_contact}}, {{privacy_email}}\nVersion: {{document_version}}\n\n1. ABOUT THE SERVICE\n\nSoftware for managing gym members, attendance, staff access, membership transactions and reports. The Gym remains responsible for its operations, staff, member services, payment collection and accurate, lawful information. Only the registered owner with authority to represent this Gym may accept.\n\n2. FREE PILOT\n\nEligible gyms may receive one {{pilot_days}}-day pilot with dashboard and member-portal access. Complete setup, publish gym member documents and accept these service documents before separate Service Provider activation. Access opens on approval; counted days start the following calendar day in Philippine time and end at 11:59:59 PM on the final day. No automatic charge or paid subscription. No automatic pilot grace period.\n\n3. PAID PLANS\n\nEach plan covers this Gym for {{paid_days}} counted calendar days. Dashboard Only: PHP {{dashboard_price}}. Dashboard + Member Portal: PHP {{portal_price}} TOTAL, not an additional fee. Dashboard Only supports staff-assisted operations. Member login, member QR passes and self-service require Member Portal entitlement. Review the selected price and exact dates in the subscription summary before payment approval. No automatic charges.\n\n4. PAYMENTS AND DATES\n\n{{billing_instructions}}\n{{tax_policy}}\nPayment requires Service Provider verification and approval; submitting a reference is not approval. New activation opens access on approval and counts from the following day. Payment approved before pilot expiry starts the paid period the day after the pilot ends. Early renewal preserves remaining paid days. {{late_payment_policy}}\n\n5. EXPIRY AND PLAN CHANGES\n\nPaid subscriptions receive {{grace_days}} dashboard-only grace days; member-portal access is disabled during grace. After grace, registrations, check-ins and transactions are suspended. The registered owner retains billing access and a {{export_days}}-day read-only export window after final operational access ends, including applicable paid grace. {{upgrade_policy}} Exceptions or extensions require Service Provider approval and a recorded reason.\n\n6. RESPONSIBLE USE\n\nProtect credentials, limit staff access and use only authorised accounts, records and features. Do not bypass access controls, falsify records or use the service unlawfully. Provide appropriate notices and a lawful basis for necessary member and staff information. {{sensitive_data_policy}} The Privacy Notice and Data Processing Agreement explain processing responsibilities.\n\n7. SUPPORT AND INTERRUPTIONS\n\nSupport: {{support_days}} {{support_hours}}. {{outage_policy}} {{liability_policy}}\n\n8. CANCELLATION AND REFUNDS\n\nYou may stop renewing by contacting the Service Provider. {{refund_policy}} {{billing_complaints}}\n\n9. RECORDS AND ENDING ACCESS\n\nExpiry or suspension does not automatically delete records. Export available records within the stated window. The Privacy Notice and Data Processing Agreement explain retention and backups. The Service Provider may restrict access for serious misuse, security threats or legal requirements, with notice where reasonably practical.\n\n10. CHANGES AND LEGAL RIGHTS\n\nPrice changes require at least {{price_notice_days}} calendar days’ advance notice to the registered owner, stating old/new prices, affected plan, effective date and options. Approved current and future periods retain approved prices. You may decline renewal without an additional cancellation penalty. Notify material changes and obtain renewed explicit acceptance where required; reading a notice is not acceptance. {{dispute_policy}} {{contract_extra}}\n", "_privacy_template": "# {{brand}} — Privacy Notice\n\nService Provider: {{provider_name}}, operating {{brand}}\nAddress: {{address}}\nSupport: {{support_email}} · Billing: {{billing_contact}}\nPrivacy/security: {{privacy_contact}}, {{privacy_email}}\nVersion: {{document_version}}\n\n1. RESPONSIBILITIES\n\nThe Gym decides why and how its operational member and staff records are used. The Service Provider handles them to deliver the agreed software and separately uses necessary owner, billing, support and security information to administer the service. Read this with the Terms of Use and Data Processing Agreement.\n\n2. INFORMATION AND PURPOSES\n\n{{privacy_purposes}} {{sensitive_data_policy}} Walk-ins need no email for staff-assisted service; email recovery needs a real contact email. Each purpose needs an appropriate lawful basis under Philippine law. Consent is obtained where required; visiting a gym or accepting Terms is not blanket permission for unrelated uses. {{marketing_policy}}\n\n3. AUTHORISED ACCESS AND PROVIDERS\n\nOnly authorised people/providers with a necessary purpose, or lawful disclosure, may receive information. {{providers}} Database region: {{database_region}}. Email delivery: {{email_provider}}. Overseas processing and safeguards: {{overseas_processing}}.\n\n4. RETENTION\n\nThe owner normally has {{export_days}} days after final operational access ends, including any paid grace, to export available records. Operational records are reviewed within {{retention_days}} days after that same endpoint. {{deletion_process}} {{security_retention}} {{payment_retention}} Backups: {{backup_policy}}.\n\n5. SECURITY AND INCIDENTS\n\n{{breach_process}} Contact {{privacy_email}}. No service promises absolute security.\n\n6. RIGHTS AND REQUESTS\n\nSubject to law, request access, correction, objection, deletion/blocking, portability or other remedies through {{privacy_email}}. Reasonable identity checks may be necessary. Coordinate gym-controlled records with the Gym; the Service Provider handles its own account/billing records. Complaints may be raised with the National Privacy Commission.\n\n7. UPDATES\n\nCommunicate material changes and obtain new consent where required. Acknowledging this notice does not waive privacy rights or authorise unrelated processing.\n", "_dpa_template": "# {{brand}} — Data Processing Agreement\n\nService Provider: {{provider_name}}, operating {{brand}}\nAddress: {{address}}\nSupport: {{support_email}} · Billing: {{billing_contact}}\nPrivacy/security: {{privacy_contact}}, {{privacy_email}}\nVersion: {{document_version}}\n\n1. PARTIES AND INSTRUCTIONS\n\nThis agreement is between the Service Provider and the Gym identified on this page and in its acceptance record, including during a pilot. The Gym determines the purposes of its operational records. The Service Provider processes them on documented lawful instructions to deliver the service. Its own account, billing and security uses are described in the Privacy Notice.\n\n2. COVERED INFORMATION\n\n{{privacy_purposes}} Use only for lawful gym-management purposes. {{sensitive_data_policy}}\n\n3. GYM RESPONSIBILITIES\n\nGive accurate notices, establish lawful bases, obtain consent where required, minimise information and keep it reasonably accurate. Authorise staff appropriately, protect credentials, remove unnecessary access and report suspected misuse. Physical presence, manual registration or Terms acceptance is not blanket consent.\n\n4. SERVICE PROVIDER RESPONSIBILITIES\n\nProcess on lawful instructions for the agreed service or as required by law; raise concerns about apparently unlawful instructions. Limit access with confidentiality duties and reasonable organisational, physical and technical safeguards. Do not sell covered data or use it for third-party advertising. Assist with lawful rights requests and proportionate compliance enquiries while protecting confidential security information.\n\n5. INFRASTRUCTURE PROVIDERS\n\nThe Gym authorises necessary providers identified here: {{providers}}. Database region: {{database_region}}. Email delivery: {{email_provider}}. Overseas processing: {{overseas_processing}}. The Service Provider remains responsible for applicable duties and safeguards. Communicate material provider changes, allowing reasonable opportunity for privacy concerns where practicable.\n\n6. INCIDENTS\n\nNotify the Gym without undue delay after awareness of a personal data breach affecting covered information, with available response details. The Gym must promptly report suspected compromise. {{breach_process}} Contact {{privacy_email}}. This agreement postpones no legal deadline.\n\n7. EXPORT, RETURN AND DELETION\n\nOwner export: {{export_days}} days after final operational access, including paid grace. Operational retention review: {{retention_days}} days after that endpoint. {{deletion_process}} Backups: {{backup_policy}}. {{security_retention}} {{payment_retention}}\n\n8. LAW AND ACCEPTANCE\n\nCommercial matters follow the Terms of Use. Mandatory Philippine law, RA 10173 and applicable NPC rules prevail. Neither party acquires ownership of individuals’ personal information. Communicate material changes and obtain renewed explicit acceptance where required. The registered owner must explicitly agree to the Terms and this Agreement and acknowledge the Privacy Notice; a notification alone is not acceptance.\n", "document_version": "1.0", "database_region": "", "email_provider": "", "overseas_processing": ""}$defaults$::jsonb) j),revision=gen_random_uuid(),updated_at=clock_timestamp() WHERE id=true;
CREATE OR REPLACE FUNCTION ironvault_private.tenant_service_documents(p_tenant text,p_version uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v ironvault_private.service_versions%ROWTYPE;g public.owners%ROWTYPE;details jsonb;identity jsonb;header text;result jsonb;
BEGIN
 SELECT * INTO STRICT v FROM ironvault_private.service_versions WHERE id=p_version AND NOT retired AND document_format='text';
 SELECT * INTO STRICT g FROM public.owners WHERE id=p_tenant;
 SELECT lv.data INTO details FROM ironvault_private.legal_settings ls JOIN ironvault_private.legal_versions lv ON lv.id=ls.current_version WHERE ls.scope=p_tenant;
 identity:=jsonb_build_object('tenant_id',g.id,'name',coalesce(nullif(details->>'name',''),g.gym_name),'address',details->>'address','email',details->>'public_email','phone',details->>'phone','owner_name',g.owner_name,'owner_email',(SELECT contact_email FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant AND role='owner' AND user_id=(SELECT owner_id FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant)));
 header:='GYM: '||coalesce(identity->>'name','')||E'\nAddress: '||coalesce(identity->>'address','')||E'\nGym contact: '||coalesce(identity->>'email','')||' '||coalesce(identity->>'phone','')||E'\nRegistered owner: '||coalesce(identity->>'owner_name','')||' · '||coalesce(identity->>'owner_email','')||E'\nTenant reference: '||g.id||E'\nEffective date: '||v.effective_date||E'\n\n';
 result:=jsonb_build_object('id',v.id,'version_label',v.version_label,'effective_date',v.effective_date,'document_format','text','data',v.data,'tenant',identity,'terms_text',header||v.terms_text,'privacy_text',header||v.privacy_text,'dpa_text',header||v.dpa_text);
 RETURN result||jsonb_build_object('review_hash',encode(sha256(convert_to(result::text,'UTF8')),'hex'));
END $fn$;
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
  version_id:=CASE WHEN EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE id=tail.version_id AND NOT retired AND document_format='text') THEN tail.version_id ELSE ironvault_private.service_current() END;
  IF version_id IS NULL THEN RAISE EXCEPTION 'Service documents must be published first';END IF;
 ELSE
  startday:=CASE WHEN tail.id IS NOT NULL AND t<=tail.end_date THEN tail.end_date+1 WHEN tail.kind='paid' AND t<=tail.end_date+tail.grace_days THEN tail.end_date+1 ELSE t+1 END;
  SELECT * INTO v FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text' AND effective_date<=startday ORDER BY effective_date DESC,published_at DESC LIMIT 1;
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
-- Preserve the corrected, tested billing/date implementation behind the extended entry point.
ALTER FUNCTION public.iv_subscription_portal(text,text,jsonb) RENAME TO subscription_portal_038_base;
ALTER FUNCTION public.subscription_portal_038_base(text,text,jsonb) SET SCHEMA ironvault_private;
REVOKE ALL ON FUNCTION ironvault_private.subscription_portal_038_base(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s ironvault_private.gym_subscriptions%ROWTYPE;r ironvault_private.subscription_requests%ROWTYPE;doc jsonb;result jsonb;docs jsonb;owner boolean;provider boolean;ref text;was_pending boolean;
BEGIN
 SELECT * INTO STRICT s FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant FOR UPDATE;
 owner:=ironvault_private.subscription_owner(p_tenant);provider:=ironvault_private.subscription_super();
 IF NOT owner AND NOT provider THEN RAISE EXCEPTION 'Registered owner or Provider required' USING ERRCODE='42501';END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>200000 THEN RAISE EXCEPTION 'Invalid request';END IF;
 IF p_action IN ('notifications','badge') THEN
  IF NOT owner THEN RAISE EXCEPTION 'Registered owner required';END IF;
  RETURN jsonb_build_object('tenant_id',p_tenant,'state',ironvault_private.subscription_state(p_tenant),'current_version',ironvault_private.service_current(),'is_owner',true,'is_test',s.is_test,'accepted',EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND version_id=ironvault_private.service_current()),'gym_documents_ready',EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant AND current_version IS NOT NULL),'platform_documents_ready',EXISTS(SELECT 1 FROM ironvault_private.legal_settings WHERE scope='platform' AND current_version IS NOT NULL),'unread_count',(SELECT count(*) FROM ironvault_private.owner_notifications n WHERE n.tenant_id=p_tenant AND n.owner_id=auth.uid() AND n.available_at<=now() AND n.read_at IS NULL AND n.resolved_at IS NULL AND n.superseded_at IS NULL),'notifications',CASE WHEN p_action='notifications' THEN coalesce((SELECT jsonb_agg(to_jsonb(n) ORDER BY available_at DESC) FROM ironvault_private.owner_notifications n WHERE n.tenant_id=p_tenant AND n.owner_id=auth.uid() AND n.available_at<=now()),'[]'::jsonb) ELSE '[]'::jsonb END);
 END IF;
 IF p_action='submit_reference' THEN
  IF NOT owner THEN RAISE EXCEPTION 'Registered owner required'; END IF;
  SELECT * INTO STRICT r FROM ironvault_private.subscription_requests WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant FOR UPDATE;
  ref:=btrim(p_data->>'reference');IF coalesce(length(ref),0) NOT BETWEEN 3 AND 180 OR r.cancelled_at IS NOT NULL OR r.approved_at IS NOT NULL OR r.kind='downgrade' THEN RAISE EXCEPTION 'Enter a reference for a pending payment';END IF;
  IF r.payment_reference IS NOT NULL AND r.payment_reference<>ref THEN RAISE EXCEPTION 'Reference already submitted; contact the Provider to correct it';END IF;
  UPDATE ironvault_private.subscription_requests SET payment_reference=ref,reference_submitted_at=coalesce(reference_submitted_at,clock_timestamp()) WHERE id=r.id;
  INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) VALUES('reference:'||r.id,p_tenant,'Payment reference submitted','Payment reference is ready for verification.') ON CONFLICT DO NOTHING;
 ELSIF p_action='cancel_request' THEN
  IF NOT owner AND NOT provider THEN RAISE EXCEPTION 'Registered owner or Provider required';END IF;
  IF provider AND coalesce(length(btrim(p_data->>'reason')),0)<5 THEN RAISE EXCEPTION 'Record why this request is returned';END IF;
  UPDATE ironvault_private.subscription_requests SET cancelled_at=clock_timestamp() WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant AND (owner_id=auth.uid() OR provider) AND approved_at IS NULL AND (reference_submitted_at IS NULL OR provider);
  IF NOT FOUND THEN RAISE EXCEPTION 'Only an unpaid pending request can be cancelled; contact the Provider otherwise';END IF;
  UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE notice_key IN ('request:'||(p_data->>'request_id'),'reference:'||(p_data->>'request_id'));
  INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_tenant,auth.uid(),'cancel_request',p_data);
  IF provider THEN PERFORM ironvault_private.subscription_notice(p_tenant,'returned:'||(p_data->>'request_id'),'Subscription request needs review','Provider note: '||(p_data->>'reason')||'. Contact the Provider about any payment already made before submitting a new quote. No refund or charge is recorded automatically.');END IF;
 ELSE
  IF p_action='accept' THEN
   PERFORM 1 FROM public.owners WHERE id=p_tenant FOR UPDATE;
   PERFORM 1 FROM ironvault_private.legal_settings WHERE scope=p_tenant FOR UPDATE;
   doc:=ironvault_private.tenant_service_documents(p_tenant,(p_data->>'version_id')::uuid);
   IF coalesce(doc->'tenant'->>'name','')='' OR coalesce(doc->'tenant'->>'address','')='' OR coalesce(doc->'tenant'->>'email','')='' OR coalesce(doc->'tenant'->>'owner_name','')='' THEN RAISE EXCEPTION 'Complete gym legal name, address, support email and owner name before acceptance';END IF;
   IF p_data->>'review_hash' IS DISTINCT FROM doc->>'review_hash' THEN RAISE EXCEPTION 'Gym details or document changed. Reopen and review before accepting';END IF;
  ELSIF p_action='confirm_plan' THEN
   IF EXISTS(SELECT 1 FROM ironvault_private.subscription_requests WHERE tenant_id=p_tenant AND approved_at IS NULL AND cancelled_at IS NULL AND id<>(p_data->>'request_id')::uuid) THEN RAISE EXCEPTION 'A request is already pending. Review it before submitting another';END IF;
  ELSIF p_action IN ('approve_payment','approve_downgrade') THEN
   SELECT * INTO STRICT r FROM ironvault_private.subscription_requests WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant FOR UPDATE;
   IF r.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'This request is cancelled';END IF;
   was_pending:=r.approved_at IS NULL;
  END IF;
  result:=ironvault_private.subscription_portal_038_base(p_tenant,p_action,p_data);
  IF p_action='accept' THEN
   UPDATE ironvault_private.service_acceptances SET accepted_documents=doc WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND version_id=(p_data->>'version_id')::uuid AND accepted_documents IS NULL;
   UPDATE ironvault_private.owner_notifications SET resolved_at=clock_timestamp() WHERE tenant_id=p_tenant AND notice_key='documents:'||(p_data->>'version_id');
   INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) VALUES('accept:'||p_tenant||':'||(p_data->>'version_id'),p_tenant,'Owner accepted service documents','Review the gym onboarding requirements.') ON CONFLICT DO NOTHING;
  ELSIF p_action='confirm_plan' THEN
   INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) VALUES('request:'||(p_data->>'request_id'),p_tenant,'Subscription request','The owner confirmed a subscription quote. Review the request.') ON CONFLICT DO NOTHING;
  ELSIF p_action IN ('approve_payment','approve_downgrade') AND was_pending THEN
   UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE notice_key IN ('request:'||r.id,'reference:'||r.id);
   IF r.kind='payment' THEN
    UPDATE ironvault_private.owner_notifications n SET resolved_at=clock_timestamp() FROM ironvault_private.subscription_periods old,ironvault_private.subscription_periods new
    WHERE new.id=r.id AND old.tenant_id=p_tenant AND old.id<>new.id AND old.end_date<new.end_date AND n.tenant_id=p_tenant AND n.notice_key LIKE old.id||':%' AND n.notice_key ~ ':(reminder:|expiry|suspend|lastgrace|retention)';
   END IF;
  ELSIF p_action='activate_pilot' THEN
   UPDATE ironvault_private.owner_notifications SET resolved_at=clock_timestamp() WHERE tenant_id=p_tenant AND notice_key='setup';
   UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE tenant_id=p_tenant AND notice_key LIKE 'accept:%';
  END IF;
  IF p_action IN ('quote','confirm_plan') THEN RETURN result;END IF;
 END IF;
 result:=ironvault_private.subscription_portal_038_base(p_tenant,'get','{}');
 SELECT coalesce(jsonb_agg(coalesce(a.accepted_documents,ironvault_private.tenant_service_documents(p_tenant,v.id)) ORDER BY v.effective_date DESC),'[]') INTO docs FROM ironvault_private.service_versions v LEFT JOIN ironvault_private.service_acceptances a ON a.tenant_id=p_tenant AND a.owner_id=s.owner_id AND a.version_id=v.id WHERE NOT v.retired AND v.document_format='text';
 RETURN result||jsonb_build_object('today',ironvault_private.subscription_today(),'documents',docs,'is_test',s.is_test,'notifications',CASE WHEN owner THEN coalesce((SELECT jsonb_agg(to_jsonb(n) ORDER BY available_at DESC) FROM ironvault_private.owner_notifications n WHERE n.tenant_id=p_tenant AND n.owner_id=auth.uid() AND n.available_at<=now()),'[]'::jsonb) ELSE '[]'::jsonb END);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_provider_console(p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE ann uuid;selection text;targets text[];r record;at_time timestamptz;was_test boolean;
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Provider required' USING ERRCODE='42501';END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>20000 THEN RAISE EXCEPTION 'Invalid console request';END IF;
 IF p_action='badge' THEN
  RETURN jsonb_build_object('unread',(SELECT count(*) FROM ironvault_private.provider_notices n LEFT JOIN ironvault_private.provider_notice_reads rd ON rd.notice_key=n.notice_key AND rd.user_id=auth.uid() WHERE n.available_at<=now() AND n.resolved_at IS NULL AND rd.read_at IS NULL));
 END IF;
 IF p_action='tag' THEN
  IF p_data->>'is_test' NOT IN ('true','false') OR p_data->>'is_test' IS NULL THEN RAISE EXCEPTION 'Choose Test or Live';END IF;
  SELECT is_test INTO STRICT was_test FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_data->>'tenant_id' FOR UPDATE;
  UPDATE ironvault_private.gym_subscriptions SET is_test=(p_data->>'is_test')::boolean WHERE tenant_id=p_data->>'tenant_id';
  INSERT INTO ironvault_private.subscription_events(tenant_id,actor_id,action,data) VALUES(p_data->>'tenant_id',auth.uid(),'tenant_tag',jsonb_build_object('was_test',was_test,'is_test',(p_data->>'is_test')::boolean));
 ELSIF p_action='read' THEN
  INSERT INTO ironvault_private.provider_notice_reads(notice_key,user_id) SELECT notice_key,auth.uid() FROM ironvault_private.provider_notices WHERE notice_key=p_data->>'key' AND available_at<=now() ON CONFLICT DO NOTHING;
 ELSIF p_action='announce' THEN
  ann:=(p_data->>'request_id')::uuid;selection:=p_data->>'audience';at_time:=coalesce((p_data->>'available_at')::timestamptz,clock_timestamp());
  IF EXISTS(SELECT 1 FROM ironvault_private.provider_announcements WHERE id=ann) THEN
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.provider_announcements WHERE id=ann AND published_by=auth.uid() AND audience=selection AND requested_targets=coalesce(p_data->'tenants','[]'::jsonb) AND title=btrim(p_data->>'title') AND message=btrim(p_data->>'message') AND (p_data->>'available_at' IS NULL OR available_at=at_time)) THEN RAISE EXCEPTION 'Request ID already used';END IF;
  ELSE
   IF coalesce(length(btrim(p_data->>'title')),0) NOT BETWEEN 1 AND 160 OR coalesce(length(btrim(p_data->>'message')),0) NOT BETWEEN 1 AND 5000 OR at_time>now()+interval '365 days' OR at_time<now()-interval '5 minutes' THEN RAISE EXCEPTION 'Enter a title, message and valid publication time';END IF;
   IF selection='live' THEN SELECT array_agg(tenant_id ORDER BY tenant_id) INTO targets FROM ironvault_private.gym_subscriptions WHERE NOT is_test AND owner_id IS NOT NULL;
   ELSIF selection='selected' THEN SELECT array_agg(value ORDER BY value) INTO targets FROM jsonb_array_elements_text(p_data->'tenants');
   ELSE RAISE EXCEPTION 'Choose all Live gyms or selected gyms';END IF;
   IF coalesce(cardinality(targets),0)=0 OR EXISTS(SELECT 1 FROM unnest(targets) x WHERE NOT EXISTS(SELECT 1 FROM ironvault_private.gym_subscriptions WHERE tenant_id=x AND owner_id IS NOT NULL)) THEN RAISE EXCEPTION 'Choose existing gyms with registered owners';END IF;
   INSERT INTO ironvault_private.provider_announcements(id,title,message,published_by,audience,requested_targets,available_at) VALUES(ann,btrim(p_data->>'title'),btrim(p_data->>'message'),auth.uid(),selection,coalesce(p_data->'tenants','[]'::jsonb),at_time);
   FOR r IN SELECT * FROM ironvault_private.gym_subscriptions WHERE tenant_id=ANY(targets) AND owner_id IS NOT NULL LOOP
    INSERT INTO ironvault_private.provider_announcement_targets VALUES(ann,r.tenant_id,r.owner_id);
    INSERT INTO ironvault_private.owner_notifications(tenant_id,owner_id,notice_key,title,message,available_at,destination) VALUES(r.tenant_id,r.owner_id,'announcement:'||ann,btrim(p_data->>'title'),btrim(p_data->>'message'),at_time,'announcement');
   END LOOP;
  END IF;
 ELSIF p_action='cleanup_check' THEN
  IF EXISTS(SELECT 1 FROM public.owners g LEFT JOIN ironvault_private.gym_subscriptions s ON s.tenant_id=g.id WHERE s.is_test IS DISTINCT FROM true) THEN RAISE EXCEPTION 'Test PDF cleanup requires every existing gym to remain Test';END IF;
  RETURN jsonb_build_object('allowed',true,'bucket','iv-service-documents');
 ELSIF p_action<>'get' THEN RAISE EXCEPTION 'Invalid console action';END IF;
 RETURN jsonb_build_object('pdf_cleanup_pending',EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE document_format='pdf') OR EXISTS(SELECT 1 FROM storage.buckets WHERE id='iv-service-documents'),'tenants',coalesce((SELECT jsonb_agg(jsonb_build_object('tenant_id',s.tenant_id,'name',g.gym_name,'is_test',s.is_test,'owner_name',g.owner_name,'state',ironvault_private.subscription_state(s.tenant_id)) ORDER BY g.gym_name) FROM ironvault_private.gym_subscriptions s JOIN public.owners g ON g.id=s.tenant_id),'[]'::jsonb),'notices',coalesce((SELECT jsonb_agg(to_jsonb(n)||jsonb_build_object('read_at',rd.read_at) ORDER BY available_at DESC) FROM ironvault_private.provider_notices n LEFT JOIN ironvault_private.provider_notice_reads rd ON rd.notice_key=n.notice_key AND rd.user_id=auth.uid() WHERE available_at<=now()),'[]'::jsonb),'announcements',coalesce((SELECT jsonb_agg(to_jsonb(a)||jsonb_build_object('delivery',coalesce((SELECT jsonb_agg(jsonb_build_object('tenant_id',t.tenant_id,'owner_id',t.owner_id,'read_at',n.read_at)) FROM ironvault_private.provider_announcement_targets t LEFT JOIN ironvault_private.owner_notifications n ON n.tenant_id=t.tenant_id AND n.notice_key='announcement:'||a.id AND n.owner_id=t.owner_id WHERE t.announcement_id=a.id),'[]'::jsonb)) ORDER BY published_at DESC) FROM ironvault_private.provider_announcements a),'[]'::jsonb),'live_totals',jsonb_build_object('gyms',(SELECT count(*) FROM ironvault_private.gym_subscriptions WHERE NOT is_test),'members',(SELECT count(*) FROM public.members m JOIN ironvault_private.gym_subscriptions s ON s.tenant_id=m.tenant_id WHERE NOT s.is_test),'approved_subscription_amount',(SELECT coalesce(sum(p.amount),0) FROM ironvault_private.subscription_periods p JOIN ironvault_private.gym_subscriptions s ON s.tenant_id=p.tenant_id WHERE NOT s.is_test AND p.kind='paid')));
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_service_documents(p_action text,p_data jsonb DEFAULT NULL,p_effective date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s ironvault_private.service_settings%ROWTYPE;v ironvault_private.service_versions%ROWTYPE;k text;clean jsonb:='{}';rendered jsonb;effective date:=coalesce(p_effective,ironvault_private.subscription_today());published_version_id uuid; notice integer; previous jsonb; request_uuid uuid; source_uuid uuid; delta text:='';
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Super Admin required' USING ERRCODE='42501'; END IF;
 SELECT * INTO STRICT s FROM ironvault_private.service_settings settings_row WHERE settings_row.id=true FOR UPDATE;
 IF p_action='publish' THEN
  request_uuid:=(p_data->>'__request_id')::uuid;source_uuid:=(p_data->>'__revision')::uuid;
  IF request_uuid IS NULL OR p_data->>'__reviewed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Review and confirm the exact documents first';END IF;
  SELECT id INTO published_version_id FROM ironvault_private.service_versions WHERE publication_request=request_uuid AND source_draft=source_uuid;
  IF FOUND THEN
   IF NOT EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE id=published_version_id AND effective_date=effective AND data=(p_data-'__request_id'-'__revision'-'__reviewed')) THEN RAISE EXCEPTION 'Publication retry changed. Reopen the saved draft';END IF;
   RETURN jsonb_build_object('published_id',published_version_id,'revision',s.revision);END IF;
 END IF;
 IF p_action IN ('save','publish') AND s.revision IS DISTINCT FROM (p_data->>'__revision')::uuid THEN RAISE EXCEPTION 'Draft changed in another session. Reopen before saving';END IF;
 SELECT greatest(30,coalesce(max((policy->>'price_notice_days')::integer),30)) INTO notice FROM ironvault_private.subscription_periods;
 SELECT greatest(notice,coalesce(max((v2.data->>'price_notice_days')::integer),30)) INTO notice FROM ironvault_private.service_versions v2 WHERE NOT v2.retired;
 IF p_action NOT IN ('get','save','preview','publish') THEN RAISE EXCEPTION 'Invalid service document action'; END IF;
 IF p_action<>'get' THEN
  IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>150000 THEN RAISE EXCEPTION 'Invalid service details'; END IF;
  FOR k IN SELECT jsonb_object_keys(s.draft) LOOP
   clean:=clean||jsonb_build_object(k,coalesce(p_data->k,s.draft->k));
   IF length(clean->>k)>50000 THEN RAISE EXCEPTION 'Field too long: %',k; END IF;
  END LOOP;
  IF (clean->>'dashboard_price')::numeric<=0 OR (clean->>'portal_price')::numeric<(clean->>'dashboard_price')::numeric OR (clean->>'portal_price')::numeric>1000000 OR (clean->>'dashboard_price')::numeric<>round((clean->>'dashboard_price')::numeric,2) OR (clean->>'portal_price')::numeric<>round((clean->>'portal_price')::numeric,2) THEN RAISE EXCEPTION 'Invalid plan prices'; END IF;
  FOREACH k IN ARRAY ARRAY['pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days'] LOOP
   IF (clean->>k)::integer<(CASE WHEN k='grace_days' THEN 0 ELSE 1 END) OR (clean->>k)::integer>3650 OR (clean->>k)::numeric<>(clean->>k)::integer THEN RAISE EXCEPTION 'Invalid day setting: %',k; END IF;
  END LOOP;
  IF (clean->>'grace_days')::integer>30 OR (clean->>'price_notice_days')::integer<30 OR (clean->>'export_days')::integer>(clean->>'retention_days')::integer THEN RAISE EXCEPTION 'Grace must be at most 30 days, price notice at least 30 days, export no longer than retention'; END IF;
  IF p_action IN ('save','publish') THEN UPDATE ironvault_private.service_settings SET draft=clean,revision=gen_random_uuid(),updated_at=clock_timestamp() WHERE service_settings.id=true; END IF;
  rendered:=ironvault_private.service_render(clean);
 END IF;
 IF p_action='publish' THEN
  FOR k IN SELECT jsonb_object_keys(clean) LOOP IF k<>'contract_extra' AND btrim(coalesce(clean->>k,''))='' THEN RAISE EXCEPTION 'Complete field before publication: %',k; END IF; END LOOP;
  FOREACH k IN ARRAY ARRAY['support_email','privacy_email'] LOOP IF clean->>k !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid contact email'; END IF; END LOOP;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text') AND effective<ironvault_private.subscription_today()+notice THEN RAISE EXCEPTION 'New service terms require 30 days advance notice'; END IF;
  IF effective<ironvault_private.subscription_today() THEN RAISE EXCEPTION 'Cannot backdate publication'; END IF;
  SELECT * INTO v FROM ironvault_private.service_versions version_row WHERE version_row.id=ironvault_private.service_current();
  IF v.id IS NOT NULL AND (v.data->>'dashboard_price' IS DISTINCT FROM clean->>'dashboard_price' OR v.data->>'portal_price' IS DISTINCT FROM clean->>'portal_price') AND effective<ironvault_private.subscription_today()+greatest(30,(v.data->>'price_notice_days')::integer) THEN RAISE EXCEPTION 'Price changes require the published advance notice period'; END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text' AND effective_date>=effective) THEN RAISE EXCEPTION 'A publication already exists on or after this date; choose a later effective date'; END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text' AND lower(version_label)=lower(clean->>'document_version')) THEN RAISE EXCEPTION 'Use a new version label';END IF;
  INSERT INTO ironvault_private.service_versions(data,terms_text,privacy_text,dpa_text,effective_date,published_by,version_label,publication_request,source_draft) VALUES(clean,rendered->>'terms_text',rendered->>'privacy_text',rendered->>'dpa_text',effective,auth.uid(),clean->>'document_version',request_uuid,source_uuid) RETURNING service_versions.id INTO published_version_id;
  FOREACH k IN ARRAY ARRAY['dashboard_price','portal_price','pilot_days','paid_days','grace_days','price_notice_days','export_days','retention_days'] LOOP delta:=delta||(CASE k WHEN 'dashboard_price' THEN 'Dashboard Only PHP' WHEN 'portal_price' THEN 'Dashboard + Member Portal total PHP' WHEN 'pilot_days' THEN 'Pilot days' WHEN 'paid_days' THEN 'Paid days' WHEN 'grace_days' THEN 'Grace days' WHEN 'price_notice_days' THEN 'Advance notice days' WHEN 'export_days' THEN 'Export days' ELSE 'Retention review days' END)||': '||coalesce(v.data->>k,'not previously published')||' → '||(clean->>k)||'; ';END LOOP;
  PERFORM ironvault_private.subscription_notice(g.tenant_id,'documents:'||published_version_id,'Service documents and settings update','Effective '||effective||'. '||delta||'Review Agreements. You may continue, change plan or decline renewal. Approved periods retain their prices and dates.') FROM ironvault_private.gym_subscriptions g;
  PERFORM ironvault_private.subscription_notice(g.tenant_id,'documents-effective:'||published_version_id,'Service documents are now effective','Review Agreements for any required acceptance. Approved periods retain their prices and dates.',effective) FROM ironvault_private.gym_subscriptions g;
 END IF;
 RETURN jsonb_build_object('revision',(SELECT revision FROM ironvault_private.service_settings WHERE id=true),'minimum_effective_date',CASE WHEN EXISTS(SELECT 1 FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text') THEN greatest(ironvault_private.subscription_today()+notice,(SELECT max(effective_date)+1 FROM ironvault_private.service_versions WHERE NOT retired AND document_format='text')) ELSE ironvault_private.subscription_today() END,'draft',CASE WHEN p_action='get' THEN s.draft ELSE clean END,'preview',rendered,'published_id',published_version_id,'versions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY effective_date DESC,published_at DESC) FROM ironvault_private.service_versions x WHERE NOT x.retired AND x.document_format='text'),'[]'::jsonb));
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_subscription_access(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT ironvault_private.subscription_super() AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND tenant_id=p_tenant AND enabled AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Gym access denied' USING ERRCODE='42501'; END IF;
 RETURN ironvault_private.subscription_state(p_tenant)||jsonb_build_object('is_owner',ironvault_private.subscription_owner(p_tenant),'super',ironvault_private.subscription_super(),'is_test',(SELECT is_test FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant));
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.tenant_purge_summary(p_tenant text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('tenant_id',g.id,'gym_name',g.gym_name,
 'is_test',(SELECT is_test FROM ironvault_private.gym_subscriptions WHERE tenant_id=g.id),
 'subscription_periods',(SELECT count(*) FROM ironvault_private.subscription_periods WHERE tenant_id=g.id),
 'subscription_requests',(SELECT count(*) FROM ironvault_private.subscription_requests WHERE tenant_id=g.id),
 'service_acceptances',(SELECT count(*) FROM ironvault_private.service_acceptances WHERE tenant_id=g.id),
 'notifications',(SELECT count(*) FROM ironvault_private.owner_notifications WHERE tenant_id=g.id),
 'members',(SELECT count(*) FROM public.members WHERE tenant_id=g.id),
 'accounts',(SELECT count(*) FROM ironvault_private.branch_accounts WHERE tenant_id=g.id),
 'transactions',(SELECT count(*) FROM public.iv_financial_transactions WHERE tenant_id=g.id),
 'attendance',(SELECT count(*) FROM public.iv_attendance_logs WHERE tenant_id=g.id),
 'activity',(SELECT count(*) FROM public.iv_activity_logs WHERE tenant_id=g.id),
 'sessions',(SELECT count(*) FROM public.iv_staff_sessions WHERE tenant_id=g.id),
 'wallet_credit',(SELECT coalesce(sum(wallet_balance),0)::text FROM public.members WHERE tenant_id=g.id),
 'wallet_accounts',(SELECT count(*) FROM public.members WHERE tenant_id=g.id AND coalesce(wallet_balance,0)<>0))
 FROM public.owners g WHERE g.id=p_tenant;
$fn$;
-- Snapshot pre-migration text acceptances before any tenant profile can be changed.
UPDATE ironvault_private.service_acceptances a SET accepted_documents=jsonb_build_object('id',v.id,'version_label',v.version_label,'effective_date',v.effective_date,'document_format','text','data',v.data,'tenant',a.gym_snapshot||jsonb_build_object('owner',a.owner_snapshot),'terms_text','Gym: '||coalesce(a.gym_snapshot->>'name','')||E'\nOwner: '||coalesce(a.owner_snapshot->>'name','')||E'\n\n'||v.terms_text,'privacy_text',v.privacy_text,'dpa_text',v.dpa_text) FROM ironvault_private.service_versions v WHERE a.version_id=v.id AND v.document_format='text' AND a.accepted_documents IS NULL;
-- Seed existing pending work once; no live gym identities are exposed to other owners.
INSERT INTO ironvault_private.provider_notices(notice_key,tenant_id,title,message) SELECT 'request:'||id,tenant_id,'Subscription request','An owner-confirmed request awaits review.' FROM ironvault_private.subscription_requests WHERE approved_at IS NULL AND cancelled_at IS NULL ON CONFLICT DO NOTHING;
DO $acl$ DECLARE tab text;sig text;BEGIN
 FOREACH tab IN ARRAY ARRAY['provider_notices','provider_notice_reads','provider_announcements','provider_announcement_targets'] LOOP EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',tab);EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',tab);EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',tab);END LOOP;
 FOREACH sig IN ARRAY ARRAY['ironvault_private.tenant_service_documents(text,uuid)','public.iv_subscription_portal(text,text,jsonb)','public.iv_provider_console(text,jsonb)','public.iv_service_documents(text,jsonb,date)'] LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',sig);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',sig);END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_subscription_portal(text,text,jsonb),public.iv_provider_console(text,jsonb),public.iv_service_documents(text,jsonb,date) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
