-- MANUAL ONLY after 039. Add receipt evidence to the existing owner agreement workflow.
-- No documents, acceptances, subscriptions or operational records are deleted or activated.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.service_acceptances') IS NULL OR to_regprocedure('ironvault_private.tenant_service_documents(text,uuid)') IS NULL THEN RAISE EXCEPTION 'Apply migrations through 039 first';END IF;
 IF to_regprocedure('ironvault_private.subscription_portal_040_base(text,text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION '040 already installed; do not reapply';END IF;
END $guard$;
ALTER TABLE ironvault_private.service_acceptances ADD COLUMN agreement_type text;
ALTER TABLE ironvault_private.service_acceptances ADD COLUMN document_versions jsonb;
ALTER TABLE ironvault_private.service_acceptances ADD COLUMN acceptance_method text;
ALTER TABLE ironvault_private.service_acceptances ADD COLUMN acknowledgment_text text;
CREATE FUNCTION ironvault_private.owner_agreement_document_refs(p_version uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('terms_of_use',jsonb_build_object('version_id',v.id,'version_label',coalesce(v.version_label,v.data->>'document_version',v.id::text)),'privacy_notice',jsonb_build_object('version_id',v.id,'version_label',coalesce(v.version_label,v.data->>'document_version',v.id::text)),'data_processing_agreement',jsonb_build_object('version_id',v.id,'version_label',coalesce(v.version_label,v.data->>'document_version',v.id::text)),'free_pilot_conditions',jsonb_build_object('version_id',v.id,'version_label',coalesce(v.version_label,v.data->>'document_version',v.id::text),'incorporated_into','terms_of_use','section','Free Pilot'))
 FROM ironvault_private.service_versions v WHERE v.id=p_version AND NOT v.retired AND v.document_format='text';
$fn$;
-- Equivalent old receipts stay valid. Do not falsely record the new checkbox text or a new acceptance date.
UPDATE ironvault_private.service_acceptances a SET agreement_type='gym_service_bundle',document_versions=ironvault_private.owner_agreement_document_refs(a.version_id),acceptance_method='legacy_recorded_owner_acceptance'
FROM ironvault_private.service_versions v WHERE a.version_id=v.id AND a.accepted_documents IS NOT NULL AND NOT v.retired AND v.document_format='text';
CREATE FUNCTION ironvault_private.owner_agreement_valid(p_tenant text,p_owner uuid,p_version uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances a JOIN ironvault_private.service_versions v ON v.id=a.version_id WHERE a.tenant_id=p_tenant AND a.owner_id=p_owner AND a.version_id=p_version AND a.accepted_at IS NOT NULL AND a.accepted_documents->>'id'=v.id::text AND NOT v.retired AND v.document_format='text' AND a.document_versions=ironvault_private.owner_agreement_document_refs(v.id) AND
 ((a.acceptance_method='legacy_recorded_owner_acceptance' AND a.agreement_type='gym_service_bundle') OR
 (a.acceptance_method='dashboard_checkbox' AND a.agreement_type='gym_owner_service_and_pilot' AND a.acknowledgment_text='I confirm that I am authorized to represent this Gym, have reviewed the documents listed above, and agree to the applicable Terms of Use, Data Processing Agreement, and Free Pilot Conditions. I acknowledge receipt of the Privacy Notice.')));
$fn$;
ALTER FUNCTION public.iv_subscription_portal(text,text,jsonb) RENAME TO subscription_portal_040_base;
ALTER FUNCTION public.subscription_portal_040_base(text,text,jsonb) SET SCHEMA ironvault_private;
REVOKE ALL ON FUNCTION ironvault_private.subscription_portal_040_base(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.iv_subscription_portal(p_tenant text,p_action text DEFAULT 'get',p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE subscription ironvault_private.gym_subscriptions%ROWTYPE;bundle ironvault_private.service_versions%ROWTYPE;receipt ironvault_private.service_acceptances%ROWTYPE;output jsonb;owner boolean;provider boolean;acknowledgment constant text:='I confirm that I am authorized to represent this Gym, have reviewed the documents listed above, and agree to the applicable Terms of Use, Data Processing Agreement, and Free Pilot Conditions. I acknowledge receipt of the Privacy Notice.';
BEGIN
 SELECT * INTO STRICT subscription FROM ironvault_private.gym_subscriptions WHERE tenant_id=p_tenant FOR UPDATE;
 owner:=ironvault_private.subscription_owner(p_tenant);provider:=ironvault_private.subscription_super();
 IF NOT owner AND NOT provider THEN RAISE EXCEPTION 'Registered owner or Provider required' USING ERRCODE='42501';END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>200000 THEN RAISE EXCEPTION 'Invalid subscription request';END IF;
 IF p_action='accept' THEN
  IF NOT owner THEN RAISE EXCEPTION 'Only the registered owner account may accept on behalf of this Gym' USING ERRCODE='42501';END IF;
  SELECT * INTO STRICT bundle FROM ironvault_private.service_versions WHERE id=(p_data->>'version_id')::uuid AND NOT retired AND document_format='text';
  SELECT * INTO receipt FROM ironvault_private.service_acceptances WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND version_id=bundle.id;
  IF FOUND THEN
   IF NOT ironvault_private.owner_agreement_valid(p_tenant,auth.uid(),bundle.id) THEN RAISE EXCEPTION 'Existing acceptance evidence needs Provider review; no history was overwritten';END IF;
   RETURN ironvault_private.subscription_portal_040_base(p_tenant,'get','{}');
  END IF;
  IF p_data->>'accepted' IS DISTINCT FROM 'true' OR p_data->>'acknowledgment_text' IS DISTINCT FROM acknowledgment THEN RAISE EXCEPTION 'Review the Service Agreement and confirm the acknowledgment before continuing';END IF;
  IF btrim(coalesce(bundle.terms_text,''))='' OR btrim(coalesce(bundle.privacy_text,''))='' OR btrim(coalesce(bundle.dpa_text,''))='' THEN RAISE EXCEPTION 'The Provider must publish all service documents before acceptance';END IF;
  IF bundle.terms_text !~* E'(^|[\r\n])[[:space:]#]*([0-9]+[.)][[:space:]]*)?FREE[[:space:]]+PILOT' THEN RAISE EXCEPTION 'The published Terms need an identifiable Free Pilot section. Contact the Provider';END IF;
  -- The existing implementation verifies the exact rendered document hash and current gym details.
  output:=ironvault_private.subscription_portal_040_base(p_tenant,'accept',p_data);
  UPDATE ironvault_private.service_acceptances SET agreement_type='gym_owner_service_and_pilot',document_versions=ironvault_private.owner_agreement_document_refs(bundle.id),acceptance_method='dashboard_checkbox',acknowledgment_text=acknowledgment
  WHERE tenant_id=p_tenant AND owner_id=auth.uid() AND version_id=bundle.id AND acceptance_method IS NULL;
  IF NOT ironvault_private.owner_agreement_valid(p_tenant,auth.uid(),bundle.id) THEN RAISE EXCEPTION 'Acceptance could not be recorded';END IF;
  RETURN ironvault_private.subscription_portal_040_base(p_tenant,'get','{}');
 ELSIF p_action='activate_pilot' THEN
  IF NOT provider THEN RAISE EXCEPTION 'Service Provider approval required' USING ERRCODE='42501';END IF;
  -- Preserve safe retries of an already completed activation; new Terms never revoke existing access.
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.subscription_periods WHERE id=(p_data->>'request_id')::uuid AND tenant_id=p_tenant AND kind='pilot') THEN
   IF NOT ironvault_private.owner_agreement_valid(p_tenant,subscription.owner_id,ironvault_private.service_current()) THEN RAISE EXCEPTION 'Registered owner must accept the current Service Agreement before pilot activation';END IF;
  END IF;
 END IF;
 -- Quote confirmation, paid feature choices and payment approvals remain separate, unchanged actions.
 output:=ironvault_private.subscription_portal_040_base(p_tenant,p_action,p_data);
 RETURN output;
END $fn$;
DO $acl$ DECLARE sig text;BEGIN
 FOREACH sig IN ARRAY ARRAY['ironvault_private.owner_agreement_document_refs(uuid)','ironvault_private.owner_agreement_valid(text,uuid,uuid)','public.iv_subscription_portal(text,text,jsonb)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',sig);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',sig);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_subscription_portal(text,text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
