-- MANUAL REVIEW/EXECUTION ONLY; not applied by the agent.
-- Classification: behavior-changing future defaults; no existing objects/data changed.
-- OPTIONAL platform-owned scope: do not run until executor authority is confirmed.
-- Failure must not be bypassed by altering Supabase-managed role memberships.
-- Scope: only supabase_admin's future public-schema objects. No global defaults, other
-- schemas, role attributes, ownership, service_role or postgres grants are changed.
-- PostgreSQL per-schema REVOKE cannot remove the built-in GLOBAL PUBLIC EXECUTE
-- default for functions. Every application function still needs explicit per-object
-- REVOKE FROM PUBLIC/anon and deliberate authenticated/service_role GRANT in its
-- creation transaction. Do NOT claim that this file alone denies future RPC calls.
-- No blanket global default change is made to platform-owned creators.
-- Order: after 001/002 if approved. 004 is optional; 005-007 do not depend on it.
-- Recovery: transaction failure changes nothing; ROLLBACK after any error. After
-- commit, correct only a demonstrated missing grant; do not restore broad defaults.
BEGIN;
SET LOCAL search_path = pg_catalog;
DO $authority$
BEGIN
 IF current_user <> 'supabase_admin'
   AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user)
   AND NOT pg_has_role(current_user,'supabase_admin','MEMBER') THEN
  RAISE EXCEPTION 'Executor cannot administer supabase_admin defaults. Stop; do not escalate managed role privileges';
 END IF;
END
$authority$;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
 REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
 REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated;
DO $verify$
BEGIN
 IF EXISTS (
  SELECT 1 FROM pg_default_acl d
  JOIN pg_roles creator ON creator.oid=d.defaclrole
  JOIN pg_namespace n ON n.oid=d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
  WHERE creator.rolname='supabase_admin' AND n.nspname='public'
   AND d.defaclobjtype IN ('f','r')
   AND (acl.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated'))
        OR (d.defaclobjtype='r' AND acl.grantee=0))
 ) THEN RAISE EXCEPTION 'Unexpected explicit public-schema API default grant remains'; END IF;
END
$verify$;
COMMIT;
-- Review only the targeted explicit defaults. This does not account for the
-- built-in/global PUBLIC function EXECUTE default; per-object ACLs remain required.
SELECT r.rolname AS object_creator,n.nspname AS schema_name,
 d.defaclobjtype AS object_type,d.defaclacl
FROM pg_default_acl d JOIN pg_roles r ON r.oid=d.defaclrole
JOIN pg_namespace n ON n.oid=d.defaclnamespace
WHERE r.rolname='supabase_admin' AND n.nspname='public' AND d.defaclobjtype IN ('f','r');
