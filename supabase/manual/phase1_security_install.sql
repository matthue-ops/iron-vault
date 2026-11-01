-- IRON VAULT PHASE 1 — MANUAL SQL EDITOR INSTALL, GENERATED FILE.
-- No SQL has been executed by the agent. Review docs/security/phase1-cutover.md.
-- Intended for the inspected schema with NO earlier Phase 1 files applied.
-- If any migrations were already applied, use the remaining individual files;
-- do NOT bypass guards or rerun this complete package blindly.
-- ONE ATOMIC TRANSACTION: failure rolls back this entire package. If SQL Editor
-- reports an error, issue ROLLBACK before another command and return the error.
-- Existing Auth IDs/emails, balances, entitlements, role links and histories are
-- fingerprinted before/after; any difference aborts. Fingerprints are data-drift
-- checks only, not cryptographic authorization. No password hashes are selected.
-- No resets, existing-table/column deletion or account recreation.
-- OPTIONAL 004 is deliberately EXCLUDED: never escalate supabase_admin rights.
-- Its separate file remains available for approved creator-default hardening.
-- This file configures DATABASE objects only, not Edge Function deployment or
-- SMTP secrets. Publish the matching functions/app only after separate approval.
-- Generated deterministically: node scripts/build-manual-sql.cjs
BEGIN;
SET LOCAL search_path=pg_catalog;
CREATE TEMP TABLE iv_phase1_preservation ON COMMIT DROP AS
SELECT jsonb_build_object(
 'auth', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,email,email_confirmed_at)::text,'|' ORDER BY id),'')) FROM auth.users),
 'roles', (SELECT md5(coalesce(string_agg(jsonb_build_array(user_id,tenant_id,role,member_id)::text,'|' ORDER BY user_id),'')) FROM public.iv_user_roles),
 'members', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,tenant_id,wallet_balance,amount,plan,expiration_date,scans_used,last_scanned_date,status)::text,'|' ORDER BY id),'')) FROM public.members),
 'gyms', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,email,token,status,pricing)::text,'|' ORDER BY id),'')) FROM public.owners),
 'ledger', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_financial_transactions x),
 'attendance', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_attendance_logs x),
 'activity', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_activity_logs x),
 'sessions', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_staff_sessions x)
) AS snapshot;

-- ===== SOURCE 202611010001_restrict_table_truncate.sql SHA256 acd662f10e2de49e13e14e4000392ea462c5691f567c16fb391137c8769e3cf6 =====
-- MANUAL REVIEW/EXECUTION ONLY. Not applied by the agent.
-- Classification: behavior-changing privileges; no row, balance, history or schema reset.
-- Purpose: remove the unnecessary TRUNCATE grants confirmed by inspection 2A.
-- Prerequisites: intended project, existing public.owners/public.members and standard
-- API roles; execute as the authorized database owner. No application uses TRUNCATE.
-- Order: first of the two grant-only hardening migrations. Broader RLS remains pending.
-- Repeating this file is safe. If an assertion fails, ROLLBACK before other SQL.
-- Recovery: transaction failure changes nothing. After commit, investigate any
-- dependency rather than restoring broad destructive privileges to API roles.

SET LOCAL search_path = pg_catalog;

REVOKE TRUNCATE ON TABLE public.owners, public.members
FROM PUBLIC, anon, authenticated;

DO $verify$
DECLARE
  api_role text;
  relation_name text;
BEGIN
  FOREACH api_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH relation_name IN ARRAY ARRAY['public.owners','public.members'] LOOP
      IF has_table_privilege(api_role, relation_name, 'TRUNCATE') THEN
        RAISE EXCEPTION 'TRUNCATE still available to % on % through inherited grants; review memberships', api_role, relation_name;
      END IF;
    END LOOP;
  END LOOP;
END
$verify$;


-- Verification: all four rows must return false. This does not verify CRUD/RLS safety.
SELECT r.api_role, t.relation_name,
  has_table_privilege(r.api_role, t.relation_name, 'TRUNCATE') AS can_truncate
FROM (VALUES ('anon'),('authenticated')) AS r(api_role)
CROSS JOIN (VALUES ('public.owners'),('public.members')) AS t(relation_name);


-- ===== SOURCE 202611010002_restrict_function_execution.sql SHA256 80ffdca099cfc01d96a01c2c5f7d8cb5798dadd75353c3ac464110c5c767d752 =====
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


-- ===== SOURCE 202611010003_restrict_postgres_public_defaults.sql SHA256 8aeec3a7a2c28bbd92d28ca01fb3554d1f4c5792db98d4e2137ddea10a3e8841 =====
-- MANUAL REVIEW/EXECUTION ONLY; not applied by the agent.
-- Classification: behavior-changing future defaults; no existing objects/data changed.
-- Application migration-creator scope. Review current defaults before manual execution.
-- Scope: only postgres's future public-schema objects. No global defaults, other
-- schemas, role attributes, ownership, service_role or postgres grants are changed.
-- PostgreSQL per-schema REVOKE cannot remove the built-in GLOBAL PUBLIC EXECUTE
-- default for functions. Every application function still needs explicit per-object
-- REVOKE FROM PUBLIC/anon and deliberate authenticated/service_role GRANT in its
-- creation transaction. Do NOT claim that this file alone denies future RPC calls.
-- No blanket global default change is made to platform-owned creators.
-- Order: after 001/002 if approved. 004 is optional; 005-007 do not depend on it.
-- Recovery: transaction failure changes nothing; ROLLBACK after any error. After
-- commit, correct only a demonstrated missing grant; do not restore broad defaults.

SET LOCAL search_path = pg_catalog;
DO $authority$
BEGIN
 IF current_user <> 'postgres'
   AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user)
   AND NOT pg_has_role(current_user,'postgres','MEMBER') THEN
  RAISE EXCEPTION 'Executor cannot administer postgres defaults. Stop; do not escalate managed role privileges';
 END IF;
END
$authority$;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
 REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
 REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated;
DO $verify$
BEGIN
 IF EXISTS (
  SELECT 1 FROM pg_default_acl d
  JOIN pg_roles creator ON creator.oid=d.defaclrole
  JOIN pg_namespace n ON n.oid=d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
  WHERE creator.rolname='postgres' AND n.nspname='public'
   AND d.defaclobjtype IN ('f','r')
   AND (acl.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated'))
        OR (d.defaclobjtype='r' AND acl.grantee=0))
 ) THEN RAISE EXCEPTION 'Unexpected explicit public-schema API default grant remains'; END IF;
END
$verify$;

-- Review only the targeted explicit defaults. This does not account for the
-- built-in/global PUBLIC function EXECUTE default; per-object ACLs remain required.
SELECT r.rolname AS object_creator,n.nspname AS schema_name,
 d.defaclobjtype AS object_type,d.defaclacl
FROM pg_default_acl d JOIN pg_roles r ON r.oid=d.defaclrole
JOIN pg_namespace n ON n.oid=d.defaclnamespace
WHERE r.rolname='postgres' AND n.nspname='public' AND d.defaclobjtype IN ('f','r');


-- ===== SOURCE 202611010005_protect_role_and_history_grants.sql SHA256 ec7bdec3c6b89c3cb99cd13e84e2317f411e40e2665b8a0a4b6b9be7ebc54bc8 =====
-- MANUAL REVIEW/EXECUTION ONLY. Behavior-changing ACLs; no records are changed.
-- Requires reviewed M4 table ownership/RLS and existing postgres-owned definers.
-- Order: after 001/002; independent of optional creator-default files 003/004.
-- Existing authenticated RPC EXECUTE and service_role grants are not changed.
-- SECURITY DEFINER postgres functions keep their existing table-write authority.
-- Role and log tables currently have SELECT policies only; no legitimate direct
-- authenticated INSERT/UPDATE/DELETE path is enabled by the supplied policies.
-- Failure aborts this transaction; ROLLBACK. Do not restore unsafe blanket grants
-- as a compatibility workaround. Does not itself repair the two read policies.

SET LOCAL search_path = pg_catalog;
DO $preflight$
DECLARE item text; signature text; function_oid oid;
BEGIN
 FOREACH item IN ARRAY ARRAY['iv_user_roles','iv_financial_transactions',
   'iv_attendance_logs','iv_activity_logs','iv_staff_sessions'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname=item AND c.relkind='r'
    AND pg_get_userbyid(c.relowner)='postgres' AND c.relrowsecurity AND NOT c.relforcerowsecurity) THEN
   RAISE EXCEPTION 'Ownership/RLS differs from reviewed M4 for %',item;
  END IF;
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['public.iv_topup(text,numeric,uuid)',
   'public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)',
   'public.iv_checkin(text,text)','public.iv_log_event(text,text,text)',
   'public.iv_staff_event(text,text)','public.iv_member_auth_signup()'] LOOP
  function_oid:=to_regprocedure(signature)::oid;
  IF function_oid IS NULL OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=function_oid
    AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres') THEN
   RAISE EXCEPTION 'Expected postgres SECURITY DEFINER dependency missing/changed: %',signature;
  END IF;
 END LOOP;
END
$preflight$;
REVOKE ALL PRIVILEGES ON TABLE public.iv_user_roles,
 public.iv_financial_transactions, public.iv_attendance_logs,
 public.iv_activity_logs, public.iv_staff_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.iv_user_roles,
 public.iv_financial_transactions, public.iv_attendance_logs,
 public.iv_activity_logs, public.iv_staff_sessions TO authenticated;
-- Explicit column ACLs can survive a table-level REVOKE. Clear them as well.
DO $columns$
DECLARE item record;
BEGIN
 FOR item IN SELECT c.relname,a.attname FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='public' AND c.relname IN ('iv_user_roles','iv_financial_transactions',
   'iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
   AND a.attnum>0 AND NOT a.attisdropped LOOP
  EXECUTE format('REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON TABLE public.%I FROM PUBLIC, anon, authenticated',
   item.attname,item.attname,item.attname,item.attname,item.relname);
 END LOOP;
END
$columns$;
DO $verify$
DECLARE relation_name text; role_name text;
BEGIN
 FOREACH relation_name IN ARRAY ARRAY['public.iv_user_roles','public.iv_financial_transactions',
  'public.iv_attendance_logs','public.iv_activity_logs','public.iv_staff_sessions'] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(role_name,relation_name,'INSERT')
    OR has_table_privilege(role_name,relation_name,'UPDATE')
    OR has_table_privilege(role_name,relation_name,'DELETE')
    OR has_table_privilege(role_name,relation_name,'TRUNCATE')
    OR has_table_privilege(role_name,relation_name,'TRIGGER')
    OR has_any_column_privilege(role_name,relation_name,'INSERT')
    OR has_any_column_privilege(role_name,relation_name,'UPDATE')
    OR (role_name='anon' AND has_any_column_privilege(role_name,relation_name,'SELECT')) THEN
    RAISE EXCEPTION 'Unexpected inherited/direct write or anonymous read privilege for % on %',role_name,relation_name;
   END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated',relation_name,'SELECT') THEN
   RAISE EXCEPTION 'Authenticated RLS-filtered SELECT was not retained for %',relation_name;
  END IF;
 END LOOP;
END
$verify$;

-- Expected: authenticated SELECT only (subject to RLS), no anon SELECT/writes.
SELECT table_name,grantee,privilege_type FROM information_schema.table_privileges
WHERE table_schema='public' AND table_name IN ('iv_user_roles','iv_financial_transactions',
 'iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
 AND grantee IN ('PUBLIC','anon','authenticated') ORDER BY table_name,grantee,privilege_type;


-- ===== SOURCE 202611010006_staff_financial_report_permissions.sql SHA256 dbd03c0a7112b92cd291fc807dc210d251753580128b8215ee73d65fe1d5b313 =====
-- MANUAL REVIEW/EXECUTION ONLY; not applied by the agent.
-- Classification: additive objects + behavior-changing permission APIs; no existing
-- accounts, role bindings, balances, transaction or attendance rows are changed.
-- Requires 005 (role/history direct writes protected), reviewed iv_log_event,
-- standard Supabase auth.users UUID identity, and an unused ironvault_private schema.
-- 003/004 are independent; per-object ACLs below protect every new function even
-- when PostgreSQL's global PUBLIC EXECUTE default remains enabled.
-- Run once, then 007. Failure aborts all new objects; ROLLBACK before other SQL.
-- Do not overwrite an existing private schema/function to force this migration.
-- Owner FK for tenant_id is deferred until the owner's key/type constraints are
-- supplied; grant API validates the tenant and current staff role instead. The
-- read helper requires that role on every request, so stale grants never suffice.
-- No normal member deletion or destructive test reset is implemented here.

SET LOCAL search_path = pg_catalog;
DO $preflight$
DECLARE relation_name text; role_name text; signature text;
BEGIN
 IF to_regnamespace('ironvault_private') IS NOT NULL THEN
  RAISE EXCEPTION 'ironvault_private already exists; inspect it or confirm an earlier application, do not overwrite';
 END IF;
 FOREACH signature IN ARRAY ARRAY['public.iv_can_read_financial_reports(text)',
  'public.iv_set_staff_financial_report_access(text,uuid,boolean)',
  'public.iv_list_staff_financial_report_access(text)'] LOOP
  IF to_regprocedure(signature) IS NOT NULL THEN
   RAISE EXCEPTION 'New permission API name already exists: %. Inspect before continuing',signature;
  END IF;
 END LOOP;
 FOREACH relation_name IN ARRAY ARRAY['public.iv_user_roles','public.iv_activity_logs'] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(role_name,relation_name,'INSERT')
    OR has_table_privilege(role_name,relation_name,'UPDATE')
    OR has_table_privilege(role_name,relation_name,'DELETE')
    OR has_table_privilege(role_name,relation_name,'TRUNCATE')
    OR has_any_column_privilege(role_name,relation_name,'INSERT')
    OR has_any_column_privilege(role_name,relation_name,'UPDATE') THEN
    RAISE EXCEPTION '005 has not established role/audit write protection for % on %',role_name,relation_name;
   END IF;
  END LOOP;
 END LOOP;
 IF md5(pg_get_functiondef(to_regprocedure('public.iv_log_event(text,text,text)')::oid))
  IS DISTINCT FROM '6277dda4611a2662780c5cc6bd52342e' THEN
  RAISE EXCEPTION 'iv_log_event differs from the reviewed definition; inspect before using it for permission audit';
 END IF;
END
$preflight$;
CREATE SCHEMA ironvault_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA ironvault_private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA ironvault_private TO authenticated, service_role;
CREATE TABLE ironvault_private.staff_report_permissions (
 tenant_id text NOT NULL,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 permission text NOT NULL CHECK(permission='financial_reports_read'),
 granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 granted_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
 PRIMARY KEY(tenant_id,user_id,permission)
);
ALTER TABLE ironvault_private.staff_report_permissions OWNER TO postgres;
ALTER TABLE ironvault_private.staff_report_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ironvault_private.staff_report_permissions
 FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION ironvault_private.is_gym_administrator(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT EXISTS (
  SELECT 1 FROM public.iv_user_roles actor
  WHERE actor.user_id=auth.uid() AND (
   (actor.role='super_admin' AND actor.tenant_id IS NULL)
   OR (actor.role='owner' AND actor.tenant_id::text=p_tenant
    AND EXISTS(SELECT 1 FROM public.owners gym WHERE gym.id::text=p_tenant))
  )
 );
$function$;
CREATE FUNCTION ironvault_private.can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT ironvault_private.is_gym_administrator(p_tenant) OR EXISTS (
  SELECT 1 FROM public.iv_user_roles actor
  WHERE actor.user_id=auth.uid() AND actor.role='staff' AND actor.tenant_id::text=p_tenant
   AND EXISTS(SELECT 1 FROM public.owners gym WHERE gym.id::text=p_tenant)
   AND EXISTS(SELECT 1 FROM ironvault_private.staff_report_permissions permission
    WHERE permission.user_id=actor.user_id AND permission.tenant_id=p_tenant
     AND permission.permission='financial_reports_read')
 );
$function$;
CREATE FUNCTION public.iv_can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $function$
 SELECT ironvault_private.can_read_financial_reports(p_tenant);
$function$;
CREATE FUNCTION public.iv_set_staff_financial_report_access(p_tenant text,p_user uuid,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF p_user IS NULL OR p_enabled IS NULL OR nullif(btrim(p_tenant),'') IS NULL THEN
  RAISE EXCEPTION 'Tenant, target account and explicit permission state are required';
 END IF;
 IF NOT ironvault_private.is_gym_administrator(p_tenant) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 IF p_enabled THEN
  IF p_user=auth.uid() THEN RAISE EXCEPTION 'Cannot grant financial-report permission to yourself'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners gym WHERE gym.id::text=p_tenant)
   OR NOT EXISTS(SELECT 1 FROM public.iv_user_roles staff
    WHERE staff.user_id=p_user AND staff.tenant_id::text=p_tenant AND staff.role='staff') THEN
   RAISE EXCEPTION 'Target is not a current staff account in this gym';
  END IF;
  INSERT INTO ironvault_private.staff_report_permissions(tenant_id,user_id,permission,granted_by)
   VALUES(p_tenant,p_user,'financial_reports_read',auth.uid())
   ON CONFLICT(tenant_id,user_id,permission) DO UPDATE
    SET granted_by=auth.uid(),granted_at=pg_catalog.now();
 ELSE
  -- Revocation remains possible after the recipient's staff role is removed.
  DELETE FROM ironvault_private.staff_report_permissions permission
   WHERE permission.tenant_id=p_tenant AND permission.user_id=p_user
    AND permission.permission='financial_reports_read';
 END IF;
 -- An audit failure rolls back the permission change, rather than silently granting.
 PERFORM public.iv_log_event(p_tenant,
  CASE WHEN p_enabled THEN 'Financial report access granted' ELSE 'Financial report access revoked' END,
  'Target Auth account: '||p_user::text);
END
$function$;
CREATE FUNCTION public.iv_list_staff_financial_report_access(p_tenant text)
RETURNS TABLE(user_id uuid,email text,financial_reports_read boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF NOT ironvault_private.is_gym_administrator(p_tenant) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 RETURN QUERY SELECT DISTINCT staff.user_id::uuid,account.email::text,
  EXISTS(SELECT 1 FROM ironvault_private.staff_report_permissions permission
   WHERE permission.tenant_id=p_tenant AND permission.user_id=staff.user_id
    AND permission.permission='financial_reports_read')
 FROM public.iv_user_roles staff JOIN auth.users account ON account.id=staff.user_id
 WHERE staff.tenant_id::text=p_tenant AND staff.role='staff';
END
$function$;
ALTER FUNCTION ironvault_private.is_gym_administrator(text) OWNER TO postgres;
ALTER FUNCTION ironvault_private.can_read_financial_reports(text) OWNER TO postgres;
ALTER FUNCTION public.iv_can_read_financial_reports(text) OWNER TO postgres;
ALTER FUNCTION public.iv_set_staff_financial_report_access(text,uuid,boolean) OWNER TO postgres;
ALTER FUNCTION public.iv_list_staff_financial_report_access(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.is_gym_administrator(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ironvault_private.can_read_financial_reports(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.iv_can_read_financial_reports(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.iv_set_staff_financial_report_access(text,uuid,boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.iv_list_staff_financial_report_access(text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION ironvault_private.can_read_financial_reports(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.iv_can_read_financial_reports(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.iv_set_staff_financial_report_access(text,uuid,boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.iv_list_staff_financial_report_access(text) TO authenticated, service_role;
DO $verify$
DECLARE signature text;
BEGIN
 IF has_schema_privilege('anon','ironvault_private','USAGE')
  OR has_schema_privilege('authenticated','ironvault_private','CREATE')
  OR has_function_privilege('authenticated','ironvault_private.is_gym_administrator(text)','EXECUTE')
  OR has_any_column_privilege('authenticated','ironvault_private.staff_report_permissions','SELECT')
  OR has_any_column_privilege('authenticated','ironvault_private.staff_report_permissions','INSERT')
  OR has_any_column_privilege('authenticated','ironvault_private.staff_report_permissions','UPDATE')
  OR has_table_privilege('authenticated','ironvault_private.staff_report_permissions','DELETE') THEN
  RAISE EXCEPTION 'Unexpected inherited private permission access';
 END IF;
 FOREACH signature IN ARRAY ARRAY['ironvault_private.is_gym_administrator(text)',
  'ironvault_private.can_read_financial_reports(text)','public.iv_can_read_financial_reports(text)',
  'public.iv_set_staff_financial_report_access(text,uuid,boolean)',
  'public.iv_list_staff_financial_report_access(text)'] LOOP
  IF has_function_privilege('anon',signature,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous permission API execution remains: %',signature; END IF;
 END LOOP;
END
$verify$;
NOTIFY pgrst,'reload schema';

-- Metadata-only verification; no grant or list function is invoked in SQL Editor.
SELECT p.oid::regprocedure AS signature,p.prosecdef AS security_definer,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p WHERE p.oid IN (
 'ironvault_private.is_gym_administrator(text)'::regprocedure,
 'ironvault_private.can_read_financial_reports(text)'::regprocedure,
 'public.iv_can_read_financial_reports(text)'::regprocedure,
 'public.iv_set_staff_financial_report_access(text,uuid,boolean)'::regprocedure,
 'public.iv_list_staff_financial_report_access(text)'::regprocedure
) ORDER BY p.oid::regprocedure::text;


-- ===== SOURCE 202611010007_fix_financial_attendance_rls.sql SHA256 b2c37dfa0f1b9cc8accaef0600285cad44ca6d3fd6d19e451b0c85fe70e41aeb =====
-- MANUAL REVIEW/EXECUTION ONLY. Behavior-changing RLS; no rows are modified.
-- Requires 005 (write/role protection), 006 (explicit financial permission helper).
-- 003/004 are independent and do not block this urgent M4 correction.
-- Preserve SELECT access: Super Admin globally; gym owner or explicitly granted
-- staff for tenant financial reports; members only their own linked records.
-- Staff attendance remains tenant-scoped without requiring financial permission.
-- Failure aborts the transaction; ROLLBACK. Never restore the self-comparison
-- policies as rollback. Fix forward to a reviewed narrow expression instead.

SET LOCAL search_path = pg_catalog;
DO $preflight$
DECLARE item record; relation_oid oid; policy_row record; actual_md5 text; api_role text;
BEGIN
 IF to_regprocedure('ironvault_private.can_read_financial_reports(text)') IS NULL THEN
  RAISE EXCEPTION '006 must be applied and verified first';
 END IF;
 FOR item IN SELECT * FROM (VALUES
  ('public.iv_attendance_logs','iv_attendance_read','4f1b6a06b40b29210463540731851fd4'),
  ('public.iv_financial_transactions','iv_financial_read','4f1b6a06b40b29210463540731851fd4')
 ) AS expected(relation_name,policy_name,qual_md5) LOOP
  relation_oid:=to_regclass(item.relation_name)::oid;
  IF NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=relation_oid AND c.relkind='r'
   AND c.relrowsecurity AND NOT c.relforcerowsecurity AND pg_get_userbyid(c.relowner)='postgres')
   OR EXISTS(SELECT 1 FROM pg_inherits WHERE inhparent=relation_oid OR inhrelid=relation_oid) THEN
   RAISE EXCEPTION 'Unexpected RLS/owner/inheritance state for %; inspect dependencies first',item.relation_name;
  END IF;
  FOREACH api_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(api_role,item.relation_name,'INSERT')
    OR has_table_privilege(api_role,item.relation_name,'UPDATE')
    OR has_table_privilege(api_role,item.relation_name,'DELETE')
    OR has_table_privilege(api_role,item.relation_name,'TRUNCATE')
    OR has_any_column_privilege(api_role,item.relation_name,'INSERT')
    OR has_any_column_privilege(api_role,item.relation_name,'UPDATE')
    OR (api_role='anon' AND has_any_column_privilege(api_role,item.relation_name,'SELECT')) THEN
    RAISE EXCEPTION '005 direct-write/anonymous-read protection missing for %',item.relation_name;
   END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_policy WHERE polrelid=relation_oid)<>1 THEN
   RAISE EXCEPTION 'Unexpected additional/missing policies on %. Inspect before proceeding',item.relation_name;
  END IF;
  SELECT * INTO policy_row FROM pg_policy WHERE polrelid=relation_oid AND polname=item.policy_name;
  IF NOT FOUND OR policy_row.polcmd<>'r' OR NOT policy_row.polpermissive
   OR policy_row.polroles IS DISTINCT FROM ARRAY[(SELECT oid FROM pg_roles WHERE rolname='authenticated')] THEN
   RAISE EXCEPTION 'Policy shape/roles changed: %',item.policy_name;
  END IF;
  actual_md5:=md5(regexp_replace(replace(pg_get_expr(policy_row.polqual,relation_oid),'public.',''),'[[:space:]]+','','g'));
  IF actual_md5 IS DISTINCT FROM item.qual_md5 THEN
   RAISE EXCEPTION 'Policy definition changed since M4: %',item.policy_name;
  END IF;
 END LOOP;
END
$preflight$;
ALTER POLICY iv_financial_read ON public.iv_financial_transactions TO authenticated USING (
 ironvault_private.can_read_financial_reports(tenant_id::text)
 OR EXISTS (
  SELECT 1 FROM public.iv_user_roles membership
  WHERE membership.user_id=auth.uid() AND membership.role='member'
   AND membership.member_id::text=public.iv_financial_transactions.member_id::text
   AND membership.tenant_id::text=public.iv_financial_transactions.tenant_id::text
 )
);
ALTER POLICY iv_attendance_read ON public.iv_attendance_logs TO authenticated USING (
 public.iv_can_access(tenant_id)
 OR EXISTS (
  SELECT 1 FROM public.iv_user_roles membership
  WHERE membership.user_id=auth.uid() AND membership.role='member'
   AND membership.member_id::text=public.iv_attendance_logs.member_id::text
   AND membership.tenant_id::text=public.iv_attendance_logs.tenant_id::text
 )
);

-- Expected: both SELECT policies show actual outer-row member/tenant correlation;
-- financial whole-tenant access uses the explicit report permission helper.
SELECT tablename,policyname,roles,cmd,qual,with_check FROM pg_policies
WHERE schemaname='public' AND tablename IN ('iv_financial_transactions','iv_attendance_logs')
ORDER BY tablename,policyname;


-- ===== SOURCE 202611010008_staff_permission_tenant_fk.sql SHA256 1d181bbde51a6762a348231def90f648f5795f71ddc1a0bc687bf4bc466a4e8d =====
-- MANUAL REVIEW ONLY; requires confirmed 006. Additive integrity constraint.
-- T3/T4: public.owners(id) is PRIMARY KEY text. No existing row is rewritten.
-- Default NO ACTION prevents tenant deletion erasing permission/audit context.
-- Failure (including orphan permissions) aborts; return error, do not delete data.

SET LOCAL search_path=pg_catalog;
DO $guard$
BEGIN
 IF to_regclass('ironvault_private.staff_report_permissions') IS NULL THEN
  RAISE EXCEPTION 'Apply and confirm migration 006 first';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='ironvault_private.staff_report_permissions'::regclass
  AND conname='staff_report_permissions_tenant_fkey') THEN
  RAISE EXCEPTION 'Constraint already exists; verify prior application instead of overwriting';
 END IF;
END
$guard$;
ALTER TABLE ironvault_private.staff_report_permissions
 ADD CONSTRAINT staff_report_permissions_tenant_fkey
 FOREIGN KEY(tenant_id) REFERENCES public.owners(id) ON DELETE NO ACTION;

SELECT conname,convalidated,pg_get_constraintdef(oid) AS definition FROM pg_constraint
WHERE conrelid='ironvault_private.staff_report_permissions'::regclass
 AND conname='staff_report_permissions_tenant_fkey';
-- Expected: validated=true, tenant_id references owners(id), no cascade.
-- Recovery: fix forward after review; no automatic constraint removal.


-- ===== SOURCE 202611010009_member_tenant_contact_uniqueness.sql SHA256 f21faf2ddf62ef1cc7d964376c2aab0718cdcaee1cb6e6c3305c00dfb24a0b65 =====
-- MANUAL REVIEW ONLY. Additive, behavior-changing uniqueness; no rows modified.
-- T4: members.tenant_id/email are text; T5 idx_members_email is NOT unique.
-- Preserve cross-gym email reuse and all existing Auth identities/financial rows.
-- Requires T3-T5 baseline and reviewed registration paths. This protects concurrent
-- duplicates; it does not implement independent branch Auth credentials.
-- Uses normalized contact email (trim + lowercase). Existing duplicate groups
-- abort safely. Do not delete/merge accounts to force this migration through.
-- Run in a coordinated maintenance window: CREATE INDEX takes a write-blocking lock.
-- Existing unscoped legacy rows are excluded; securing their lifecycle is separate.

SET LOCAL search_path=pg_catalog;
DO $guard$
BEGIN
 IF to_regclass('public.iv_members_tenant_contact_email_unique') IS NOT NULL THEN
  RAISE EXCEPTION 'Index name already exists; inspect prior application, do not replace';
 END IF;
 IF EXISTS(SELECT 1 FROM public.members WHERE tenant_id IS NOT NULL
  GROUP BY tenant_id,lower(btrim(email)) HAVING count(*)>1) THEN
  RAISE EXCEPTION 'Normalized duplicate emails within a gym; review affected records without deleting them';
 END IF;
END
$guard$;
CREATE UNIQUE INDEX iv_members_tenant_contact_email_unique
 ON public.members(tenant_id,lower(btrim(email))) WHERE tenant_id IS NOT NULL;

SELECT indexname,indexdef FROM pg_indexes
WHERE schemaname='public' AND indexname='iv_members_tenant_contact_email_unique';
-- Expected: UNIQUE on tenant_id, lower(btrim(email)), excluding null tenants.
-- Keep existing idx_members_email and Auth/role/request unique indexes unchanged.
-- Recovery: reviewed fix forward; do not remove uniqueness to bypass registration errors.


-- ===== SOURCE 202611010010_financial_request_receipts.sql SHA256 27544cbbf5f049b2eea1eaecb878f022743b11147f0fc41b0e49dc6b147a371b =====
-- MANUAL ONLY. Additive foundation after 005/006/008. No legacy rows changed.
-- Existing global ledger request uniqueness is retained; no IDs are backfilled.

SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.financial_requests') IS NOT NULL THEN
  RAISE EXCEPTION 'Receipt table already exists; inspect prior application';
 END IF;
 IF has_table_privilege('authenticated','public.iv_user_roles','UPDATE') THEN
  RAISE EXCEPTION 'Apply role protection 005 first';
 END IF;
END $guard$;
CREATE TABLE ironvault_private.financial_requests (
 request_id uuid PRIMARY KEY,
 tenant_id text NOT NULL REFERENCES public.owners(id),
 member_id text NOT NULL REFERENCES public.members(id),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 payload jsonb NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ironvault_private.financial_requests OWNER TO postgres;
ALTER TABLE ironvault_private.financial_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ironvault_private.financial_requests FROM PUBLIC,anon,authenticated,service_role;
DO $verify$
DECLARE api_role text;
BEGIN
 FOREACH api_role IN ARRAY ARRAY['anon','authenticated'] LOOP
  IF has_table_privilege(api_role,'ironvault_private.financial_requests','SELECT')
   OR has_table_privilege(api_role,'ironvault_private.financial_requests','INSERT')
   OR has_table_privilege(api_role,'ironvault_private.financial_requests','UPDATE')
   OR has_table_privilege(api_role,'ironvault_private.financial_requests','DELETE')
   OR has_table_privilege(api_role,'ironvault_private.financial_requests','TRUNCATE') THEN
   RAISE EXCEPTION 'Unexpected inherited receipt access for %',api_role;
  END IF;
 END LOOP;
END $verify$;

SELECT c.relrowsecurity,pg_get_userbyid(c.relowner) AS owner,
 has_table_privilege('authenticated',c.oid,'SELECT') AS client_select,
 has_table_privilege('authenticated',c.oid,'INSERT') AS client_insert
FROM pg_class c WHERE c.oid='ironvault_private.financial_requests'::regclass;
-- Expect RLS true, owner postgres, client false. On error ROLLBACK; no resets.


-- ===== SOURCE 202611010011_financial_transaction_api.sql SHA256 a87343408c498f76db780e33cca2cc8da5384aac536e93f05d6aae0d2eff28d9 =====
-- MANUAL ONLY. Requires 010 and original reviewed topup/purchase definitions.
-- Behavior-changing: new RPCs, safe topup wrapper, legacy signature validates server outcome.
-- No historical row rewrite. Coordinate app cutover, do NOT deploy independently.
-- Full release also requires owners/members write protection: current broad ALL
-- policies otherwise allow callers to change authoritative prices/member discounts.
-- No migration is assumed applied. Errors abort; ROLLBACK and return error.

SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.financial_requests') IS NULL THEN RAISE EXCEPTION '010 required'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.iv_topup(text,numeric,uuid)')))
  IS DISTINCT FROM '08e84b7ad3f3a02c34ef083d62715469'
 OR md5(pg_get_functiondef(to_regprocedure('public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)')))
  IS DISTINCT FROM 'e09886b42457a094026b106a7b6af98e' THEN
  RAISE EXCEPTION 'Financial definitions differ from reviewed source';
 END IF;
 IF to_regprocedure('public.iv_financial_transaction(text,text,text,numeric,numeric,uuid)') IS NOT NULL
 OR to_regprocedure('public.iv_quote_plan(text,text)') IS NOT NULL
 OR to_regprocedure('ironvault_private.plan_terms(text,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'Proposed API name already exists; inspect before continuing';
 END IF;
END $guard$;
CREATE FUNCTION ironvault_private.plan_terms(p_member text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; pricing jsonb; price numeric; discount numeric; days integer; key text;
BEGIN
 SELECT * INTO STRICT m FROM public.members WHERE id=p_member;
 SELECT o.pricing INTO STRICT pricing FROM public.owners o WHERE o.id=m.tenant_id AND o.status='ACTIVE';
 CASE p_plan WHEN '1-Day Pass' THEN key:='day';days:=0;
 WHEN '1-Week Pass' THEN key:='week';days:=7;
 WHEN '1-Month Unlimited' THEN key:='month';days:=30;
 ELSE RAISE EXCEPTION 'Unsupported plan'; END CASE;
 price:=(pricing->>key)::numeric;discount:=coalesce(m.discount_percentage,0);
 IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<=0 OR price>10000000
 OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>=100 THEN
  RAISE EXCEPTION 'Invalid configured price or discount';
 END IF;
 -- Preserve existing desk discounted-price whole-peso rounding. Zero-price
 -- entitlements require a separate explicit complimentary-plan workflow.
 IF discount>0 THEN price:=round(price*(1-discount/100)); END IF;
 IF price<=0 OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid configured monetary precision'; END IF;
 RETURN jsonb_build_object('price',price,'expiration_date',
  ((now() AT TIME ZONE 'Asia/Manila')::date+days)::text,'wallet_balance',coalesce(m.wallet_balance,0));
END $fn$;
CREATE FUNCTION public.iv_quote_plan(p_member_id text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.iv_can_access(m.tenant_id)
 OR m.status IS DISTINCT FROM 'ACTIVE' THEN RAISE EXCEPTION 'Not authorized or member inactive'; END IF;
 RETURN ironvault_private.plan_terms(p_member_id,p_plan);
END $fn$;
CREATE FUNCTION public.iv_financial_transaction(p_operation text,p_member_id text,p_plan text,
 p_amount numeric,p_cash_amount numeric,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; receipt ironvault_private.financial_requests%ROWTYPE;
 payload jsonb; result jsonb; terms jsonb; price numeric; wallet numeric; cash numeric; balance numeric; actor uuid:=auth.uid();
BEGIN
 IF actor IS NULL OR p_request_id IS NULL OR p_operation IS NULL OR p_operation NOT IN ('topup','purchase')
 OR p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity')
 OR p_amount<=0 OR p_amount>10000000 OR p_amount<>round(p_amount,2)
 OR p_cash_amount IS NULL OR p_cash_amount::text IN ('NaN','Infinity','-Infinity')
 OR p_cash_amount<0 OR p_cash_amount<>round(p_cash_amount,2) THEN RAISE EXCEPTION 'Invalid financial request'; END IF;
 IF p_operation='topup' AND (p_amount>1000000 OR p_cash_amount<>0 OR p_plan IS NOT NULL) THEN
  RAISE EXCEPTION 'Invalid top-up'; END IF;
 payload:=jsonb_build_object('operation',p_operation,'member_id',p_member_id,'plan',p_plan,'amount',p_amount,'cash',p_cash_amount);
 -- All writers lock request then member. Same-key retries serialize even across
 -- different members; full payload+actor+tenant binding is checked before return.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,0));
 SELECT * INTO m FROM public.members WHERE id=p_member_id AND public.iv_can_access(tenant_id) FOR UPDATE;
 IF NOT FOUND OR NOT public.iv_can_access(m.tenant_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT * INTO receipt FROM ironvault_private.financial_requests WHERE request_id=p_request_id;
 IF FOUND THEN
  IF receipt.actor_id<>actor OR receipt.tenant_id<>m.tenant_id OR receipt.member_id<>m.id OR receipt.payload<>payload THEN
   RAISE EXCEPTION 'Request key belongs to a different operation'; END IF;
  RETURN receipt.result;
 END IF;
 IF EXISTS(SELECT 1 FROM public.iv_financial_transactions WHERE request_id=p_request_id) THEN
  RAISE EXCEPTION 'Legacy request key cannot be safely replayed'; END IF;
 IF m.status IS DISTINCT FROM 'ACTIVE' OR NOT EXISTS(SELECT 1 FROM public.owners o WHERE o.id=m.tenant_id AND o.status='ACTIVE') THEN
  RAISE EXCEPTION 'Gym or member inactive'; END IF;
 balance:=coalesce(m.wallet_balance,0);
 IF balance::text IN ('NaN','Infinity','-Infinity') OR balance<0 OR balance<>round(balance,2)
 OR coalesce(m.amount,0)::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Invalid existing financial state'; END IF;
 IF p_operation='topup' THEN
  balance:=balance+p_amount;
  UPDATE public.members SET wallet_balance=balance WHERE id=m.id;
  INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
   VALUES(m.tenant_id,m.id,'topup',p_amount,actor,p_request_id,'Cash wallet top-up');
 ELSE
  -- Stabilize gym pricing against concurrent administrator updates until commit.
  PERFORM 1 FROM public.owners WHERE id=m.tenant_id FOR SHARE;
  IF m.plan IN ('1-Day Pass','1-Week Pass','1-Month Unlimited') AND m.expiration_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
   BEGIN
    IF m.expiration_date::date >= (now() AT TIME ZONE 'Asia/Manila')::date THEN RAISE EXCEPTION 'Member already has a valid plan'; END IF;
   EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN NULL; END;
  END IF;
  terms:=ironvault_private.plan_terms(m.id,p_plan);price:=(terms->>'price')::numeric;
  IF p_amount<>price OR p_cash_amount>price THEN RAISE EXCEPTION 'Price changed or invalid payment split; quote again'; END IF;
  cash:=p_cash_amount;wallet:=price-cash;
  IF wallet>balance THEN RAISE EXCEPTION 'Insufficient wallet funds'; END IF;
  balance:=balance-wallet;
  UPDATE public.members SET wallet_balance=balance,plan=p_plan,
   expiration_date=terms->>'expiration_date',amount=coalesce(amount,0)+price,
   date_joined=(now() AT TIME ZONE 'Asia/Manila')::date::text WHERE id=m.id;
  IF wallet>0 THEN
   INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
    VALUES(m.tenant_id,m.id,'plan_wallet',wallet,actor,p_request_id,p_plan);
  END IF;
  IF cash>0 THEN
   INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
    VALUES(m.tenant_id,m.id,'plan_cash',cash,actor,CASE WHEN wallet=0 THEN p_request_id ELSE NULL END,p_plan);
  END IF;
 END IF;
 result:=jsonb_build_object('request_id',p_request_id,'wallet_balance',balance,'operation',p_operation,
  'price',CASE WHEN p_operation='purchase' THEN price ELSE p_amount END,'expiration_date',terms->>'expiration_date');
 INSERT INTO ironvault_private.financial_requests(request_id,tenant_id,member_id,actor_id,payload,result)
  VALUES(p_request_id,m.tenant_id,m.id,actor,payload,result);
 RETURN result;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_topup(p_member_id text,p_amount numeric,p_request_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN RETURN (public.iv_financial_transaction('topup',p_member_id,NULL,p_amount,0,p_request_id)->>'wallet_balance')::numeric; END $fn$;
CREATE OR REPLACE FUNCTION public.iv_purchase(p_member_id text,p_plan text,p_price numeric,
 p_wallet_amount numeric,p_cash_amount numeric,p_expiration date,p_request_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE outcome jsonb;
BEGIN
 IF p_wallet_amount IS NULL OR p_cash_amount IS NULL OR p_price IS NULL OR p_expiration IS NULL
 OR p_wallet_amount::text IN ('NaN','Infinity','-Infinity') OR p_wallet_amount<0
 OR p_wallet_amount<>round(p_wallet_amount,2) OR p_wallet_amount+p_cash_amount<>p_price THEN
  RAISE EXCEPTION 'Invalid purchase split'; END IF;
 outcome:=public.iv_financial_transaction('purchase',p_member_id,p_plan,p_price,p_cash_amount,p_request_id);
 IF p_expiration::text IS DISTINCT FROM outcome->>'expiration_date' THEN
  RAISE EXCEPTION 'Expiry differs from authoritative membership term'; END IF;
 RETURN (outcome->>'wallet_balance')::numeric;
END $fn$;
ALTER FUNCTION ironvault_private.plan_terms(text,text) OWNER TO postgres;
ALTER FUNCTION public.iv_quote_plan(text,text) OWNER TO postgres;
ALTER FUNCTION public.iv_financial_transaction(text,text,text,numeric,numeric,uuid) OWNER TO postgres;
ALTER FUNCTION public.iv_topup(text,numeric,uuid) OWNER TO postgres;
ALTER FUNCTION public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.plan_terms(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_quote_plan(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_financial_transaction(text,text,text,numeric,numeric,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_topup(text,numeric,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.iv_quote_plan(text,text),public.iv_financial_transaction(text,text,text,numeric,numeric,uuid),
 public.iv_topup(text,numeric,uuid),public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid) TO authenticated,service_role;
DO $verify$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.iv_quote_plan(text,text)',
 'public.iv_financial_transaction(text,text,text,numeric,numeric,uuid)',
 'public.iv_topup(text,numeric,uuid)','public.iv_purchase(text,text,numeric,numeric,numeric,date,uuid)'] LOOP
  IF has_function_privilege('anon',signature,'EXECUTE')
   OR NOT has_function_privilege('authenticated',signature,'EXECUTE') THEN
   RAISE EXCEPTION 'Unexpected effective API privilege on %',signature;
  END IF;
 END LOOP;
 IF has_function_privilege('authenticated','ironvault_private.plan_terms(text,text)','EXECUTE') THEN
  RAISE EXCEPTION 'Private pricing helper exposed'; END IF;
END $verify$;
NOTIFY pgrst,'reload schema';

SELECT oid::regprocedure,prosecdef,proconfig,
 has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute
FROM pg_proc WHERE oid IN ('public.iv_quote_plan(text,text)'::regprocedure,
 'public.iv_financial_transaction(text,text,text,numeric,numeric,uuid)'::regprocedure);
-- Expect anon false, authenticated true, empty search path. No RPC invoked.
-- All state changes are one transaction. On compatibility failures use reviewed
-- fix-forward; do not restore original unsafe purchase implementation.


-- ===== SOURCE 202611010012_scoped_application_data.sql SHA256 db671c88bcb73c2af87c99f93ee15580a880e001f669232c69140ad2456422f9 =====
-- MANUAL ONLY. Coordinated application/API/RLS cutover after 001-011 (004 optional).
-- Additive + behavior-changing. No existing row is deleted or financial value rewritten.
-- Existing enabled roles default true. Base tables become private; compatibility
-- views expose safe projections. Application profile saves cannot alter money,
-- plans, expiry, scans, Auth IDs, tenant links or credentials.

SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.financial_requests') IS NULL THEN RAISE EXCEPTION '010 required'; END IF;
 IF to_regclass('public.iv_gyms') IS NOT NULL OR to_regclass('public.iv_members') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.iv_user_roles'::regclass AND attname='enabled' AND NOT attisdropped) THEN
  RAISE EXCEPTION 'Cutover objects already exist; inspect prior application'; END IF;
 IF (SELECT count(*) FROM pg_policy WHERE polrelid='public.owners'::regclass)<>1
 OR (SELECT count(*) FROM pg_policy WHERE polrelid='public.members'::regclass)<>1 THEN
  RAISE EXCEPTION 'Owner/member policy baseline changed; review drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.owners'::regclass AND polname='Allow public access to owners' AND polcmd='*'
  AND pg_get_expr(polqual,polrelid)='true' AND pg_get_expr(polwithcheck,polrelid)='true')
 OR NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.members'::regclass AND polname='Allow public access to members' AND polcmd='*'
  AND pg_get_expr(polqual,polrelid)='true' AND pg_get_expr(polwithcheck,polrelid)='true') THEN
  RAISE EXCEPTION 'Expected public ALL policies differ from inspection'; END IF;
END $guard$;
ALTER TABLE public.iv_user_roles ADD COLUMN enabled boolean NOT NULL DEFAULT true;
ALTER TABLE public.iv_user_roles ADD COLUMN disabled_at timestamptz;
CREATE OR REPLACE FUNCTION public.iv_can_access(p_tenant text,p_roles text[] DEFAULT ARRAY['owner','staff']::text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND
 ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.tenant_id=p_tenant AND r.role=ANY(p_roles) AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'))));
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.is_gym_administrator(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT public.iv_can_access(p_tenant,ARRAY['owner']::text[]);
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.is_gym_administrator(p_tenant) OR EXISTS(
  SELECT 1 FROM public.iv_user_roles r JOIN ironvault_private.staff_report_permissions p ON p.user_id=r.user_id AND p.tenant_id=r.tenant_id
  WHERE r.user_id=auth.uid() AND r.enabled AND r.role='staff' AND r.tenant_id=p_tenant
   AND p.permission='financial_reports_read' AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'));
$fn$;
ALTER POLICY iv_roles_read ON public.iv_user_roles USING
 (enabled AND (user_id=auth.uid() OR public.iv_can_access(tenant_id,ARRAY['owner']::text[])));
-- Every helper uses caller auth.uid(), never current_user (the definer).
CREATE FUNCTION ironvault_private.can_read_member(p_id text,p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.members m WHERE m.id=p_id AND m.tenant_id IS NOT DISTINCT FROM p_tenant)
 AND (public.iv_can_access(p_tenant) OR EXISTS(SELECT 1 FROM public.iv_user_roles r
 WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=p_id AND r.tenant_id=p_tenant
 AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE')));
$fn$;
CREATE FUNCTION public.iv_visible_gyms()
RETURNS TABLE(id text,gym_name text,token text,logo text,status text,pricing jsonb,date_created timestamptz,created_at timestamptz,
 owner_name text,email text,password text,staff jsonb,audit_logs jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $visible$

 SELECT g.id,g.gym_name,g.token,g.logo,g.status,jsonb_build_object('day',g.pricing->'day','week',g.pricing->'week','month',g.pricing->'month','studentDiscount',g.pricing->'studentDiscount','seniorDiscount',g.pricing->'seniorDiscount'),g.date_created,g.created_at,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN g.owner_name ELSE NULL END AS owner_name,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN g.email ELSE NULL END AS email,
 NULL::text AS password,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN
  coalesce((SELECT jsonb_agg(jsonb_build_object('name',s.value->>'name','email',s.value->>'email','auth_user_id',s.value->>'auth_user_id','dateCreated',s.value->>'dateCreated')) FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s
   WHERE EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.tenant_id=g.id AND r.disabled_at IS NULL AND r.role='staff'
    AND r.user_id::text=s.value->>'auth_user_id')),'[]'::jsonb) ELSE '[]'::jsonb END AS staff,
 '[]'::jsonb AS audit_logs
 FROM public.owners g WHERE g.status IN ('ACTIVE','PROVISIONING') OR public.iv_can_access(g.id);
$visible$;
CREATE VIEW public.iv_gyms WITH(security_barrier=true) AS SELECT * FROM public.iv_visible_gyms();
CREATE VIEW public.iv_members WITH(security_barrier=true) AS
 SELECT m.id,m.tenant_id,m.tenant_token,m.name,m.email,m.phone,NULL::text AS password,
 m.classification,m.discount_percentage,m.plan,m.card_barcode,m.wallet_balance,
 CASE WHEN ironvault_private.can_read_financial_reports(m.tenant_id) OR EXISTS(
  SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=m.id AND r.tenant_id=m.tenant_id)
 THEN m.amount ELSE NULL END AS amount,
 m.scans_used,m.last_scanned_date,m.expiration_date,m.status,m.date_joined,m.avatar,m.created_at
 FROM public.members m WHERE ironvault_private.can_read_member(m.id,m.tenant_id);
ALTER VIEW public.iv_gyms OWNER TO postgres;
ALTER VIEW public.iv_members OWNER TO postgres;
REVOKE ALL ON public.iv_gyms,public.iv_members FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.iv_gyms TO anon,authenticated;
GRANT SELECT ON public.iv_members TO authenticated;
CREATE FUNCTION public.iv_save_member_profiles(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; m public.members%ROWTYPE; tenant text; operator boolean; owner_access boolean; discount numeric;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>500 THEN RAISE EXCEPTION 'Invalid profile batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO m FROM public.members WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Create member accounts through registration; restore cannot create financial records'; END IF;
  tenant:=m.tenant_id;operator:=public.iv_can_access(tenant);owner_access:=public.iv_can_access(tenant,ARRAY['owner']::text[]);
  IF NOT operator AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
   AND r.role='member' AND r.member_id=m.id AND r.tenant_id=tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=tenant AND g.status='ACTIVE')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF item ? 'tenant_id' AND item->>'tenant_id' IS DISTINCT FROM tenant THEN RAISE EXCEPTION 'Cannot move membership'; END IF;
  IF length(coalesce(item->>'name',m.name)) NOT BETWEEN 1 AND 160 OR length(coalesce(item->>'phone',''))>50
   OR length(coalesce(item->>'avatar',''))>750000 THEN RAISE EXCEPTION 'Invalid profile fields'; END IF;
  IF item ? 'email' AND lower(btrim(item->>'email')) IS DISTINCT FROM lower(btrim(m.email)) THEN
   RAISE EXCEPTION 'Contact email changes require verification'; END IF;
  -- Names/phone/avatar are personal edits. Operators additionally manage approval,
  -- classification and card IDs; only gym administrators change a discount.
  IF operator AND item ? 'status' AND item->>'status' NOT IN ('ACTIVE','PENDING','INACTIVE') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF operator AND item ? 'classification' AND item->>'classification' NOT IN ('Regular','Student','Senior') THEN RAISE EXCEPTION 'Invalid classification'; END IF;
  IF operator AND NOT owner_access AND m.status='INACTIVE' AND item->>'status'='ACTIVE' THEN RAISE EXCEPTION 'Gym administrator required to restore inactive membership'; END IF;
  discount:=coalesce(m.discount_percentage,0);
  IF operator AND item ? 'classification' AND item->>'classification' IS DISTINCT FROM m.classification THEN
   SELECT CASE WHEN item->>'classification'='Student' THEN (g.pricing->>'studentDiscount')::numeric
    WHEN item->>'classification'='Senior' THEN (g.pricing->>'seniorDiscount')::numeric ELSE 0 END
   INTO discount FROM public.owners g WHERE g.id=tenant;
  END IF;
  IF owner_access AND item ? 'discount_percentage' THEN
   discount:=(item->>'discount_percentage')::numeric;
   IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  END IF;
  IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid configured member discount'; END IF;
  UPDATE public.members SET name=coalesce(item->>'name',name),phone=CASE WHEN item ? 'phone' THEN item->>'phone' ELSE phone END,
   avatar=CASE WHEN item ? 'avatar' THEN item->>'avatar' ELSE avatar END,
   status=CASE WHEN operator THEN coalesce(item->>'status',status) ELSE status END,
   classification=CASE WHEN operator THEN coalesce(item->>'classification',classification) ELSE classification END,
   card_barcode=CASE WHEN operator AND item ? 'card_barcode' THEN item->>'card_barcode' ELSE card_barcode END,
   discount_percentage=discount WHERE id=m.id;
  INSERT INTO public.iv_activity_logs(tenant_id,actor_id,event,details) VALUES(tenant,auth.uid(),'Member profile updated',m.id);
 END LOOP;
END $fn$;
CREATE FUNCTION public.iv_save_gym_settings(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; gym public.owners%ROWTYPE; key text; price numeric; super boolean;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>100 THEN RAISE EXCEPTION 'Invalid gym batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO gym FROM public.owners WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND OR NOT public.iv_can_access(gym.id,ARRAY['owner']::text[]) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  super:=public.iv_can_access(NULL,ARRAY[]::text[]);
  IF length(coalesce(item->>'gym_name',gym.gym_name)) NOT BETWEEN 1 AND 160
   OR length(coalesce(item->>'owner_name',gym.owner_name)) NOT BETWEEN 1 AND 160
   OR length(coalesce(item->>'logo',''))>750000 THEN RAISE EXCEPTION 'Invalid branding'; END IF;
  IF item ? 'pricing' THEN
   FOREACH key IN ARRAY ARRAY['day','week','month','studentDiscount','seniorDiscount'] LOOP
    price:=(item->'pricing'->>key)::numeric;
    IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<0
     OR (key NOT LIKE '%Discount' AND price<=0) OR price>(CASE WHEN key LIKE '%Discount' THEN 100 ELSE 10000000 END) OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid pricing'; END IF;
   END LOOP;
  END IF;
  IF super AND item ? 'status' AND item->>'status' IS DISTINCT FROM gym.status AND item->>'status' NOT IN ('ACTIVE','SUSPENDED') THEN RAISE EXCEPTION 'Invalid gym status'; END IF;
  UPDATE public.owners SET gym_name=coalesce(item->>'gym_name',gym_name),owner_name=coalesce(item->>'owner_name',owner_name),
   logo=CASE WHEN item ? 'logo' THEN item->>'logo' ELSE logo END,
   pricing=CASE WHEN item ? 'pricing' THEN item->'pricing' ELSE pricing END,
   status=CASE WHEN super THEN coalesce(item->>'status',status) ELSE status END WHERE id=gym.id;
  -- Email, Auth, staff JSON, credentials, tenant IDs and tokens are never patched.
 END LOOP;
END $fn$;
CREATE FUNCTION public.iv_deactivate_member(p_member_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id FOR UPDATE;
 IF NOT FOUND OR NOT public.iv_can_access(m.tenant_id,ARRAY['owner']::text[]) THEN RAISE EXCEPTION 'Gym administrator required'; END IF;
 IF coalesce(m.wallet_balance,0)<>0 THEN RAISE EXCEPTION 'Settle wallet balance before deactivation'; END IF;
 UPDATE public.members SET status='INACTIVE' WHERE id=m.id;
 UPDATE public.iv_user_roles SET enabled=false,disabled_at=now() WHERE member_id=m.id AND tenant_id=m.tenant_id;
 PERFORM public.iv_log_event(m.tenant_id,'Member deactivated',m.id);
END $fn$;
CREATE FUNCTION public.iv_deactivate_gym(p_tenant text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT public.iv_can_access(NULL,ARRAY[]::text[]) THEN RAISE EXCEPTION 'Super Admin required'; END IF;
 IF EXISTS(SELECT 1 FROM public.members WHERE tenant_id=p_tenant AND coalesce(wallet_balance,0)<>0) THEN RAISE EXCEPTION 'Settle gym wallet liabilities first'; END IF;
 UPDATE public.owners SET status='SUSPENDED' WHERE id=p_tenant;
 PERFORM public.iv_log_event(p_tenant,'Gym suspended','Records and history retained');
END $fn$;
CREATE FUNCTION public.iv_revoke_staff(p_tenant text,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT public.iv_can_access(p_tenant,ARRAY['owner']::text[]) OR auth.uid()=p_user THEN RAISE EXCEPTION 'Not authorized'; END IF;
 UPDATE public.iv_user_roles SET enabled=false,disabled_at=now() WHERE user_id=p_user AND tenant_id=p_tenant AND role='staff';
 IF NOT FOUND THEN RAISE EXCEPTION 'Staff link not found'; END IF;
 PERFORM public.iv_log_event(p_tenant,'Staff access revoked',p_user::text);
END $fn$;
ALTER POLICY iv_financial_read ON public.iv_financial_transactions USING (
 ironvault_private.can_read_financial_reports(tenant_id) OR EXISTS(SELECT 1 FROM public.iv_user_roles r
 WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member'
 AND r.member_id=public.iv_financial_transactions.member_id AND r.tenant_id=public.iv_financial_transactions.tenant_id
 AND ironvault_private.can_read_member(r.member_id,r.tenant_id)));
ALTER POLICY iv_attendance_read ON public.iv_attendance_logs USING (
 public.iv_can_access(tenant_id) OR EXISTS(SELECT 1 FROM public.iv_user_roles r
 WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member'
 AND r.member_id=public.iv_attendance_logs.member_id AND r.tenant_id=public.iv_attendance_logs.tenant_id
 AND ironvault_private.can_read_member(r.member_id,r.tenant_id)));
-- Remove the known public ALL policies; no permissive compatibility fallback.
DROP POLICY "Allow public access to owners" ON public.owners;
DROP POLICY "Allow public access to members" ON public.members;
REVOKE ALL ON public.owners,public.members FROM PUBLIC,anon,authenticated;
DO $columns$
DECLARE item record; signature text;
BEGIN
 FOR item IN SELECT c.relname,a.attname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='public' AND c.relname IN ('owners','members') AND a.attnum>0 AND NOT a.attisdropped LOOP
  EXECUTE format('REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.%I FROM PUBLIC,anon,authenticated',item.attname,item.attname,item.attname,item.attname,item.relname);
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['public.iv_visible_gyms()','ironvault_private.can_read_member(text,text)',
 'public.iv_save_member_profiles(jsonb)','public.iv_save_gym_settings(jsonb)','public.iv_deactivate_member(text)',
 'public.iv_deactivate_gym(text)','public.iv_revoke_staff(text,uuid)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated,service_role',signature);
 END LOOP;
END $columns$;
GRANT EXECUTE ON FUNCTION public.iv_visible_gyms() TO anon;
-- Only this scoped branding projection is intentionally anonymously callable.
-- Views run as postgres to read private base tables but explicitly evaluate auth.uid
-- and current enabled role rows. Never change these to unrestricted SELECT * views.
DO $verify$
DECLARE t text; r text;
BEGIN
 FOREACH t IN ARRAY ARRAY['public.owners','public.members'] LOOP
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_any_column_privilege(r,t,'SELECT') OR has_any_column_privilege(r,t,'UPDATE')
    OR has_any_column_privilege(r,t,'INSERT') OR has_table_privilege(r,t,'DELETE') OR has_table_privilege(r,t,'TRUNCATE') THEN
    RAISE EXCEPTION 'Inherited base privilege remains on % for %',t,r; END IF;
  END LOOP;
 END LOOP;
END $verify$;
NOTIFY pgrst,'reload schema';

SELECT tablename,policyname,cmd FROM pg_policies WHERE schemaname='public' AND tablename IN ('owners','members');
-- Expect no public base policies; SELECT through scoped safe views only. On error
-- ROLLBACK; never restore public ALL. Existing records/password columns remain.


-- ===== SOURCE 202611010013_member_wallet_and_daily_passes.sql SHA256 d71df90584468385271116108323d3dfad5d93bbaf119857a57e569845afbcb3 =====
-- MANUAL ONLY. After 012. Member wallet-only purchases plus server-issued,
-- unguessable, expiring, tenant-bound daily pass tickets. No legacy row rewrite.
-- Unsigned member-ID/date QR codes intentionally cease to authorize admission.
-- No persistent signing secret is sent to browsers. An opaque server ticket
-- provides forgery resistance; it is not a cryptographically signed offline QR.

SET LOCAL search_path=pg_catalog;
CREATE FUNCTION ironvault_private.is_own_membership(p_member text,p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
  AND r.role='member' AND r.member_id=p_member AND r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_quote_plan(p_member_id text,p_plan text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id;
 IF NOT FOUND OR auth.uid() IS NULL OR (NOT public.iv_can_access(m.tenant_id) AND NOT ironvault_private.is_own_membership(m.id,m.tenant_id))
 OR m.status IS DISTINCT FROM 'ACTIVE' THEN RAISE EXCEPTION 'Not authorized or member inactive'; END IF;
 RETURN ironvault_private.plan_terms(p_member_id,p_plan);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_financial_transaction(p_operation text,p_member_id text,p_plan text,
 p_amount numeric,p_cash_amount numeric,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; receipt ironvault_private.financial_requests%ROWTYPE;
 payload jsonb; result jsonb; terms jsonb; price numeric; wallet numeric; cash numeric; balance numeric; actor uuid:=auth.uid();
BEGIN
 IF actor IS NULL OR p_request_id IS NULL OR p_operation IS NULL OR p_operation NOT IN ('topup','purchase')
 OR p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity')
 OR p_amount<=0 OR p_amount>10000000 OR p_amount<>round(p_amount,2)
 OR p_cash_amount IS NULL OR p_cash_amount::text IN ('NaN','Infinity','-Infinity')
 OR p_cash_amount<0 OR p_cash_amount<>round(p_cash_amount,2) THEN RAISE EXCEPTION 'Invalid financial request'; END IF;
 IF p_operation='topup' AND (p_amount>1000000 OR p_cash_amount<>0 OR p_plan IS NOT NULL) THEN
  RAISE EXCEPTION 'Invalid top-up'; END IF;
 payload:=jsonb_build_object('operation',p_operation,'member_id',p_member_id,'plan',p_plan,'amount',p_amount,'cash',p_cash_amount);
 -- All writers lock request then member. Same-key retries serialize even across
 -- different members; full payload+actor+tenant binding is checked before return.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,0));
 SELECT * INTO m FROM public.members WHERE id=p_member_id AND (public.iv_can_access(tenant_id) OR (p_operation='purchase' AND p_cash_amount=0 AND ironvault_private.is_own_membership(id,tenant_id))) FOR UPDATE;
 IF NOT FOUND OR (NOT public.iv_can_access(m.tenant_id) AND NOT (p_operation='purchase' AND p_cash_amount=0 AND ironvault_private.is_own_membership(m.id,m.tenant_id))) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT * INTO receipt FROM ironvault_private.financial_requests WHERE request_id=p_request_id;
 IF FOUND THEN
  IF receipt.actor_id<>actor OR receipt.tenant_id<>m.tenant_id OR receipt.member_id<>m.id OR receipt.payload<>payload THEN
   RAISE EXCEPTION 'Request key belongs to a different operation'; END IF;
  RETURN receipt.result;
 END IF;
 IF EXISTS(SELECT 1 FROM public.iv_financial_transactions WHERE request_id=p_request_id) THEN
  RAISE EXCEPTION 'Legacy request key cannot be safely replayed'; END IF;
 IF m.status IS DISTINCT FROM 'ACTIVE' OR NOT EXISTS(SELECT 1 FROM public.owners o WHERE o.id=m.tenant_id AND o.status='ACTIVE') THEN
  RAISE EXCEPTION 'Gym or member inactive'; END IF;
 balance:=coalesce(m.wallet_balance,0);
 IF balance::text IN ('NaN','Infinity','-Infinity') OR balance<0 OR balance<>round(balance,2)
 OR coalesce(m.amount,0)::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Invalid existing financial state'; END IF;
 IF p_operation='topup' THEN
  balance:=balance+p_amount;
  UPDATE public.members SET wallet_balance=balance WHERE id=m.id;
  INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
   VALUES(m.tenant_id,m.id,'topup',p_amount,actor,p_request_id,'Cash wallet top-up');
 ELSE
  -- Stabilize gym pricing against concurrent administrator updates until commit.
  PERFORM 1 FROM public.owners WHERE id=m.tenant_id FOR SHARE;
  IF m.plan IN ('1-Day Pass','1-Week Pass','1-Month Unlimited') AND m.expiration_date ~ '^\d{4}-\d{2}-\d{2}$' THEN
   BEGIN
    IF m.expiration_date::date >= (now() AT TIME ZONE 'Asia/Manila')::date THEN RAISE EXCEPTION 'Member already has a valid plan'; END IF;
   EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN NULL; END;
  END IF;
  terms:=ironvault_private.plan_terms(m.id,p_plan);price:=(terms->>'price')::numeric;
  IF p_amount<>price OR p_cash_amount>price THEN RAISE EXCEPTION 'Price changed or invalid payment split; quote again'; END IF;
  cash:=p_cash_amount;wallet:=price-cash;
  IF wallet>balance THEN RAISE EXCEPTION 'Insufficient wallet funds'; END IF;
  balance:=balance-wallet;
  UPDATE public.members SET wallet_balance=balance,plan=p_plan,
   expiration_date=terms->>'expiration_date',amount=coalesce(amount,0)+price,
   date_joined=(now() AT TIME ZONE 'Asia/Manila')::date::text WHERE id=m.id;
  IF wallet>0 THEN
   INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
    VALUES(m.tenant_id,m.id,'plan_wallet',wallet,actor,p_request_id,p_plan);
  END IF;
  IF cash>0 THEN
   INSERT INTO public.iv_financial_transactions(tenant_id,member_id,kind,amount,actor_id,request_id,description)
    VALUES(m.tenant_id,m.id,'plan_cash',cash,actor,CASE WHEN wallet=0 THEN p_request_id ELSE NULL END,p_plan);
  END IF;
 END IF;
 result:=jsonb_build_object('request_id',p_request_id,'wallet_balance',balance,'operation',p_operation,
  'price',CASE WHEN p_operation='purchase' THEN price ELSE p_amount END,'expiration_date',terms->>'expiration_date');
 INSERT INTO ironvault_private.financial_requests(request_id,tenant_id,member_id,actor_id,payload,result)
  VALUES(p_request_id,m.tenant_id,m.id,actor,payload,result);
 RETURN result;
END $fn$;

CREATE TABLE ironvault_private.daily_passes (
 token uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 member_id text NOT NULL REFERENCES public.members(id),
 tenant_id text NOT NULL REFERENCES public.owners(id),
 business_day date NOT NULL,
 expires_at timestamptz NOT NULL,
 used_at timestamptz,
 UNIQUE(member_id,business_day)
);
ALTER TABLE ironvault_private.daily_passes OWNER TO postgres;
ALTER TABLE ironvault_private.daily_passes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.daily_passes FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.valid_entitlement(p_member text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; expiry date;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member;
 IF NOT FOUND OR m.status IS DISTINCT FROM 'ACTIVE'
  OR m.plan IS NULL OR m.plan NOT IN ('1-Day Pass','1-Week Pass','1-Month Unlimited')
  OR m.expiration_date IS NULL OR m.expiration_date !~ '^\d{4}-\d{2}-\d{2}$'
  OR NOT EXISTS(SELECT 1 FROM public.owners WHERE id=m.tenant_id AND status='ACTIVE') THEN RETURN false; END IF;
 BEGIN expiry:=m.expiration_date::date; EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN false; END;
 RETURN expiry >= (now() AT TIME ZONE 'Asia/Manila')::date;
END $fn$;
CREATE FUNCTION public.iv_issue_member_pass(p_member_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; ticket ironvault_private.daily_passes%ROWTYPE; today date:=(now() AT TIME ZONE 'Asia/Manila')::date;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id FOR UPDATE;
 IF NOT FOUND OR NOT ironvault_private.is_own_membership(m.id,m.tenant_id) OR NOT ironvault_private.valid_entitlement(m.id) THEN
  RAISE EXCEPTION 'No valid membership for this pass'; END IF;
 IF m.last_scanned_date=today::text OR EXISTS(SELECT 1 FROM public.iv_attendance_logs WHERE member_id=m.id
  AND (created_at AT TIME ZONE 'Asia/Manila')::date=today) THEN RAISE EXCEPTION 'Already admitted today'; END IF;
 INSERT INTO ironvault_private.daily_passes(member_id,tenant_id,business_day,expires_at)
  VALUES(m.id,m.tenant_id,today,(today+1)::timestamp AT TIME ZONE 'Asia/Manila') ON CONFLICT(member_id,business_day) DO NOTHING;
 SELECT * INTO STRICT ticket FROM ironvault_private.daily_passes WHERE member_id=m.id AND business_day=today;
 IF ticket.used_at IS NOT NULL THEN RAISE EXCEPTION 'Pass already used'; END IF;
 RETURN jsonb_build_object('payload','IV1|'||ticket.token::text,'business_day',today,'expires_at',ticket.expires_at);
END $fn$;
CREATE FUNCTION ironvault_private.record_admission(p_member text,p_method text)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE; today text:=((now() AT TIME ZONE 'Asia/Manila')::date)::text; admitted timestamptz:=now();
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.iv_can_access(m.tenant_id) OR NOT ironvault_private.valid_entitlement(m.id) THEN RAISE EXCEPTION 'Not authorized or membership invalid'; END IF;
 IF m.last_scanned_date=today OR EXISTS(SELECT 1 FROM public.iv_attendance_logs WHERE member_id=m.id
  AND (created_at AT TIME ZONE 'Asia/Manila')::date=today::date) THEN RAISE EXCEPTION 'Already admitted today'; END IF;
 UPDATE public.members SET scans_used=coalesce(scans_used,0)+1,last_scanned_date=today WHERE id=m.id;
 INSERT INTO public.iv_attendance_logs(tenant_id,member_id,method,actor_id,created_at) VALUES(m.tenant_id,m.id,p_method,auth.uid(),admitted);
 RETURN admitted;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_checkin(p_member_id text,p_method text)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF p_method IS DISTINCT FROM 'manual' THEN RAISE EXCEPTION 'QR admission requires a server-issued pass'; END IF;
 RETURN ironvault_private.record_admission(p_member_id,'manual');
END $fn$;
CREATE FUNCTION public.iv_redeem_member_pass(p_token uuid,p_tenant text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE ticket ironvault_private.daily_passes%ROWTYPE; admitted timestamptz;
BEGIN
 -- Lock member in record_admission before touching ticket to match pass issuance;
 -- token lookup itself is read-only, tickets are immutable except used_at.
 SELECT * INTO ticket FROM ironvault_private.daily_passes WHERE token=p_token;
 IF NOT FOUND OR ticket.tenant_id IS DISTINCT FROM p_tenant OR NOT public.iv_can_access(ticket.tenant_id)
  OR ticket.used_at IS NOT NULL OR ticket.expires_at<=now()
  OR ticket.business_day<>(now() AT TIME ZONE 'Asia/Manila')::date THEN RAISE EXCEPTION 'Invalid, expired or used pass'; END IF;
 admitted:=ironvault_private.record_admission(ticket.member_id,'qr');
 UPDATE ironvault_private.daily_passes SET used_at=admitted WHERE token=p_token AND used_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pass already used'; END IF;
 RETURN jsonb_build_object('member_id',ticket.member_id,'admitted_at',admitted);
END $fn$;
DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['ironvault_private.is_own_membership(text,text)',
 'ironvault_private.valid_entitlement(text)','ironvault_private.record_admission(text,text)',
 'public.iv_issue_member_pass(text)','public.iv_redeem_member_pass(uuid,text)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_issue_member_pass(text),public.iv_redeem_member_pass(uuid,text) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.iv_checkin(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.iv_checkin(text,text) TO authenticated,service_role;
NOTIFY pgrst,'reload schema';

SELECT oid::regprocedure,has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute FROM pg_proc
WHERE oid IN ('public.iv_issue_member_pass(text)'::regprocedure,'public.iv_redeem_member_pass(uuid,text)'::regprocedure);
-- Expect anon false/authenticated true. No account/financial/history deletion.
-- On error ROLLBACK; fix forward, never re-enable unsigned QR authorization.


-- ===== SOURCE 202611010014_branch_account_lifecycle.sql SHA256 d88fcc373f917d92b6fbda9ec35e35f9ba35faf79a0efdd02038c978e01be7ad =====
-- MANUAL ONLY; after 012/013. Additive mappings/jobs/tokens/rate windows.
-- Preserve existing Auth IDs/passwords and all financial history. No Auth tables
-- are created, altered or deleted. Existing contact mappings are backfilled.

SET LOCAL search_path=pg_catalog;
CREATE TABLE ironvault_private.branch_accounts (
 tenant_id text NOT NULL REFERENCES public.owners(id),
 role text NOT NULL CHECK(role IN ('owner','staff','member')),
 contact_email text NOT NULL CHECK(contact_email=lower(btrim(contact_email))),
 user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id),
 contact_verified boolean NOT NULL DEFAULT false,
 PRIMARY KEY(tenant_id,role,contact_email)
);
INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id,contact_verified)
SELECT r.tenant_id,r.role,lower(btrim(CASE WHEN r.role='member' THEN m.email WHEN r.role='owner' THEN g.email
 ELSE coalesce((SELECT s.value->>'email' FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s
 WHERE s.value->>'auth_user_id'=r.user_id::text LIMIT 1),u.email) END)),r.user_id,u.email_confirmed_at IS NOT NULL
FROM public.iv_user_roles r JOIN auth.users u ON u.id=r.user_id JOIN public.owners g ON g.id=r.tenant_id
LEFT JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
WHERE r.role IN ('owner','staff','member');
CREATE TABLE ironvault_private.provision_requests (
 request_id uuid PRIMARY KEY,
 tenant_id text NOT NULL REFERENCES public.owners(id),
 role text NOT NULL CHECK(role IN ('owner','staff','member')),
 contact_email text NOT NULL,
 alias text NOT NULL UNIQUE,
 actor_id uuid REFERENCES auth.users(id),
 payload jsonb NOT NULL,
 completed_user uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,role,contact_email)
);
CREATE TABLE ironvault_private.email_actions (
 token_hash text PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES auth.users(id),
 kind text NOT NULL CHECK(kind IN ('verify','change_old','change_new','correct_unverified')),
 new_email text,
 base_email text NOT NULL,
 group_id uuid NOT NULL,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '1 hour',
 confirmed_at timestamptz
);
CREATE TABLE ironvault_private.auth_rate_windows (
 bucket text PRIMARY KEY,window_start timestamptz NOT NULL,attempts integer NOT NULL
);
CREATE FUNCTION public.iv_auth_rate_limit(p_bucket text,p_limit integer,p_seconds integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE attempts integer;
BEGIN
 IF p_limit<1 OR p_limit>1000 OR p_seconds<1 OR p_seconds>86400 OR length(p_bucket)>200 THEN RAISE EXCEPTION 'Invalid rate policy'; END IF;
 INSERT INTO ironvault_private.auth_rate_windows AS w(bucket,window_start,attempts) VALUES(p_bucket,now(),1)
 ON CONFLICT(bucket) DO UPDATE SET window_start=CASE WHEN w.window_start<now()-p_seconds*interval '1 second' THEN now() ELSE w.window_start END,
 attempts=CASE WHEN w.window_start<now()-p_seconds*interval '1 second' THEN 1 ELSE w.attempts+1 END RETURNING w.attempts INTO attempts;
 RETURN attempts<=p_limit;
END $fn$;
CREATE FUNCTION public.iv_branch_identity(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id,a.role FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles) AND a.contact_email=lower(btrim(p_email))
  AND a.contact_verified AND r.enabled AND r.tenant_id=a.tenant_id AND r.role=a.role;
$fn$;
CREATE FUNCTION public.iv_prepare_branch_account(p_request uuid,p_actor uuid,p_tenant text,p_role text,p_email text,p_alias text,p_payload jsonb,p_new_gym boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.provision_requests%ROWTYPE; actor public.iv_user_roles%ROWTYPE; key text; price numeric; name text;
BEGIN
 IF p_request IS NULL OR p_role NOT IN ('owner','staff','member') OR p_email IS NULL OR p_email<>lower(btrim(p_email))
  OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  OR p_alias !~ '^[a-f0-9]{64}@accounts\.ironvault\.invalid$'
  OR p_payload ? 'password' OR p_payload ? 'service_role' THEN RAISE EXCEPTION 'Invalid account request'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text,1));
 SELECT * INTO job FROM ironvault_private.provision_requests WHERE request_id=p_request;
 IF FOUND THEN
  IF job.actor_id IS DISTINCT FROM p_actor OR job.tenant_id<>p_tenant OR job.role<>p_role OR job.contact_email<>p_email
   OR job.alias<>p_alias OR job.payload<>p_payload THEN RAISE EXCEPTION 'Provision request mismatch'; END IF;
 END IF;
 SELECT * INTO actor FROM public.iv_user_roles WHERE user_id=p_actor AND enabled;
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
  IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant AND (status='ACTIVE' OR (status='PROVISIONING' AND actor.role='super_admin' AND p_role='staff'))) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
  IF p_actor IS NULL THEN
   IF p_role<>'member' THEN RAISE EXCEPTION 'Member registration only'; END IF;
  ELSIF actor.role IS DISTINCT FROM 'super_admin' THEN
   IF actor.tenant_id IS DISTINCT FROM p_tenant OR actor.role NOT IN ('owner','staff')
    OR (p_role='staff' AND actor.role<>'owner') OR p_role='owner' THEN RAISE EXCEPTION 'Not authorized'; END IF;
  END IF;
 END IF;
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
CREATE FUNCTION public.iv_find_created_account(p_request uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT u.id FROM ironvault_private.provision_requests p JOIN auth.users u ON u.email=p.alias
 WHERE p.request_id=p_request AND u.raw_app_meta_data->>'iv_provision_request'=p_request::text;
$fn$;
CREATE FUNCTION public.iv_finish_branch_account(p_request uuid,p_user uuid)
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
 IF job.role<>'owner' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=job.tenant_id AND (status='ACTIVE' OR (status='PROVISIONING' AND job.role='staff' AND EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=job.actor_id AND enabled AND role='super_admin')))) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user AND email=job.alias AND raw_app_meta_data->>'iv_provision_request'=p_request::text) THEN
  RAISE EXCEPTION 'Auth account does not match protected provisioning metadata'; END IF;
 IF job.role='member' THEN
  member_id:='MEM-'||gen_random_uuid()::text;
  SELECT o.token INTO STRICT token FROM public.owners o WHERE o.id=job.tenant_id;
  INSERT INTO public.members(id,tenant_id,tenant_token,name,email,phone,password,auth_user_id,
   classification,discount_percentage,plan,wallet_balance,amount,scans_used,status,date_joined)
  VALUES(member_id,job.tenant_id,token,job.payload->>'name',job.contact_email,coalesce(job.payload->>'phone',''),NULL,p_user,
   'Regular',0,'Not Selected',0,0,0,CASE WHEN job.actor_id IS NULL THEN 'PENDING' ELSE 'ACTIVE' END,
   ((now() AT TIME ZONE 'Asia/Manila')::date)::text);
 END IF;
 INSERT INTO public.iv_user_roles(user_id,tenant_id,role,member_id,enabled) VALUES(p_user,job.tenant_id,job.role,member_id,false);
 INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id) VALUES(job.tenant_id,job.role,job.contact_email,p_user);
 IF job.role='staff' THEN
  UPDATE public.owners SET staff=coalesce(staff,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('name',job.payload->>'name',
   'email',job.contact_email,'auth_user_id',p_user,'dateCreated',((now() AT TIME ZONE 'Asia/Manila')::date)::text)) WHERE id=job.tenant_id;
 END IF;
 UPDATE ironvault_private.provision_requests SET completed_user=p_user WHERE request_id=p_request;
 RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'member_id',member_id,'user_id',p_user);
END $fn$;
CREATE FUNCTION public.iv_queue_email_action(p_user uuid,p_hash text,p_kind text,p_group uuid,p_new_email text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF p_hash !~ '^[a-f0-9]{64}$' OR p_kind NOT IN ('verify','change_old','change_new','correct_unverified') THEN RAISE EXCEPTION 'Invalid verification action'; END IF;
 IF p_kind<>'verify' AND (p_new_email IS NULL OR p_new_email<>lower(btrim(p_new_email))) THEN RAISE EXCEPTION 'Invalid contact email'; END IF;
 INSERT INTO ironvault_private.email_actions(token_hash,user_id,kind,group_id,new_email,base_email)
 SELECT p_hash,p_user,p_kind,p_group,p_new_email,contact_email FROM ironvault_private.branch_accounts WHERE user_id=p_user;
 IF NOT FOUND THEN RAISE EXCEPTION 'Account mapping unavailable'; END IF;
END $fn$;
CREATE FUNCTION public.iv_confirm_email_action(p_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE action ironvault_private.email_actions%ROWTYPE; account ironvault_private.branch_accounts%ROWTYPE;
BEGIN
 SELECT * INTO STRICT action FROM ironvault_private.email_actions WHERE token_hash=p_hash FOR UPDATE;
 IF action.expires_at<=now() OR action.confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'Verification link expired or used'; END IF;
 SELECT * INTO STRICT account FROM ironvault_private.branch_accounts WHERE user_id=action.user_id FOR UPDATE;
 IF account.contact_email IS DISTINCT FROM action.base_email THEN RAISE EXCEPTION 'Contact changed since this link was issued'; END IF;
 UPDATE ironvault_private.email_actions SET confirmed_at=now() WHERE token_hash=p_hash;
 IF action.kind='verify' THEN
  UPDATE ironvault_private.branch_accounts SET contact_verified=true WHERE user_id=account.user_id;
  UPDATE public.iv_user_roles SET enabled=true WHERE user_id=account.user_id AND disabled_at IS NULL;
  IF account.role='owner' THEN UPDATE public.owners SET status='ACTIVE' WHERE id=account.tenant_id AND status='PROVISIONING'; END IF;
 ELSE
  IF action.kind='correct_unverified' THEN
   IF account.contact_verified THEN RAISE EXCEPTION 'Verified contact requires both address proofs'; END IF;
  ELSE
  IF NOT EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=action.group_id AND user_id=action.user_id
   AND kind='change_old' AND confirmed_at IS NOT NULL AND expires_at>now())
  OR NOT EXISTS(SELECT 1 FROM ironvault_private.email_actions WHERE group_id=action.group_id AND user_id=action.user_id
   AND kind='change_new' AND confirmed_at IS NOT NULL AND expires_at>now()) THEN RETURN false; END IF;
  END IF;
  UPDATE ironvault_private.branch_accounts SET contact_email=action.new_email,contact_verified=true WHERE user_id=account.user_id;
  IF account.role='member' THEN UPDATE public.members SET email=action.new_email WHERE id=(SELECT member_id FROM public.iv_user_roles WHERE user_id=account.user_id AND role='member') AND tenant_id=account.tenant_id; END IF;
  IF account.role='staff' THEN
   UPDATE public.owners SET staff=(SELECT jsonb_agg(CASE WHEN s.value->>'auth_user_id'=account.user_id::text THEN s.value||jsonb_build_object('email',action.new_email) ELSE s.value END)
    FROM jsonb_array_elements(staff) s) WHERE id=account.tenant_id;
  END IF;
 END IF;
 UPDATE public.iv_user_roles SET enabled=true WHERE user_id=account.user_id AND disabled_at IS NULL;
 IF account.role='owner' THEN UPDATE public.owners SET status='ACTIVE' WHERE id=account.tenant_id AND status='PROVISIONING'; END IF;
 RETURN true;
END $fn$;
CREATE FUNCTION public.iv_branch_account_details(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('user_id',a.user_id,'tenant_id',a.tenant_id,'role',a.role,'email',a.contact_email,
 'verified',a.contact_verified,'enabled',r.enabled,'gym_name',g.gym_name,'token',g.token,'auth_email',u.email)
 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 JOIN public.owners g ON g.id=a.tenant_id JOIN auth.users u ON u.id=a.user_id WHERE a.user_id=p_user;
$fn$;
CREATE FUNCTION public.iv_lookup_branch_account(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id FROM ironvault_private.branch_accounts a WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles) AND a.contact_email=lower(btrim(p_email));
$fn$;
CREATE FUNCTION public.iv_update_staff_name(p_tenant text,p_user uuid,p_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT public.iv_can_access(p_tenant,ARRAY['owner']::text[]) OR length(p_name) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'Not authorized or invalid name'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=p_user AND tenant_id=p_tenant AND role='staff' AND enabled) THEN RAISE EXCEPTION 'Staff not found'; END IF;
 UPDATE public.owners SET staff=coalesce((SELECT jsonb_agg(CASE WHEN x.value->>'auth_user_id'=p_user::text THEN x.value||jsonb_build_object('name',p_name) ELSE x.value END)
  FROM jsonb_array_elements(staff) x),'[]'::jsonb) WHERE id=p_tenant;
 PERFORM public.iv_log_event(p_tenant,'Staff name updated',p_user::text);
END $fn$;
REVOKE ALL ON FUNCTION public.iv_update_staff_name(text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_update_staff_name(text,uuid,text) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.iv_save_member_profiles(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; m public.members%ROWTYPE; tenant text; operator boolean; owner_access boolean; discount numeric;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>500 THEN RAISE EXCEPTION 'Invalid profile batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO m FROM public.members WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Create member accounts through registration; restore cannot create financial records'; END IF;
  tenant:=m.tenant_id;operator:=public.iv_can_access(tenant);owner_access:=public.iv_can_access(tenant,ARRAY['owner']::text[]);
  IF NOT operator AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
   AND r.role='member' AND r.member_id=m.id AND r.tenant_id=tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=tenant AND g.status='ACTIVE')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF item ? 'tenant_id' AND item->>'tenant_id' IS DISTINCT FROM tenant THEN RAISE EXCEPTION 'Cannot move membership'; END IF;
  IF length(coalesce(item->>'name',m.name)) NOT BETWEEN 1 AND 160 OR length(coalesce(item->>'phone',''))>50
   OR length(coalesce(item->>'avatar',''))>750000 THEN RAISE EXCEPTION 'Invalid profile fields'; END IF;
  IF item ? 'email' AND lower(btrim(item->>'email')) IS DISTINCT FROM lower(btrim(m.email)) THEN
   RAISE EXCEPTION 'Contact email changes require verification'; END IF;
  -- Names/phone/avatar are personal edits. Operators additionally manage approval,
  -- classification and card IDs; only gym administrators change a discount.
  IF operator AND item ? 'status' AND item->>'status' NOT IN ('ACTIVE','PENDING','INACTIVE') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF operator AND item ? 'classification' AND item->>'classification' NOT IN ('Regular','Student','Senior') THEN RAISE EXCEPTION 'Invalid classification'; END IF;
  IF operator AND NOT owner_access AND m.status='INACTIVE' AND item->>'status'='ACTIVE' THEN RAISE EXCEPTION 'Gym administrator required to restore inactive membership'; END IF;
  discount:=coalesce(m.discount_percentage,0);
  IF operator AND item ? 'classification' AND item->>'classification' IS DISTINCT FROM m.classification THEN
   SELECT CASE WHEN item->>'classification'='Student' THEN (g.pricing->>'studentDiscount')::numeric
    WHEN item->>'classification'='Senior' THEN (g.pricing->>'seniorDiscount')::numeric ELSE 0 END
   INTO discount FROM public.owners g WHERE g.id=tenant;
  END IF;
  IF owner_access AND item ? 'discount_percentage' THEN
   discount:=(item->>'discount_percentage')::numeric;
   IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  END IF;
  IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid configured member discount'; END IF;
  UPDATE public.members SET name=coalesce(item->>'name',name),phone=CASE WHEN item ? 'phone' THEN item->>'phone' ELSE phone END,
   avatar=CASE WHEN item ? 'avatar' THEN item->>'avatar' ELSE avatar END,
   status=CASE WHEN operator THEN coalesce(item->>'status',status) ELSE status END,
   classification=CASE WHEN operator THEN coalesce(item->>'classification',classification) ELSE classification END,
   card_barcode=CASE WHEN operator AND item ? 'card_barcode' THEN item->>'card_barcode' ELSE card_barcode END,
   discount_percentage=discount WHERE id=m.id;
  IF owner_access AND item->>'status'='ACTIVE' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id WHERE r.member_id=m.id AND a.tenant_id=tenant AND r.tenant_id=tenant AND a.contact_verified) THEN
   UPDATE public.iv_user_roles SET enabled=true,disabled_at=NULL WHERE member_id=m.id AND tenant_id=tenant AND role='member';
  END IF;
  INSERT INTO public.iv_activity_logs(tenant_id,actor_id,event,details) VALUES(tenant,auth.uid(),'Member profile updated',m.id);
 END LOOP;
END $fn$;
CREATE FUNCTION public.iv_contact_status()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('email',a.contact_email,'verified',a.contact_verified)
 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 WHERE a.user_id=auth.uid() AND r.enabled;
$fn$;
REVOKE ALL ON FUNCTION public.iv_contact_status() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_contact_status() TO authenticated,service_role;
-- Close the old metadata-only signup path: private aliases are provisioned by the
-- trusted service with protected app_metadata, not caller-editable user_metadata.
-- Keep the existing trigger attachment, as required. New gateway sets no old flag.
CREATE OR REPLACE FUNCTION public.iv_member_auth_signup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF coalesce(NEW.raw_user_meta_data->>'iv_member_signup','')='true' THEN
  RAISE EXCEPTION 'Use branch-aware member registration'; END IF;
 RETURN NEW;
END $fn$;
-- Reflect verified owner contact, not private alias, in the safe compatibility view.
-- Existing view column order/types stay identical.
CREATE OR REPLACE FUNCTION public.iv_visible_gyms()
RETURNS TABLE(id text,gym_name text,token text,logo text,status text,pricing jsonb,date_created timestamptz,created_at timestamptz,
 owner_name text,email text,password text,staff jsonb,audit_logs jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $visible$

 SELECT g.id,g.gym_name,g.token,g.logo,g.status,jsonb_build_object('day',g.pricing->'day','week',g.pricing->'week','month',g.pricing->'month','studentDiscount',g.pricing->'studentDiscount','seniorDiscount',g.pricing->'seniorDiscount'),g.date_created,g.created_at,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN g.owner_name ELSE NULL END AS owner_name,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN coalesce((SELECT contact_email FROM ironvault_private.branch_accounts a WHERE a.tenant_id=g.id AND a.role='owner'),g.email) ELSE NULL END AS email,
 NULL::text AS password,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN
  coalesce((SELECT jsonb_agg(jsonb_build_object('name',s.value->>'name','email',s.value->>'email','auth_user_id',s.value->>'auth_user_id','dateCreated',s.value->>'dateCreated')) FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s
   WHERE EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.tenant_id=g.id AND r.disabled_at IS NULL AND r.role='staff' AND r.user_id::text=s.value->>'auth_user_id')),'[]'::jsonb)
 ELSE '[]'::jsonb END AS staff,'[]'::jsonb AS audit_logs
 FROM public.owners g WHERE g.status IN ('ACTIVE','PROVISIONING') OR public.iv_can_access(g.id);
$visible$;
CREATE OR REPLACE VIEW public.iv_gyms WITH(security_barrier=true) AS SELECT * FROM public.iv_visible_gyms();
DO $acl$
DECLARE t text; signature text;
BEGIN
 FOREACH t IN ARRAY ARRAY['branch_accounts','provision_requests','email_actions','auth_rate_windows'] LOOP
  EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',t);
  EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['public.iv_auth_rate_limit(text,integer,integer)',
 'public.iv_branch_identity(text,text[],text)','public.iv_prepare_branch_account(uuid,uuid,text,text,text,text,jsonb,boolean)',
 'public.iv_find_created_account(uuid)','public.iv_finish_branch_account(uuid,uuid)',
 'public.iv_queue_email_action(uuid,text,text,uuid,text)','public.iv_confirm_email_action(text)',
 'public.iv_branch_account_details(uuid)','public.iv_lookup_branch_account(text,text[],text)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',signature);
 END LOOP;
END $acl$;
REVOKE ALL ON FUNCTION public.iv_member_auth_signup() FROM PUBLIC,anon,authenticated;
NOTIFY pgrst,'reload schema';

SELECT role,count(*) FROM ironvault_private.branch_accounts GROUP BY role;
-- Original snapshot expected 4 member/2 owner; no staff; no Auth account changed.
-- If backfill/uniqueness/role dependencies fail, ROLLBACK, preserve all rows and
-- return the error. Never force success by deleting accounts/history.


-- ===== SOURCE 202611010015_reports_and_profile_restore.sql SHA256 0834dcfa6f3353e057493704bcb76076d7cf13a2cb5ff0513537ba09d42b6bd0 =====
-- MANUAL ONLY after 012-014. Scoped report snapshot (no API row truncation)
-- and atomic PROFILE/BRANDING restore. Never restores wallet/ledger/credentials.

SET LOCAL search_path=pg_catalog;
CREATE FUNCTION public.iv_report_snapshot(p_tenant text,p_start date,p_end date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb; start_at timestamptz; end_at timestamptz;
BEGIN
 IF NOT ironvault_private.can_read_financial_reports(p_tenant) OR p_start IS NULL OR p_end IS NULL OR p_end<p_start THEN
  RAISE EXCEPTION 'Not authorized or invalid report dates'; END IF;
 start_at:=p_start::timestamp AT TIME ZONE 'Asia/Manila';end_at:=(p_end+1)::timestamp AT TIME ZONE 'Asia/Manila';
 SELECT jsonb_build_object(
  'financial',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_financial_transactions x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'attendance',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_attendance_logs x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'activity',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_activity_logs x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'sessions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC) FROM public.iv_staff_sessions x WHERE tenant_id=p_tenant AND created_at>=start_at AND created_at<end_at),'[]'::jsonb),
  'members',coalesce((SELECT jsonb_agg(jsonb_build_object('id',m.id,'tenant_id',m.tenant_id,'name',m.name,'classification',m.classification,
    'plan',m.plan,'wallet_balance',m.wallet_balance,'status',m.status)) FROM public.members m WHERE tenant_id=p_tenant),'[]'::jsonb)) INTO result;
 RETURN result;
END $fn$;
CREATE FUNCTION public.iv_restore_profiles(p_gyms jsonb,p_members jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 -- Atomic profile/branding-only restore of existing records. Unknown identities,
 -- tenant moves and unauthorized rows abort the whole RPC; no implicit creation.
 PERFORM public.iv_save_gym_settings(p_gyms);
 PERFORM public.iv_save_member_profiles(p_members);
END $fn$;
ALTER POLICY iv_activity_read ON public.iv_activity_logs USING(ironvault_private.can_read_financial_reports(tenant_id));
ALTER POLICY iv_sessions_read ON public.iv_staff_sessions USING(
 ironvault_private.can_read_financial_reports(tenant_id) OR (actor_id=auth.uid() AND public.iv_can_access(tenant_id)));
CREATE OR REPLACE FUNCTION public.iv_list_staff_financial_report_access(p_tenant text)
RETURNS TABLE(user_id uuid,email text,financial_reports_read boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT ironvault_private.is_gym_administrator(p_tenant) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 RETURN QUERY SELECT r.user_id,a.contact_email,EXISTS(SELECT 1 FROM ironvault_private.staff_report_permissions p
  WHERE p.tenant_id=p_tenant AND p.user_id=r.user_id AND p.permission='financial_reports_read')
 FROM public.iv_user_roles r JOIN ironvault_private.branch_accounts a ON a.user_id=r.user_id
 WHERE r.enabled AND r.role='staff' AND r.tenant_id=p_tenant;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_set_staff_financial_report_access(p_tenant text,p_user uuid,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF p_user IS NULL OR p_enabled IS NULL OR nullif(btrim(p_tenant),'') IS NULL THEN
  RAISE EXCEPTION 'Tenant, target account and explicit permission state are required';
 END IF;
 IF NOT ironvault_private.is_gym_administrator(p_tenant) THEN RAISE EXCEPTION 'Not authorized'; END IF;
 IF p_enabled THEN
  IF p_user=auth.uid() THEN RAISE EXCEPTION 'Cannot grant financial-report permission to yourself'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.owners gym WHERE gym.id::text=p_tenant)
   OR NOT EXISTS(SELECT 1 FROM public.iv_user_roles staff
    WHERE staff.user_id=p_user AND staff.tenant_id::text=p_tenant AND staff.role='staff' AND staff.enabled) THEN
   RAISE EXCEPTION 'Target is not a current staff account in this gym';
  END IF;
  INSERT INTO ironvault_private.staff_report_permissions(tenant_id,user_id,permission,granted_by)
   VALUES(p_tenant,p_user,'financial_reports_read',auth.uid())
   ON CONFLICT(tenant_id,user_id,permission) DO UPDATE
    SET granted_by=auth.uid(),granted_at=pg_catalog.now();
 ELSE
  -- Revocation remains possible after the recipient's staff role is removed.
  DELETE FROM ironvault_private.staff_report_permissions permission
   WHERE permission.tenant_id=p_tenant AND permission.user_id=p_user
    AND permission.permission='financial_reports_read';
 END IF;
 -- An audit failure rolls back the permission change, rather than silently granting.
 PERFORM public.iv_log_event(p_tenant,
  CASE WHEN p_enabled THEN 'Financial report access granted' ELSE 'Financial report access revoked' END,
  'Target Auth account: '||p_user::text);
END
$function$;
DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.iv_report_snapshot(text,date,date)','public.iv_restore_profiles(jsonb,jsonb)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated,service_role',signature);
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';

SELECT oid::regprocedure,has_function_privilege('anon',oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute FROM pg_proc
WHERE oid IN ('public.iv_report_snapshot(text,date,date)'::regprocedure,'public.iv_restore_profiles(jsonb,jsonb)'::regprocedure);
-- Expect anon false/auth true. No report/RPC is executed by this verification.
-- No financial/identity restore, reset, truncation or deletion is included.


-- ===== SOURCE 202611010016_member_optional_email_verification.sql SHA256 0847b6a001760030298ad3f7dcee96b62e5f75b7693612afaca91d331b5708a0 =====
-- Apply only after migrations 001-015. No Auth DML or record deletion.
-- Members may sign in without contact verification. Gym approval remains separate.

CREATE OR REPLACE FUNCTION public.iv_branch_identity(p_tenant text,p_roles text[],p_email text)
RETURNS TABLE(user_id uuid,role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT a.user_id,a.role FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id
 WHERE a.tenant_id=p_tenant AND a.role=ANY(p_roles) AND a.contact_email=lower(btrim(p_email))
  AND (a.contact_verified OR a.role='member') AND r.enabled AND r.tenant_id=a.tenant_id AND r.role=a.role;
$fn$;


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
 IF job.role<>'owner' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=job.tenant_id AND (status='ACTIVE' OR (status='PROVISIONING' AND job.role='staff' AND EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=job.actor_id AND enabled AND role='super_admin')))) THEN RAISE EXCEPTION 'Gym unavailable'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user AND email=job.alias AND raw_app_meta_data->>'iv_provision_request'=p_request::text) THEN
  RAISE EXCEPTION 'Auth account does not match protected provisioning metadata'; END IF;
 IF job.role='member' THEN
  member_id:='MEM-'||gen_random_uuid()::text;
  SELECT o.token INTO STRICT token FROM public.owners o WHERE o.id=job.tenant_id;
  INSERT INTO public.members(id,tenant_id,tenant_token,name,email,phone,password,auth_user_id,
   classification,discount_percentage,plan,wallet_balance,amount,scans_used,status,date_joined)
  VALUES(member_id,job.tenant_id,token,job.payload->>'name',job.contact_email,coalesce(job.payload->>'phone',''),NULL,p_user,
   'Regular',0,'Not Selected',0,0,0,CASE WHEN job.actor_id IS NULL THEN 'PENDING' ELSE 'ACTIVE' END,
   ((now() AT TIME ZONE 'Asia/Manila')::date)::text);
 END IF;
 INSERT INTO public.iv_user_roles(user_id,tenant_id,role,member_id,enabled) VALUES(p_user,job.tenant_id,job.role,member_id,job.role='member');
 INSERT INTO ironvault_private.branch_accounts(tenant_id,role,contact_email,user_id) VALUES(job.tenant_id,job.role,job.contact_email,p_user);
 IF job.role='staff' THEN
  UPDATE public.owners SET staff=coalesce(staff,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('name',job.payload->>'name',
   'email',job.contact_email,'auth_user_id',p_user,'dateCreated',((now() AT TIME ZONE 'Asia/Manila')::date)::text)) WHERE id=job.tenant_id;
 END IF;
 UPDATE ironvault_private.provision_requests SET completed_user=p_user WHERE request_id=p_request;
 RETURN jsonb_build_object('ok',true,'tenantId',job.tenant_id,'member_id',member_id,'user_id',p_user);
END $fn$;


CREATE OR REPLACE FUNCTION public.iv_save_member_profiles(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; m public.members%ROWTYPE; tenant text; operator boolean; owner_access boolean; discount numeric;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>500 THEN RAISE EXCEPTION 'Invalid profile batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO m FROM public.members WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Create member accounts through registration; restore cannot create financial records'; END IF;
  tenant:=m.tenant_id;operator:=public.iv_can_access(tenant);owner_access:=public.iv_can_access(tenant,ARRAY['owner']::text[]);
  IF NOT operator AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
   AND r.role='member' AND r.member_id=m.id AND r.tenant_id=tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=tenant AND g.status='ACTIVE')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF item ? 'tenant_id' AND item->>'tenant_id' IS DISTINCT FROM tenant THEN RAISE EXCEPTION 'Cannot move membership'; END IF;
  IF length(coalesce(item->>'name',m.name)) NOT BETWEEN 1 AND 160 OR length(coalesce(item->>'phone',''))>50
   OR length(coalesce(item->>'avatar',''))>750000 THEN RAISE EXCEPTION 'Invalid profile fields'; END IF;
  IF item ? 'email' AND lower(btrim(item->>'email')) IS DISTINCT FROM lower(btrim(m.email)) THEN
   RAISE EXCEPTION 'Contact email changes require verification'; END IF;
  -- Names/phone/avatar are personal edits. Operators additionally manage approval,
  -- classification and card IDs; only gym administrators change a discount.
  IF operator AND item ? 'status' AND item->>'status' NOT IN ('ACTIVE','PENDING','INACTIVE') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF operator AND item ? 'classification' AND item->>'classification' NOT IN ('Regular','Student','Senior') THEN RAISE EXCEPTION 'Invalid classification'; END IF;
  IF operator AND NOT owner_access AND m.status='INACTIVE' AND item->>'status'='ACTIVE' THEN RAISE EXCEPTION 'Gym administrator required to restore inactive membership'; END IF;
  discount:=coalesce(m.discount_percentage,0);
  IF operator AND item ? 'classification' AND item->>'classification' IS DISTINCT FROM m.classification THEN
   SELECT CASE WHEN item->>'classification'='Student' THEN (g.pricing->>'studentDiscount')::numeric
    WHEN item->>'classification'='Senior' THEN (g.pricing->>'seniorDiscount')::numeric ELSE 0 END
   INTO discount FROM public.owners g WHERE g.id=tenant;
  END IF;
  IF owner_access AND item ? 'discount_percentage' THEN
   discount:=(item->>'discount_percentage')::numeric;
   IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  END IF;
  IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid configured member discount'; END IF;
  UPDATE public.members SET name=coalesce(item->>'name',name),phone=CASE WHEN item ? 'phone' THEN item->>'phone' ELSE phone END,
   avatar=CASE WHEN item ? 'avatar' THEN item->>'avatar' ELSE avatar END,
   status=CASE WHEN operator THEN coalesce(item->>'status',status) ELSE status END,
   classification=CASE WHEN operator THEN coalesce(item->>'classification',classification) ELSE classification END,
   card_barcode=CASE WHEN operator AND item ? 'card_barcode' THEN item->>'card_barcode' ELSE card_barcode END,
   discount_percentage=discount WHERE id=m.id;
  IF owner_access AND item->>'status'='ACTIVE' AND EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a JOIN public.iv_user_roles r ON r.user_id=a.user_id WHERE r.member_id=m.id AND a.tenant_id=tenant AND r.tenant_id=tenant ) THEN
   UPDATE public.iv_user_roles SET enabled=true,disabled_at=NULL WHERE member_id=m.id AND tenant_id=tenant AND role='member';
  END IF;
  INSERT INTO public.iv_activity_logs(tenant_id,actor_id,event,details) VALUES(tenant,auth.uid(),'Member profile updated',m.id);
 END LOOP;
END $fn$;

-- Resume member accounts blocked only by the previous mail gate; preserve explicit
-- revocations (disabled_at) and inactive memberships. Contact remains unverified.
UPDATE public.iv_user_roles r SET enabled=true
FROM ironvault_private.branch_accounts a, public.members m
WHERE r.user_id=a.user_id AND r.role='member' AND a.role='member'
 AND r.tenant_id=a.tenant_id AND m.id=r.member_id AND m.tenant_id=r.tenant_id
 AND m.status IN ('ACTIVE','PENDING') AND NOT r.enabled AND r.disabled_at IS NULL;


-- ===== SOURCE 202611010017_super_admin_tenant_purge.sql SHA256 625659a16bed79016dd3cce97189d0f4350097f7c9347e3f9ba7fc54b7db3469 =====
-- MANUAL INSTALL ONLY, after 016. Defines a destructive API; does not purge data.
-- Application data is deleted atomically; Auth deletion uses the supported Admin API.

CREATE TABLE ironvault_private.tenant_purge_jobs (
 request_id uuid PRIMARY KEY,
 tenant_id text NOT NULL UNIQUE,
 actor_id uuid NOT NULL,
 pending_users uuid[] NOT NULL,
 summary jsonb NOT NULL,
 retained_accounts integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ironvault_private.tenant_purge_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ironvault_private.tenant_purge_jobs FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION ironvault_private.tenant_purge_summary(p_tenant text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT jsonb_build_object('tenant_id',g.id,'gym_name',g.gym_name,
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
REVOKE ALL ON FUNCTION ironvault_private.tenant_purge_summary(text) FROM PUBLIC,anon,authenticated,service_role;
-- Preserve identities still referenced by another gym or another application table.
CREATE FUNCTION ironvault_private.purge_auth_is_shared(p_user uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE link record; present boolean;
BEGIN
 IF EXISTS(SELECT 1 FROM public.members WHERE auth_user_id=p_user) THEN RETURN true; END IF;
 FOR link IN SELECT c.conrelid::regclass AS relation,a.attname AS column_name
  FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_class t ON t.oid=c.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
  WHERE c.contype='f' AND c.confrelid='auth.users'::regclass
   AND cardinality(c.conkey)=1 AND n.nspname IN ('public','ironvault_private')
 LOOP
  EXECUTE pg_catalog.format('SELECT EXISTS(SELECT 1 FROM %s WHERE %I=$1)',link.relation,link.column_name)
   INTO present USING p_user;
  IF present THEN RETURN true; END IF;
 END LOOP;
 RETURN false;
END $fn$;
REVOKE ALL ON FUNCTION ironvault_private.purge_auth_is_shared(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.iv_tenant_purge_control(p_actor uuid,p_action text,p_tenant text DEFAULT NULL,
 p_request uuid DEFAULT NULL,p_review jsonb DEFAULT NULL,p_confirmation text DEFAULT NULL,p_user uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE job ironvault_private.tenant_purge_jobs%ROWTYPE; users uuid[]; review jsonb;
BEGIN
 -- Only service_role can call this API. The Edge function supplies its verified actor.
 PERFORM 1 FROM public.iv_user_roles WHERE user_id=p_actor AND role='super_admin' AND tenant_id IS NULL AND enabled FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Super Admin required'; END IF;
 IF p_action='list' THEN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('request_id',request_id,'tenant_id',tenant_id,
   'remaining',cardinality(pending_users))) FROM ironvault_private.tenant_purge_jobs),'[]'::jsonb);
 END IF;
 IF p_action='preview' THEN
  review:=ironvault_private.tenant_purge_summary(p_tenant);
  IF review IS NULL THEN RAISE EXCEPTION 'Gym not found'; END IF;
  RETURN review;
 END IF;
 IF p_request IS NULL OR p_tenant IS NULL THEN RAISE EXCEPTION 'Invalid purge request'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant,17));
 SELECT * INTO job FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request FOR UPDATE;
 IF FOUND AND job.tenant_id<>p_tenant THEN RAISE EXCEPTION 'Purge request belongs to another gym'; END IF;
 IF p_action='start' AND job.request_id IS NULL THEN
  IF p_confirmation IS DISTINCT FROM 'PURGE '||p_tenant THEN RAISE EXCEPTION 'Exact tenant confirmation required'; END IF;
  PERFORM 1 FROM public.owners WHERE id=p_tenant FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Gym not found'; END IF;
  review:=ironvault_private.tenant_purge_summary(p_tenant);
  IF p_review IS DISTINCT FROM review THEN RAISE EXCEPTION 'Gym changed; review the purge again'; END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.tenant_purge_jobs WHERE tenant_id=p_tenant) THEN RAISE EXCEPTION 'Resume the existing purge'; END IF;
  SELECT coalesce(array_agg(DISTINCT id),'{}'::uuid[]) INTO users FROM (
   SELECT user_id AS id FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant
   UNION SELECT user_id FROM public.iv_user_roles WHERE tenant_id=p_tenant
   UNION SELECT auth_user_id FROM public.members WHERE tenant_id=p_tenant AND auth_user_id IS NOT NULL
   UNION SELECT completed_user FROM ironvault_private.provision_requests WHERE tenant_id=p_tenant AND completed_user IS NOT NULL
   UNION SELECT u.id FROM auth.users u JOIN ironvault_private.provision_requests p
    ON u.raw_app_meta_data->>'iv_provision_request'=p.request_id::text WHERE p.tenant_id=p_tenant
  ) candidates WHERE candidates.id<>p_actor AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=candidates.id AND r.role='super_admin')
   AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=candidates.id AND r.tenant_id IS DISTINCT FROM p_tenant)
   AND NOT EXISTS(SELECT 1 FROM public.members m WHERE m.auth_user_id=candidates.id AND m.tenant_id<>p_tenant)
   AND NOT EXISTS(SELECT 1 FROM ironvault_private.branch_accounts a WHERE a.user_id=candidates.id AND a.tenant_id<>p_tenant);
  INSERT INTO ironvault_private.tenant_purge_jobs(request_id,tenant_id,actor_id,pending_users,summary)
   VALUES(p_request,p_tenant,p_actor,users,review);
  DELETE FROM ironvault_private.email_actions WHERE user_id IN (SELECT user_id FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant);
  DELETE FROM ironvault_private.staff_report_permissions WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.daily_passes WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.financial_requests WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_staff_sessions WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_attendance_logs WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_financial_transactions WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_activity_logs WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.provision_requests WHERE tenant_id=p_tenant;
  DELETE FROM ironvault_private.branch_accounts WHERE tenant_id=p_tenant;
  DELETE FROM public.iv_user_roles WHERE tenant_id=p_tenant;
  DELETE FROM public.members WHERE tenant_id=p_tenant;
  DELETE FROM public.owners WHERE id=p_tenant;
  SELECT * INTO STRICT job FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request;
 END IF;
 IF job.request_id IS NULL THEN
  IF p_action='next' AND NOT EXISTS(SELECT 1 FROM public.owners WHERE id=p_tenant) THEN RETURN jsonb_build_object('complete',true); END IF;
  RAISE EXCEPTION 'Purge job not found';
 END IF;
 IF p_action='check' THEN
  IF p_user IS NULL OR NOT p_user=ANY(job.pending_users) THEN RAISE EXCEPTION 'Account not in purge job'; END IF;
  RETURN jsonb_build_object('eligible',p_user<>p_actor AND NOT ironvault_private.purge_auth_is_shared(p_user),
   'shared',p_user=p_actor OR ironvault_private.purge_auth_is_shared(p_user));
 END IF;
 IF p_action='retain' THEN
  IF p_user IS NULL OR NOT p_user=ANY(job.pending_users)
   OR (p_user<>p_actor AND NOT ironvault_private.purge_auth_is_shared(p_user)) THEN RAISE EXCEPTION 'Account is not shared'; END IF;
  UPDATE ironvault_private.tenant_purge_jobs SET pending_users=array_remove(pending_users,p_user),
   retained_accounts=retained_accounts+1 WHERE request_id=p_request;
 ELSIF p_action='ack' THEN
  IF p_user IS NULL OR NOT p_user=ANY(job.pending_users) THEN RAISE EXCEPTION 'Account not in purge job'; END IF;
  -- Only acknowledge confirmed Admin API deletion, never delete auth.users in SQL.
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=p_user) THEN RAISE EXCEPTION 'Auth account still exists'; END IF;
  UPDATE ironvault_private.tenant_purge_jobs SET pending_users=array_remove(pending_users,p_user) WHERE request_id=p_request;
 ELSIF p_action='finish' THEN
  IF cardinality(job.pending_users)<>0 THEN RAISE EXCEPTION 'Auth cleanup incomplete'; END IF;
  DELETE FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request;
  RETURN jsonb_build_object('complete',true,'retained_accounts',job.retained_accounts);
 ELSIF p_action NOT IN ('start','next') THEN RAISE EXCEPTION 'Unknown purge action'; END IF;
 SELECT * INTO STRICT job FROM ironvault_private.tenant_purge_jobs WHERE request_id=p_request;
 RETURN jsonb_build_object('request_id',job.request_id,'tenant_id',job.tenant_id,'pending_users',job.pending_users,
  'remaining',cardinality(job.pending_users),'retained_accounts',job.retained_accounts);
END $fn$;
REVOKE ALL ON FUNCTION public.iv_tenant_purge_control(uuid,text,text,uuid,jsonb,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iv_tenant_purge_control(uuid,text,text,uuid,jsonb,text,uuid) TO service_role;


-- Preserve every pre-existing identity/financial/audit row through schema cutover.
DO $preservation$
DECLARE actual jsonb;
BEGIN
 SELECT jsonb_build_object(
 'auth', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,email,email_confirmed_at)::text,'|' ORDER BY id),'')) FROM auth.users),
 'roles', (SELECT md5(coalesce(string_agg(jsonb_build_array(user_id,tenant_id,role,member_id)::text,'|' ORDER BY user_id),'')) FROM public.iv_user_roles),
 'members', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,tenant_id,wallet_balance,amount,plan,expiration_date,scans_used,last_scanned_date,status)::text,'|' ORDER BY id),'')) FROM public.members),
 'gyms', (SELECT md5(coalesce(string_agg(jsonb_build_array(id,email,token,status,pricing)::text,'|' ORDER BY id),'')) FROM public.owners),
 'ledger', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_financial_transactions x),
 'attendance', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_attendance_logs x),
 'activity', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_activity_logs x),
 'sessions', (SELECT md5(coalesce(string_agg(to_jsonb(x)::text,'|' ORDER BY id),'')) FROM public.iv_staff_sessions x)
) INTO actual;
 IF actual IS DISTINCT FROM (SELECT snapshot FROM pg_temp.iv_phase1_preservation) THEN
  RAISE EXCEPTION 'Preservation check failed: entire installation rolled back; do not reset data';
 END IF;
END
$preservation$;
COMMIT;
-- The temporary preservation object is removed on commit; no existing table is dropped.
-- Read-only final acceptance. No business RPC is invoked.
-- MANUAL, READ-ONLY acceptance after all approved migrations. No RPCs invoked.
-- V1/V2 may also be exported BEFORE migration as a preservation baseline, then
-- compared after. These are acceptance checks, not requests to repeat inspections.
-- V1: account/role/member counts. Existing identities must not disappear.
SELECT (SELECT count(*) FROM auth.users) AS auth_users,
 (SELECT count(*) FROM public.owners) AS gyms,
 (SELECT count(*) FROM public.members) AS members,
 (SELECT count(*) FROM public.iv_user_roles) AS role_rows;
-- V2: financial preservation. Schema cutover itself must not alter these values.
SELECT (SELECT coalesce(sum(wallet_balance),0) FROM public.members) AS wallet_total,
 (SELECT count(*) FROM public.iv_financial_transactions) AS ledger_rows,
 (SELECT coalesce(sum(amount),0) FROM public.iv_financial_transactions) AS ledger_amount_total,
 (SELECT count(*) FROM public.iv_attendance_logs) AS attendance_rows;
-- V3: base API access must be false, including effective inherited column grants.
SELECT r,t,has_any_column_privilege(r,t,'SELECT') AS can_read_base,
 has_any_column_privilege(r,t,'UPDATE') AS can_update_base,
 has_any_column_privilege(r,t,'INSERT') AS can_insert_base,
 has_table_privilege(r,t,'DELETE') AS can_delete_base,
 has_table_privilege(r,t,'TRUNCATE') AS can_truncate_base
FROM unnest(ARRAY['anon','authenticated']) r CROSS JOIN unnest(ARRAY['public.owners','public.members']) t;
-- V4: no broad public policy; schema/view ACLs are separate from function ACLs.
SELECT schemaname,tablename,policyname,roles,cmd,qual,with_check FROM pg_policies
WHERE schemaname='public' AND tablename IN ('owners','members','iv_user_roles','iv_financial_transactions','iv_attendance_logs')
ORDER BY tablename,policyname;
-- V5: only iv_visible_gyms() deliberately allows anon branding access; other
-- definer entry points deny anon. Service-only account helpers deny auth too.
SELECT n.nspname,p.oid::regprocedure,p.prosecdef,p.proconfig,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
 has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='public' AND p.proname LIKE 'iv_%') OR n.nspname='ironvault_private'
ORDER BY n.nspname,p.proname;
-- V6: preserved Auth signup trigger and explicit RLS on every private table.
SELECT t.tgname,pg_get_triggerdef(t.oid) FROM pg_trigger t
WHERE t.tgrelid='auth.users'::regclass AND NOT t.tgisinternal;
SELECT c.relname,c.relrowsecurity,pg_get_userbyid(c.relowner) AS owner
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='ironvault_private' AND c.relkind='r';
-- V7: do not expose ironvault_private through Dashboard Data API configuration.
SELECT rolname,rolsuper,rolbypassrls FROM pg_roles WHERE rolname IN ('anon','authenticated');
