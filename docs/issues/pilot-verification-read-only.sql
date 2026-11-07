-- MANUAL DIAGNOSTIC ONLY. Run in Supabase SQL Editor as the project administrator.
-- SELECT statements only: no financial RPC calls, writes or schema changes.
-- Returns code-presence indicators, not member data, credentials or full definitions.
-- These indicators support review; they do not replace concurrency execution tests.

WITH definitions AS (
 SELECT n.nspname AS schema_name,p.proname AS routine_name,
        pg_get_function_identity_arguments(p.oid) AS arguments,
        lower(pg_get_functiondef(p.oid)) AS definition
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prokind='f' AND (
  (n.nspname='public' AND p.proname IN ('iv_refunds','iv_financial_transaction')) OR
  (n.nspname='ironvault_private' AND p.proname IN ('refund_preview','financial_transaction_044_base'))
 )
)
SELECT schema_name,routine_name,arguments,
 CASE WHEN routine_name IN ('iv_refunds','financial_transaction_044_base','iv_financial_transaction')
      THEN position('pg_advisory_xact_lock' IN definition)>0 END AS has_advisory_lock,
 CASE WHEN routine_name IN ('financial_transaction_044_base','iv_financial_transaction')
      THEN position('return receipt.result' IN definition)>0 END AS returns_saved_payment_receipt,
 CASE WHEN routine_name='iv_refunds'
      THEN position('refund_preview(p_tenant,r.payload)' IN definition)>0 END AS rechecks_refund_at_approval,
 CASE WHEN routine_name='iv_refunds'
      THEN position('review_hash' IN definition)>0 END AS checks_review_hash,
 CASE WHEN routine_name='iv_refunds'
      THEN position('if r.status=''approved'' then return' IN definition)>0 END AS approved_retry_returns_existing,
 CASE WHEN routine_name='refund_preview'
      THEN position('amount exceeds the remaining eligible amount' IN definition)>0 END AS checks_remaining_eligibility,
 CASE WHEN routine_name='iv_financial_transaction'
      THEN position('financial_transaction_044_base' IN definition)>0 END AS delegates_to_044_base
FROM definitions ORDER BY schema_name,routine_name,arguments;

-- Required refund/reference objects. A NULL object_name means absent.
SELECT expected_name,to_regclass(expected_name)::text AS object_name
FROM (VALUES ('ironvault_private.financial_requests'),
             ('ironvault_private.refund_cases'),
             ('ironvault_private.transaction_references')) AS expected(expected_name);
