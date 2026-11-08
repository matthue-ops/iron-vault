const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function fixture(path='/g/GYM-A/login',search=''){
 const entries=new Map([['sb-old-auth-token','old-shared-token']]),moves=[],created=[];
 const storage={getItem:k=>entries.get(k)||null,setItem:(k,v)=>entries.set(k,String(v)),removeItem:k=>entries.delete(k)};
 const root={URL,URLSearchParams,localStorage:storage,location:{pathname:path,search,hash:'',href:'https://site.test'+path+search,replace:url=>moves.push(url)}};
 vm.runInNewContext(fs.readFileSync('assets/session-scopes.js','utf8'),root);
 const sdk={createClient:(url,key,options)=>{const client={auth:{}};created.push({url,key,options,client});return client;}};
 return {root,scope:root.IronVaultSessionScopes,sdk,storage,entries,moves,created};
}
test('gym/provider auth storage and refresh locks use stable distinct project-specific namespaces',()=>{
 const f=fixture();const a=f.scope.createClient(f.sdk,'https://project.supabase.co','public');f.root.location.pathname='/g/GYM-B/profile';const b=f.scope.createClient(f.sdk,'https://project.supabase.co','public');f.root.location.pathname='/_provider/index';const p=f.scope.createClient(f.sdk,'https://project.supabase.co','public');
 const keys=[a,b,p].map(c=>f.scope.metadata(c).storageKey);assert.equal(new Set(keys).size,3);assert(keys.every(k=>k.startsWith('iv-auth:v1:project.supabase.co:')));
 for(const call of f.created){assert.equal(call.options.auth.persistSession,true);assert.equal(call.options.auth.autoRefreshToken,true);assert.equal(call.options.auth.detectSessionInUrl,false);}
 f.root.location.pathname='/g/GYM-A/admin';const again=f.scope.createClient(f.sdk,'https://project.supabase.co','public');assert.equal(f.scope.metadata(again).storageKey,keys[0]);
 const different=f.scope.createClient(f.sdk,'https://other.supabase.co','public');assert.notEqual(f.scope.metadata(different).storageKey,keys[0]);assert.equal(f.entries.get('sb-old-auth-token'),'old-shared-token');
});
test('unknown legacy pages use a nonpersistent bootstrap, never the shared legacy credential',()=>{
 const f=fixture('/fitness-gym');f.scope.createClient(f.sdk,'https://project.supabase.co','public');const options=f.created[0].options.auth;assert.equal(options.persistSession,false);assert.equal(options.autoRefreshToken,false);assert.equal(options.detectSessionInUrl,false);assert.match(options.storageKey,/bootstrap/);assert.equal(f.entries.size,1);
});
test('legacy handoff preserves callback proof and public parameters before any auth consumption',()=>{
 const f=fixture('/fitness-gym','?tab=admin');f.root.location.hash='#iv_recovery=fixture-proof';f.root.location.href+=''+f.root.location.hash;
 assert.equal(f.scope.handoff({id:'GYM-A',token:'public-a'}),true);assert.equal(f.moves[0],'/g/GYM-A/login?tab=admin&key=public-a#iv_recovery=fixture-proof');
 f.root.location.pathname='/gym/admin';f.root.location.search='?key=public-a';assert.equal(f.scope.context().realm,'gym:GYM-A');
 f.root.location.pathname='/g/GYM-A/login';assert.equal(f.scope.handoff({id:'GYM-A',token:'public-a'}),false);
 assert.equal(f.entries.get('sb-old-auth-token'),'old-shared-token');assert.equal([...f.entries.values()].includes('fixture-proof'),false);
});
test('scoped gym context wins over forged provider query and storage failures do not mix realms',()=>{
 const f=fixture('/g/GYM-A/reports','?from=index');assert.equal(f.scope.context().realm,'gym:GYM-A');
 const bad={getItem(){throw Error('blocked')}};assert.equal(f.scope.context({pathname:'/gym/login',search:'?key=unknown'},bad).realm,null);
 assert.equal(f.scope.context({pathname:'/gym/reports.html',search:'?from=superadmin'},bad).realm,'provider');
});
function resumeFixture(role='member',available=true){
 const redirects=[],messages=[],values=new Map();let lookups=0;
 const binding={user_id:'u',tenant_id:'GYM-A',role,member_id:role==='member'?'m':null};
 const root={sessionStorage:{setItem:(k,v)=>values.set(k,v)},location:{replace:url=>redirects.push(url)},document:{getElementById:()=>null,createElement:()=>({}),addEventListener(){},querySelectorAll:()=>[]},IronVaultAuth:{requireRole:async()=>{lookups++;return binding;}}};
 vm.runInNewContext(fs.readFileSync('assets/branch-auth.js','utf8'),root);
 const client={auth:{getSession:async()=>({data:{session:{user:{id:'u'}}}}),getUser:async()=>({data:{user:{id:'u'}}})}};
 const app={currentTenantId:'GYM-A',matchedOwnerRecord:{id:'GYM-A',token:'public-a',status:'ACTIVE'},showAlert:m=>messages.push(m),ivCanResumeRole:r=>r.role!=='member'||available};root.IronVaultBranchAuth.install(app,client);
 return {app,client,redirects,messages,values,lookups:()=>lookups};
}
test('resume reconstructs only UI hints and navigation after fresh authorization; portal gating remains',async()=>{
 const member=resumeFixture();assert.equal(await member.app.resumeSession(),true);assert.equal(member.values.get('ironvault_active_member'),'m');assert.equal(member.redirects[0],'profile.html');
 const denied=resumeFixture('member',false);assert.equal(await denied.app.resumeSession(),false);assert.equal(denied.redirects.length,0);
 const owner=resumeFixture('owner',false);assert.equal(await owner.app.resumeSession(),true);assert.match(owner.redirects[0],/admin.html/);
});
test('no stored session causes no role reads; identity changes during resume fail closed',async()=>{
 const missing=resumeFixture();missing.client.auth.getSession=async()=>({data:{session:null}});assert.equal(await missing.app.resumeSession(),false);assert.equal(missing.lookups(),0);
 const changed=resumeFixture();changed.client.auth.getUser=async()=>({data:{user:{id:'different'}}});assert.equal(await changed.app.resumeSession(),false);assert.equal(changed.redirects.length,0);assert.match(changed.messages[0],/changed/);
});
