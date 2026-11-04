-- MANUAL ONLY after 030. Correct full templates for NEW publications; preserve existing versions/receipts.
BEGIN;
CREATE OR REPLACE FUNCTION ironvault_private.fill_legal_tokens_v2(template text,fields jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result text:=''; rest text:=template; token text; start_at integer; end_at integer;
BEGIN
 LOOP
  start_at:=strpos(rest,'{{');IF start_at=0 THEN RETURN result||rest; END IF;
  end_at:=strpos(substr(rest,start_at+2),'}}');IF end_at=0 THEN RETURN result||rest; END IF;
  token:=substr(rest,start_at+2,end_at-1);
  result:=result||substr(rest,1,start_at-1)||coalesce(fields->>token,'');
  rest:=substr(rest,start_at+end_at+3);
 END LOOP;
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.render_full_legal_v2(g jsonb,p jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE terms text:=g->>'_terms_template'; privacy text:=g->>'_privacy_template'; values_map jsonb; item record;
BEGIN
 values_map:=g||jsonb_build_object('gym_identity',coalesce(g->>'name','')||', '||coalesce(g->>'address',''),
 'platform_identity',coalesce(p->>'name','')||', '||coalesce(p->>'address',''),'platform_name',coalesce(p->>'name',''),
 'gym_contact',concat_ws(' / ',nullif(g->>'public_email',''),nullif(g->>'phone','')),
 'gym_phone_address',concat_ws(' / ',nullif(g->>'phone',''),nullif(g->>'address','')),
 'privacy_contact',concat_ws(', ',nullif(g->>'privacy_name',''),nullif(g->>'privacy_email',''),nullif(g->>'address','')),
 'providers',coalesce(p->>'providers',''),'overseas_info',coalesce(p->>'overseas_info',''),
 'age_policy',coalesce(nullif(g->>'age_policy',''),'Ask the gym for its minimum-age and parent/guardian requirements.'));
 IF coalesce(g->>'refund_policy','')='' THEN terms:=replace(terms,E'**Gym policy:** {{refund_policy}}\n\n',''); END IF;
 -- Replace only tokens in the original template, never tokens contained in user-entered values.
 terms:=ironvault_private.fill_legal_tokens_v2(terms,values_map);
 privacy:=ironvault_private.fill_legal_tokens_v2(privacy,values_map);
 RETURN jsonb_build_object('terms_text',terms,'privacy_text',privacy);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_legal_manage(p_action text,p_tenant text DEFAULT NULL,p_data jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE scope_key text:=coalesce(p_tenant,'platform'); setting ironvault_private.legal_settings%ROWTYPE;
 clean jsonb:='{}'; document_data jsonb; key text; value text; version_id uuid; terms text; privacy text; entry record; provider_data jsonb; rendered jsonb;
BEGIN
 IF NOT ironvault_private.can_manage_legal(p_tenant) THEN RAISE EXCEPTION 'Legal settings access denied' USING ERRCODE='42501'; END IF;
 IF p_action NOT IN ('get','save','preview','publish') THEN RAISE EXCEPTION 'Invalid legal action'; END IF;
 IF p_tenant IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF p_action<>'get' THEN
  IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>50000 THEN RAISE EXCEPTION 'Invalid legal details'; END IF;
  FOREACH key IN ARRAY ARRAY['name','address','public_email','phone','privacy_email','retention','providers','membership_policy','refund_policy','age_policy','terms_extra','privacy_extra','effective_date','notice_version','privacy_name','notification_method','overseas_info','retention_profile','retention_attendance','retention_financial','retention_security','retention_backups'] LOOP
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
  FOREACH key IN ARRAY ARRAY['name','address','public_email','privacy_email'] LOOP
   IF coalesce(document_data->>key,'')='' THEN RAISE EXCEPTION 'Complete the name, address and public/privacy email rows'; END IF;
  END LOOP;
  FOREACH key IN ARRAY ARRAY['public_email','privacy_email'] LOOP
   IF (document_data->>key) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Enter valid email addresses'; END IF;
  END LOOP;
  IF p_tenant IS NULL THEN
   IF coalesce(document_data->>'providers','')='' OR coalesce(document_data->>'overseas_info','')='' THEN RAISE EXCEPTION 'Complete provider and overseas-processing details'; END IF;
  ELSE
   FOREACH key IN ARRAY ARRAY['effective_date','notice_version','privacy_name','notification_method','retention_profile','retention_attendance','retention_financial','retention_security','retention_backups'] LOOP
    IF coalesce(document_data->>key,'')='' THEN RAISE EXCEPTION 'Complete the required document detail rows'; END IF;
   END LOOP;
   IF document_data->>'effective_date' !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Choose an effective date'; END IF;
   PERFORM (document_data->>'effective_date')::date;
  END IF;
  END IF;
  IF p_tenant IS NULL THEN
   terms:=format('Iron Vault operator details

Legal operator: %s
Address: %s
Support contact: %s
Phone: %s',document_data->>'name',document_data->>'address',document_data->>'public_email',document_data->>'phone');
   privacy:=format('Iron Vault privacy details

Privacy contact: %s
Providers and locations:
%s

Overseas processing:
%s',document_data->>'privacy_email',document_data->>'providers',document_data->>'overseas_info');
  ELSE
   document_data:=document_data||jsonb_build_object('_template_format',2,'_terms_template',$terms$**Effective date:** {{effective_date}}  
**Gym:** {{gym_identity}}  
**Platform provider:** {{platform_identity}}  
**Contact:** {{gym_contact}}

### 1. About the service

The Iron Vault member portal allows participating gym members to manage their profiles, view membership and account-credit information, receive announcements, and generate QR passes where available.

Your gym provides the memberships, facilities, and training services. Iron Vault supplies the software used to manage these services.

### 2. Registration and account approval

Provide accurate registration details and keep them updated. Account registration does not automatically grant gym access. Your gym may require approval, payment, and an active membership before admitting you.

You must meet your gym’s age requirements. Where required, a parent or legal guardian must complete or authorize registration for a minor.

### 3. Account security

Keep your password and QR passes private. Do not share your account or use another member’s credentials or pass.

Notify your gym promptly if you suspect unauthorized access. You are responsible for activity you authorize through your account.

### 4. Memberships and entry

Membership prices, discounts, operating hours, and admission rules are set by your gym and should be disclosed before purchase.

Unless your gym expressly states otherwise:

- A day pass is valid only on its assigned date.
- A weekly pass covers seven consecutive calendar days, including its start date.
- The portal’s monthly pass covers **30 consecutive calendar days**, including its start date.
- Missed visits do not pause or extend a pass.
- Passes expire at midnight immediately after the final valid date, using **Asia/Manila time**.
- QR passes are personal and subject to daily entry restrictions.

A successful electronic check-in records entry; it does not override safety rules or other lawful gym admission requirements.

### 5. Payments and account credits

Payments and credit top-ups are handled through your gym’s authorized process. Review the price and membership details before confirming a purchase.

Account credits represent amounts recorded for use with your gym. They are not a bank deposit and do not earn interest. Transfer, withdrawal, expiry, and refund rules must be disclosed by your gym before funds are accepted.

Contact the gym promptly about an incorrect balance, purchase, or check-in. The gym will investigate using available payment and system records.

### 6. Cancellations and refunds

Your gym’s disclosed cancellation and refund policy applies, subject to Philippine law and your applicable consumer rights.

**Gym policy:** {{refund_policy}}

Nothing in these terms removes rights that cannot lawfully be waived.

### 7. Acceptable use

Do not:

- Submit fraudulent information or impersonate another person.
- Share, alter, sell, or attempt to reuse another person’s QR pass.
- Attempt to access another gym’s or member’s records.
- Disrupt the service, bypass access controls, or misuse personal information.

### 8. Availability and record corrections

The portal may be temporarily unavailable because of maintenance, connectivity problems, or service interruptions. Your gym may use manual procedures during an interruption.

Report suspected record errors to the gym. Corrections will be handled through authorized procedures; payment or attendance history may be retained where necessary.

### 9. Suspension and account closure

Your gym may restrict access for membership expiry, security concerns, misuse, or violations of its lawful rules. Where appropriate, the gym will explain the restriction and provide a way to raise a concern.

Closing or deactivating an account does not automatically erase financial, attendance, or other records that must or may lawfully be retained.

### 10. Privacy

Personal information is handled as described in the **Member Portal Privacy Notice**. Please read it before registering.

### 11. Responsibility and disputes

The gym is responsible for its facilities, staff, memberships, prices, and handling of payments. The platform provider is responsible for its software services under applicable law and its agreement with the gym.

Nothing in these terms excludes liability that cannot legally be excluded.

Raise concerns first with {{gym_contact}}. Unresolved matters may be referred to the appropriate Philippine authority or court. These terms are governed by Philippine law, without limiting mandatory consumer protections.

### 12. Changes to these terms

Material changes will be communicated through {{notification_method}}, with an effective date. Updated acceptance will be requested where necessary. Changes will not remove accrued rights or alter completed purchases retrospectively without a lawful basis.
$terms$,'_privacy_template',$privacy$**Effective date:** {{effective_date}}  
**Notice version:** {{notice_version}}  
**Gym:** {{name}}  
**Privacy contact:** {{privacy_contact}}

### 1. Who handles your information

{{name}} determines why and how member information is used for gym operations and acts as the **Personal Information Controller** for those activities.

{{platform_name}} processes member information on the gym’s instructions to provide the platform, acting as its **Personal Information Processor** for those activities.

Any processing the platform provider independently determines—for example, its own business billing or security obligations—must be described separately where applicable. The parties’ actual roles must match their written agreement and operating practices.

### 2. Information collected

Depending on the features you use, the portal may process:

- Name, email address, phone number, and assigned member ID.
- Account credentials and authentication records.
- Profile photo, if you choose to provide one.
- Membership plan, validity dates, and account status.
- Membership classifications and discount information.
- Recorded top-ups, purchases, account-credit balances, and related transaction history.
- Attendance dates, times, entry methods, and QR-pass records.
- Verification, account-recovery, support, and security records.

Do not upload medical records, identification documents, or other sensitive information unless the gym has explained the need and provided an appropriate collection process.

### 3. Why information is used

Information is used to:

- Register, identify, and administer members.
- Authenticate accounts and help recover access.
- Manage memberships, discounts, payments, and account credits.
- Validate entry and record attendance.
- Send service-related announcements and account messages.
- Prepare operational and financial reports.
- Investigate errors, misuse, disputes, and security incidents.
- Meet applicable legal and recordkeeping obligations.

### 4. Legal bases

Processing may be necessary to perform your membership agreement, comply with legal obligations, or pursue legitimate operational and security interests, subject to your rights.

Where consent is required, it will be requested for the specific purpose. Sensitive personal information requires an applicable basis under Philippine law; ordinary contractual necessity alone should not be assumed sufficient.

Optional promotional messages require a separate choice where applicable. Acknowledging this notice is not blanket consent to unrelated uses.

### 5. Who can access information

Access is limited according to authorized roles and operational needs:

- Your gym’s authorized owner and staff.
- Authorized platform administrators providing support, maintenance, and security.
- Contracted hosting, database, authentication, and email providers.
- Professional advisers or authorities where disclosure is necessary and lawful.

The platform is intended to restrict one gym from accessing another gym’s member records.

**Current service providers and relevant hosting locations:**  
{{providers}}

### 6. Overseas processing

Service providers may store or process information outside the Philippines. The gym and platform provider must apply appropriate contractual, organizational, and technical safeguards and remain accountable for applicable data-protection obligations.

**Relevant locations or information source:** {{overseas_info}}

### 7. Retention and deletion

Information is retained only for as long as necessary for its stated purpose and applicable obligations.

The applicable retention schedule is:

| Record category | Retention period or criterion |
|---|---|
| Member profile and account | {{retention_profile}} |
| Attendance history | {{retention_attendance}} |
| Financial and transaction records | {{retention_financial}} |
| Security and support records | {{retention_security}} |
| Backups and exported copies | {{retention_backups}} |

Deactivation does not immediately erase all records. Some records may be retained for legal obligations, accounting, security, or resolving disputes.

Deleting records from the active platform may not immediately remove copies in backups or independently held exports. Those copies must follow their applicable retention and disposal procedures.

### 8. Security

The service uses measures designed to protect information, including authentication and role-based access controls. No system can guarantee absolute security.

Keep credentials private, use a strong password, and report suspected unauthorized access to {{gym_contact}}.

### 9. Your rights

Subject to Philippine law and applicable exceptions, you may request information about processing, access to your data, correction, objection, erasure or blocking, and data portability where applicable. You may withdraw consent for processing that relies on consent.

Send requests to {{privacy_contact}}. Identity verification may be required. A request may be limited where retaining or processing information remains legally necessary; the reason should be explained.

You may also raise a complaint with the **Philippine National Privacy Commission** through its official channels at [privacy.gov.ph](https://privacy.gov.ph).

### 10. Required and optional information

Fields identified as required are needed for the stated registration or membership process. Without them, the gym may be unable to provide the relevant service.

Optional information, such as a profile photo where not required by the gym, may be omitted without affecting unrelated services.

### 11. Minors

{{age_policy}}

Any information about minors must be handled with appropriate safeguards and applicable authorization.

### 12. Changes and contact

Material changes to this notice will be communicated through {{notification_method}}.

For privacy questions or requests, contact:

**{{privacy_name}}**  
{{privacy_email}}  
{{gym_phone_address}}
$privacy$);
   SELECT v.data INTO provider_data FROM ironvault_private.legal_settings s JOIN ironvault_private.legal_versions v ON v.id=s.current_version WHERE s.scope='platform';
   IF provider_data IS NULL THEN
    IF p_action='publish' THEN RAISE EXCEPTION 'Super Admin must publish platform details first'; END IF;
    provider_data:=jsonb_build_object('name','Platform details not yet published','address','','providers','Platform details not yet published','overseas_info','Platform details not yet published');
   END IF;
   IF p_action='publish' AND coalesce(provider_data->>'overseas_info','')='' THEN RAISE EXCEPTION 'Super Admin must complete and republish platform provider details'; END IF;
   rendered:=ironvault_private.render_full_legal_v2(document_data,provider_data);
   terms:=rendered->>'terms_text';privacy:=rendered->>'privacy_text';
  END IF;
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
DECLARE tenant text; platform_id uuid; gym_id uuid; platform_record jsonb; gym_record jsonb; documents jsonb;
BEGIN
 SELECT id INTO tenant FROM public.owners WHERE token=p_token AND status='ACTIVE';
 IF tenant IS NULL THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 SELECT current_version INTO platform_id FROM ironvault_private.legal_settings WHERE scope='platform';
 SELECT current_version INTO gym_id FROM ironvault_private.legal_settings WHERE scope=tenant;
 platform_id:=coalesce(p_platform,platform_id);gym_id:=coalesce(p_gym,gym_id);
 SELECT to_jsonb(v)-'published_by' INTO platform_record FROM ironvault_private.legal_versions v WHERE id=platform_id AND scope='platform';
 SELECT to_jsonb(v)-'published_by' INTO gym_record FROM ironvault_private.legal_versions v WHERE id=gym_id AND scope=tenant;
 IF gym_record->'data'->>'_template_format'='2' AND platform_record IS NOT NULL THEN
  documents:=ironvault_private.render_full_legal_v2(gym_record->'data',platform_record->'data')||jsonb_build_object('id',gym_id,'published_at',gym_record->>'published_at');
 END IF;
 RETURN jsonb_build_object('platform',platform_record,'gym',gym_record,'documents',documents);
END $fn$;
ALTER FUNCTION ironvault_private.fill_legal_tokens_v2(text,jsonb) OWNER TO postgres;
ALTER FUNCTION ironvault_private.render_full_legal_v2(jsonb,jsonb) OWNER TO postgres;
ALTER FUNCTION public.iv_legal_manage(text,text,jsonb) OWNER TO postgres;
ALTER FUNCTION public.iv_legal_public(text,uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.fill_legal_tokens_v2(text,jsonb),ironvault_private.render_full_legal_v2(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_legal_manage(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_legal_manage(text,text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.iv_legal_public(text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_legal_public(text,uuid,uuid) TO anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
