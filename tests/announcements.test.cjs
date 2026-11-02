const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const A=require('../assets/announcements.js');
function fixture(role='owner'){
 const elements=new Map(),events={},auth=[],calls=[],alerts=[];let account={user_id:'owner-id',tenant_id:'gym-a',role},notices=[];
 function element(tag='div'){
  const children=[],classes=new Set();let text='';return {tag,children,value:'',checked:false,hidden:false,disabled:false,dataset:{},classList:{add:x=>classes.add(x),remove:x=>classes.delete(x),toggle(x,force){if(force===undefined? !classes.has(x):force)classes.add(x);else classes.delete(x)}},appendChild(child){children.push(child)},focus(){},get textContent(){return text},set textContent(value){text=value;children.length=0}};
 }
 const document={getElementById(id){if(!elements.has(id))elements.set(id,element());return elements.get(id)},createElement:element};
 const app={currentTenantId:'gym-a',authenticatedRole:{user_id:'owner-id'},applyUIRoleVisibility(){}};
 const client={auth:{onAuthStateChange:fn=>auth.push(fn)},rpc:async(name,args)=>{
  calls.push({name,args});
  if(name==='iv_list_announcements')return {data:{items:notices.filter(n=>args.p_state==='archived'?!!n.archived_at:!n.archived_at).slice(args.p_page*20,(args.p_page+1)*20),total:notices.filter(n=>args.p_state==='archived'?!!n.archived_at:!n.archived_at).length,can_manage:account.role==='owner',server_now:'2026-11-02T06:00:00Z'}};
  if(name==='iv_save_announcement'){
   let notice=notices.find(n=>n.id===args.p_id);if(notice&&notice.version!==args.p_expected_version)return {error:{message:'Announcement changed. Reload before saving',code:'P0001'}};
   const row={id:args.p_id,tenant_id:args.p_tenant,title:args.p_title,body:args.p_body,starts_at:args.p_starts_at,ends_at:args.p_ends_at,pinned:args.p_pinned,version:notice?notice.version+1:1,archived_at:null};notices=notices.filter(n=>n.id!==row.id).concat(row);return {data:row};
  }
  const row=notices.find(n=>n.id===args.p_id);row.archived_at='2026-11-02T06:00:00Z';row.version++;return {data:{...row}};
 }};
 const context={Date,Intl,crypto,console,document,confirm:()=>true,alert:text=>alerts.push(text),addEventListener:(name,fn)=>{events[name]=fn},IronVaultAuth:{requireRole:async(_,options)=>{
  if(account.disabled||!options.roles.includes(account.role)||options.tenantId!==account.tenant_id){const error=Error('Access denied');error.code='ACCESS_DENIED';throw error;}return {...account};
 }}};
 vm.createContext(context);vm.runInContext(fs.readFileSync('assets/announcements.js','utf8'),context);context.IronVaultAnnouncements.install(app,client);
 return {app,client,context,calls,alerts,auth,events,node:document.getElementById,account:value=>{account={...account,...value}},notices:value=>{notices=value},rows:()=>notices};
}
function draft(f){f.node('announcement-title').value='Holiday closure';f.node('announcement-body').value='Closed Monday. Open Tuesday.';f.node('announcement-start').value='2026-11-02T08:00';f.node('announcement-end').value='2026-11-03T08:00';}
function notice(overrides={}){return {id:'notice-id',tenant_id:'gym-a',title:'Holiday closure',body:'Closed Monday',starts_at:'2026-11-02T00:00:00Z',ends_at:'2026-11-03T00:00:00Z',pinned:false,version:1,archived_at:null,...overrides};}
test('announcement time inputs use Manila regardless of device timezone and reject invalid dates',()=>{
 assert.equal(A.instant('2026-11-02T08:30'),'2026-11-02T00:30:00.000Z');assert.equal(A.localTime('2026-11-02T00:30:00Z'),'2026-11-02T08:30');
 for(const date of ['2026-02-31T08:00','2026-11-02T24:01','2026-11-02','bad'])assert.throws(()=>A.instant(date),/valid start/);
 const row=notice();assert.equal(A.schedule(row,'2026-11-01T23:59:59Z'),'Scheduled');assert.equal(A.schedule(row,row.starts_at),'Active schedule');assert.equal(A.schedule(row,row.ends_at),'Expired');assert.equal(A.schedule({...row,archived_at:row.starts_at},row.starts_at),'Removed');
});
test('owner creates an announcement with tenant, stable ID, version and explicit Manila schedule',async()=>{
 const f=fixture();await f.app.openAnnouncements();assert.equal(f.node('announcement-new').hidden,false);await f.app.newAnnouncement();draft(f);await f.app.saveAnnouncement({preventDefault(){}});
 const call=f.calls.find(c=>c.name==='iv_save_announcement');assert.equal(call.args.p_tenant,'gym-a');assert.equal(call.args.p_expected_version,null);assert.match(call.args.p_id,/^[a-f0-9-]{36}$/);assert.equal(call.args.p_starts_at,'2026-11-02T00:00:00.000Z');assert.equal(f.rows().length,1);assert.match(f.node('announcements-message').textContent,/Announcement saved/);
});
test('staff see announcements but cannot create, edit, pin or remove even through direct method calls',async()=>{
 const f=fixture('staff');f.notices([notice()]);await f.app.openAnnouncements();assert.equal(f.node('announcement-new').hidden,true);assert.match(f.node('announcements-access').textContent,/Staff view/);
 await f.app.newAnnouncement();await f.app.editAnnouncement('notice-id');await f.app.pinAnnouncement('notice-id');await f.app.removeAnnouncement('notice-id');assert.equal(f.calls.filter(c=>c.name!=='iv_list_announcements').length,0);
});
test('revoked owners and wrong-tenant accounts cannot read announcement data',async()=>{
 for(const change of [{disabled:true},{tenant_id:'gym-b'},{role:'member'}]){const f=fixture();f.account(change);await f.app.openAnnouncements();assert.equal(f.calls.length,0);assert.equal(f.node('announcements-panel').hidden,true);}
});
test('title/message are rendered as text in list and preview',async()=>{
 const f=fixture(),unsafe='<img src=x onerror=alert(1)>';f.notices([notice({title:unsafe,body:'<script>bad</script>'})]);await f.app.openAnnouncements();const card=f.node('announcements-list').children[0];assert.equal(card.children[0].textContent,unsafe);assert.equal(card.children[2].textContent,'<script>bad</script>');
 await f.app.newAnnouncement();f.node('announcement-title').value=unsafe;f.app.previewAnnouncement();assert.equal(f.node('announcement-preview-title').textContent,unsafe);
});
test('owner edit, pin and removal use optimistic versions; removal retains the notice',async()=>{
 const f=fixture();f.notices([notice()]);await f.app.openAnnouncements();await f.app.pinAnnouncement('notice-id');let call=f.calls.find(c=>c.name==='iv_save_announcement');assert.equal(call.args.p_expected_version,1);assert.equal(call.args.p_pinned,true);
 await f.app.editAnnouncement('notice-id');f.node('announcement-title').value='New title';await f.app.saveAnnouncement({preventDefault(){}});assert.equal(f.rows()[0].title,'New title');
 await f.app.removeAnnouncement('notice-id');assert.equal(f.rows().length,1);assert.ok(f.rows()[0].archived_at);assert.ok(f.calls.some(c=>c.name==='iv_archive_announcement'));
});
test('invalid message lengths and end-before-start never reach a write RPC',async()=>{
 const f=fixture();await f.app.openAnnouncements();await f.app.newAnnouncement();draft(f);f.node('announcement-end').value='2026-11-01T08:00';await f.app.saveAnnouncement({preventDefault(){}});assert.match(f.node('announcements-message').textContent,/after start/);
 draft(f);f.node('announcement-body').value='x'.repeat(4001);await f.app.saveAnnouncement({preventDefault(){}});assert.equal(f.calls.filter(c=>c.name==='iv_save_announcement').length,0);
});
test('closing the panel discards a late response without exposing data',async()=>{
 const f=fixture();let release;f.client.rpc=(name,args)=>{f.calls.push({name,args});return new Promise(resolve=>{release=resolve})};const pending=f.app.openAnnouncements();while(!release)await new Promise(resolve=>setImmediate(resolve));f.app.closeAnnouncements();release({data:{items:[notice()],total:1,can_manage:true,server_now:'2026-11-02T06:00:00Z'}});await pending;assert.equal(f.node('announcements-panel').hidden,true);assert.equal(f.node('announcements-list').children.length,0);
});
test('account changes while loading and explicit sign-out clear announcement content',async()=>{
 const f=fixture();const rpc=f.client.rpc;f.client.rpc=async(...args)=>{const result=await rpc(...args);f.account({user_id:'replacement'});return result};await f.app.openAnnouncements();assert.equal(f.node('announcements-list').children.length,0);assert.equal(f.node('announcements-panel').hidden,true);
 const g=fixture();g.notices([notice()]);await g.app.openAnnouncements();await g.app.newAnnouncement();draft(g);g.auth[0]('SIGNED_OUT',null);assert.equal(g.node('announcement-title').value,'');assert.equal(g.node('announcements-list').children.length,0);assert.equal(g.node('announcements-panel').hidden,true);
});
test('missing migration gives setup guidance without changing any other admin feature',async()=>{
 const f=fixture();f.client.rpc=async()=>({error:{code:'PGRST202'}});await f.app.openAnnouncements();assert.match(f.node('announcements-message').textContent,/stage-one SQL/);assert.equal(f.node('announcement-new').hidden,true);
});
test('a response containing another tenant notice is rejected',async()=>{
 const f=fixture();f.notices([notice({tenant_id:'gym-b'})]);await f.app.openAnnouncements();assert.match(f.node('announcements-message').textContent,/invalid response/);assert.equal(f.node('announcements-list').children.length,0);
});

test('stale announcement versions show a reload message and never fall back to a table write',async()=>{
 const f=fixture();f.notices([notice()]);await f.app.openAnnouncements();await f.app.editAnnouncement('notice-id');f.node('announcement-title').value='Changed draft';f.notices([notice({version:2,title:'Other owner change'})]);
 await f.app.saveAnnouncement({preventDefault(){}});assert.match(f.node('announcements-message').textContent,/changed.*Reload/);assert.equal(f.rows()[0].title,'Other owner change');assert.equal(f.node('announcement-editor').hidden,false);
});
test('create retries reuse the same notice ID after an uncertain network outcome',async()=>{
 const f=fixture();await f.app.openAnnouncements();await f.app.newAnnouncement();draft(f);const original=f.client.rpc;let fail=true;
 f.client.rpc=async(name,args)=>{if(name==='iv_save_announcement'&&fail){f.calls.push({name,args});fail=false;return {error:{message:'Connection lost'}}}return original(name,args)};
 await f.app.saveAnnouncement({preventDefault(){}});await f.app.saveAnnouncement({preventDefault(){}});const writes=f.calls.filter(c=>c.name==='iv_save_announcement');assert.equal(writes.length,2);assert.equal(writes[0].args.p_id,writes[1].args.p_id);assert.equal(f.rows().length,1);
});
test('pagination requests the selected tenant/page and staff never receive removed controls',async()=>{
 const f=fixture('staff');f.notices(Array.from({length:21},(_,i)=>notice({id:'notice-'+i})));await f.app.openAnnouncements();assert.equal(f.node('announcements-next').disabled,false);await f.app.announcementsPage(1);
 assert.equal(f.calls.at(-1).args.p_page,1);assert.equal(f.calls.at(-1).args.p_tenant,'gym-a');assert.equal(f.node('announcements-list').children.length,1);assert.equal(f.node('announcements-archived-option').hidden,true);
});
