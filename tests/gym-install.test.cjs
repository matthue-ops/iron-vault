const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const install=require('../assets/gym-install.js');
const handler=()=>import('data:text/javascript;base64,'+Buffer.from(fs.readFileSync('functions/[[path]].js','utf8')).toString('base64'));
test('install metadata requires a resolved gym and encodes public branding without credentials',()=>{
 assert.equal(install.details(null),null);assert.equal(install.details({id:'a',token:'../bad'}),null);
 assert.equal(install.details({id:'a',token:'key',status:'PROVISIONING'}),null);
 const a=install.details({id:'gym-a',token:'public-key',gymName:'A & B Gym'}),b=install.details({id:'gym-b',token:'public-key',gymName:'Other Gym'});
 assert.notEqual(a.storageKey,b.storageKey);assert.equal(new URL(a.manifest,'https://demo.test').searchParams.get('name'),'A & B Gym');
 assert.equal(install.recovery({hash:'#iv_recovery=secret',search:''}),true);assert.equal(install.recovery({hash:'',search:'?key=public'}),false);
});
test('manifest identity is gym-specific and stable across rename or token rotation',async()=>{
 const {onRequest}=await handler();const get=async query=>{const response=await onRequest({request:new Request('https://demo.test/gym-app.webmanifest?'+new URLSearchParams(query)),env:{}});assert.equal(response.status,200);assert.match(response.headers.get('Content-Type'),/manifest\+json/);assert.equal(response.headers.get('Cache-Control'),'no-store');return response.json();};
 const first=await get({gym:'gym-a',key:'public-key',name:'A Gym'}),renamed=await get({gym:'gym-a',key:'new-key',name:'Renamed Gym'}),other=await get({gym:'gym-b',key:'other-key',name:'B Gym'});
 assert.equal(first.id,renamed.id);assert.notEqual(first.id,other.id);assert.equal(renamed.name,'Renamed Gym');assert.equal(renamed.start_url,'/g/gym-a/login?key=new-key');assert.equal(first.scope,'/g/gym-a/');assert.equal(first.display,'standalone');
 for(const icon of first.icons)assert(fs.existsSync('.'+icon.src));assert.deepEqual(first.icons.map(i=>i.sizes),['192x192','512x512']);
});
test('manifest endpoint rejects invalid identifiers and writes without touching database or assets',async()=>{
 const {onRequest}=await handler();
 for(const query of ['','gym=a&key=..%2Fbad','gym=%3Cscript%3E&key=public','gym='+('a'.repeat(161))+'&key=public']){
  const response=await onRequest({request:new Request('https://demo.test/gym-app.webmanifest?'+query),env:{}});assert.equal(response.status,400);
 }
 for(const method of ['POST','DELETE'])assert.equal((await onRequest({request:new Request('https://demo.test/gym-app.webmanifest?gym=a&key=public',{method}),env:{}})).status,405);
 const head=await onRequest({request:new Request('https://demo.test/gym-app.webmanifest?gym=a&key=public',{method:'HEAD'}),env:{}});assert.equal(head.status,200);assert.equal(await head.text(),'');
});
