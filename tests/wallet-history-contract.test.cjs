// Contract checks only: no SQL execution or database access.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/202611020023_wallet_after_history.sql','utf8');
test('wallet history manual update changes only the report function, with no financial writes or grant changes',()=>{
 assert.equal(sql,fs.readFileSync('supabase/manual/wallet_after_history.sql','utf8'));
 assert.doesNotMatch(sql,/\b(?:INSERT INTO|DELETE FROM|UPDATE public|UPDATE ironvault_private|ALTER TABLE|CREATE TABLE|CREATE TRIGGER|GRANT|REVOKE)\b/i);
 assert.equal((sql.match(/CREATE OR REPLACE FUNCTION/g)||[]).length,1);
 assert.match(sql,/IF NOT ironvault_private.can_read_financial_reports\(p_tenant\)/);
});
test('wallet history requires the exact receipt ID, tenant, member, actor and operation',()=>{
 const financial=sql.split("  'financial',")[1].split("  'attendance',")[0];
 for(const text of ['r.request_id=x.request_id','r.tenant_id=x.tenant_id','r.member_id=x.member_id','r.actor_id=x.actor_id',"r.result->>'request_id'=x.request_id::text","r.result->>'operation'=r.payload->>'operation'","THEN r.result->'wallet_balance' ELSE NULL END",'x.tenant_id=p_tenant','x.created_at>=start_at AND x.created_at<end_at'])assert.ok(financial.includes(text),text);
 assert.doesNotMatch(financial,/members|wallet_balance\s*[+\-]|r.created_at\s*=\s*x.created_at|sum\(/i);
});
test('all other report data and Activity identity enrichment remain unchanged from migration 022',()=>{
 const previous=fs.readFileSync('supabase/migrations/202611020022_activity_actor_names.sql','utf8');
 assert.equal(sql.slice(sql.indexOf("  'attendance',")),previous.slice(previous.indexOf("  'attendance',")));
});
