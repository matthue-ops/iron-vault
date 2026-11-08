/* Real Supabase browser SDK, local mock Auth/PostgREST only. Never calls Supabase. */
const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const sdkFile=process.env.SUPABASE_BROWSER_SDK||'/tmp/iv-supabase-browser.js';if(!fs.existsSync(sdkFile))throw Error('Set SUPABASE_BROWSER_SDK to a downloaded copy of the frontend Supabase UMD SDK.');
 const people={
  'a@example.invalid':{id:'11111111-1111-4111-8111-111111111111',tenant_id:'GYM-A',member_id:'MEM-A',role:'member'},
  'b@example.invalid':{id:'22222222-2222-4222-8222-222222222222',tenant_id:'GYM-B',member_id:null,role:'owner'},
  'provider@example.invalid':{id:'33333333-3333-4333-8333-333333333333',tenant_id:null,member_id:null,role:'super_admin'}
 };
 const sessions=new Map(),access=new Map(),refresh=new Map(),disabled=new Set(),refreshes=[],logouts=[],verifications=[],passwordUpdates=[];let serial=0,portalAllowed=true;
 const user=email=>({id:people[email].id,email,aud:'authenticated',role:'authenticated',app_metadata:{provider:'email',providers:['email']},user_metadata:{name:email.split('@')[0]},created_at:'2026-01-01T00:00:00Z'});
 function issue(email,id=crypto.randomUUID()){
  const expires=Math.floor(Date.now()/1000)+3600,payload={sub:people[email].id,aud:'authenticated',role:'authenticated',session_id:id,exp:expires,iat:expires-3600};
  const token=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify(payload)).toString('base64url')+'.'+Buffer.from('fixture-'+(++serial)).toString('base64url');
  const rt='fixture-refresh-'+crypto.randomUUID(),record={email,id,active:true};sessions.set(id,record);access.set(token,record);refresh.set(rt,record);
  return {access_token:token,refresh_token:rt,token_type:'bearer',expires_in:3600,expires_at:expires,user:user(email)};
 }
 const html=url=>{
  const provider=url.pathname.startsWith('/_provider/'),match=/^\/g\/([^/]+)\//.exec(url.pathname),id=match?.[1]||'GYM-A';
  return `<!doctype html><html><head><meta charset="utf-8"><script src="/vendor.js"></script><script src="/assets/session-scopes.js"></script><script src="/assets/auth-session.js"></script><script src="/assets/gym-portals.js"></script><script src="/assets/branch-auth.js"></script></head><body><h1>${url.pathname}</h1><button id="resume" onclick="app.resumeSession()">Resume</button><p id="feedback"></p><script>
   window.events=[];window.client=IronVaultSessionScopes.createClient(supabase,location.origin,'fixture-anon',${JSON.stringify({provider})});
   client.auth.onAuthStateChange((event,session)=>events.push({event,user:session?.user?.id}));
   window.app={currentTenantId:${JSON.stringify(id)},matchedOwnerRecord:{id:${JSON.stringify(id)},token:'key-'+${JSON.stringify(id)},status:'ACTIVE'},showAlert:m=>document.getElementById('feedback').textContent=m,ivCanResumeRole:()=>true};IronVaultBranchAuth.install(app,client);
  </script></body></html>`;
 };
 const server=http.createServer(async(req,res)=>{try{
  const url=new URL(req.url,'http://localhost'),authorization=(req.headers.authorization||'').replace(/^Bearer /,''),actor=access.get(authorization);
  res.setHeader('Cache-Control','no-store');
  const json=(data,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(data));};
  if(url.pathname==='/auth/v1/token'){
   let raw='';for await(const chunk of req)raw+=chunk;const input=JSON.parse(raw||'{}');
   if(url.searchParams.get('grant_type')==='password'){if(!people[input.email]||input.password!=='fixture-only')return json({msg:'invalid login'},400);return json(issue(input.email));}
   const old=refresh.get(input.refresh_token);if(!old?.active)return json({msg:'invalid refresh token',error_code:'refresh_token_not_found'},400);refresh.delete(input.refresh_token);refreshes.push(old.email);return json(issue(old.email,old.id));
  }
  if(url.pathname==='/auth/v1/verify'){
   let raw='';for await(const chunk of req)raw+=chunk;const input=JSON.parse(raw||'{}');verifications.push({hash:input.token_hash,referer:req.headers.referer});
   if(!['fixture-recovery-a','fixture-recovery-b'].includes(input.token_hash))return json({msg:'invalid recovery token'},400);return json(issue(input.token_hash==='fixture-recovery-a'?'a@example.invalid':'b@example.invalid'));
  }
  if(url.pathname==='/auth/v1/user'){if(!actor?.active)return json({msg:'invalid token'},401);if(req.method==='PUT'){let raw='';for await(const chunk of req)raw+=chunk;const input=JSON.parse(raw||'{}');if(input.password)passwordUpdates.push(actor.email);}return json(user(actor.email));}
  if(url.pathname==='/functions/v1/iv-branch-auth'){
   let raw='';for await(const chunk of req)raw+=chunk;const input=JSON.parse(raw||'{}'),p=people[input.email];
   if(input.action!=='signin'||!p||input.gym_token!=='key-'+p.tenant_id||input.password!=='fixture-only')return json({error:'invalid login'},400);
   const session=issue(input.email);return json({session:{access_token:session.access_token,refresh_token:session.refresh_token}});
  }
  if(url.pathname==='/rest/v1/iv_gyms'){
   const gyms=[{id:'GYM-A',token:'key-GYM-A',portal_slug:'fitness-gym',gym_name:'Gym A',status:'ACTIVE',logo:'',pricing:{day:100,week:500,month:1000}},{id:'GYM-B',token:'key-GYM-B',gym_name:'Gym B',status:'ACTIVE',logo:'',pricing:{day:100}}];
   return json(gyms.filter(g=>['id','token','portal_slug'].every(key=>!url.searchParams.has(key)||url.searchParams.get(key)==='eq.'+g[key])));
  }
  if(url.pathname.startsWith('/rest/v1/rpc/'))return json(url.pathname.endsWith('/iv_subscription_public')?{portal:portalAllowed,message:portalAllowed?'Available':'Member portal unavailable'}:null);

  if(url.pathname==='/auth/v1/logout'){if(actor){actor.active=false;logouts.push({email:actor.email,scope:url.searchParams.get('scope')});}res.writeHead(204);res.end();return;}
  if(url.pathname==='/rest/v1/iv_user_roles'){
   if(!actor?.active||disabled.has(actor.email))return json([]);
   const p=people[actor.email];if(url.searchParams.get('user_id')!=='eq.'+p.id)return json([]);
   return json([{user_id:p.id,tenant_id:p.tenant_id,member_id:p.member_id,role:p.role}]);
  }
  if(url.pathname==='/vendor.js'){res.setHeader('Content-Type','text/javascript; charset=utf-8');res.end(fs.readFileSync(sdkFile));return;}
  if(url.pathname.startsWith('/assets/')){const file=path.resolve('.','.'+url.pathname);if(!file.startsWith(process.cwd()+path.sep)||!fs.existsSync(file)){res.writeHead(404);res.end();return;}res.setHeader('Content-Type','text/javascript; charset=utf-8');res.end(fs.readFileSync(file));return;}
  if(url.searchParams.get('real')==='1'){
   let source=fs.readFileSync(url.pathname.includes('/reports')?'gym/reports.html':'gym/login.html','utf8').replace(/https:\/\/uarvhalocgyrikjbrloh\.supabase\.co/g,'http://'+req.headers.host).replace('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2','/vendor.js').replaceAll('../assets/','/assets/');
   source=source.replace(/<script[^>]+src="https:[^"]+"[^>]*><\/script>/g,'').replace('<head>','<head><script>window.tailwind={}</script><style>.hidden{display:none}</style>');
   const scoped=/^\/g\/([^/]+)\//.exec(url.pathname);if(scoped)source=source.replace('<head>','<head><base href="/g/'+scoped[1]+'/">');
   res.setHeader('Content-Type','text/html; charset=utf-8');res.end(source);return;
  }
  if(url.pathname==='/service-worker.js'||url.pathname==='/offline.html'){res.setHeader('Content-Type',url.pathname.endsWith('.js')?'text/javascript':'text/html');res.end(fs.readFileSync('.'+url.pathname));return;}
  res.setHeader('Content-Type','text/html; charset=utf-8');res.end(html(url));
 }catch(error){res.writeHead(500);res.end(error.message)}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port,legacyKey='sb-127-auth-token',legacySession=JSON.stringify(issue('b@example.invalid')),profile=fs.mkdtempSync(path.join(os.tmpdir(),'iv-session-browser-'));let context;
 const launch=async()=>{const c=await chromium.launchPersistentContext(profile,{executablePath:'/usr/bin/chromium',args:['--no-sandbox']});await c.route('**/*',route=>route.request().url().startsWith(origin)?route.continue():route.abort());return c;};
 const signed=async p=>(await p.evaluate(()=>client.auth.getUser())).data.user?.id;
 const login=async(p,email)=>{const result=await p.evaluate(email=>client.auth.signInWithPassword({email,password:'fixture-only'}),email);assert.equal(result.error,null);};
 try{
  context=await launch();await context.addInitScript(({key,session})=>{try{if(!localStorage.getItem(key))localStorage.setItem(key,session)}catch(_){}},{key:legacyKey,session:legacySession});const a=await context.newPage(),b=await context.newPage(),provider=await context.newPage();
  await a.goto(origin+'/g/GYM-A/login');await b.goto(origin+'/g/GYM-B/login');await provider.goto(origin+'/_provider/index');
  assert.equal((await a.evaluate(()=>client.auth.getSession())).data.session,null);
  await a.evaluate(()=>IronVaultBranchAuth.signIn(client,{gym_token:'key-GYM-A',portal:'member',email:'a@example.invalid',password:'fixture-only'}));await login(b,'b@example.invalid');await login(provider,'provider@example.invalid');
  assert.equal(await signed(a),people['a@example.invalid'].id);assert.equal(await signed(b),people['b@example.invalid'].id);assert.equal(await signed(provider),people['provider@example.invalid'].id);
  const keys=await Promise.all([a,b,provider].map(p=>p.evaluate(()=>IronVaultSessionScopes.metadata(client).storageKey)));assert.equal(new Set(keys).size,3);
  assert.equal(await a.evaluate(()=>events.some(e=>e.user&&e.user!=='11111111-1111-4111-8111-111111111111')),false);
  await context.close();context=null;
  // Restart the entire browser profile. Force A's saved access-token expiry before SDK initialization.
  context=await launch();await context.addInitScript(key=>{if(location.pathname.startsWith('/g/GYM-A/')&&!localStorage.getItem('fixture-expiry-done')){const saved=JSON.parse(localStorage.getItem(key));saved.expires_at=1;localStorage.setItem(key,JSON.stringify(saved));localStorage.setItem('fixture-expiry-done','yes');}},keys[0]);
  const aa=await context.newPage(),bb=await context.newPage(),pp=await context.newPage();await aa.goto(origin+'/g/GYM-A/login');await bb.goto(origin+'/g/GYM-B/login');await pp.goto(origin+'/_provider/index');
  assert.equal(await signed(aa),people['a@example.invalid'].id);assert.equal(await signed(bb),people['b@example.invalid'].id);assert.equal(await signed(pp),people['provider@example.invalid'].id);assert(refreshes.includes('a@example.invalid'));
  await aa.locator('#resume').click();await aa.waitForURL('**/g/GYM-A/profile.html');await bb.locator('#resume').click();await bb.waitForURL('**/g/GYM-B/admin.html?key=key-GYM-B');
  await pp.evaluate(()=>IronVaultAuth.requireRole(client,{roles:['super_admin']}));
  console.log('Real SDK: two gyms + provider remain independently signed in after full browser restart and access-token refresh.');
  // Same-gym tabs share sign-out; other gyms/provider do not.
  const sibling=await context.newPage();await sibling.goto(origin+'/g/GYM-A/profile');assert.equal(await signed(sibling),people['a@example.invalid'].id);
  await aa.evaluate(()=>IronVaultAuth.signOut(client,sessionStorage,localStorage));await sibling.waitForFunction(async()=>!(await client.auth.getSession()).data.session);
  assert.equal((await aa.evaluate(()=>client.auth.getSession())).data.session,null);assert.equal(await signed(bb),people['b@example.invalid'].id);assert.equal(await signed(pp),people['provider@example.invalid'].id);assert(logouts.every(e=>e.scope==='local'));
  assert.equal(await pp.evaluate(key=>localStorage.getItem(key),legacyKey),legacySession);
  console.log('Real SDK: local logout propagates to the same gym only; other saved sessions and legacy storage stay untouched.');
  // Revoked role and changed namespace cannot grant a different gym or Super Admin.
  disabled.add('b@example.invalid');await bb.goto(origin+'/g/GYM-B/login');await bb.locator('#resume').click();await bb.waitForFunction(()=>document.getElementById('feedback').textContent.includes('could not be verified'));assert.equal(new URL(bb.url()).pathname,'/g/GYM-B/login');assert.equal(await signed(pp),people['provider@example.invalid'].id);
  disabled.delete('b@example.invalid');await login(bb,'a@example.invalid');await bb.locator('#resume').click();await bb.waitForFunction(()=>document.getElementById('feedback').textContent.includes('could not be verified'));assert.equal(new URL(bb.url()).pathname,'/g/GYM-B/login');
  await login(aa,'a@example.invalid');await bb.evaluate(()=>IronVaultAuth.signOut(client,sessionStorage,localStorage));assert.equal(await signed(aa),people['a@example.invalid'].id);assert.equal(await signed(pp),people['provider@example.invalid'].id);
  console.log('Real SDK: revoked roles/wrong-gym sessions fail closed; even the same Auth user in another realm cannot globally sign out its sibling session.');
  // Execute the actual public login page: resolve legacy callback -> canonical realm before consuming proof.
  await login(bb,'b@example.invalid');const recovery=await context.newPage();await recovery.goto(origin+'/fitness-gym?real=1#iv_recovery=fixture-recovery-a');
  await recovery.waitForURL('**/g/GYM-A/login?real=1&key=key-GYM-A');await recovery.locator('#iv-recovery-panel').waitFor({state:'visible'});
  assert.equal(verifications.length,1);assert(verifications[0].referer.includes('/g/GYM-A/login'));assert.equal(new URL(recovery.url()).hash,'');assert.equal(await signed(bb),people['b@example.invalid'].id);assert.equal(await signed(pp),people['provider@example.invalid'].id);
  await recovery.locator('#iv-recovery-password').fill('fixture-new-password');await recovery.locator('#iv-recovery-confirm').fill('fixture-new-password');await recovery.evaluate(()=>ivCompleteRecovery({preventDefault(){}}));
  assert.deepEqual(passwordUpdates,['a@example.invalid']);assert.equal((await recovery.evaluate(()=>supabaseClient.auth.getSession())).data.session,null);assert.equal(await signed(bb),people['b@example.invalid'].id);assert.equal(await signed(pp),people['provider@example.invalid'].id);
  // Actual login-page onload resumes the stored member account once, without a synthetic payment/staff-login event.
  await login(aa,'a@example.invalid');const resumed=await context.newPage();await resumed.goto(origin+'/g/GYM-A/login?real=1&key=key-GYM-A');await resumed.waitForURL('**/g/GYM-A/profile.html');
  console.log('Actual login HTML: legacy recovery proof is consumed only in its canonical realm, password reset signs out that gym only, and ordinary onload resumes the saved account.');
  const wrongRecovery=await context.newPage();await wrongRecovery.goto(origin+'/g/GYM-A/login?real=1&key=key-GYM-A#iv_recovery=fixture-recovery-b');await wrongRecovery.waitForFunction(()=>document.getElementById('form-alert-msg').textContent.includes('does not match'));assert.equal(await wrongRecovery.locator('#iv-recovery-panel').isVisible(),false);assert.equal(await signed(bb),people['b@example.invalid'].id);assert.equal(await signed(pp),people['provider@example.invalid'].id);
  await login(aa,'a@example.invalid');portalAllowed=false;const limited=await context.newPage();await limited.goto(origin+'/g/GYM-A/login?real=1&key=key-GYM-A');await limited.waitForFunction(()=>typeof app.ivCanResumeRole==='function'&&!app.ivCanResumeRole({role:'member'}));assert.equal(await limited.evaluate(()=>app.resumeSession()),false);assert.equal(new URL(limited.url()).pathname,'/g/GYM-A/login');
  const dashboardOwner=await context.newPage();await dashboardOwner.goto(origin+'/g/GYM-B/login?real=1&key=key-GYM-B');await dashboardOwner.waitForURL('**/g/GYM-B/admin.html?key=key-GYM-B');portalAllowed=true;
  console.log('Actual login HTML: wrong-gym recovery cannot sign out the other gym, unavailable member portals do not resume, and dashboard-only owners still resume normally.');
  const nativeProof=issue('a@example.invalid'),native=await context.newPage();await native.goto(origin+'/gym/login.html?real=1&key=key-GYM-A#'+new URLSearchParams({type:'recovery',access_token:nativeProof.access_token,refresh_token:nativeProof.refresh_token}));await native.waitForURL('**/g/GYM-A/login?real=1&key=key-GYM-A');await native.locator('#iv-recovery-panel').waitFor({state:'visible'});assert.equal(new URL(native.url()).hash,'');assert.equal(await signed(bb),people['b@example.invalid'].id);assert.equal(await signed(pp),people['provider@example.invalid'].id);console.log('Legacy implicit-token recovery also stays in its own realm and requires verified account/gym binding.');
  await pp.evaluate(()=>IronVaultAuth.signOut(client,sessionStorage,localStorage));const deniedReport=await context.newPage();await deniedReport.goto(origin+'/_provider/reports?real=1&key=key-GYM-A&from=index');await deniedReport.waitForURL('**/_provider/index.html');assert.equal(await signed(bb),people['b@example.invalid'].id);console.log('Expired/signed-out provider Reports returns to provider login, not a gym portal or Command.');




 }finally{await context?.close();await new Promise(r=>server.close(r));fs.rmSync(profile,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exit(1)});
