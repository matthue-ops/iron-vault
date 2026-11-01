const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
function portal(file,{user=null,roles=[],owners=[],members=[],records={},search='?key=token-a'}={}){
 const calls=[],alerts=[],redirects=[],events={},authEvents=[],elements=new Map(),state=new Map();
 const storage={getItem:k=>state.get(k)||null,setItem:(k,v)=>state.set(k,String(v)),removeItem:k=>state.delete(k)};
 function element(id){if(!elements.has(id))elements.set(id,{value:'',innerText:'',textContent:'',innerHTML:'',style:{},classList:{add(){},remove(){},contains(){return false},toggle(){}},parentNode:{append(){}},setAttribute(){}});return elements.get(id)}
 const client={rpc:async()=>({data:null,error:null}),auth:{getUser:async()=>({data:{user}}),signOut:async()=>({error:null}),onAuthStateChange:fn=>authEvents.push(fn)},from(table){
  const entry={table,fields:null,filters:[]};calls.push(entry);
  const q={select(fields){entry.fields=fields;return q},eq(k,v){entry.filters.push([k,v]);return q},order(){return q},limit(){return q},then(resolve){const rows=table==='iv_user_roles'?roles:table==='owners'?owners:table==='members'?members:(records[table]||[]);resolve({data:rows.filter(row=>entry.filters.every(([k,v])=>row[k]===v)),error:null})}};return q;
 }};
 const context={console,Intl,Date,URL,URLSearchParams,crypto,tailwind:{},supabase:{createClient:()=>client},document:{body:element('body'),getElementById:element,createElement:()=>element('created'),documentElement:{style:{setProperty(){}}}},sessionStorage:storage,localStorage:storage,alert:message=>alerts.push(message),addEventListener:(name,fn)=>{events[name]=fn},setTimeout:()=>0,location:{search,href:'https://app.example.invalid/'+file+search,replace:url=>redirects.push(url)}};
 context.window=context;vm.createContext(context);
 const html=fs.readFileSync(file,'utf8');
 for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){
  const src=match[1].match(/src="([^"]+)"/);
  if(src){if(!src[1].startsWith('http'))vm.runInContext(fs.readFileSync(path.resolve(path.dirname(file),src[1]),'utf8'),context);}
  else if(match[2].trim())vm.runInContext(match[2],context,{filename:file});
 }
 return {context,calls,alerts,redirects,storage,element,events,authEvents,client,get:expression=>vm.runInContext(expression,context)};
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
function qrFixture(){
 const roles=[{user_id:'desk-user',role:'staff',tenant_id:'gym-a'}];
 const p=portal('gym/admin.html',{user:{id:'desk-user'},roles});
 const app=p.get('adminApp');app.currentTenantId='gym-a';
 app.members=[{id:'member-a',tenantId:'gym-a',name:'Member'}];
 app.saveMembers=async()=>{throw new Error('QR admission must never bulk-upsert profiles')};
 app.loadMembers=async()=>{};app.pauseScannerAfterSuccess=()=>{};
 const results=[];app.showScanResult=(ok,title,description)=>results.push({ok,title,description});
 class Clock extends Date{constructor(...args){super(...(args.length?args:['2026-10-31T17:00:00Z']))}}
 p.context.Date=Clock;
 return {...p,app,roles,results};
}
test('QR admission uses the reviewed RPC and accepts the Manila date before 08:00',async()=>{
 const p=qrFixture();const rpc=[];p.client.rpc=async(name,args)=>{rpc.push({name,args});return {data:'timestamp',error:null}};
 await p.app.processScannedCode('member-a|2026-11-01');
 assert.equal(rpc.length,2);assert.equal(rpc[0].name,'iv_checkin');assert.equal(rpc[1].name,'iv_log_event');
 assert.equal(rpc[0].args.p_member_id,'member-a');assert.equal(rpc[0].args.p_method,'qr');
 assert.equal(p.results.at(-1).ok,true);
});
test('QR admission does not show success when the server rejects duplicate or expired admission',async()=>{
 const p=qrFixture();p.client.rpc=async()=>({error:{message:'Already checked in today'}});
 await p.app.processScannedCode('member-a|2026-11-01');
 assert.equal(p.results.at(-1).ok,false);assert.match(p.results.at(-1).description,/Already checked in/);
});
test('QR rejects wrong-tenant, malformed, outdated and revoked-role inputs before an RPC',async()=>{
 const p=qrFixture();let rpc=0;p.client.rpc=async()=>{rpc++;return {error:null}};
 await p.app.processScannedCode('member-a|2026-10-31');
 await p.app.processScannedCode('malformed');
 p.app.members[0].tenantId='gym-b';await p.app.processScannedCode('member-a|2026-11-01');
 p.app.members[0].tenantId='gym-a';p.roles.splice(0);await p.app.processScannedCode('member-a|2026-11-01');
 assert.equal(rpc,0);assert.equal(p.results.length,4);assert.ok(p.results.every(r=>!r.ok));
});
test('confirmed QR check-in is not reported as failed if roster refresh subsequently fails',async()=>{
 const p=qrFixture();p.app.loadMembers=async()=>{throw new Error('refresh unavailable')};
 await p.app.processScannedCode('member-a|2026-11-01');
 assert.equal(p.results.at(-1).ok,true);assert.equal(p.results.at(-1).title,'ENTRY RECORDED');
});
test('an activity-note failure cannot undo or misreport a confirmed QR admission',async()=>{
 const p=qrFixture();p.client.rpc=async name=>name==='iv_checkin'
  ?{data:'timestamp',error:null}:{data:null,error:{message:'note unavailable'}};
 await p.app.processScannedCode('member-a|2026-11-01');
 assert.equal(p.results.at(-1).ok,true);assert.match(p.results.at(-1).description,/Activity note unavailable/);
});
function reportFixture(role='owner',enabled=true){
 const p=portal('gym/reports.html',{user:{id:'report-user'},roles:[{user_id:'report-user',role,tenant_id:role==='super_admin'?null:'gym-a'}],
  owners:[{id:'gym-a',token:'token-a',gym_name:'Gym A'}],members:[{id:'member-a',tenant_id:'gym-a',name:'Member',wallet_balance:100}],
  records:{iv_financial_transactions:[{id:'tx',tenant_id:'gym-a',member_id:'deleted-member',kind:'topup',amount:125,created_at:'2026-11-01T03:00:00+08:00'}]}});
 const permission={enabled,calls:0};p.client.rpc=async(name,args)=>{assert.equal(name,'iv_can_read_financial_reports');assert.equal(args.p_tenant,'gym-a');permission.calls++;return {data:permission.enabled,error:null}};
 class Clock extends Date{constructor(...args){super(...(args.length?args:['2026-11-01T12:00:00+08:00']))}}
 p.context.Date=Clock;return {...p,permission,app:p.get('reportsApp')};
}
test('report initialization denies anonymous access before private or branding queries',async()=>{
 const p=portal('gym/reports.html');await p.get('reportsApp').init();assert.equal(p.calls.length,0);assert.equal(p.redirects.length,1);
});
test('ordinary staff cannot load financial/member/log data without backend permission',async()=>{
 const p=reportFixture('staff',false);await p.app.init();
 assert.ok(p.calls.every(c=>c.table==='iv_user_roles'||c.table==='owners'));assert.equal(p.redirects.length,1);
});
for(const role of ['owner','staff','super_admin']){
 test(`report workflow remains available to authorized ${role} and includes ledger entries whose member profile is absent`,async()=>{
  const p=reportFixture(role,true);await p.app.init();assert.equal(p.redirects.length,0);
  assert.equal(p.app.ivFinance.length,1);assert.match(p.element('metric-revenue').textContent,/125/);
  const dataCalls=p.calls.filter(c=>c.table!=='iv_user_roles'&&c.table!=='owners');
  assert.ok(dataCalls.length>=5);assert.ok(dataCalls.every(c=>c.filters.some(([k,v])=>k==='tenant_id'&&v==='gym-a')));
  assert.ok(!p.calls.find(c=>c.table==='members').fields.includes('password'));
 });
}
test('financial permission revocation clears cached results and blocks subsequent print and refresh',async()=>{
 const p=reportFixture('staff',true);await p.app.init();let prints=0;p.context.print=()=>{prints++};
 p.permission.enabled=false;await p.app.printReport();assert.equal(prints,0);assert.equal(p.app.ivFinance.length,0);
 assert.equal(p.element('financial-tbody').textContent,'');
 await p.app.filterAndRenderReport('2026-11-01','2026-11-01');assert.equal(p.app.ivFinance.length,0);
});
test('reporting has no first-gym or private-cache fallback on a wrong-tenant link',async()=>{
 const p=reportFixture('owner',true);p.context.location.search='?key=wrong';
 p.storage.setItem('ironvault_owners_db',JSON.stringify([{id:'gym-b',token:'wrong'}]));
 await p.app.init();assert.equal(p.permission.calls,0);assert.equal(p.redirects.length,1);
});
test('report backend missing during staged deployment fails closed before member or history reads',async()=>{
 const p=reportFixture('owner',true);p.client.rpc=async()=>({data:null,error:{code:'PGRST202'}});await p.app.init();
 assert.ok(!p.calls.some(c=>c.table==='members'||c.table.startsWith('iv_financial')));assert.equal(p.redirects.length,1);
});
test('denied report navigation keeps ordinary staff in the desk portal',async()=>{
 const p=portal('gym/admin.html',{user:{id:'desk'},roles:[{user_id:'desk',role:'staff',tenant_id:'gym-a'}]});
 const app=p.get('adminApp');app.currentTenantId='gym-a';app.matchedOwnerRecord={token:'token-a'};
 p.client.rpc=async()=>({data:false,error:null});const before=p.context.location.href;
 await app.openReportsPage();assert.equal(p.context.location.href,before);assert.equal(p.alerts.length,1);
});

test('desk sale uses a server quote and payment RPC without saving client financial fields',async()=>{
 const p=portal('gym/admin.html',{user:{id:'staff'},roles:[{user_id:'staff',role:'staff',tenant_id:'gym-a'}]});
 const app=p.get('adminApp');app.currentTenantId='gym-a';app.activeCheckInMemberId='member';p.context.confirm=()=>true;
 let admitted=0;app.finalizeDeskCheckIn=async()=>{admitted++};app.saveMembers=async()=>{throw Error('Client write forbidden')};
 const calls=[];p.client.rpc=async(name,args)=>{calls.push({name,args});return name==='iv_quote_plan'?{data:{price:150,wallet_balance:100}}:{data:{request_id:args.p_request_id,wallet_balance:0}}};
 await app.confirmPlanSelection('1-Day Pass');
 assert.equal(calls[0].name,'iv_quote_plan');assert.equal(calls[1].name,'iv_financial_transaction');
 assert.equal(calls[1].args.p_amount,150);assert.equal(calls[1].args.p_cash_amount,50);assert.equal(admitted,1);
 assert.equal(app.activeCheckInMemberId,null);
});
test('desk retries an unknown purchase outcome with the original key and split without quoting again',async()=>{
 const p=portal('gym/admin.html',{user:{id:'staff'},roles:[{user_id:'staff',role:'staff',tenant_id:'gym-a'}]});
 const app=p.get('adminApp');app.currentTenantId='gym-a';app.activeCheckInMemberId='member';p.context.confirm=()=>true;
 let admitted=0,quotes=0;const requests=[];app.finalizeDeskCheckIn=async()=>{admitted++};
 p.client.rpc=async(name,args)=>{if(name==='iv_quote_plan'){quotes++;return{data:{price:150,wallet_balance:100}}}
  requests.push(args);if(requests.length===1)throw Error('Lost response');return{data:{request_id:args.p_request_id,wallet_balance:0}}};
 await app.confirmPlanSelection('1-Day Pass');assert.equal(admitted,0);
 await app.confirmPlanSelection('1-Day Pass');assert.equal(admitted,1);assert.equal(quotes,1);
 assert.equal(requests[0].p_request_id,requests[1].p_request_id);assert.equal(requests[1].p_cash_amount,50);
});
test('denied or missing financial backend cannot fall back to client balance mutations or admission',async()=>{
 const p=portal('gym/admin.html',{user:{id:'staff'},roles:[{user_id:'staff',role:'staff',tenant_id:'gym-a'}]});
 const app=p.get('adminApp');app.currentTenantId='gym-a';app.activeCheckInMemberId='member';p.context.confirm=()=>true;
 let writes=0;app.saveMembers=async()=>{writes++};app.finalizeDeskCheckIn=async()=>{writes++};
 p.client.rpc=async()=>({error:{code:'PGRST202',message:'Missing RPC'}});
 await app.confirmPlanSelection('1-Day Pass');assert.equal(writes,0);assert.equal(app.activeCheckInMemberId,'member');
});
