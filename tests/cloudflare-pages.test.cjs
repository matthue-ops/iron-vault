const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const handler=()=>import('data:text/javascript;base64,'+Buffer.from(fs.readFileSync('functions/[[path]].js','utf8')).toString('base64'));
test('Pages build publishes only the app and disables implicit SPA fallback',()=>{
 require('../scripts/build-cloudflare.cjs');
 for(const name of ['index.html','gym/login.html','gym/profile.html','gym/admin.html','gym/reports.html','gym/memberlogin.html','assets/auth-session.js','404.html','_routes.json'])assert.ok(fs.existsSync(path.join('dist',name)),name);
 for(const name of ['supabase','docs','tests','AGENTS.md','.git','package.json','vercel.json','functions'])assert.equal(fs.existsSync(path.join('dist',name)),false,name);
 const routes=JSON.parse(fs.readFileSync('dist/_routes.json'));assert.ok(routes.exclude.includes('/assets/*'));assert.ok(routes.exclude.includes('/gym/*'));
});
test('Pages serves existing files first and internally resolves gym slug without losing query',async()=>{
 const {onRequest}=await handler();const seen=[];
 const env={ASSETS:{fetch:async request=>{seen.push(request.url);return request.url.includes('/gym/login?')?new Response('login',{status:200}):new Response('missing',{status:404});}}};
 const response=await onRequest({request:new Request('https://demo.pages.dev/fitness-gym/?from=qr'),env});assert.equal(response.status,200);assert.equal(seen[1],'https://demo.pages.dev/gym/login?from=qr');
 const existing={ASSETS:{fetch:async()=>new Response('existing')}};assert.equal(await (await onRequest({request:new Request('https://demo.pages.dev/fitness-gym'),env:existing})).text(),'existing');
});
test('Pages does not rewrite source paths, invalid slugs or write requests',async()=>{
 const {onRequest}=await handler();for(const [pathname,method]of [['/supabase/manual/test.sql','GET'],['/gym/missing','GET'],['/BAD_slug','GET'],['/fitness-gym','POST']]){
 let calls=0;const response=await onRequest({request:new Request('https://demo.pages.dev'+pathname,{method}),env:{ASSETS:{fetch:async()=>{calls++;return new Response('missing',{status:404});}}}});assert.equal(response.status,404);assert.equal(calls,1);
 }
});
