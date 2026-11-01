-- MANUAL ONLY. Additive foundation after 005/006/008. No legacy rows changed.
-- Existing global ledger request uniqueness is retained; no IDs are backfilled.
BEGIN;
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
COMMIT;
SELECT c.relrowsecurity,pg_get_userbyid(c.relowner) AS owner,
 has_table_privilege('authenticated',c.oid,'SELECT') AS client_select,
 has_table_privilege('authenticated',c.oid,'INSERT') AS client_insert
FROM pg_class c WHERE c.oid='ironvault_private.financial_requests'::regclass;
-- Expect RLS true, owner postgres, client false. On error ROLLBACK; no resets.
