const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const handler=()=>import('data:text/javascript;base64,'+Buffer.from(fs.readFileSync('functions/[[path]].js','utf8')).toString('base64'));
test('two gyms and the provider have distinct path identities, starts, scopes and icons',async()=>{
 const {onRequest}=await handler();const get=async path=>(await onRequest({request:new Request('https://demo.test'+path),env:{}})).json();
 const a=await get('/gym-app.webmanifest?gym=GYM-A&key=a'),b=await get('/gym-app.webmanifest?gym=GYM-B&key=b'),p=await get('/provider-app.webmanifest');
 assert.equal(a.scope,'/g/GYM-A/');assert.equal(b.scope,'/g/GYM-B/');assert.equal(p.scope,'/_provider/');
 for(const m of [a,b,p]){assert.equal(m.id,m.scope);assert(m.start_url.startsWith(m.scope));for(const other of [a,b,p])if(other!==m)assert(!m.start_url.startsWith(other.scope));}
 assert.equal(p.start_url,'/_provider/index');assert.equal(p.name,'Iron Vault Admin');assert(p.icons.every(i=>/provider-/.test(i.src)&&fs.existsSync('.'+i.src)));
});
test('scoped pages use the same existing assets with scoped relative navigation and absolute scripts',async()=>{
 const {onRequest}=await handler();
 for(const [path,asset,base]of [['/g/GYM-A/login?key=alpha','/gym/login?key=alpha','/g/GYM-A/'],['/g/GYM-B/admin.html?key=beta','/gym/admin?key=beta','/g/GYM-B/'],['/_provider/index','/gym/index','/_provider/'],['/_provider/reports?key=alpha','/gym/reports?key=alpha','/_provider/']]){
  const seen=[];const response=await onRequest({request:new Request('https://demo.test'+path),env:{ASSETS:{fetch:async req=>{seen.push(new URL(req.url).pathname+new URL(req.url).search);return new Response('<html><head></head><script src="../assets/auth-session.js"></script><a href="reports.html">Reports</a></html>',{headers:{'Content-Type':'text/html','ETag':'old'}});}}}});
  const html=await response.text();assert.deepEqual(seen,[asset]);assert(html.includes('<base href="'+base+'">'));assert(html.includes('src="/assets/auth-session.js"'));assert.equal(new URL('reports.html','https://demo.test'+base).pathname,base+'reports.html');assert.equal(response.headers.get('ETag'),null);
 }
});
test('scoped routing never serves master pages inside a gym or other source files',async()=>{
 const {onRequest}=await handler();for(const path of ['/g/GYM-A/index','/g/GYM-A/../../supabase/test.sql','/g/GYM-A/missing','/_provider/admin','/_provider/../supabase/test.sql']){
  const response=await onRequest({request:new Request('https://demo.test'+path),env:{ASSETS:{fetch:async()=>new Response('missing',{status:404})}}});assert.equal(response.status,404,path);
 }
 const post=await onRequest({request:new Request('https://demo.test/g/GYM-A/login',{method:'POST'}),env:{}});assert.equal(post.status,405);
 const head=await onRequest({request:new Request('https://demo.test/_provider/index',{method:'HEAD'}),env:{ASSETS:{fetch:async()=>new Response('<head></head>')}}});assert.equal(await head.text(),'');
});
test('member/admin navigation retains gym path scope and rejects a mismatched account context',()=>{
 const context={URL,location:{pathname:'/g/GYM-A/login'},module:{exports:{}}};vm.runInNewContext(fs.readFileSync('assets/gym-portals.js','utf8'),context);const p=context.module.exports;
 assert.equal(p.page('profile.html'),'/g/GYM-A/profile.html');assert.equal(p.page('admin.html?key=alpha'),'/g/GYM-A/admin.html?key=alpha');assert.doesNotThrow(()=>p.assertScope('GYM-A'));assert.throws(()=>p.assertScope('GYM-B'),/different gym/);
 context.location.pathname='/gym/login';assert.equal(p.page('profile.html'),'/gym/profile.html');
});
test('per-gym manifest paths cannot be relabeled as a different gym',async()=>{
 const {onRequest}=await handler();const ok=await onRequest({request:new Request('https://demo.test/g/GYM-A/manifest.webmanifest?key=alpha'),env:{}});assert.equal((await ok.json()).scope,'/g/GYM-A/');
 const wrong=await onRequest({request:new Request('https://demo.test/g/GYM-A/manifest.webmanifest?gym=GYM-B&key=beta'),env:{}});assert.equal(wrong.status,400);
});
