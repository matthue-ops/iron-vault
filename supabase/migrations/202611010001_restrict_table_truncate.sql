-- MANUAL REVIEW/EXECUTION ONLY. Not applied by the agent.
-- Classification: behavior-changing privileges; no row, balance, history or schema reset.
-- Purpose: remove the unnecessary TRUNCATE grants confirmed by inspection 2A.
-- Prerequisites: intended project, existing public.owners/public.members and standard
-- API roles; execute as the authorized database owner. No application uses TRUNCATE.
-- Order: first of the two grant-only hardening migrations. Broader RLS remains pending.
-- Repeating this file is safe. If an assertion fails, ROLLBACK before other SQL.
-- Recovery: transaction failure changes nothing. After commit, investigate any
-- dependency rather than restoring broad destructive privileges to API roles.
BEGIN;
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

COMMIT;

-- Verification: all four rows must return false. This does not verify CRUD/RLS safety.
SELECT r.api_role, t.relation_name,
  has_table_privilege(r.api_role, t.relation_name, 'TRUNCATE') AS can_truncate
FROM (VALUES ('anon'),('authenticated')) AS r(api_role)
CROSS JOIN (VALUES ('public.owners'),('public.members')) AS t(relation_name);
