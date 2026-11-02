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
