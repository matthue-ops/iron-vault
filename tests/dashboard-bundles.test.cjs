const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const {spawnSync}=require('node:child_process');const {stripTypeScriptTypes}=require('node:module');const vm=require('node:vm');
test('all Dashboard entries match modular sources and parse without local imports',()=>{
 const check=spawnSync(process.execPath,['scripts/build-dashboard-functions.cjs','--check'],{encoding:'utf8'});assert.equal(check.status,0,check.stderr);
 for(const name of ['iv-create-member','provision-gym-tenant','iv-admin-correct-member-email','iv-branch-auth','iv-purge-tenant']){
  const text=fs.readFileSync('supabase/dashboard/'+name+'.ts','utf8');assert.doesNotMatch(text,/^import .*from ['"]\./m);
  const js=stripTypeScriptTypes(text,{mode:'strip'}).replace(/^import .*;\s*$/gm,'');new vm.Script(js);
  assert.equal((text.match(/^serve\(/gm)||[]).length,1);
 }
});
