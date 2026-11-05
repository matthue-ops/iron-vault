-- MANUAL ONLY after 038 and explicit Storage cleanup. Removes ONLY test service PDFs/acceptances.
-- Approved subscription periods retain prices, policies and dates via retired non-PDF reference rows.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.provider_notices') IS NULL THEN RAISE EXCEPTION 'Apply 038 first';END IF;
 IF EXISTS(SELECT 1 FROM public.owners g LEFT JOIN ironvault_private.gym_subscriptions s ON s.tenant_id=g.id WHERE s.is_test IS DISTINCT FROM true) THEN RAISE EXCEPTION 'Stop: existing gyms must still be Test for this one-time cleanup';END IF;
 IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='iv-service-documents') THEN RAISE EXCEPTION 'Remove test PDF objects through Storage API first; never delete storage.objects directly';END IF;
END $guard$;
CREATE TEMP TABLE iv_test_pdf_replacements(old_id uuid PRIMARY KEY,new_id uuid NOT NULL) ON COMMIT DROP;
INSERT INTO iv_test_pdf_replacements SELECT id,gen_random_uuid() FROM ironvault_private.service_versions WHERE document_format='pdf';
INSERT INTO ironvault_private.service_versions(id,data,terms_text,privacy_text,dpa_text,effective_date,published_at,published_by,document_format,retired)
SELECT m.new_id,ironvault_private.service_parameters(v.data),'Test document reset. Numeric subscription policy retained; this is not a service agreement.','Test document reset.','Test document reset.',v.effective_date,v.published_at,v.published_by,'text',true FROM iv_test_pdf_replacements m JOIN ironvault_private.service_versions v ON v.id=m.old_id;
UPDATE ironvault_private.subscription_periods p SET version_id=m.new_id FROM iv_test_pdf_replacements m WHERE p.version_id=m.old_id;
UPDATE ironvault_private.subscription_requests r SET quote=jsonb_set(quote,'{version_id}',to_jsonb(m.new_id::text)),cancelled_at=CASE WHEN approved_at IS NULL THEN clock_timestamp() ELSE cancelled_at END FROM iv_test_pdf_replacements m WHERE r.quote->>'version_id'=m.old_id::text;
UPDATE ironvault_private.subscription_events e SET data=jsonb_set(data,'{quote,version_id}',to_jsonb(m.new_id::text)) FROM iv_test_pdf_replacements m WHERE e.data->'quote'->>'version_id'=m.old_id::text;
UPDATE ironvault_private.subscription_events e SET data=jsonb_set(data,'{previous_period,version_id}',to_jsonb(m.new_id::text)) FROM iv_test_pdf_replacements m WHERE e.data->'previous_period'->>'version_id'=m.old_id::text;
DELETE FROM ironvault_private.service_acceptances WHERE version_id IN (SELECT old_id FROM iv_test_pdf_replacements);
DELETE FROM ironvault_private.owner_notifications WHERE notice_key IN (SELECT 'documents:'||old_id FROM iv_test_pdf_replacements UNION ALL SELECT 'documents-effective:'||old_id FROM iv_test_pdf_replacements);
UPDATE ironvault_private.provider_notices n SET resolved_at=clock_timestamp() FROM ironvault_private.subscription_requests r WHERE r.cancelled_at IS NOT NULL AND n.notice_key='request:'||r.id;
DELETE FROM ironvault_private.service_versions WHERE id IN (SELECT old_id FROM iv_test_pdf_replacements);
DELETE FROM ironvault_private.service_pdf_draft;
DELETE FROM ironvault_private.service_pdf_files;
NOTIFY pgrst,'reload schema';
COMMIT;
