// Contract checks only: no SQL execution or database access.
const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/202611020021_owner_without_confirmation.sql','utf8');
test('owner delta works on 017 without display-code schema and manual file matches',()=>{
 assert.equal(fs.readFileSync('supabase/manual/owner_login_update.sql','utf8'),sql);
 assert.match(sql,/to_jsonb\(m\)->>'display_code'/);assert.doesNotMatch(sql,/m\.display_code/);
 assert.doesNotMatch(sql,/\b(?:DELETE FROM|TRUNCATE|DROP TABLE|ALTER TABLE|UPDATE auth\.users)\b/i);
 assert.match(sql,/FROM PUBLIC,anon,authenticated/);assert.match(sql,/TO service_role/);
});
test('identity removes all contact verification gates while retaining tenant, role and approval boundaries',()=>{
 const body=sql.split('CREATE OR REPLACE FUNCTION public.iv_finish_branch_account')[0];
 assert.doesNotMatch(body,/a\.contact_verified/);assert.match(body,/g\.status='ACTIVE'/);
 for(const text of ['r.enabled','r.disabled_at IS NULL','r.tenant_id=a.tenant_id','r.role=a.role',"m.status IN ('ACTIVE','PENDING')",'a.role=ANY(p_roles)'])assert.ok(body.includes(text),text);
});
test('owner completion activates only provisioning gyms after authenticated account binding and role creation',()=>{
 const body=sql.split('CREATE OR REPLACE FUNCTION public.iv_finish_branch_account')[1].split('CREATE OR REPLACE FUNCTION public.iv_confirm_email_action')[0];
 assert.match(body,/raw_app_meta_data->>'iv_provision_request'=p_request::text/);
 assert.match(body,/job\.role='owner'.*status='PROVISIONING'.*RAISE EXCEPTION 'Gym unavailable'/);
 assert.match(body,/member_id,true\)/);
 assert.ok(body.indexOf("SET status='ACTIVE'")>body.indexOf('SET completed_user=p_user'));
 assert.match(body,/CASE WHEN job.actor_id IS NULL THEN 'PENDING' ELSE 'ACTIVE' END/);
 assert.match(body,/Provisioning authority revoked/);
});
test('existing owner activation requires completed matching provisioning and preserves revocations and suspensions',()=>{
 const body=sql.split('-- Resume only completed owner provisioning')[1];
 for(const text of ["g.status='PROVISIONING'",'j.completed_user=a.user_id','j.tenant_id=a.tenant_id','j.role=a.role',"u.raw_app_meta_data->>'iv_provision_request'=j.request_id::text",'r.disabled_at IS NULL',"g.status='ACTIVE'",'NOT a.contact_verified'])assert.ok(body.includes(text),text);
 assert.doesNotMatch(body,/disabled_at\s*=\s*NULL|contact_verified\s*=\s*true/);
});
test('email proof cannot activate suspended gyms or restore revoked or inactive member roles',()=>{
 const body=sql.split('CREATE OR REPLACE FUNCTION public.iv_confirm_email_action')[1].split('-- Resume only completed')[0];
 assert.doesNotMatch(body,/SET status='ACTIVE'/);assert.match(body,/r.disabled_at IS NULL/);
 assert.match(body,/g.status='ACTIVE'/);assert.match(body,/m.status IN \('ACTIVE','PENDING'\)/);
 assert.match(body,/change_old/);assert.match(body,/change_new/);
});
