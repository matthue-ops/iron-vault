-- MANUAL REVIEW/EXECUTION ONLY. Behavior-changing RLS; no rows are modified.
-- Requires 005 (write/role protection), 006 (explicit financial permission helper).
-- 003/004 are independent and do not block this urgent M4 correction.
-- Preserve SELECT access: Super Admin globally; gym owner or explicitly granted
-- staff for tenant financial reports; members only their own linked records.
-- Staff attendance remains tenant-scoped without requiring financial permission.
-- Failure aborts the transaction; ROLLBACK. Never restore the self-comparison
-- policies as rollback. Fix forward to a reviewed narrow expression instead.
BEGIN;
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
COMMIT;
-- Expected: both SELECT policies show actual outer-row member/tenant correlation;
-- financial whole-tenant access uses the explicit report permission helper.
SELECT tablename,policyname,roles,cmd,qual,with_check FROM pg_policies
WHERE schemaname='public' AND tablename IN ('iv_financial_transactions','iv_attendance_logs')
ORDER BY tablename,policyname;
