const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/202611050033_precise_activity_audit.sql','utf8');
const reports=require('../assets/reports-analysis.js');
test('precise audit migration has an identical manual copy and preserves transaction business functions',()=>{
 assert.equal(sql,fs.readFileSync('supabase/manual/precise_activity_audit.sql','utf8'));
 assert.match(sql,/Apply 032 before/);assert.doesNotMatch(sql,/CREATE OR REPLACE FUNCTION public.iv_financial|UPDATE public.iv_activity_logs|DELETE FROM public.iv_activity_logs/);
 assert.match(sql,/AFTER INSERT ON ironvault_private.financial_requests/);assert.match(sql,/AFTER INSERT ON public.iv_attendance_logs/);
 assert.match(sql,/NEW.result->>'request_id' IS DISTINCT FROM NEW.request_id::text/);
 assert.match(sql,/'wallet_before',before_balance,'wallet_after',after_balance/);
});
test('changed fields are audited without unchanged batch noise or photo contents',()=>{
 assert.match(sql,/IF before_value IS DISTINCT FROM after_value THEN/);assert.doesNotMatch(sql,/Member profile updated/);
 assert.match(sql,/Profile photo updated \(image data excluded\)/);assert.match(sql,/Contact email changes require verification/);
 assert.match(sql,/Cannot move membership/);assert.match(sql,/Gym administrator required to restore inactive membership/);
});
test('email audit gateway is service-only, scoped and linked to confirmed recipient proof',()=>{
 assert.match(sql,/GRANT EXECUTE ON FUNCTION public.iv_queue_contact_change\(uuid,uuid,text,text,uuid,text,text\) TO service_role/);
 assert.match(sql,/r.disabled_at IS NULL/);assert.match(sql,/p_base_email IS DISTINCT FROM target.contact_email/);
 assert.match(sql,/Contact group mismatch/);assert.ok(sql.indexOf('THEN RETURN false; END IF;')<sql.indexOf('Completed using recipient email proof'));
 assert.match(sql,/Requester unavailable \(older request\)/);assert.match(sql,/AS RESTRICTIVE FOR SELECT TO authenticated/);
 const source=fs.readFileSync('supabase/functions/_shared/contact.ts','utf8');
 assert.match(source,/rpc\('iv_queue_contact_change'/);assert.match(source,/p_actor:user.id/);assert.match(source,/p_base_email:info.email/);
});
test('audit identity snapshots are tenant-scoped and preserve the recorded actor name',()=>{
 const row={audit_data:{version:1,tenant_id:'gym-a',actor:{name:'Original Staff',role:'staff'}}};
 assert.equal(reports.auditActor(row,'gym-a'),'Original Staff — Staff');
 assert.equal(reports.auditActor(row,'gym-b'),null);assert.equal(reports.auditSnapshot({audit_data:{version:2,tenant_id:'gym-a'}},'gym-a'),null);
});
