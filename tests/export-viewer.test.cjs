const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const viewer=require('../assets/export-viewer.js');
function entry(text){return{internalStream(){const handlers={};return{on(event,fn){handlers[event]=fn;return this},pause(){},resume(){handlers.data(new TextEncoder().encode(text));handlers.end();}}}};}
function file(name,text){return{name,size:Buffer.byteLength(text),text:async()=>text};}
test('export viewer reads old camel-case and SQL-shaped member snapshots without retaining credentials',()=>{
 const data=viewer.normalize([{id:'gym',gymName:'Archived Gym',ownerName:'Owner',password:'private',token:'portal-key',pricing:{day:100},staff:[{name:'Staff',email:'staff@example.invalid',password:'private'}],auditLogs:[{date:'2026-11-01',action:'Updated'}]}],
 [{id:'m1',tenantId:'gym',name:'Member',walletBalance:150,password:'private',auth_user_id:'auth-private'},
 {id:'m2',tenant_id:'gym',name:'Member Two',wallet_balance:0,status:'INACTIVE'}]);
 assert.equal(data.gyms[0].gym,'Archived Gym');assert.equal(data.members[0].wallet,'150');assert.equal(data.members[1].wallet,'0');assert.equal(data.staff.length,1);assert.equal(data.activity.length,1);
 assert.equal(JSON.stringify(data).includes('private'),false);assert.equal(JSON.stringify(data).includes('portal-key'),false);
});
test('JSON export can be viewed without a live tenant or backend',async()=>{
 const data=await viewer.readFile(file('tenant_members_export.json',JSON.stringify([{id:'m',tenantId:'purged-gym',name:'Former Member'}])));
 assert.equal(data.members[0].tenant,'purged-gym');assert.equal(data.members[0].name,'Former Member');
 await assert.rejects(viewer.readFile(file('x.json','{"members":[]}')),/export array/);
 await assert.rejects(viewer.readFile({name:'x.json',size:21*1024*1024}),/20 MB/);
});
test('tenant and Master ZIP readers extract only supported files and reject ambiguous archives',async()=>{
 for(const prefix of ['tenant','ironvault']){
  const gyms=prefix==='tenant'?'tenant_owner_export.json':'ironvault_owners_export.json';
  const members=prefix+'_members_export.json';
  const files={[gyms]:entry('[{"id":"gym","gymName":"Gym"}]'),[members]:entry('[{"id":"m","name":"Member"}]'),'untrusted.html':entry('<script>bad</script>')};
  const data=await viewer.readFile({name:'export.zip',size:100},{loadAsync:async()=>({files,file:name=>files[name]||null})});
  assert.equal(data.gyms.length,1);assert.equal(data.members.length,1);
 }
 const files={'tenant_owner_export.json':entry('[]'),'ironvault_owners_export.json':entry('[]')};
 await assert.rejects(viewer.readFile({name:'export.zip',size:100},{loadAsync:async()=>({files,file:name=>files[name]||null})}),/ambiguous/);
});
test('expanded ZIP size and encoding are checked before parsing data',async()=>{
 const huge={internalStream(){const handlers={};return{on(event,fn){handlers[event]=fn;return this},pause(){},resume(){handlers.data(new Uint8Array(10*1024*1024+1));handlers.end();}}}};
 await assert.rejects(viewer.readEntry(huge,{bytes:0}),/Expanded export/);
 const bad={internalStream(){const handlers={};return{on(event,fn){handlers[event]=fn;return this},pause(){},resume(){handlers.data(new Uint8Array([255]));handlers.end();}}}};
 await assert.rejects(viewer.readEntry(bad,{bytes:0}),/UTF-8/);
});
test('search and gym filters apply to archived records without mixing tenants',()=>{
 const data=viewer.normalize([],[{id:'one',tenantId:'gym-a',name:'Alice',status:'INACTIVE'},{id:'two',tenantId:'gym-b',name:'Alice'}]);
 assert.deepEqual(viewer.selectRows(data,'members','ALICE','gym-a').map(r=>r.id),['one']);
 assert.equal(viewer.selectRows(data,'members','INACTIVE','').length,1);
});
test('viewer renders export strings as text, with no backend or import path',()=>{
 const source=fs.readFileSync('assets/export-viewer.js','utf8'),html=fs.readFileSync('gym/export-viewer.html','utf8');
 assert.doesNotMatch(source,/innerHTML|fetch\(|\.rpc\(|\.functions\.|localStorage|sessionStorage/);
 assert.doesNotMatch(html,/supabase-js|auth-session|application-workflows/);assert.match(source,/td\.textContent=row\[key\]/);
});
