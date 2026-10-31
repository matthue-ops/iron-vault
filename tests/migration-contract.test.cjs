// Text/contract validation only: no PostgreSQL server, connection, or SQL execution.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const contract=require('./fixtures/inspection-function-contract.json');
const first=fs.readFileSync('supabase/migrations/202611010001_restrict_table_truncate.sql','utf8');
const second=fs.readFileSync('supabase/migrations/202611010002_restrict_function_execution.sql','utf8');
function statements(sql){return sql.replace(/--[^\n]*/g,'');}
function escaped(text){return text.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}
test('TRUNCATE hardening targets both reviewed tables and effective API-role privileges',()=>{
 assert.match(first,/REVOKE TRUNCATE ON TABLE public\.owners, public\.members\s+FROM PUBLIC, anon, authenticated;/);
 assert.match(first,/has_table_privilege\(api_role, relation_name, 'TRUNCATE'\)/);
 assert.match(first,/RAISE EXCEPTION/);
});
test('every reviewed function is fingerprinted before any execution-grant change',()=>{
 assert.equal(contract.functions.length,8);
 for(const f of contract.functions){
  assert.ok(second.includes(`('${f.signature}','${f.definition_md5}')`));
  assert.match(f.definition_md5,/^[a-f0-9]{32}$/);
 }
 assert.ok(second.indexOf('$preflight$;')<second.indexOf('REVOKE EXECUTE'));
 assert.match(second,/md5\(pg_get_functiondef\(function_oid\)\)/);
 assert.match(second,/Definition changed since inspection/);
});
test('anonymous and PUBLIC execution is removed without revoking authenticated ordinary RPCs',()=>{
 for(const f of contract.functions){
  const targets=f.trigger_only?'PUBLIC, anon, authenticated':'PUBLIC, anon';
  assert.match(second,new RegExp(`REVOKE EXECUTE ON FUNCTION ${escaped(f.signature)} FROM ${targets};`));
 }
 assert.equal((statements(second).match(/REVOKE EXECUTE ON FUNCTION/g)||[]).length,8);
});
test('effective privileges verify inherited grants and retained service-role access',()=>{
 assert.match(second,/has_function_privilege\('anon',function_oid,'EXECUTE'\)/);
 assert.match(second,/IS DISTINCT FROM \(NOT item\.trigger_only\)/);
 assert.match(second,/has_function_privilege\('service_role',function_oid,'EXECUTE'\)/);
});
test('both migrations are transactional and contain no record resets or function replacements',()=>{
 for(const sql of [first,second]){
  const text=statements(sql);
  assert.match(text,/(?<![A-Za-z_])BEGIN;/);assert.match(text,/COMMIT;/);
  assert.doesNotMatch(text,/\b(?:CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION|DROP\s+(?:TABLE|FUNCTION)|DELETE\s+FROM|INSERT\s+INTO|UPDATE\s+public\.|ALTER\s+TABLE)\b/i);
  assert.doesNotMatch(text,/(?:^|;)\s*TRUNCATE\b/im);
  assert.doesNotMatch(text,/\bGRANT\b/i);
 }
});
test('supplementary inspection is SELECT-only and excludes application RPC calls',()=>{
 const sql=statements(fs.readFileSync('supabase/inspection/20261101_remaining_authorization_checks.sql','utf8'));
 assert.doesNotMatch(sql,/\b(?:INSERT|UPDATE|DELETE|TRUNCATE|REVOKE|GRANT|CREATE|DROP|ALTER|DO)\s/i);
 assert.doesNotMatch(sql,/\b(?:iv_purchase|iv_topup|iv_checkin|iv_log_event|iv_staff_event)\s*\(/i);
 assert.match(sql,/users_without_password_credentials/);
 assert.match(sql,/duplicate_groups_within_tenant/);
});
