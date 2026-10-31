-- MANUAL REVIEW/EXECUTION ONLY. Not applied by the agent.
-- Classification: behavior-changing ACL hardening; no function-body or data changes.
-- Purpose: remove anonymous/PUBLIC execution from the eight reviewed definers;
-- also remove authenticated execution of trigger/event-trigger-only functions.
-- Preserve authenticated RPC/helper and service_role execution explicitly present in 3A.
-- Prerequisites: run 202611010001_restrict_table_truncate.sql; intended project and
-- database owner; definitions must match the supplied 3B snapshot exactly.
-- Fingerprints compare pg_get_functiondef text, including stored body line endings.
-- A mismatch safely aborts: obtain the changed function definition, do not bypass it.
-- Existing trigger attachments and managed auth tables are not altered. Trigger and
-- event-trigger functions are not ordinary callable RPCs; removing client EXECUTE
-- does not detach their existing triggers. Test the attached flows before release.
-- Repeating this file is safe while definitions and required retained grants match.
-- Recovery: any failure aborts this transaction; issue ROLLBACK before other SQL.
-- After commit, review a proven dependency before restoring any narrow privilege;
-- never blanket-GRANT PUBLIC/anon to make an error disappear. Retain 3A as ACL baseline.
-- This does not replace broad table policies or repair financial implementation.
BEGIN;
SET LOCAL search_path = pg_catalog;

DO $preflight$
DECLARE
  item record;
  function_oid oid;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('public.iv_can_access(text,text[])','dbfc8e22afae12695e67a0e0e3b172c4'),
    ('public.iv_checkin(text,text)','1254141edf8f9b51c63874d5a16bf2ef'),
    ('public.iv_log_event(text,text,text)','6277dda4611a2662780c5cc6bd52342e'),
    ('public.iv_member_auth_signup()','b5ad4dd3f49ee8d3e5c3e21862b8c763'),
    ('public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)','e09886b42457a094026b106a7b6af98e'),
    ('public.iv_staff_event(text,text)','4529039226d5609e3930d148dafac36a'),
    ('public.iv_topup(text,numeric,uuid)','08e84b7ad3f3a02c34ef083d62715469'),
    ('public.rls_auto_enable()','846ec2fbff751d24b890656d63c3a9bf')
  ) AS expected(signature, definition_md5) LOOP
    function_oid := to_regprocedure(item.signature)::oid;
    IF function_oid IS NULL THEN
      RAISE EXCEPTION 'Required reviewed function is missing: %', item.signature;
    END IF;
    IF md5(pg_get_functiondef(function_oid)) IS DISTINCT FROM item.definition_md5 THEN
      RAISE EXCEPTION 'Definition changed since inspection: %. Stop and review the new definition', item.signature;
    END IF;
    IF (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid=function_oid) <> 'postgres' THEN
      RAISE EXCEPTION 'Function ownership changed since inspection: %', item.signature;
    END IF;
  END LOOP;
END
$preflight$;

REVOKE EXECUTE ON FUNCTION public.iv_can_access(text,text[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.iv_checkin(text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.iv_log_event(text,text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.iv_member_auth_signup() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.iv_staff_event(text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.iv_topup(text,numeric,uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

DO $verify$
DECLARE
  item record;
  function_oid oid;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('public.iv_can_access(text,text[])',false),
    ('public.iv_checkin(text,text)',false),
    ('public.iv_log_event(text,text,text)',false),
    ('public.iv_member_auth_signup()',true),
    ('public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)',false),
    ('public.iv_staff_event(text,text)',false),
    ('public.iv_topup(text,numeric,uuid)',false),
    ('public.rls_auto_enable()',true)
  ) AS expected(signature, trigger_only) LOOP
    function_oid := to_regprocedure(item.signature)::oid;
    IF has_function_privilege('anon',function_oid,'EXECUTE') THEN
      RAISE EXCEPTION 'Anonymous execution remains inherited for %',item.signature;
    END IF;
    IF has_function_privilege('authenticated',function_oid,'EXECUTE') IS DISTINCT FROM (NOT item.trigger_only) THEN
      RAISE EXCEPTION 'Unexpected authenticated execution rights for %',item.signature;
    END IF;
    IF NOT has_function_privilege('service_role',function_oid,'EXECUTE') THEN
      RAISE EXCEPTION 'Required existing service-role execution is missing for %',item.signature;
    END IF;
  END LOOP;
END
$verify$;

COMMIT;

-- Verification: anon false for every row; authenticated true for ordinary
-- RPCs/helper and false for the two trigger-only functions; service_role true.
SELECT p.oid::regprocedure AS function_signature,
  has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
  has_function_privilege('service_role',p.oid,'EXECUTE') AS service_role_execute
FROM pg_proc p
WHERE p.oid IN (
  'public.iv_can_access(text,text[])'::regprocedure,
  'public.iv_checkin(text,text)'::regprocedure,
  'public.iv_log_event(text,text,text)'::regprocedure,
  'public.iv_member_auth_signup()'::regprocedure,
  'public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)'::regprocedure,
  'public.iv_staff_event(text,text)'::regprocedure,
  'public.iv_topup(text,numeric,uuid)'::regprocedure,
  'public.rls_auto_enable()'::regprocedure
)
ORDER BY p.oid::regprocedure::text;
