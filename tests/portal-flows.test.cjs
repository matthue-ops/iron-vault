const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
function portal(file,{user=null,roles=[],owners=[],members=[],records={},search='?key=token-a'}={}){
 const calls=[],alerts=[],redirects=[],events={},authEvents=[],elements=new Map(),state=new Map();let created=0;
 const storage={getItem:k=>state.get(k)||null,setItem:(k,v)=>state.set(k,String(v)),removeItem:k=>state.delete(k)};
 function element(id){if(!elements.has(id))elements.set(id,{dataset:{},children:[],appendChild(child){this.children.push(child)},addEventListener(name,fn){(this.listeners??={})[name]=fn},click(){},value:'',innerText:'',textContent:'',innerHTML:'',style:{},classList:{add(){},remove(){},contains(){return false},toggle(){}},parentNode:{append(){}},setAttribute(){}});return elements.get(id)}
 const client={rpc:async()=>({data:null,error:null}),auth:{getUser:async()=>({data:{user}}),signOut:async()=>({error:null}),onAuthStateChange:fn=>authEvents.push(fn)},from(table){
  table=({iv_gyms:'owners',iv_members:'members'})[table]||table;
  const entry={table,fields:null,filters:[]};calls.push(entry);
  const q={select(fields){entry.fields=fields;return q},eq(k,v){entry.filters.push([k,v]);return q},gt(k,v){entry.after=[k,v];return q},order(){return q},limit(){return q},single(){return new Promise(resolve=>q.then(({data,error})=>resolve(data.length===1?{data:data[0],error}:{data:null,error:{message:'Expected one row'}})))},then(resolve){const rows=table==='iv_user_roles'?roles:table==='owners'?owners:table==='members'?members:(records[table]||[]);resolve({data:rows.filter(row=>entry.filters.every(([k,v])=>row[k]===v)&&(!entry.after||row[entry.after[0]]>entry.after[1])),error:null})}};return q;
 }};
 const context={console,Intl,Date,URL,URLSearchParams,crypto,tailwind:{},supabase:{createClient:()=>client},document:{body:element('body'),getElementById:element,createElement:()=>element('created-'+(++created)),documentElement:{tagName:'HTML',style:{setProperty(){}}}},sessionStorage:storage,localStorage:storage,alert:message=>alerts.push(message),addEventListener:(name,fn)=>{events[name]=fn},setTimeout:()=>0,location:{search,hash:'',pathname:'/'+file,href:'https://app.example.invalid/'+file+search,replace:url=>redirects.push(url)}};
 context.window=context;vm.createContext(context);
 const html=fs.readFileSync(file,'utf8');
 for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){
  const src=match[1].match(/src="([^"]+)"/);
  if(src){if(!src[1].startsWith('http'))vm.runInContext(fs.readFileSync(path.resolve(src[1].startsWith('/')?'.':path.dirname(file),src[1].replace(/^\//,'')),'utf8'),context);}
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
 const p=portal('gym/login.html',{owners:[{id:'gym-a',token:'token-a',gym_name:'Gym A',status:'ACTIVE'}]});
 await p.get('app').init();assert.equal(p.calls.length,1);
 assert.equal(p.calls[0].table,'owners');assert.deepEqual(p.calls[0].filters,[['token','token-a']]);
 assert.equal(p.calls[0].fields,'id,gym_name,token,logo,status,pricing');
 assert.equal(p.get('app').currentTenantId,'gym-a');
});
test('public login does not restore a deleted or denied gym from cache',async()=>{
 const p=portal('gym/login.html');p.storage.setItem('ironvault_owners_db',JSON.stringify([{id:'gym-a',token:'token-a'}]));
 await p.get('app').init();assert.equal(p.get('app').currentTenantId,null);
});
test('actual member data query binds both member identity and tenant',async()=>{
 const p=portal('gym/profile.html',{members:[{id:'member-a',tenant_id:'gym-a'},{id:'member-b',tenant_id:'gym-b'}]});
 const app=p.get('profileApp');app.authenticatedRole={member_id:'member-a',tenant_id:'gym-a'};
 await app.loadData();assert.equal(app.allMembersSystem.length,1);assert.equal(app.allMembersSystem[0].id,'member-a');
 assert.deepEqual(p.calls[0].filters,[['id','member-a'],['tenant_id','gym-a']]);
});
test('actual member logout signs out, clears private state, and returns to the gym link',async()=>{
 const p=portal('gym/profile.html');const app=p.get('profileApp');let signouts=0;
 // The application client is the shared mock produced by createClient.
 p.context.supabase.createClient().auth.signOut=async()=>{signouts++;return {error:null}};
 app.currentMember={tenantToken:'token-a'};app.allMembersSystem=[{id:'private'}];
 p.storage.setItem('ironvault_active_member','private');await app.logout();
 assert.equal(signouts,1);assert.equal(app.currentMember,null);assert.equal(app.allMembersSystem.length,0);
 assert.equal(p.storage.getItem('ironvault_active_member'),null);assert.equal(p.redirects[0],'login.html?key=token-a');
});
test('cached admin restoration verifies Auth again instead of trusting session flags',async()=>{
 const p=portal('gym/admin.html');p.storage.setItem('ironvault_active_role','admin');
 const app=p.get('adminApp');let initializations=0;app.init=()=>{initializations++};
 p.events.pageshow({persisted:true});assert.equal(initializations,1);
});
test('cached member restoration re-enters the verified initialization gate',()=>{
 const p=portal('gym/profile.html');const app=p.get('profileApp');let initializations=0;
 app.init=()=>{initializations++};p.events.pageshow({persisted:true});assert.equal(initializations,1);
});
test('Auth sign-out hides cached admin and member content before redirecting',()=>{
 for(const file of ['gym/admin.html','gym/profile.html']){
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
 const p=portal('gym/profile.html',{user:{id:'member-user'},roles});const app=p.get('profileApp');
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
test('QR admission redeems a server-issued ticket in the selected gym',async()=>{
 const p=qrFixture();const rpc=[];p.client.rpc=async(name,args)=>{rpc.push({name,args});return {data:'timestamp',error:null}};
 await p.app.processScannedCode('IV1|01234567-89ab-4cde-8fab-0123456789ab');
 assert.equal(rpc.length,2);assert.equal(rpc[0].name,'iv_redeem_member_pass');assert.equal(rpc[1].name,'iv_log_event');
 assert.equal(rpc[0].args.p_token,'01234567-89ab-4cde-8fab-0123456789ab');assert.equal(rpc[0].args.p_tenant,'gym-a');
 assert.equal(p.results.at(-1).ok,true);
});
test('QR admission does not show success when the server rejects duplicate or expired admission',async()=>{
 const p=qrFixture();p.client.rpc=async()=>({error:{message:'Already checked in today'}});
 await p.app.processScannedCode('IV1|01234567-89ab-4cde-8fab-0123456789ab');
 assert.equal(p.results.at(-1).ok,false);assert.match(p.results.at(-1).description,/Already checked in/);
});
test('QR rejects unsigned, malformed and revoked-role inputs before an RPC',async()=>{
 const p=qrFixture();let rpc=0;p.client.rpc=async()=>{rpc++;return {error:null}};
 await p.app.processScannedCode('member-a|2026-10-31');
 await p.app.processScannedCode('malformed');
 p.app.members[0].tenantId='gym-b';await p.app.processScannedCode('member-a|2026-11-01');
 p.app.members[0].tenantId='gym-a';p.roles.splice(0);await p.app.processScannedCode('IV1|01234567-89ab-4cde-8fab-0123456789ab');
 assert.equal(rpc,0);assert.equal(p.results.length,4);assert.ok(p.results.every(r=>!r.ok));
});
test('confirmed QR check-in is not reported as failed if roster refresh subsequently fails',async()=>{
 const p=qrFixture();p.app.loadMembers=async()=>{throw new Error('refresh unavailable')};
 await p.app.processScannedCode('IV1|01234567-89ab-4cde-8fab-0123456789ab');
 assert.equal(p.results.at(-1).ok,true);assert.equal(p.results.at(-1).title,'ENTRY RECORDED');
});
test('an activity-note failure cannot undo or misreport a confirmed QR admission',async()=>{
 const p=qrFixture();p.client.rpc=async name=>name==='iv_redeem_member_pass'
  ?{data:'timestamp',error:null}:{data:null,error:{message:'note unavailable'}};
 await p.app.processScannedCode('IV1|01234567-89ab-4cde-8fab-0123456789ab');
 assert.equal(p.results.at(-1).ok,true);assert.match(p.results.at(-1).description,/Activity note unavailable/);
});
function reportFixture(role='owner',enabled=true){
 const p=portal('gym/reports.html',{user:{id:'report-user'},roles:[{user_id:'report-user',role,tenant_id:role==='super_admin'?null:'gym-a'}],
  owners:[{id:'gym-a',token:'token-a',gym_name:'Gym A'}],members:[{id:'member-a',tenant_id:'gym-a',name:'Member',wallet_balance:100}],
  records:{iv_financial_transactions:[{id:'tx',tenant_id:'gym-a',member_id:'deleted-member',kind:'topup',amount:125,created_at:'2026-11-01T03:00:00+08:00'}]}});
 const permission={enabled,calls:0,snapshots:[]};p.client.rpc=async(name,args)=>{if(name==='iv_report_snapshot'){permission.snapshots.push(args);return {data:{financial:[{id:'tx',tenant_id:'gym-a',member_id:'deleted-member',kind:'topup',amount:125,created_at:'2026-11-01T03:00:00+08:00'}],attendance:[],activity:[],sessions:[],members:[{id:'member-a',tenant_id:'gym-a',name:'Member',wallet_balance:100}]}};}assert.equal(name,'iv_can_read_financial_reports');assert.equal(args.p_tenant,'gym-a');permission.calls++;return {data:permission.enabled,error:null}};
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
  assert.equal(p.app.ivFinance.length,1);assert.equal(p.element('metric-revenue').textContent,'₱0.00');
  const dataCalls=p.calls.filter(c=>c.table!=='iv_user_roles'&&c.table!=='owners');
  assert.equal(dataCalls.length,0);assert.equal(p.permission.snapshots.length,1);assert.equal(p.permission.snapshots[0].p_tenant,'gym-a');assert.ok(dataCalls.every(c=>c.filters.some(([k,v])=>k==='tenant_id'&&v==='gym-a')));
  assert.equal(p.calls.find(c=>c.table==='members'),undefined);
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

test('member plan selection uses wallet-only RPC and cannot submit a cash payment or local entitlement',async()=>{
 const p=portal('gym/profile.html',{user:{id:'member'},roles:[{user_id:'member',role:'member',tenant_id:'gym-a',member_id:'member-a'}]});
 const app=p.get('profileApp');app.currentMember={id:'member-a',tenantId:'gym-a',name:'Member',plan:'Not Selected',walletBalance:200};app.confirmAction=async()=>true;
 app.renderProfile=()=>{};app.showAlert=()=>{};app.saveData=async()=>{throw Error('No raw entitlement writes')};
 const calls=[];p.client.rpc=async(name,args)=>{calls.push({name,args});return name==='iv_quote_plan'?{data:{price:150,wallet_balance:200}}:{data:{request_id:args.p_request_id,wallet_balance:50,expiration_date:'2026-11-01'}}};
 await app.selectPlan('1-Day Pass');assert.equal(calls[1].args.p_cash_amount,0);assert.equal(app.currentMember.walletBalance,50);assert.equal(app.currentMember.plan,'1-Day Pass');
});
test('self profile save submits only name phone and avatar, never wallet status email or discounts',async()=>{
 const p=portal('gym/profile.html');const app=p.get('profileApp');app.currentMember={id:'member',tenantId:'gym-a',name:'Member',email:'new@example.invalid',walletBalance:999,discountPercentage:100,status:'ACTIVE'};
 const calls=[];p.client.rpc=async(name,args)=>{calls.push({name,args});return{data:null,error:null}};
 await app.saveData();const row=calls[0].args.p_records[0];for(const key of ['wallet_balance','status','email','discount_percentage'])assert.equal(key in row,false);
});
test('admin logout still attempts local signout after an audit network failure',async()=>{
 const p=portal('gym/admin.html');const app=p.get('adminApp');app.currentTenantId='gym-a';app.matchedOwnerRecord={token:'token-a'};let signs=0;
 p.client.rpc=async()=>{throw Error('Audit unavailable')};p.client.auth.signOut=async()=>{signs++;return{error:null}};
 await app.logoutAdmin();assert.equal(signs,1);assert.equal(p.redirects.at(-1),'login.html?key=token-a');
});

test('top-up uses verified active member state and stable transaction RPC after the data cutover',async()=>{
 const p=portal('gym/admin.html',{user:{id:'staff'},roles:[{user_id:'staff',role:'staff',tenant_id:'gym-a'}],members:[{id:'member',tenant_id:'gym-a',status:'ACTIVE'}]});
 const app=p.get('adminApp');app.currentTenantId='gym-a';app.activeModalMemberId='member';app.members=[{id:'member',name:'Member'}];p.context.confirm=()=>true;
 app.loadMembers=async()=>{};app.openProfileModal=()=>{};const calls=[];
 p.client.rpc=async(name,args)=>{calls.push({name,args});return{data:{request_id:args.p_request_id,wallet_balance:100}}};
 await app.addModalCredits(100);assert.equal(calls[0].name,'iv_financial_transaction');assert.equal(calls[0].args.p_operation,'topup');assert.equal(app.members[0].walletBalance,100);
});

test('deactivation removes a member from the active roster after refresh while retaining their record',async()=>{
 const members=[{id:'removed-member',tenant_id:'gym-a',name:'Archived Person',email:'old@example.invalid',status:'ACTIVE'},
 {id:'current-member',tenant_id:'gym-a',name:'Current Person',email:'current@example.invalid',status:'ACTIVE'}];
 const p=portal('gym/admin.html',{user:{id:'owner'},roles:[{user_id:'owner',role:'owner',tenant_id:'gym-a',enabled:true}],members});
 const app=p.get('adminApp');app.currentTenantId='gym-a';p.context.confirm=()=>true;
 p.client.rpc=async(name,args)=>{assert.equal(name,'iv_deactivate_member');assert.equal(args.p_member_id,'removed-member');members[0].status='INACTIVE';return{data:null,error:null}};
 await app.loadMembers();assert.match(p.element('roster-tbody').innerHTML,/Archived Person/);
 await app.deleteMember('removed-member');
 for(let refresh=0;refresh<2;refresh++){
  await app.loadMembers();assert.doesNotMatch(p.element('roster-tbody').innerHTML,/Archived Person/);
  assert.match(p.element('roster-tbody').innerHTML,/Current Person/);assert.equal(p.element('showing-count').innerText,1);
 }
 assert.equal(members.length,2);assert.equal(app.members.find(m=>m.id==='removed-member').status,'INACTIVE');
 assert.match(p.alerts.at(-1),/History retained/);
});

test('master purge requires typed tenant confirmation and clears password after the operation',async()=>{
 const p=portal('gym/index.html',{user:{id:'master'},roles:[{user_id:'master',role:'super_admin',tenant_id:null,enabled:true}]});
 const app=p.get('indexApp');const calls=[];
 // The API object is frozen; inject a test transport before installing the purge controller.
 p.context.IronVaultBranchAuth={invoke:async(client,name,body)=>{calls.push(body);assert.equal(name,'iv-purge-tenant');
  return body.action==='preview'?{gym_name:'Gym',members:2,accounts:3,transactions:4,attendance:5,activity:6,sessions:7,wallet_credit:'150',wallet_accounts:1}:{complete:true};}};
 p.context.IronVaultTenantPurge.install(app,p.client);app.loadData=async()=>{};app.renderDashboard=()=>{};
 await app.openTenantPurge('gym-a');assert.match(p.element('purge-summary').textContent,/150/);
 p.element('purge-password').value='private-password';p.element('purge-confirmation').value='gym-a';
 await app.confirmTenantPurge({preventDefault(){}});assert.equal(calls.length,1);
 p.element('purge-confirmation').value='PURGE gym-a';await app.confirmTenantPurge({preventDefault(){}});
 assert.equal(calls[1].action,'purge');assert.equal(calls[1].tenant_id,'gym-a');assert.equal(p.element('purge-password').value,'');
 assert.equal(p.alerts.at(-1),'Tenant and its dedicated accounts permanently purged.');
});

test('signout clears private tenant purge details and the password',async()=>{
 const p=portal('gym/index.html',{user:{id:'master'},roles:[{user_id:'master',role:'super_admin',tenant_id:null,enabled:true}]});
 const app=p.get('indexApp');p.context.IronVaultBranchAuth={invoke:async()=>({gym_name:'Private Gym',wallet_credit:'100'})};
 p.context.IronVaultTenantPurge.install(app,p.client);await app.openTenantPurge('gym-a');
 p.element('purge-password').value='private-password';assert.match(p.element('purge-summary').textContent,/Private Gym/);
 p.authEvents.at(-1)('SIGNED_OUT',null);assert.equal(p.element('purge-password').value,'');assert.equal(p.element('purge-summary').textContent,'');
});

test('roster displays and searches short codes while retaining internal IDs in actions',async()=>{
 const p=portal('gym/admin.html',{members:[{id:'long-internal-id',display_code:'MEM-0001',tenant_id:'gym-a',name:'Short Code Member',email:'test@example.invalid',status:'ACTIVE'}]});
 const app=p.get('adminApp');app.currentTenantId='gym-a';await app.loadMembers();
 assert.match(p.element('roster-tbody').innerHTML,/MEM-0001/);assert.match(p.element('roster-tbody').innerHTML,/openProfileModal\(decodeURIComponent\('long-internal-id'\)/);
 p.element('roster-search').value='MEM-0001';app.filterRoster();assert.match(p.element('roster-tbody').innerHTML,/Short Code Member/);
});
test('bad report date ranges are explained without querying or treating them as an authorization failure',async()=>{
 const p=reportFixture();await p.app.init();const before=p.permission.snapshots.length;
 p.element('filter-date-start').value='2026-11-05';p.element('filter-date-end').value='2026-11-01';await p.app.onDateFilterChange();
 assert.equal(p.permission.snapshots.length,before);assert.equal(p.redirects.length,0);assert.match(p.element('report-validation').textContent,/last valid report/);
});

test('last seven days uses seven inclusive Manila dates and All-Time stops at today',async()=>{
 const p=reportFixture();await p.app.init();await p.app.setQuickRange('week');
 assert.equal(p.element('filter-date-start').value,'2026-10-26');assert.equal(p.element('filter-date-end').value,'2026-11-01');
 await p.app.setQuickRange('all');assert.equal(p.element('filter-date-end').value,'2026-11-01');assert.equal(p.element('filter-date-start').value,'1900-01-01');
});

test('manual desk search excludes pending and removed members even by exact name or code',()=>{
 const p=portal('gym/admin.html');const app=p.get('adminApp');app.members=[
 {id:'active',displayCode:'MEM-0001',name:'Active Person',status:'ACTIVE'},
 {id:'inactive',displayCode:'MEM-0002',name:'Removed Person',status:'INACTIVE'},
 {id:'pending',displayCode:'MEM-0003',name:'Pending Person',status:'PENDING'}];
 app.searchManualCheckIn();const html=p.element('manual-search-results').innerHTML;
 assert.match(html,/Active Person/);assert.doesNotMatch(html,/Removed Person|Pending Person/);
 p.element('manual-search-input').value='MEM-0002';app.searchManualCheckIn();assert.match(p.element('manual-search-results').innerHTML,/No matching/);
});
test('member removal checks owner authority and zero wallet credit before invoking the server',async()=>{
 for(const [role,balance] of [['owner',100],['staff',0]]){
  const p=portal('gym/admin.html',{user:{id:'operator'},roles:[{user_id:'operator',role,tenant_id:'gym-a'}]});const app=p.get('adminApp');
  app.currentTenantId='gym-a';app.members=[{id:'m',name:'Member',walletBalance:balance}];let calls=0;p.client.rpc=async()=>{calls++;return{error:null}};p.context.confirm=()=>true;
  await app.deleteMember('m');assert.equal(calls,0);assert.ok(p.alerts.length>0);
 }
});
test('member profile renders the short code while its database query keeps the internal ID',async()=>{
 const p=portal('gym/profile.html',{members:[{id:'long-internal-id',display_code:'MEM-0042',tenant_id:'gym-a',name:'Member',wallet_balance:0,status:'ACTIVE'}]});
 const app=p.get('profileApp');app.authenticatedRole={member_id:'long-internal-id',tenant_id:'gym-a'};await app.loadData();app.currentMember=app.allMembersSystem[0];app.renderProfile();
 assert.equal(p.element('profile-card-id').innerText,'MEM-0042');assert.equal(app.currentMember.id,'long-internal-id');
});
test('attendance shows current expiry and activity never falls back to the money log',async()=>{
 const p=reportFixture();await p.app.init();p.app.branchMembers=[{id:'member-a',name:'Member',displayCode:'MEM-0001',plan:'1-Week Pass',expiration_date:'2026-11-08',status:'ACTIVE'}];
 p.app.ivAttendance=[{member_id:'member-a',method:'manual',created_at:'2026-11-01T01:00:00+08:00'}];
 p.app.ivActivity=[{created_at:'2026-11-01T02:00:00+08:00',event:'Pricing updated',details:'New rates'}];
 p.app.ivActors=[{user_id:'staff',name:'Staff Person',role:'staff'}];p.app.ivSessions=[{created_at:'2026-11-01T02:00:00+08:00',event:'login',actor_id:'staff'}];
 await p.app.ivRender('2026-11-01','2026-11-01');p.app.switchTab('attendance');
 const attendance=p.element('attendance-tbody').children.at(-1).children.map(c=>c.textContent);assert.match(attendance[5],/8 Nov 2026.*7 days left/);
 p.app.switchTab('audit');assert.equal(p.app.ivMode,'all');p.app.ivChoose('activity');let row=p.element('audit-tbody').children.at(-1).children.map(c=>c.textContent);assert.equal(row[2],'Pricing updated');
 p.app.ivChoose('sessions');row=p.element('audit-tbody').children.at(-1).children.map(c=>c.textContent);assert.equal(row[2],'Staff login');
 p.app.switchTab('audit');assert.equal(p.app.ivMode,'sessions');
});

test('server wallet checks can still reject removal after a stale zero-balance preview',async()=>{
 const p=portal('gym/admin.html',{user:{id:'owner'},roles:[{user_id:'owner',role:'owner',tenant_id:'gym-a'}]});const app=p.get('adminApp');
 app.currentTenantId='gym-a';app.members=[{id:'m',name:'Member',status:'ACTIVE',walletBalance:0}];p.context.confirm=()=>true;
 p.client.rpc=async()=>({error:{message:'Settle wallet balance before deactivation'}});await app.deleteMember('m');
 assert.equal(app.members[0].status,'ACTIVE');assert.match(p.alerts.at(-1),/Settle wallet balance/);
});

test('active gym owner portal stays enabled and incomplete provisioning gives setup guidance without email gating',async()=>{
 for(const status of ['ACTIVE','PROVISIONING']){
  const p=portal('gym/login.html',{owners:[{id:'gym-a',token:'token-a',gym_name:'Gym A',status}]});
  await p.get('app').init();
  assert.equal(p.element('btn-submit-admin').disabled,status!=='ACTIVE');
  if(status==='PROVISIONING')assert.match(p.element('portal-subtitle').innerText,/setup is incomplete/);
  assert.doesNotMatch(p.element('portal-subtitle').innerText,/owner email verification/);
 }
});

test('reports start with four overview cards and table switching preserves the shared period without another fetch',async()=>{
 const p=reportFixture();await p.app.init();assert.equal(p.app.currentTab,'overview');
 assert.equal(p.element('report-overview').children.length,4);assert.equal(p.element('report-table-tools').hidden,true);
 const count=p.permission.snapshots.length;
 p.app.switchTab('financial');assert.equal(p.element('report-table-tools').hidden,false);
 p.element('report-search').value='top-up';p.app.switchTab('attendance');assert.equal(p.element('report-search').value,'');
 p.element('report-search').value='manual';p.app.switchTab('financial');assert.equal(p.element('report-search').value,'top-up');
 assert.equal(p.permission.snapshots.length,count);assert.equal(p.element('filter-date-start').value,'2026-11-01');
});
test('activity combines administrative and staff events within the selected dates and supports independent filtering',async()=>{
 const p=reportFixture();await p.app.init();p.app.ivActivity=[{created_at:'2026-11-01T02:00:00+08:00',event:'Pricing updated',actor_id:'owner'}];
 p.app.ivSessions=[{created_at:'2026-11-01T03:00:00+08:00',event:'login',actor_id:'staff'},{created_at:'2026-10-01T03:00:00+08:00',event:'logout',actor_id:'staff'}];
 await p.app.ivRender('2026-11-01','2026-11-01');p.app.switchTab('audit');
 assert.match(p.element('report-page').textContent,/of 2 matching rows/);
 p.app.ivChoose('sessions');assert.match(p.element('report-page').textContent,/of 1 matching rows/);
 p.element('report-search').value='Pricing';p.element('report-search').listeners?.input?.();
 p.app.ivChoose('activity');assert.match(p.element('report-page').textContent,/of 1 matching rows/);
});

test('staff list collapses email and management actions beneath name, role and verified access status',async()=>{
 const p=portal('gym/admin.html',{user:{id:'owner'},roles:[{user_id:'owner',role:'owner',tenant_id:'gym-a',enabled:true},{user_id:'staff-id',role:'staff',tenant_id:'gym-a',enabled:true}]});
 const app=p.get('adminApp');app.matchedOwnerRecord={id:'gym-a',status:'ACTIVE',token:'token-a',staff:[{name:'Staff Person',email:'staff@example.invalid',auth_user_id:'staff-id'}]};
 app.renderExistingStaffList();await new Promise(resolve=>setImmediate(resolve));
 const card=p.element('existing-staff-list').children.at(-1),summary=card.children[0],details=card.children[1];
 assert.equal(summary.children[0].textContent,'Staff Person · Staff');assert.equal(summary.children[1].textContent,'Active');assert.equal(card.open,undefined);
 assert.equal(details.children[0].textContent,'Email: staff@example.invalid');
 assert.ok(details.children.some(child=>child.textContent==='Send password recovery'));
 assert.ok(details.children.some(child=>child.textContent==='Deactivate access'));
 assert.equal(details.children[1].dataset.staffTenant,'gym-a');
});

const activityOwner='11111111-1111-4111-8111-111111111111',activityStaff='22222222-2222-4222-8222-222222222222';
async function namedActivity(){
 const p=reportFixture();await p.app.init();
 p.app.ivActors=[{user_id:activityOwner,name:'Yannie Hue',role:'owner'},{user_id:activityStaff,name:'Desk Person',role:'staff'}];
 p.app.ivActivity=[{created_at:'2026-11-01T02:00:00+08:00',actor_id:activityOwner,event:'Financial report access granted',details:'Target account: '+activityStaff}];
 p.app.ivSessions=[{created_at:'2026-11-01T03:00:00+08:00',actor_id:activityOwner,event:'login'},{created_at:'2026-11-01T04:00:00+08:00',actor_id:activityStaff,event:'logout'}];
 await p.app.ivRender('2026-11-01','2026-11-01');p.app.switchTab('audit');return p;
}
test('Activity resolves owner and staff names/roles in sessions and administrative target details',async()=>{
 const p=await namedActivity();const rows=p.element('audit-tbody').children.slice(-3).map(r=>r.children.map(c=>c.textContent));
 assert.deepEqual(rows.map(r=>r[1]),['Desk Person — Staff','Yannie Hue — Gym Admin','Yannie Hue — Gym Admin']);
 assert.equal(rows[0][2],'Staff logout');assert.equal(rows[1][2],'Gym Admin login');assert.equal(rows[2][3],'Target account: Desk Person — Staff');
 assert.ok(rows.flat().every(value=>!String(value).includes(activityOwner)&&!String(value).includes(activityStaff)));
 p.element('report-search').value='Yannie';p.element('report-search').listeners.input();assert.match(p.element('report-page').textContent,/of 2 matching rows/);
 p.element('report-search').value='Gym Admin';p.element('report-search').listeners.input();assert.match(p.element('report-page').textContent,/of 2 matching rows/);
});
test('Activity CSV and print use the same filtered names and roles, with permission checks',async()=>{
 const p=await namedActivity();let blob,printed=0;
 p.context.Blob=Blob;p.context.URL={createObjectURL:value=>{blob=value;return 'blob:synthetic'},revokeObjectURL(){}};p.context.print=()=>{printed++};
 p.element('report-search').value='Yannie';p.element('report-search').listeners.input();
 await p.app.exportReportCsv();const csv=await blob.text();assert.match(csv,/Name \/ role/);assert.match(csv,/Yannie Hue — Gym Admin/);assert.match(csv,/Target account: Desk Person — Staff/);assert.doesNotMatch(csv,new RegExp(activityOwner+'|'+activityStaff));
 await p.app.printReport();assert.equal(printed,1);
 p.permission.enabled=false;await p.app.printReport();assert.equal(printed,1);assert.equal(p.app.ivActors.length,0);
});
test('unavailable actors and system events remain honest and names are rendered as text',async()=>{
 const p=await namedActivity();p.app.ivActors=[{user_id:activityStaff,name:'<img src=x onerror=alert(1)>',role:'staff'}];
 p.app.ivActivity=[{created_at:'2026-11-01T03:00:00+08:00',actor_id:null,event:'System task',details:'No user'},
 {created_at:'2026-11-01T02:00:00+08:00',actor_id:activityOwner,event:'Old event',details:'Target account: '+activityOwner}];
 p.app.ivSessions=[{created_at:'2026-11-01T04:00:00+08:00',actor_id:activityStaff,event:'login'}];
 await p.app.ivRender('2026-11-01','2026-11-01');const rows=p.element('audit-tbody').children.slice(-3);
 assert.equal(rows[0].children[1].textContent,'<img src=x onerror=alert(1)> — Staff');assert.equal(rows[0].children[1].innerHTML,'');
 assert.equal(rows[1].children[1].textContent,'System');assert.equal(rows[2].children[1].textContent,'Account unavailable');assert.equal(rows[2].children[3].textContent,'Target account: Account unavailable');
});

test('non-account UUID details such as transaction references remain unchanged',async()=>{
 const p=await namedActivity(),reference='33333333-3333-4333-8333-333333333333';
 p.app.ivSessions=[];p.app.ivActivity=[{created_at:'2026-11-01T02:00:00+08:00',actor_id:activityOwner,event:'Payment reference',details:'Receipt: '+reference}];
 await p.app.ivRender('2026-11-01','2026-11-01');assert.equal(p.element('audit-tbody').children.at(-1).children[3].textContent,'Receipt: '+reference);
});

async function memberActivity(){
 const p=await namedActivity(),memberId='MEM-6f27ac52-443b-43c5-8f4a-22d91682f534';
 p.app.branchMembers=[{id:memberId,tenantId:'gym-a',name:'Anika Kelly',displayCode:'MEM-0013',status:'INACTIVE'}];
 p.app.ivSessions=[];p.app.ivActivity=[{created_at:'2026-11-01T02:00:00+08:00',actor_id:activityOwner,event:'Member profile updated',details:memberId}];
 await p.app.ivRender('2026-11-01','2026-11-01');return {...p,memberId};
}
test('Activity member references show name and short code without changing the stored log',async()=>{
 const p=await memberActivity();assert.equal(p.element('audit-tbody').children.at(-1).children[3].textContent,'Anika Kelly · MEM-0013');
 assert.equal(p.app.ivActivity[0].details,p.memberId);
 for(const query of ['Anika','MEM-0013']){p.element('report-search').value=query;p.element('report-search').listeners.input();assert.match(p.element('report-page').textContent,/of 1 matching rows/);}
 p.element('report-search').value='No such member';p.element('report-search').listeners.input();assert.equal(p.element('report-page').textContent,'No matching records');
});
test('Activity CSV and print use the member name and code in matching details',async()=>{
 const p=await memberActivity();let blob,prints=0;
 p.context.Blob=Blob;p.context.URL={createObjectURL:value=>{blob=value;return 'blob:member'},revokeObjectURL(){}};p.context.print=()=>{prints++};
 p.element('report-search').value='Anika';p.element('report-search').listeners.input();
 await p.app.exportReportCsv();const csv=await blob.text();assert.match(csv,/Anika Kelly · MEM-0013/);assert.ok(!csv.includes(p.memberId));
 await p.app.printReport();assert.equal(prints,1);assert.equal(p.element('audit-tbody').children.at(-1).children[3].textContent,'Anika Kelly · MEM-0013');
});
test('member details match complete references only and preserve unknown and other-tenant IDs',async()=>{
 const p=await memberActivity();const foreign='MEM-foreign',unknown='MEM-unknown';p.app.branchMembers.push({id:foreign,tenantId:'gym-b',name:'Private Name',displayCode:'MEM-9999'});
 p.app.ivActivity[0].details=p.memberId+', '+p.memberId.toUpperCase()+'; '+p.memberId+'-suffix; '+foreign+'; '+unknown;
 await p.app.ivRender('2026-11-01','2026-11-01');const details=p.element('audit-tbody').children.at(-1).children[3].textContent;
 assert.equal(details,'Anika Kelly · MEM-0013, Anika Kelly · MEM-0013; '+p.memberId+'-suffix; '+foreign+'; '+unknown);assert.ok(!details.includes('Private Name'));
});
test('member names are safe text and missing short codes never fall back to long internal IDs',async()=>{
 const p=await memberActivity();p.app.branchMembers[0].name='<img src=x onerror=alert(1)>';p.app.branchMembers[0].displayCode=p.memberId;
 await p.app.ivRender('2026-11-01','2026-11-01');const cell=p.element('audit-tbody').children.at(-1).children[3];assert.equal(cell.textContent,'<img src=x onerror=alert(1)>');assert.equal(cell.innerHTML,'');
});
test('member reference matching escapes regex punctuation in legacy IDs',async()=>{
 const p=await memberActivity();p.app.branchMembers[0].id='MEM-old.123';p.app.ivActivity[0].details='MEM-old.123 / MEM-oldX123';
 await p.app.ivRender('2026-11-01','2026-11-01');assert.equal(p.element('audit-tbody').children.at(-1).children[3].textContent,'Anika Kelly · MEM-0013 / MEM-oldX123');
});

async function walletHistoryReport(){
 const p=reportFixture();await p.app.init();
 p.app.branchMembers=[{id:'ian',displayCode:'MEM-0014',tenantId:'gym-a',name:'Ian Debo',walletBalance:50}];
 p.app.ivFinance=[{id:'topup-1',member_id:'ian',kind:'topup',amount:100,wallet_after:100,created_at:'2026-11-01T01:00:00+08:00'},
 {id:'purchase',member_id:'ian',kind:'plan_wallet',amount:100,wallet_after:0,created_at:'2026-11-01T02:00:00+08:00'},
 {id:'topup-2',member_id:'ian',kind:'topup',amount:50,wallet_after:50,created_at:'2026-11-01T03:00:00+08:00'}];
 await p.app.ivRender('2026-11-01','2026-11-01');p.app.switchTab('financial');return p;
}
test('Money retains 100, zero, 50 historical wallet values when the current wallet changes',async()=>{
 const p=await walletHistoryReport();const balances=()=>p.element('financial-tbody').children.slice(-3).map(row=>row.children[5].textContent);
 assert.deepEqual(balances(),['₱100.00','₱0.00','₱50.00']);
 p.app.branchMembers[0].walletBalance=999;await p.app.ivRender('2026-11-01','2026-11-01');assert.deepEqual(balances(),['₱100.00','₱0.00','₱50.00']);
 assert.equal(p.element('metric-credits').textContent,'₱999.00');assert.equal(p.element('metric-revenue').textContent,'₱100.00');
 p.element('report-search').value='wallet';p.element('report-search').listeners.input();assert.deepEqual(balances(),['₱100.00','₱0.00','₱50.00']);
});
test('Money marks unlinked, cash-part and invalid historical values unavailable rather than guessing',async()=>{
 const p=await walletHistoryReport();p.app.ivFinance=[
 {member_id:'ian',kind:'plan_cash',amount:50,created_at:'2026-11-01T02:00:00+08:00'},
 {member_id:'ian',kind:'refund_cash',amount:50,wallet_after:null,created_at:'2026-11-01T02:00:00+08:00'},
 {member_id:'ian',kind:'topup',amount:50,wallet_after:-5,created_at:'2026-11-01T02:00:00+08:00'}];
 await p.app.ivRender('2026-11-01','2026-11-01');assert.deepEqual(p.element('financial-tbody').children.slice(-3).map(row=>row.children[5].textContent),['Unavailable','Unavailable','Unavailable']);
});
test('Money CSV and Print share historical values and the new headings',async()=>{
 const p=await walletHistoryReport();let blob,printed=0;
 p.context.Blob=Blob;p.context.URL={createObjectURL:value=>{blob=value;return 'blob:wallet'},revokeObjectURL(){}};p.context.print=()=>{printed++};
 await p.app.exportReportCsv();const csv=await blob.text();assert.match(csv,/"Transaction amount","Wallet after"/);assert.doesNotMatch(csv,/Current wallet credit/);
 assert.match(csv,/"Pass paid from wallet","₱100.00","₱0.00"/);assert.match(csv,/"Wallet top-up","₱100.00","₱100.00"/);
 await p.app.printReport();assert.equal(printed,1);assert.deepEqual(p.element('financial-tbody').children.slice(-3).map(row=>row.children[5].textContent),['₱100.00','₱0.00','₱50.00']);
 p.permission.enabled=false;blob=null;await p.app.exportReportCsv();assert.equal(blob,null);
});
test('changing the report period filters entries without recalculating saved wallet history',async()=>{
 const p=await walletHistoryReport();p.app.ivFinance.push({id:'tomorrow',member_id:'ian',kind:'topup',amount:30,wallet_after:80,created_at:'2026-11-02T03:00:00+08:00'});
 await p.app.ivRender('2026-11-02','2026-11-02');const cells=p.element('financial-tbody').children.at(-1).children;assert.equal(cells[5].textContent,'₱80.00');assert.match(p.element('report-page').textContent,/of 1 matching rows/);
});

function captureExcel(p){
 let blob;const links=[];p.context.JSZip=require('jszip');p.context.Blob=Blob;
 p.context.URL={createObjectURL:value=>{blob=value;return 'blob:excel'},revokeObjectURL(){}};
 const create=p.context.document.createElement;p.context.document.createElement=tag=>{const node=create(tag);if(tag==='a')links.push(node);return node};
 return {links,blob:()=>blob,zip:async()=>require('jszip').loadAsync(Buffer.from(await blob.arrayBuffer()))};
}
test('Overview Excel exports all four sheets and all period records regardless of table search, page and activity filter',async()=>{
 const p=await walletHistoryReport(),captured=captureExcel(p);p.app.currentTenant.gymName='FITNESS GYM';
 p.app.ivFinance=Array.from({length:105},(_,i)=>({member_id:'ian',kind:'topup',amount:1,wallet_after:i+1,created_at:'2026-11-01T02:00:00+08:00',description:'Topup '+i}));
 p.app.ivAttendance=[{member_id:'ian',method:'qr',created_at:'2026-11-01T02:00:00+08:00'}];
 p.app.ivActivity=[{actor_id:null,event:'Pricing updated',details:'Rates',created_at:'2026-11-01T02:00:00+08:00'}];
 p.app.ivSessions=[{actor_id:null,event:'login',created_at:'2026-11-01T03:00:00+08:00'}];
 await p.app.ivRender('2026-11-01','2026-11-01');p.app.switchTab('financial');p.element('report-search').value='no matches';p.element('report-search').listeners.input();p.app.ivChoose('sessions');p.app.switchTab('overview');
 const calls=p.permission.snapshots.length;await p.app.exportAllReportsXlsx();assert.equal(p.permission.snapshots.length,calls,'no new report query');assert.equal(captured.links.length,1);
 assert.equal(captured.links[0].download,'FITNESS_GYM_REPORTS_2026-11-01_2026-11-01.xlsx');assert.equal(captured.blob().type,'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
 const zip=await captured.zip();const workbook=await zip.file('xl/workbook.xml').async('string');assert.equal((workbook.match(/<sheet /g)||[]).length,4);
 const overview=await zip.file('xl/worksheets/sheet1.xml').async('string');assert.match(overview,/Current snapshot/);assert.match(overview,/Money summary/);assert.match(overview,/Selected period/);
 const money=await zip.file('xl/worksheets/sheet2.xml').async('string');assert.equal((money.match(/<row /g)||[]).length,112);assert.match(money,/Topup 104/);assert.match(money,/Transaction amount \(PHP\)/);
 assert.match(await zip.file('xl/worksheets/sheet3.xml').async('string'),/QR scan/);
 const activity=await zip.file('xl/worksheets/sheet4.xml').async('string');assert.match(activity,/Pricing updated/);assert.match(activity,/Account login/);
 assert.equal(p.app.currentTab,'overview');assert.equal(p.app.ivMode,'sessions');assert.equal(p.element('report-export-excel').disabled,false);
});
test('all-report Excel preserves wallet-after history as numeric cells and missing history as unavailable',async()=>{
 const p=await walletHistoryReport(),captured=captureExcel(p);p.app.ivFinance.push({member_id:'ian',kind:'plan_cash',amount:20,created_at:'2026-11-01T03:00:00+08:00'});await p.app.ivRender('2026-11-01','2026-11-01');
 await p.app.exportAllReportsXlsx();const zip=await captured.zip(),money=await zip.file('xl/worksheets/sheet2.xml').async('string');
 assert.match(money,/<c r="F8" s="2"><v>100<\/v>/);assert.match(money,/<c r="F9" s="2"><v>0<\/v>/);assert.match(money,/<c r="F10" s="2"><v>50<\/v>/);assert.match(money,/<c r="F11"[^>]*t="inlineStr">.*?Unavailable/);
});
test('Excel blocks downloads when report access is revoked during generation and clears private report data',async()=>{
 const p=await walletHistoryReport(),captured=captureExcel(p);p.context.IronVaultReportsExcel={create:async()=>{p.permission.enabled=false;return new Uint8Array([1])}};
 await p.app.exportAllReportsXlsx();assert.equal(captured.links.length,0);assert.equal(p.app.ivActors.length,0);assert.equal(p.redirects.length,1);assert.equal(p.element('report-export-excel').disabled,true);
});
test('Excel discards a workbook if the report changes during generation without logging out the user',async()=>{
 const p=await walletHistoryReport(),captured=captureExcel(p);p.context.IronVaultReportsExcel={create:async()=>{await p.app.ivRender('2026-11-01','2026-11-01');return new Uint8Array([1])}};
 await p.app.exportAllReportsXlsx();assert.equal(captured.links.length,0);assert.match(p.alerts.at(-1),/report changed during export/);assert.equal(p.redirects.length,0);assert.equal(p.element('report-export-excel').disabled,false);
});
test('Excel library errors do not hide or clear a valid report',async()=>{
 const p=await walletHistoryReport(),captured=captureExcel(p);p.context.JSZip=null;await p.app.exportAllReportsXlsx();assert.equal(captured.links.length,0);assert.match(p.alerts.at(-1),/library could not load/);assert.equal(p.redirects.length,0);assert.equal(p.element('report-export-excel').disabled,false);
});

test('an empty report period exports four valid sheets with headers and zero summary values',async()=>{
 const p=reportFixture();await p.app.init();const captured=captureExcel(p);p.app.ivFinance=[];p.app.ivAttendance=[];p.app.ivActivity=[];p.app.ivSessions=[];p.app.branchMembers=[];
 await p.app.ivRender('2026-11-01','2026-11-01');await p.app.exportAllReportsXlsx();const zip=await captured.zip();
 for(const index of [2,3,4])assert.equal(((await zip.file('xl/worksheets/sheet'+index+'.xml').async('string')).match(/<row /g)||[]).length,7);
 assert.match(await zip.file('xl/worksheets/sheet1.xml').async('string'),/<v>0<\/v>/);
});
test('Excel never creates a download for staff without report permission',async()=>{
 const p=reportFixture('staff',false),captured=captureExcel(p);await p.app.init();await p.app.exportAllReportsXlsx();assert.equal(captured.links.length,0);
});
test('repeated Excel clicks cannot start duplicate downloads',async()=>{
 const p=await walletHistoryReport(),captured=captureExcel(p);let release,signal,count=0;const entered=new Promise(resolve=>{signal=resolve});
 p.context.IronVaultReportsExcel={create:async()=>{count++;signal();await new Promise(resolve=>{release=resolve});return new Uint8Array([1])},filename:()=> 'Gym_REPORTS.xlsx'};
 const first=p.app.exportAllReportsXlsx();await entered;await p.app.exportAllReportsXlsx();release();await first;assert.equal(count,1);assert.equal(captured.links.length,1);
});

test('friendly gym login requests only exact slug branding, including a trailing slash',async()=>{
 for(const pathname of ['/fitness-gym','/fitness-gym/']){
  const p=portal('gym/login.html',{owners:[{id:'gym-a',token:'token-a',gym_name:'Fitness Gym',portal_slug:'fitness-gym',status:'ACTIVE'}],search:'?key=foreign-token'});p.context.location.pathname=pathname;await p.get('app').init();
  assert.equal(p.get('app').currentTenantId,'gym-a');assert.equal(p.element('header-gym-name').innerText,'Fitness Gym');assert.deepEqual(p.calls[0].filters,[['portal_slug','fitness-gym']]);assert.equal(p.calls[0].fields,'id,gym_name,token,logo,status,pricing,portal_slug');assert.equal(p.calls.length,1);
 }
});
test('unknown friendly URL fails closed without a cached or first-gym fallback',async()=>{
 const p=portal('gym/login.html',{owners:[{id:'gym-a',portal_slug:'fitness-gym',token:'token-a',gym_name:'Fitness Gym'}],search:''});p.context.location.pathname='/unknown-gym';await p.get('app').init();assert.equal(p.get('app').currentTenantId,null);assert.equal(p.element('btn-submit-signin').disabled,true);assert.equal(p.element('btn-submit-admin').disabled,true);assert.equal(p.element('btn-submit-signup').disabled,true);assert.equal(p.calls.length,1);
});
test('sign-in from a readable URL navigates into gym pages and retains scoped authentication',async()=>{
 for(const role of ['member','owner']){
  const p=portal('gym/login.html',{user:{id:'user-a'},roles:[{user_id:'user-a',role,tenant_id:'gym-a',member_id:role==='member'?'member-a':null}],owners:[{id:'gym-a',token:'token-a',gym_name:'Fitness Gym',portal_slug:'fitness-gym',status:'ACTIVE'}],search:''});p.context.location.pathname='/fitness-gym/';const app=p.get('app');await app.init();let payload;
  p.client.functions={invoke:async(_,args)=>{payload=args.body;return {data:{session:{access_token:'test-token',refresh_token:'test-refresh'}}}}};p.client.auth.setSession=async()=>({error:null});
  p.element('signin-identifier').value='member@example.invalid';p.element('signin-password').value='test-password';p.element('admin-login-email').value='owner@example.invalid';p.element('admin-login-password').value='test-password';
  await (role==='member'?app.handleSignInSubmit({preventDefault(){}}):app.handleAdminLoginSubmit({preventDefault(){}}));
  assert.equal(payload.gym_token,'token-a');assert.equal(p.context.location.href,role==='member'?'/gym/profile.html':'/gym/admin.html?key=token-a');
 }
});
test('a different gym membership cannot sign in through a friendly URL',async()=>{
 const p=portal('gym/login.html',{user:{id:'member-user'},roles:[{user_id:'member-user',role:'member',tenant_id:'gym-b',member_id:'member-b'}],owners:[{id:'gym-a',token:'token-a',portal_slug:'fitness-gym',gym_name:'Fitness Gym',status:'ACTIVE'}],search:''});p.context.location.pathname='/fitness-gym';const app=p.get('app');await app.init();p.client.auth.setSession=async()=>({error:null});p.client.functions={invoke:async()=>({data:{session:{access_token:'test',refresh_token:'test-refresh'}}})};p.element('signin-identifier').value='member@example.invalid';p.element('signin-password').value='test-password';const original=p.context.location.href;await app.handleSignInSubmit({preventDefault(){}});assert.equal(p.storage.getItem('ironvault_active_member'),null);assert.equal(p.context.location.href,original);assert.match(p.element('form-alert-msg').innerText,/cannot access/i);
});
