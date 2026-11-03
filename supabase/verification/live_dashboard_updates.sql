-- USER-RUN, READ-ONLY metadata checks after 027. No business writes or RPC calls.
-- Expect one iv_live_signals entry; inspect any pre-existing publication members separately.
SELECT schemaname,tablename FROM pg_publication_tables WHERE pubname='supabase_realtime' ORDER BY schemaname,tablename;
SELECT pubname,puballtables,pubinsert,pubupdate FROM pg_publication WHERE pubname='supabase_realtime';
-- Expect authenticated SELECT true, anon SELECT false and authenticated writes false.
-- Inspect service_role privileges separately if your project has custom role inheritance.
SELECT role_name,
 has_table_privilege(role_name::name,'public.iv_live_signals','SELECT') AS can_select,
 has_table_privilege(role_name::name,'public.iv_live_signals','INSERT') AS can_insert,
 has_table_privilege(role_name::name,'public.iv_live_signals','UPDATE') AS can_update,
 has_table_privilege(role_name::name,'public.iv_live_signals','DELETE') AS can_delete
FROM (VALUES('anon'),('authenticated'),('service_role')) roles(role_name);
SELECT relrowsecurity FROM pg_class WHERE oid='public.iv_live_signals'::regclass;
SELECT policyname,roles,cmd,qual FROM pg_policies WHERE schemaname='public' AND tablename='iv_live_signals';
-- Expect four source triggers, all deferrable and initially deferred.
SELECT tgname,tgrelid::regclass AS source,tgdeferrable,tginitdeferred FROM pg_trigger
 WHERE tgname IN ('iv_live_member_changed','iv_live_gym_changed','iv_live_role_changed','iv_live_permission_changed') ORDER BY tgname;
-- Check metadata columns and source counts without revealing member identities.
SELECT column_name,data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='iv_live_signals' ORDER BY ordinal_position;
SELECT kind,count(*) FROM public.iv_live_signals GROUP BY kind ORDER BY kind;
