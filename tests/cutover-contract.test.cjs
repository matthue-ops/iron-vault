const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const read=n=>fs.readFileSync('supabase/migrations/'+n,'utf8');
test('cutover removes exact public policies and direct column/table privileges without deleting records',()=>{
 const sql=read('202611010012_scoped_application_data.sql');assert.match(sql,/DROP POLICY "Allow public access to owners"/);assert.match(sql,/DROP POLICY "Allow public access to members"/);
 assert.match(sql,/REVOKE ALL ON public\.owners,public\.members FROM PUBLIC,anon,authenticated/);assert.match(sql,/REVOKE SELECT \(%I\), INSERT/);
 assert.doesNotMatch(sql,/\b(?:DELETE FROM|TRUNCATE TABLE|DROP TABLE|DROP COLUMN)\b/i);assert.match(sql,/SET enabled=false,disabled_at=now\(\)/);
});
test('branch RPCs are service-only and existing identities are mapped rather than recreated',()=>{
 const sql=read('202611010014_branch_account_lifecycle.sql');assert.match(sql,/INSERT INTO ironvault_private\.branch_accounts/);assert.match(sql,/JOIN auth\.users u ON u\.id=r\.user_id/);
 assert.match(sql,/GRANT EXECUTE ON FUNCTION %s TO service_role/);assert.doesNotMatch(sql,/(?:INSERT INTO|UPDATE|DELETE FROM|ALTER TABLE|CREATE TABLE) auth\./i);
 assert.match(sql,/raw_app_meta_data->>'iv_provision_request'/);assert.match(sql,/Contact changed since this link was issued/);
});
test('member purchase and QR paths retain scoped enabled-role checks and replay protection',()=>{
 const sql=read('202611010013_member_wallet_and_daily_passes.sql');assert.match(sql,/p_operation='purchase' AND p_cash_amount=0 AND ironvault_private\.is_own_membership/);
 assert.match(sql,/r\.enabled/);assert.match(sql,/ticket\.tenant_id IS DISTINCT FROM p_tenant/);assert.match(sql,/ticket\.expires_at<=now\(\)/);assert.match(sql,/FOR UPDATE/);
 assert.match(sql,/QR admission requires a server-issued pass/);assert.match(sql,/UNIQUE\(member_id,business_day\)/);
});
test('report snapshot is permission-gated and cannot silently truncate API rows',()=>{
 const sql=read('202611010015_reports_and_profile_restore.sql');assert.match(sql,/STABLE SECURITY DEFINER/);assert.match(sql,/can_read_financial_reports\(p_tenant\)/);assert.match(sql,/created_at>=start_at AND created_at<end_at/);assert.doesNotMatch(sql,/LIMIT\s+\d/i);
 const html=fs.readFileSync('gym/reports.html','utf8');assert.match(html,/iv_report_snapshot/);assert.doesNotMatch(html,/limit\(10000\)/);
});
test('anonymous branding uses its own safe definer projection without reopening role helpers',()=>{
 const sql=read('202611010012_scoped_application_data.sql');assert.match(sql,/CREATE FUNCTION public\.iv_visible_gyms\(\)/);
 assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.iv_visible_gyms\(\) TO anon/);
 assert.doesNotMatch(sql,/GRANT EXECUTE ON FUNCTION public\.iv_can_access.*TO anon/);
 assert.match(sql,/SELECT \* FROM public\.iv_visible_gyms\(\)/);
});
test('manual SQL is a fresh atomic package that excludes optional managed-role mutation',()=>{
 const {spawnSync}=require('node:child_process');const check=spawnSync(process.execPath,['scripts/build-manual-sql.cjs','--check'],{encoding:'utf8'});assert.equal(check.status,0,check.stderr);
 const sql=fs.readFileSync('supabase/manual/phase1_security_install.sql','utf8');
 assert.equal((sql.match(/^BEGIN;\s*$/gm)||[]).length,1);assert.equal((sql.match(/^COMMIT;\s*$/gm)||[]).length,1);
 assert.doesNotMatch(sql,/ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin/);assert.match(sql,/Preservation check failed/);assert.match(sql,/iv_phase1_preservation ON COMMIT DROP/);
});
