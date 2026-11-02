// Static SQL/security contracts only; this suite executes no SQL or database calls.
const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const dir='supabase/migrations/';
const read=name=>fs.readFileSync(dir+name,'utf8');
const defaults=[read('202611010003_restrict_postgres_public_defaults.sql'),read('202611010004_restrict_supabase_admin_public_defaults.sql')];
const writes=read('202611010005_protect_role_and_history_grants.sql');
const permissions=read('202611010006_staff_financial_report_permissions.sql');
const policies=read('202611010007_fix_financial_attendance_rls.sql');
test('future default cleanup is creator/public-schema scoped and does not revoke existing RPCs or global platform defaults',()=>{
 for(const [index,sql]of defaults.entries()){
  const creator=index?'supabase_admin':'postgres';
  assert.match(sql,new RegExp(`ALTER DEFAULT PRIVILEGES FOR ROLE ${creator} IN SCHEMA public\\s+REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated`));
  assert.match(sql,new RegExp(`ALTER DEFAULT PRIVILEGES FOR ROLE ${creator} IN SCHEMA public\\s+REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated`));
  assert.match(sql,/global PUBLIC EXECUTE/i);assert.match(sql,/pg_has_role/);assert.match(sql,/RAISE EXCEPTION/);
  assert.doesNotMatch(sql,/ALTER ROLE|GRANT .* TO (?:postgres|supabase_admin)|REVOKE EXECUTE ON FUNCTION public\./i);
 }
});
test('authority/history grant cleanup preserves authenticated SELECT, definer writes and existing function EXECUTE',()=>{
 for(const table of ['iv_user_roles','iv_financial_transactions','iv_attendance_logs','iv_activity_logs','iv_staff_sessions'])assert.ok(writes.includes(table));
 assert.match(writes,/GRANT SELECT ON TABLE/);assert.match(writes,/REVOKE SELECT \(%I\), INSERT/);
 assert.match(writes,/p\.prosecdef/);assert.match(writes,/NOT c\.relforcerowsecurity/);
 assert.doesNotMatch(writes,/REVOKE[^;]*ON FUNCTION/i);
});
test('financial and attendance policies bind both member and tenant to the actual outer row',()=>{
 for(const table of ['iv_financial_transactions','iv_attendance_logs']){
  assert.ok(policies.includes(`membership.member_id::text=public.${table}.member_id::text`));
  assert.ok(policies.includes(`membership.tenant_id::text=public.${table}.tenant_id::text`));
 }
 assert.doesNotMatch(policies,/membership\.(member_id|tenant_id)\s*(?:::text)?\s*=\s*membership\./);
 assert.match(policies,/membership\.role='member'/);assert.match(policies,/count\(\*\).*pg_policy/);
 assert.match(policies,/pg_inherits/);assert.match(policies,/qual_md5/);
 const finance=policies.split('ALTER POLICY iv_financial_read')[1].split('ALTER POLICY iv_attendance_read')[0];
 assert.match(finance,/ironvault_private\.can_read_financial_reports/);assert.doesNotMatch(finance,/public\.iv_can_access/);
});
test('staff report flags alone do not grant access without current tenant roles',()=>{
 const body=permissions.split('CREATE FUNCTION ironvault_private.can_read_financial_reports')[1].split('$function$;')[0];
 assert.match(body,/actor\.user_id=auth\.uid\(\)/);assert.match(body,/actor\.role='staff'/);
 assert.match(body,/actor\.tenant_id::text=p_tenant/);assert.match(body,/permission\.user_id=actor\.user_id/);
 assert.match(body,/permission\.tenant_id=p_tenant/);assert.match(body,/financial_reports_read/);
 assert.doesNotMatch(body,/raw_user_meta_data|jwt\(/);
});
test('permission mutation requires administrator authority, denies self-grant, validates staff scope and audits atomically',()=>{
 const body=permissions.split('CREATE FUNCTION public.iv_set_staff_financial_report_access')[1].split('$function$;')[0];
 assert.match(body,/IF NOT ironvault_private\.is_gym_administrator/);
 assert.match(body,/IF p_user=auth\.uid\(\) THEN RAISE EXCEPTION/);
 assert.match(body,/staff\.user_id=p_user AND staff\.tenant_id::text=p_tenant AND staff\.role='staff'/);
 assert.match(body,/DELETE FROM ironvault_private\.staff_report_permissions/);
 assert.match(body,/PERFORM public\.iv_log_event/);
 assert.match(permissions,/REVOKE ALL ON TABLE ironvault_private\.staff_report_permissions/);
 assert.match(permissions,/ENABLE ROW LEVEL SECURITY/);
});
test('every new function explicitly clears PUBLIC/anonymous defaults in its creation transaction',()=>{
 const identities=['ironvault_private.is_gym_administrator(text)','ironvault_private.can_read_financial_reports(text)',
  'public.iv_can_read_financial_reports(text)','public.iv_set_staff_financial_report_access(text,uuid,boolean)',
  'public.iv_list_staff_financial_report_access(text)'];
 for(const identity of identities)assert.ok(permissions.includes(`REVOKE ALL ON FUNCTION ${identity} FROM PUBLIC, anon, authenticated, service_role;`));
 assert.match(permissions,/GRANT EXECUTE ON FUNCTION public\.iv_can_read_financial_reports\(text\) TO authenticated, service_role/);
 assert.doesNotMatch(permissions,/CREATE OR REPLACE|DROP SCHEMA|DROP TABLE|UPDATE public\.(members|owners)|DELETE FROM public\./i);
});
test('M4 correction is transactional and does not reset accounts, balances, or financial history',()=>{
 for(const sql of [writes,permissions,policies]){
  assert.match(sql,/\bBEGIN;/);assert.match(sql,/COMMIT;/);
  assert.doesNotMatch(sql,/(?:^|;)\s*(?:TRUNCATE|DELETE FROM public\.|UPDATE public\.(?:members|owners)|DROP TABLE|DROP FUNCTION)/im);
 }
 assert.match(policies,/ALTER POLICY iv_financial_read/);assert.match(policies,/ALTER POLICY iv_attendance_read/);
});
