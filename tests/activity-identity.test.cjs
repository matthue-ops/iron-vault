// SQL contract checks only; no database connection or SQL execution.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/202611020022_activity_actor_names.sql','utf8');
test('manual Activity update matches migration and preserves authorization without data writes',()=>{
 assert.equal(sql,fs.readFileSync('supabase/manual/activity_actor_names.sql','utf8'));
 assert.match(sql,/IF NOT ironvault_private.can_read_financial_reports\(p_tenant\)/);
 assert.doesNotMatch(sql,/\b(?:INSERT INTO|UPDATE public|DELETE FROM|ALTER TABLE|CREATE TABLE|GRANT|REVOKE)\b/i);
 assert.match(sql,/BEGIN;/);assert.match(sql,/COMMIT;/);
});
test('actor lookup is restricted to report-referenced users and the selected tenant, including deactivated accounts',()=>{
 const identity=sql.split('WITH referenced AS (')[1];
 for(const text of ["(result->'activity')||(result->'sessions')",'JOIN public.iv_user_roles r ON r.user_id=ref.user_id','r.tenant_id=p_tenant',"r.role='super_admin' AND r.tenant_id IS NULL",'m.tenant_id=p_tenant','p.tenant_id=p_tenant','p.completed_user=r.user_id','p.role=r.role',"s.value->>'auth_user_id'=r.user_id::text"])assert.ok(identity.includes(text),text);
 assert.doesNotMatch(identity,/r.enabled|disabled_at IS NULL|contact_email|u.email|password/i);
 assert.match(identity,/'user_id',user_id,'name',name,'role',role/);
});
test('financial, attendance, member and purchase calculations remain exactly as migration 020',()=>{
 const original=fs.readFileSync('supabase/migrations/202611010020_clear_report_snapshots.sql','utf8');
 const section=s=>s.slice(s.indexOf(' start_at:='),s.indexOf('END $fn$;')).split(' -- Resolve only identities')[0].trim();
 assert.equal(section(sql),section(original).replace(" RETURN result||jsonb_build_object('purchases'"," result:=result||jsonb_build_object('purchases'"));
});
