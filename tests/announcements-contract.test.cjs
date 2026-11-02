// SQL contract checks only. No SQL execution or Supabase connection.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/202611020024_admin_announcements.sql','utf8');
test('announcement SQL is isolated and manual; ordinary removal archives rather than deletes',()=>{
 assert.equal(sql,fs.readFileSync('supabase/manual/admin_announcements.sql','utf8'));assert.match(sql,/BEGIN;/);assert.match(sql,/COMMIT;/);
 assert.doesNotMatch(sql,/\bDELETE FROM|\bDROP TABLE|\bUPDATE public\.(owners|members|iv_user_roles)|\bALTER TABLE public\.(owners|members)/i);
 assert.match(sql,/UPDATE public.iv_announcements SET archived_at=now\(\)/);
 assert.match(sql,/tenant_id text NOT NULL REFERENCES public.owners\(id\) ON DELETE CASCADE/,'compatible with the existing explicitly-confirmed whole-gym purge');
});
test('base table access is closed to clients and all RPCs explicitly restrict stage-one roles and tenants',()=>{
 assert.match(sql,/ENABLE ROW LEVEL SECURITY/);assert.match(sql,/REVOKE ALL ON public.iv_announcements FROM PUBLIC,anon,authenticated,service_role/);
 assert.match(sql,/FROM PUBLIC,anon,authenticated,service_role;/);assert.match(sql,/TO authenticated;/);assert.doesNotMatch(sql,/TO anon|role='member'|role='super_admin'|CREATE POLICY/i);
 for(const body of sql.match(/CREATE OR REPLACE FUNCTION[\s\S]*?END \$fn\$;/g)){
  assert.ok(body.includes('r.user_id=auth.uid()'));assert.ok(body.includes('r.tenant_id=p_tenant'));assert.ok(body.includes("g.status='ACTIVE'"));assert.ok(body.includes('r.enabled AND r.disabled_at IS NULL'));
 }
});
test('owners are locked and checked for writes, with optimistic versions and request-safe creation',()=>{
 const save=sql.split('CREATE OR REPLACE FUNCTION public.iv_save_announcement')[1].split('CREATE OR REPLACE FUNCTION public.iv_archive_announcement')[0];
 for(const text of ["r.role='owner'",'FOR SHARE OF r,g','ON CONFLICT(id) DO NOTHING','created_by=auth.uid()','notice.version=1','notice.version<>p_expected_version','FOR UPDATE','WHERE id=p_id AND tenant_id=p_tenant','version=version+1'])assert.ok(save.includes(text),text);
 assert.match(save,/IF notice.created_by=auth.uid\(\)[\s\S]*?THEN RETURN to_jsonb\(notice\);/);
 assert.match(sql,/notice.archived_at IS NOT NULL THEN RETURN to_jsonb\(notice\)/);
});
test('listing has bounded tenant-scoped pagination and correct exclusive-end scheduling',()=>{
 const list=sql.split('CREATE OR REPLACE FUNCTION public.iv_list_announcements')[1].split('CREATE OR REPLACE FUNCTION public.iv_save_announcement')[0];
 assert.match(list,/p_state='archived' AND NOT can_manage/);assert.match(list,/a.starts_at<=now\(\) AND a.ends_at>now\(\)/);assert.match(list,/a.ends_at<=now\(\)/);
 assert.match(list,/LIMIT 20 OFFSET p_page\*20/);assert.equal((list.match(/a.tenant_id=p_tenant/g)||[]).length,2);assert.match(sql,/CHECK\(ends_at>starts_at\)/);
});
