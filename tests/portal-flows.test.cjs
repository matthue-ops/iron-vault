const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
function portal(file,{user=null,roles=[],owners=[],members=[],search='?key=token-a'}={}){
 const calls=[],alerts=[],redirects=[],events={},authEvents=[],elements=new Map(),state=new Map();
 const storage={getItem:k=>state.get(k)||null,setItem:(k,v)=>state.set(k,String(v)),removeItem:k=>state.delete(k)};
 function element(id){if(!elements.has(id))elements.set(id,{value:'',innerText:'',textContent:'',innerHTML:'',style:{},classList:{add(){},remove(){},contains(){return false},toggle(){}},parentNode:{append(){}},setAttribute(){}});return elements.get(id)}
 const client={auth:{getUser:async()=>({data:{user}}),signOut:async()=>({error:null}),onAuthStateChange:fn=>authEvents.push(fn)},from(table){
  const entry={table,fields:null,filters:[]};calls.push(entry);
  const q={select(fields){entry.fields=fields;return q},eq(k,v){entry.filters.push([k,v]);return q},then(resolve){const rows=table==='iv_user_roles'?roles:table==='owners'?owners:table==='members'?members:[];resolve({data:rows.filter(row=>entry.filters.every(([k,v])=>row[k]===v)),error:null})}};return q;
 }};
 const context={console,Intl,Date,URL,URLSearchParams,crypto,tailwind:{},supabase:{createClient:()=>client},document:{body:element('body'),getElementById:element,createElement:()=>element('created'),documentElement:{style:{setProperty(){}}}},sessionStorage:storage,localStorage:storage,alert:message=>alerts.push(message),addEventListener:(name,fn)=>{events[name]=fn},setTimeout:()=>0,location:{search,href:'https://app.example.invalid/'+file+search,replace:url=>redirects.push(url)}};
 context.window=context;vm.createContext(context);
 const html=fs.readFileSync(file,'utf8');
 for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){
  const src=match[1].match(/src="([^"]+)"/);
  if(src){if(!src[1].startsWith('http'))vm.runInContext(fs.readFileSync(path.resolve(path.dirname(file),src[1]),'utf8'),context);}
  else if(match[2].trim())vm.runInContext(match[2],context,{filename:file});
 }
 return {context,calls,alerts,redirects,storage,element,events,authEvents,get:expression=>vm.runInContext(expression,context)};
}
test('actual admin initialization denies anonymous users before any private table read',async()=>{
 const p=portal('gym/admin.html');await p.get('adminApp').init();
 assert.equal(p.calls.length,0);assert.equal(p.redirects.length,1);
});
test('actual admin initialization ignores a forged administrator UI flag for staff',async()=>{
 const p=portal('gym/admin.html',{user:{id:'staff-user'},roles:[{user_id:'staff-user',role:'staff',tenant_id:'gym-a'}]});
 p.storage.setItem('ironvault_active_role','admin');const app=p.get('adminApp');
 app.detectTenantFromUrl=async()=>{app.currentTenantId='gym-a'};let uiRole,loaded=0;
 app.applyUIRoleVisibility=role=>uiRole=role;app.loadMembers=async()=>{loaded++};await app.init();
 assert.equal(uiRole,'staff');assert.equal(loaded,1);assert.equal(p.storage.getItem('ironvault_active_role'),'staff');
});
test('actual admin initialization denies a gym link outside the role tenant',async()=>{
 const p=portal('gym/admin.html',{user:{id:'owner'},roles:[{user_id:'owner',role:'owner',tenant_id:'gym-a'}]});
 const app=p.get('adminApp');app.detectTenantFromUrl=async()=>{app.currentTenantId='gym-b'};
 let loaded=0;app.loadMembers=async()=>{loaded++};await app.init();
 assert.equal(loaded,0);assert.equal(p.redirects.length,1);
});
test('public login initialization requests only selected branding and never a member roster',async()=>{
 const p=portal('gym/memberlogin.html',{owners:[{id:'gym-a',token:'token-a',gym_name:'Gym A',status:'ACTIVE'}]});
 await p.get('app').init();assert.equal(p.calls.length,1);
 assert.equal(p.calls[0].table,'owners');assert.deepEqual(p.calls[0].filters,[['token','token-a']]);
 assert.equal(p.calls[0].fields,'id,gym_name,token,logo,status,pricing');
 assert.equal(p.get('app').currentTenantId,'gym-a');
});
test('public login does not restore a deleted or denied gym from cache',async()=>{
 const p=portal('gym/memberlogin.html');p.storage.setItem('ironvault_owners_db',JSON.stringify([{id:'gym-a',token:'token-a'}]));
 await p.get('app').init();assert.equal(p.get('app').currentTenantId,null);
});
test('actual member data query binds both member identity and tenant',async()=>{
 const p=portal('gym/memberprofile.html',{members:[{id:'member-a',tenant_id:'gym-a'},{id:'member-b',tenant_id:'gym-b'}]});
 const app=p.get('profileApp');app.authenticatedRole={member_id:'member-a',tenant_id:'gym-a'};
 await app.loadData();assert.equal(app.allMembersSystem.length,1);assert.equal(app.allMembersSystem[0].id,'member-a');
 assert.deepEqual(p.calls[0].filters,[['id','member-a'],['tenant_id','gym-a']]);
});
test('actual member logout signs out, clears private state, and returns to the gym link',async()=>{
 const p=portal('gym/memberprofile.html');const app=p.get('profileApp');let signouts=0;
 // The application client is the shared mock produced by createClient.
 p.context.supabase.createClient().auth.signOut=async()=>{signouts++;return {error:null}};
 app.currentMember={tenantToken:'token-a'};app.allMembersSystem=[{id:'private'}];
 p.storage.setItem('ironvault_active_member','private');await app.logout();
 assert.equal(signouts,1);assert.equal(app.currentMember,null);assert.equal(app.allMembersSystem.length,0);
 assert.equal(p.storage.getItem('ironvault_active_member'),null);assert.equal(p.redirects[0],'memberlogin.html?key=token-a');
});
test('cached admin restoration verifies Auth again instead of trusting session flags',async()=>{
 const p=portal('gym/admin.html');p.storage.setItem('ironvault_active_role','admin');
 const app=p.get('adminApp');let initializations=0;app.init=()=>{initializations++};
 p.events.pageshow({persisted:true});assert.equal(initializations,1);
});
test('cached member restoration re-enters the verified initialization gate',()=>{
 const p=portal('gym/memberprofile.html');const app=p.get('profileApp');let initializations=0;
 app.init=()=>{initializations++};p.events.pageshow({persisted:true});assert.equal(initializations,1);
});
test('Auth sign-out hides cached admin and member content before redirecting',()=>{
 for(const file of ['gym/admin.html','gym/memberprofile.html']){
  const p=portal(file);for(const listener of p.authEvents)listener('SIGNED_OUT');
  assert.equal(p.redirects.length,1);
 }
});
test('admin role revoked during data loading prevents completing initialization',async()=>{
 const roles=[{user_id:'operator',role:'staff',tenant_id:'gym-a'}];
 const p=portal('gym/admin.html',{user:{id:'operator'},roles});const app=p.get('adminApp');
 app.detectTenantFromUrl=async()=>{app.currentTenantId='gym-a'};
 app.applyUIRoleVisibility=()=>{};app.loadMembers=async()=>{roles.splice(0)};
 await app.init();assert.equal(p.redirects.length,1);
});
test('member role revoked during data loading prevents completing initialization',async()=>{
 const roles=[{user_id:'member-user',role:'member',tenant_id:'gym-a',member_id:'member-a'}];
 const p=portal('gym/memberprofile.html',{user:{id:'member-user'},roles});const app=p.get('profileApp');
 app.loadData=async()=>{roles.splice(0)};app.checkSession=async()=>{};
 await app.init();assert.equal(p.redirects.length,1);assert.equal(app.currentMember,null);
});
test('administrator downgraded to staff during loading cannot retain administrator UI initialization',async()=>{
 const roles=[{user_id:'operator',role:'owner',tenant_id:'gym-a'}];
 const p=portal('gym/admin.html',{user:{id:'operator'},roles});const app=p.get('adminApp');
 app.detectTenantFromUrl=async()=>{app.currentTenantId='gym-a'};app.applyUIRoleVisibility=()=>{};
 app.loadMembers=async()=>{roles[0]={...roles[0],role:'staff'}};
 await app.init();assert.equal(p.redirects.length,1);
});
