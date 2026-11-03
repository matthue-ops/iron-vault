/* Read-only adapters. Background refresh never calls legacy save/check-in/payment load paths. */
(function(root){
 'use strict';
 function member(m){return {id:m.id,displayCode:m.display_code||m.id,tenantId:m.tenant_id,tenantToken:m.tenant_token,name:m.name,email:m.email,phone:m.phone,
  classification:m.classification,discountPercentage:m.discount_percentage,plan:m.plan,cardBarcode:m.card_barcode,walletBalance:Number(m.wallet_balance||0),amount:m.amount==null?null:Number(m.amount),scansUsed:m.scans_used,lastScannedDate:m.last_scanned_date,expirationDate:m.expiration_date,status:m.status,dateJoined:m.date_joined,avatar:m.avatar};}
 function gym(g){return {id:g.id,displayCode:g.display_code||g.id,gymName:g.gym_name,ownerName:g.owner_name,email:g.email,token:g.token,portalSlug:g.portal_slug||null,logo:g.logo,accentColor:g.accent_color,status:g.status,pricing:g.pricing,staff:g.staff||[],auditLogs:g.audit_logs||[],dateCreated:g.date_created};}
 function displayMember(m,kind,today){const value={...m};if(/^\d{4}-\d{2}-\d{2}$/.test(value.expirationDate||'')&&value.expirationDate<today){value.plan='Not Selected';if(kind==='member')value.expirationDate=null;else if(kind==='admin')value.scansUsed=0;}return value;}
 function install(app,client,kind){
  const d=root.document;if(!d?.addEventListener||!root.IronVaultLiveUpdates)return;
  const node=id=>d.getElementById(id),shown=id=>{const n=node(id);return !!n&&!n.hidden&&!n.classList.contains('hidden');};
  const statusNode=d.createElement('p');statusNode.id='live-updates-status';statusNode.hidden=true;statusNode.className='text-xs text-slate-400 mb-3';statusNode.setAttribute('role','status');statusNode.setAttribute('aria-live','polite');(d.querySelector('main')||d.body).prepend(statusNode);
  const dirty=new Set();let lastRole=null,controller;
  d.addEventListener('input',e=>{if(e.target.id&&/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName))dirty.add(e.target.id);if(e.target.id==='edit-member-classification')dirty.add('edit-member-discount');});
  d.addEventListener('change',e=>{if(e.target.id&&/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName))dirty.add(e.target.id);if(e.target.id==='edit-member-classification')dirty.add('edit-member-discount');});
  function context(){
   if(kind==='master')return shown('super-dashboard')?{kind,tenant:null,member:null}:null;
   const r=app.authenticatedRole;if(!r?.user_id||d.body.classList.contains('iv-auth-pending'))return null;
   return kind==='member'?(app.currentMember?{kind,tenant:r.tenant_id,member:r.member_id,actor:r.user_id}:null):(app.currentTenantId?{kind,tenant:app.currentTenantId,member:null,actor:r.user_id}:null);
  }
  async function authorize(){
   const ctx=context();if(!ctx){const e=Error('Account or gym changed.');e.code='ACTOR_CHANGED';throw e;}
   const role=await root.IronVaultAuth.requireRole(client,{roles:kind==='master'?['super_admin']:kind==='member'?['member']:['owner','staff'],tenantId:ctx.tenant||undefined,memberId:ctx.member||undefined,allowGlobalSuperAdmin:kind==='master'});
   if(ctx.actor&&ctx.actor!==role.user_id){const e=Error('Account changed.');e.code='ACTOR_CHANGED';throw e;}lastRole=role;return role;
  }
  function detailKey(n){if(n.id)return '#'+n.id;const staff=n.querySelector('[data-staff-id]');if(staff)return 'staff:'+staff.dataset.staffId;const row=n.closest('tr'),body=n.closest('tbody');return body&&row?body.id+':'+row.firstElementChild?.textContent.trim()+':'+Array.from(row.querySelectorAll('details')).indexOf(n):null;}
  function preserve(render){
   const fields=[];const tracked=new Set(dirty);if(d.activeElement?.id&&/^(INPUT|TEXTAREA|SELECT)$/.test(d.activeElement.tagName))tracked.add(d.activeElement.id);for(const id of tracked){const n=node(id);if(n&&n.type!=='file')fields.push([n,n.value,n.checked,n.selectionStart,n.selectionEnd]);}
   const open=new Set(Array.from(d.querySelectorAll('details[open]')).map(detailKey).filter(Boolean));
   const scrolls=Array.from(d.querySelectorAll('[id]')).filter(n=>n.scrollTop||n.scrollLeft).map(n=>[n.id,n.scrollTop,n.scrollLeft]);
   const x=root.scrollX,y=root.scrollY;try{render();}finally{
   for(const [n,value,checked,start,end] of fields){if(!n.isConnected)continue;n.value=value;n.checked=checked;if(start!=null&&n===d.activeElement)try{n.setSelectionRange(start,end);}catch(_){}}
   for(const n of d.querySelectorAll('details'))if(open.has(detailKey(n)))n.open=true;
   for(const [id,top,left] of scrolls){const n=node(id);if(n){n.scrollTop=top;n.scrollLeft=left;}}
   if(root.scrollTo)root.scrollTo(x,y);}
  }
  async function rows(query){const {data,error}=await query;if(error)throw error;if(!Array.isArray(data))throw Error('Live refresh returned invalid records.');return data;}
  async function read(scope,hints){
   if(kind==='member'){
    const [ms,gs]=await Promise.all([rows(client.from('members').select('*').eq('id',scope.member).eq('tenant_id',scope.tenant)),rows(client.from('owners').select('id,gym_name,token,logo,status,pricing').eq('id',scope.tenant))]);
    if(ms.length!==1||gs.length!==1||ms[0].id!==scope.member||ms[0].tenant_id!==scope.tenant||gs[0].id!==scope.tenant||ms[0].status!=='ACTIVE'||gs[0].status!=='ACTIVE'){const e=Error('Membership access changed.');e.code='ACCESS_DENIED';throw e;}
    return {members:ms.map(member),gyms:gs.map(gym),full:true};
   }
   if(kind==='admin'&&hints?.some(h=>h.kind==='gym'))hints=null;
   if(!hints){
    if(kind==='master'){const loaded=await root.IronVaultData.loadMaster(client);return {members:loaded.members,gyms:loaded.owners,full:true};}
    const [ms,gs]=await Promise.all([rows(client.from('members').select('*').eq('tenant_id',scope.tenant)),rows(client.from('owners').select('*').eq('id',scope.tenant))]);
    if(gs.length!==1||gs[0].id!==scope.tenant||gs[0].status!=='ACTIVE'||ms.some(m=>m.tenant_id!==scope.tenant)){const e=Error('Gym access changed.');e.code='ACCESS_DENIED';throw e;}
    return {members:ms.map(member),gyms:gs.map(gym),full:true};
   }
   const members=[],gyms=[];await Promise.all(hints.map(async hint=>{
    const ms=hint.kind==='member';const found=await rows(client.from(ms?'members':'owners').select('*').eq('id',hint.entity_id).eq(ms?'tenant_id':'id',hint.tenant_id));
    if(found.some(r=>r.id!==hint.entity_id||(ms&&r.tenant_id!==hint.tenant_id)))throw Error('Live refresh returned a different gym or member.');
    if(kind==='admin'&&!ms&&(found.length!==1||found[0].status!=='ACTIVE')){const e=Error('Gym access changed.');e.code='ACCESS_DENIED';throw e;}
    (ms?members:gyms).push({id:hint.entity_id,tenantId:hint.tenant_id,row:found[0]?(ms?member(found[0]):gym(found[0])):null});
   }));return {members,gyms,full:false};
  }
  function merge(current,changes){const next=new Map((current||[]).map(r=>[r.id,r]));for(const change of changes){if(change.row)next.set(change.id,change.row);else next.delete(change.id);}return Array.from(next.values());}
  function branding(owner){
   if(kind==='member'){
    node('header-gym-name').innerText=owner.gymName;node('page-title').innerText=owner.gymName+' - Member Profile';
    if(owner.pricing)root._facilityPricing={...owner.pricing};
   }else if(kind==='admin'){
    root.IronVaultGymAccent?.apply(owner.accentColor);
    node('header-gym-title').innerText=owner.gymName;node('page-title').innerText=owner.gymName+' - Admin & Staff Portal';
    // Update read-only price labels; never reset an open pricing editor.
    const p=owner.pricing||{},money=v=>'₱'+Number(v||0).toLocaleString();
    for(const [id,value] of [['display-price-day',money(p.day)],['display-price-week',money(p.week)],['display-price-month',money(p.month)],['display-discount-student',Number(p.studentDiscount||0)+'%'],['display-discount-senior',Number(p.seniorDiscount||0)+'%']])if(node(id))node(id).innerText=value;
   }
   const img=node('header-logo-img'),icon=node('header-logo-icon');if(img){if(owner.logo){if(img.getAttribute('src')!==owner.logo)img.src=owner.logo;img.classList.remove('hidden');icon?.classList.add('hidden');}else{img.removeAttribute('src');img.classList.add('hidden');icon?.classList.remove('hidden');}}
  }
  function apply(data,hints){preserve(()=>{
   if(kind==='member'){
    const old=app.currentMember;app.currentMember=displayMember(data.members[0],'member',new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()));app.allMembersSystem=[app.currentMember];branding(data.gyms[0]);app.renderProfile();
    if(old&&(old.plan!==app.currentMember.plan||old.expirationDate!==app.currentMember.expirationDate)){node('qr-wrapper')?.classList.add('hidden');node('qr-wrapper')?.classList.remove('flex');}
   }else if(kind==='admin'){
    app.members=data.full?data.members:merge(app.members,data.members);const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());app.members=app.members.map(m=>displayMember(m,'admin',today));app.members.sort((a,b)=>(a.name||'').localeCompare(b.name||''));app.allMembersSystem=app.members;
    const owner=data.full?data.gyms[0]:data.gyms.find(g=>g.id===app.currentTenantId)?.row;
    if(owner){app.matchedOwnerRecord=owner;branding(owner);}else if(!data.full&&data.gyms.some(g=>g.id===app.currentTenantId&&!g.row)){const e=Error('Gym unavailable.');e.code='ACCESS_DENIED';throw e;}
    app.updateStats();app.renderPendingRequests();app.filterRoster();if(shown('manual-checkin-modal'))app.searchManualCheckIn();
    if(app.activeModalMemberId&&shown('member-profile-modal')){const m=app.members.find(m=>m.id===app.activeModalMemberId);if(!m)app.closeProfileModal();else{node('modal-member-name').innerText=m.name;node('modal-member-status-badge').innerText=m.status;node('modal-member-balance').innerText='₱'+Number(m.walletBalance||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});node('edit-member-plan').value=m.plan||'Not Selected';node('edit-member-expiry').value=m.expirationDate||'';for(const [id,value] of [['edit-member-name',m.name],['edit-member-email',m.email],['edit-member-phone',m.phone||''],['edit-member-classification',m.classification||'Regular'],['edit-member-discount',m.discountPercentage||0],['edit-member-barcode',m.cardBarcode||''],['edit-member-status',m.status]])if(node(id)&&!dirty.has(id)&&node(id)!==d.activeElement)node(id).value=value;const allowed=m.status==='ACTIVE';node('modal-cash-topup-section').querySelectorAll('button,input').forEach(n=>{n.disabled=!allowed;n.classList.toggle('opacity-40',!allowed);n.classList.toggle('cursor-not-allowed',!allowed);});node('modal-topup-approval-notice').classList.toggle('hidden',allowed);node('modal-pending-banner').classList.toggle('hidden',m.status!=='PENDING');}}
    if(data.full||data.gyms.length){app.refreshFinancialReportAccess();if(shown('staff-signup-modal')&&app.matchedOwnerRecord)app.renderExistingStaffList();}
   }else{
    app.owners=data.full?data.gyms:merge(app.owners,data.gyms);app.members=data.full?data.members:merge(app.members,data.members);
    if(!data.full)for(const g of data.gyms)if(!g.row)app.members=app.members.filter(m=>m.tenantId!==g.id);
    app.renderDashboard();if(app.currentInspectOwnerId&&shown('branch-inspect-modal')){const owner=app.owners.find(g=>g.id===app.currentInspectOwnerId);if(!owner){app.closeInspectModal();}else if(data.full||data.gyms.some(g=>g.id===owner.id)){app.openInspectModal(owner.id);}else app.refreshInspectMembers(owner);}
   }
  });}
  function clearPrivate(){
   app.members=[];app.allMembersSystem=[];if(kind==='member'){app.currentMember=null;d.body.classList.add('iv-auth-pending');}
   else if(kind==='admin'){d.body.classList.add('iv-auth-pending');app.activeModalMemberId=null;}
   else{app.owners=[];app.currentInspectOwnerId=null;for(const id of ['super-dashboard','branch-inspect-modal','edit-owner-modal','qr-code-modal'])node(id)?.classList.add('hidden');for(const id of ['owners-tbody','inspect-members-tbody','inspect-staff-list'])if(node(id))node(id).textContent='';}
   dirty.clear();for(const n of d.querySelectorAll('input[type="password"]'))n.value='';
  }
  const labels={connecting:'Connecting automatic updates…',live:'Live updates connected',fallback:'Automatic checks active; connecting live updates…',reconnecting:'Reconnecting — showing last confirmed values',unavailable:'Automatic updates unavailable — refresh manually'};
  controller=root.IronVaultLiveUpdates.create({client,context,authorize,read,apply,isVisible:()=>!d.hidden&&root.navigator?.onLine!==false,
   status:state=>{if(state==='stopped'){statusNode.hidden=true;return;}statusNode.hidden=false;const value=labels[state]||state;if(statusNode.textContent!==value)statusNode.textContent=value;},
   onDenied:()=>{clearPrivate();if(kind==='master')Promise.resolve(app.logout()).catch(()=>{});else{const token=app.matchedOwnerRecord?.token;root.IronVaultAuth.clearState(root.sessionStorage,root.localStorage);root.location.replace('login.html'+(token?'?key='+encodeURIComponent(token):''));}}
  });app.liveUpdates=controller;
  const init=app.init;app.init=async function(...args){controller.stop();const result=await init.apply(this,args);await controller.start();return result;};
  if(kind==='master'){const hub=app.showHubView;if(typeof hub==='function')app.showHubView=function(...args){controller.stop();return hub.apply(this,args);};const check=app.checkSession;app.checkSession=async function(...args){const ok=await check.apply(this,args);if(ok)await controller.start();else controller.stop();return ok;};}
  const writes=kind==='member'?['selectPlan','handleProfileUpdate','handleAvatarUpload','generateDailyQR']:kind==='admin'?['addModalCredits','confirmPlanSelection','finalizeDeskCheckIn','handleSaveMemberDetails','quickApproveMember','approvePendingMember','handleAdminAddMember','handleStaffSignup','saveStaffEdit','deleteStaff','handleSavePricing','deleteMember','processScannedCode']:['handleRegisterOwner','handleUpdateOwner','toggleOwnerStatus','handleInspectAddStaff','handleInspectDeleteStaff','handleInspectEditStaff','handleInspectRestore','handleRestoreBackup','confirmTenantPurge'];
  for(const name of writes){const original=app[name];if(typeof original!=='function')continue;app[name]=async function(...args){const release=controller.hold();try{return await original.apply(this,args);}finally{release();}};}
  function wake(){if(!context())return;if(controller.running)controller.check(true);else controller.start();}
  d.addEventListener('visibilitychange',()=>{if(d.hidden)controller.stop();else wake();});root.addEventListener('offline',()=>{controller.stop();statusNode.hidden=false;statusNode.textContent='Offline — showing last confirmed values';});root.addEventListener('online',wake);root.addEventListener('focus',wake);root.addEventListener('pagehide',()=>controller.stop());root.addEventListener('pageshow',wake);
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'){controller.stop();clearPrivate();}else if(lastRole&&session?.user?.id&&session.user.id!==lastRole.user_id){controller.stop();clearPrivate();}else if(event==='TOKEN_REFRESHED'){root.setTimeout(()=>{if(client.realtime?.setAuth)Promise.resolve(client.realtime.setAuth(session?.access_token)).catch(()=>{});wake();},0);}});
 }
 root.IronVaultDashboardLive=Object.freeze({install,member,gym,displayMember});if(typeof module==='object'&&module.exports)module.exports=root.IronVaultDashboardLive;
})(globalThis);
