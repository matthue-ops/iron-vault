/* Menu visibility follows scoped server grants. Every protected API checks authority again. */
(function(root){
 'use strict';
 const definitions=[['manual_checkin','Manual Check-In'],['reports_read','Reports & Analytics'],['reports_export','Export / print reports'],['announcements_manage','Manage announcements'],['pricing_manage','Membership Pricing'],['subscription_read','Subscription · view only']];
 const make=(tag,text,cls)=>{const n=root.document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
 async function exportAccess(app,client){
  const role=await app.ivRequireReport();if(role.role==='owner'||role.role==='super_admin')return;
  const {data,error}=await client.rpc('iv_staff_access',{p_tenant:app.currentTenant.id,p_action:'mine'});
  const after=await app.ivRequireReport();
  if(error||role.user_id!==after.user_id||data?.state!=='active'||data.permissions?.reports_export!==true){const denied=Error('The owner has not granted report export permission.');denied.code='EXPORT_ACCESS_DENIED';throw denied;}
 }
 function installReports(app,client){
  app.ivRequireExport=()=>exportAccess(app,client);
  const deny=app.ivDeny;app.ivDeny=function(error){if(error.code==='EXPORT_ACCESS_DENIED'){root.alert(error.message);return;}return deny.apply(this,arguments);};
 }
 function installAdmin(app,client){
  const d=root.document;if(!d.querySelector)return;const node=id=>d.getElementById(id);let epoch=0,serial=0,grants={},state=null,feed=[],feedSerial=0,feedLoaded=false,feedError='',poll=null,disconnected=false;
  const owner=()=>!disconnected&&app.authenticatedRole?.role==='owner';
  const actor=()=>disconnected?null:app.authenticatedRole?.user_id;
  async function rpc(name,args){
   const stamp=epoch,tenant=app.currentTenantId,user=actor();if(!tenant||!user)throw Error('Sign in required.');
   const before=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});
   if(before.user_id!==user)throw Error('Account changed.');
   const {data,error}=await client.rpc(name,args);if(error)throw Error(error.message||'Request failed.');
   const after=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});
   if(stamp!==epoch||tenant!==app.currentTenantId||user!==actor()||after.user_id!==user)throw Error('Account changed.');return data;
  }
  async function requirePermission(permission){const data=await rpc('iv_staff_access',{p_tenant:app.currentTenantId,p_action:'mine'});if(data?.state!=='active'||data.permissions?.[permission]!==true)throw Error('Permission required: '+definitions.find(([key])=>key===permission)?.[1]);return data;}
  function visible(id,show){const n=node(id);if(n){n.hidden=!show;n.classList.toggle('hidden',!show);}}
  function allowed(permission){return owner()||state==='active'&&grants[permission]===true;}
  function apply(){
   for(const [id,permission] of [['btn-reports-analytics','reports_read'],['btn-announcements','announcements_manage'],['btn-membership-pricing','pricing_manage'],['owner-subscription-menu','subscription_read']])visible(id,allowed(permission));
   visible('btn-staff-management',owner());visible('btn-gym-legal',owner());
   const manual=d.querySelector('button[onclick="adminApp.openManualCheckInModal()"]');if(manual)manual.disabled=!allowed('manual_checkin');
   app.staffPermissions=state==='active'?grants:{};app.staffAnnouncementAccess=!!actor();app.accountNoticeCount=feed.filter(n=>n.unread).length;
   const bell=node('owner-billing-bell'),count=node('owner-notification-count');if(bell){bell.hidden=!actor();const total=(owner()?(app.ownerNoticeCount||0):0)+app.accountNoticeCount;bell.dataset.unread=String(total>0);bell.setAttribute('aria-label','Notifications'+(total?', '+total+' unread':''));if(count){count.textContent=String(total);count.hidden=!total;}}
   if(!allowed('pricing_manage'))node('pricing-modal')?.classList.add('hidden');
   if(!allowed('announcements_manage')&&!node('announcements-panel')?.hidden)app.closeAnnouncements?.();
  }
  async function refresh(){if(!actor()||!app.currentTenantId||d.hidden)return;const ticket=++serial;try{const data=await rpc('iv_staff_access',{p_tenant:app.currentTenantId,p_action:'mine'});if(ticket!==serial)return;state=data?.state;grants=data?.permissions||{};}catch(error){if(ticket!==serial)return;state=null;grants={};}apply();}
  const account=make('button',undefined,'staff-menu-account');account.id='btn-my-account';account.type='button';const accountIcon=make('i');accountIcon.className='fa-solid fa-user-gear';accountIcon.setAttribute('aria-hidden','true');account.append(accountIcon,make('span','My Account'));node('btn-membership-pricing').after(account);
  const dialog=make('dialog',undefined,'staff-account-dialog');dialog.setAttribute('aria-labelledby','staff-account-title');const accountTitle=make('h2','My Account');accountTitle.id='staff-account-title';const accountMessage=make('p','Change your password using a private link sent to your account email. You can only reset your own password.');const reset=make('button','Change Password'),close=make('button','Close'),status=make('p');status.setAttribute('role','status');reset.type=close.type='button';dialog.append(accountTitle,accountMessage,reset,status,close);d.body.appendChild(dialog);
  account.onclick=()=>{node('admin-account-menu').open=false;status.textContent='';dialog.showModal();};close.onclick=()=>dialog.close();
  reset.onclick=async()=>{if(reset.disabled)return;reset.disabled=true;status.textContent='Sending reset instructions…';const stamp=epoch;try{const tenant=app.currentTenantId,user=actor();await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});const result=await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'own_recovery'});if(stamp===epoch&&tenant===app.currentTenantId&&user===actor())status.textContent=result.message;}catch(error){if(stamp===epoch)status.textContent=error.message;}finally{reset.disabled=false;}};
  app.openStaffSubscription=function(){if(owner())return null;return (async()=>{try{await requirePermission('subscription_read');const data=await rpc('iv_staff_subscription_view',{p_tenant:app.currentTenantId});const box=make('dialog',undefined,'staff-account-dialog'),done=make('button','Close');box.append(make('h2','Subscription'),make('p','View only. The registered owner manages agreements and payments.'),make('p',(data.state?.status||'Unavailable')+' · '+(data.state?.plan||'')));for(const p of data.periods||[])box.appendChild(make('p',p.kind+' · '+p.start_date+' – '+p.end_date+' · ₱'+Number(p.amount).toLocaleString()));done.type='button';done.onclick=()=>box.close();box.appendChild(done);box.addEventListener('close',()=>box.remove());d.body.appendChild(box);box.showModal();}catch(error){root.alert(error.message);}})();};
  for(const name of ['openManualCheckInModal','finalizeDeskCheckIn','admitMemberDirectly']){const original=app[name];if(typeof original==='function')app[name]=async function(){try{await requirePermission('manual_checkin');return await original.apply(this,arguments);}catch(error){this.notifyAdmin?this.notifyAdmin(error.message,false):root.alert(error.message);}};}
  for(const [name,permission] of [['openPricingModal','pricing_manage'],['openAnnouncements','announcements_manage']]){const original=app[name];app[name]=async function(){try{await requirePermission(permission);return await original.apply(this,arguments);}catch(error){root.alert(error.message);}};}
  app.handleSavePricing=async function(event){event.preventDefault();try{await requirePermission('pricing_manage');const pricing=Object.fromEntries([['day','input-price-day'],['week','input-price-week'],['month','input-price-month'],['studentDiscount','input-discount-student'],['seniorDiscount','input-discount-senior']].map(([key,id])=>[key,Number(node(id).value)]));await rpc('iv_staff_pricing',{p_tenant:app.currentTenantId,p_pricing:pricing});this.matchedOwnerRecord.pricing=pricing;this.loadBranchPricingIntoUI(this.matchedOwnerRecord);this.closePricingModal();this.notifyAdmin?.('Membership pricing saved.');}catch(error){root.alert(error.message);}};
  const roleVisibility=app.applyUIRoleVisibility;app.applyUIRoleVisibility=function(){const result=roleVisibility.apply(this,arguments);apply();return result;};
  const financial=app.refreshFinancialReportAccess;app.refreshFinancialReportAccess=async function(){const result=await financial.apply(this,arguments);apply();return result;};
  const staffBox=node('existing-staff-list');let staffSerial=0;
  async function renderStaff(){
   const ticket=++staffSerial;staffBox.textContent='Loading staff access…';try{const data=await rpc('iv_staff_access',{p_tenant:app.currentTenantId,p_action:'list'});if(ticket!==staffSerial)return;staffBox.textContent='';const reminder=make('p','Suspend access immediately when a staff member resigns or no longer needs access. Review outstanding responsibilities before removal.','staff-access-reminder');staffBox.appendChild(reminder);const former=make('details',undefined,'staff-access-former');former.appendChild(make('summary','Former Staff'));let removed=0;
    for(const staff of data.staff||[]){const row=make('details',undefined,'staff-access-row');row.appendChild(make('summary',staff.name+' · '+(staff.state==='active'?'Active':staff.state==='removed'?'Removed':'Suspended')));row.appendChild(make('p',staff.email||'No contact email'));if(staff.state==='removed'){removed++;former.appendChild(row);continue;}
     const choices=make('fieldset');choices.appendChild(make('legend','Administrative access · select individual permissions'));const inputs=new Map();for(const [key,label] of definitions){const wrap=make('label'),input=make('input');input.type='checkbox';input.checked=staff.permissions?.[key]===true;inputs.set(key,input);wrap.append(input,make('span',label));choices.appendChild(wrap);}row.appendChild(choices);
     function action(label,operation){const b=make('button',label);b.type='button';b.onclick=async()=>{if(b.disabled)return;if(operation!=='permissions'&&!root.confirm(label+' for '+staff.name+'? Gym history and other-gym access will be kept.'))return;b.disabled=true;const feedback=make('p','Processing…');feedback.setAttribute('role','status');row.appendChild(feedback);try{await rpc('iv_staff_access',{p_tenant:app.currentTenantId,p_action:operation,p_user:staff.user_id,p_data:operation==='permissions'?{permissions:Object.fromEntries([...inputs].map(([k,n])=>[k,n.checked]))}:{}});await renderStaff();const confirmed=make('p',label+' completed.');confirmed.setAttribute('role','status');staffBox.prepend(confirmed);}catch(error){feedback.textContent=error.message;b.disabled=false;}};row.appendChild(b);}
     action('Save permissions','permissions');action(staff.state==='active'?'Suspend Access':'Reactivate Access',staff.state==='active'?'suspend':'reactivate');action('Remove Staff','remove');
     const index=app.matchedOwnerRecord?.staff?.findIndex(s=>s.auth_user_id===staff.user_id);if(index>=0&&staff.state==='active'){for(const [label,fn] of [['Edit name / email',()=>app.saveStaffEdit(index)],['Send password recovery',()=>root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'recovery',portal:'admin',gym_token:app.matchedOwnerRecord.token,email:staff.email}).then(result=>root.alert(result.message)).catch(error=>root.alert(error.message))]]){const b=make('button',label);b.type='button';b.onclick=fn;row.appendChild(b);}}
     staffBox.appendChild(row);
    }
    former.firstElementChild.textContent='Former Staff ('+removed+')';staffBox.appendChild(former);if(!data.staff?.length)staffBox.appendChild(make('p','No staff accounts registered.'));
   }catch(error){if(ticket===staffSerial)staffBox.textContent='Staff controls unavailable: '+error.message+' Apply migration 041 before using these controls.';}
  }
  app.renderExistingStaffList=()=>{void renderStaff();};
  const openStaff=app.openStaffSignupModal;app.openStaffSignupModal=async function(){const result=await openStaff.apply(this,arguments);node('staff-report-permissions').textContent='';await renderStaff();return result;};
  async function refreshFeed(){if(!actor()||!app.currentTenantId||d.hidden)return;const ticket=++feedSerial;try{const data=await rpc('iv_account_announcements',{p_tenant:app.currentTenantId,p_mode:'list'});if(ticket!==feedSerial)return;if(!Array.isArray(data?.items)||data.items.some(n=>n.tenant_id!==app.currentTenantId))throw Error('Invalid announcement feed');feed=data.items;feedLoaded=true;feedError='';}catch(error){if(ticket!==feedSerial)return;feed=[];feedLoaded=false;feedError='Gym announcements are unavailable. Please retry.';}apply();}
  app.openAccountNotifications=async function(){await refreshFeed();const box=make('dialog',undefined,'staff-account-dialog'),done=make('button','Close');done.type='button';done.onclick=()=>box.close();box.append(make('h2','Notifications'),done);if(owner()){const billing=make('button','Subscription notices');billing.type='button';billing.onclick=()=>{box.close();app.openSubscriptionNotifications?.();};box.appendChild(billing);}if(!feedLoaded)box.appendChild(make('p',feedError));else if(!feed.length)box.appendChild(make('p','No active gym announcements.'));for(const notice of feed){const article=make('article');article.append(make('h3',notice.title),make('p',notice.body));box.appendChild(article);}box.addEventListener('close',()=>box.remove());d.body.appendChild(box);box.showModal();const read=feed.map(n=>({id:n.id,revision:n.revision}));if(read.length)try{await rpc('iv_account_announcements',{p_tenant:app.currentTenantId,p_mode:'read',p_read:read});await refreshFeed();}catch(error){box.appendChild(make('p','Read status could not be saved.'));}};
  const init=app.init;app.init=async function(){disconnected=false;const result=await init.apply(this,arguments);await refresh();await refreshFeed();return result;};
  d.addEventListener('visibilitychange',()=>{if(!d.hidden){void refresh();void refreshFeed();}});root.addEventListener('focus',()=>{void refresh();void refreshFeed();});poll=root.setInterval(()=>{void refresh();void refreshFeed();},60000);root.addEventListener('pagehide',()=>root.clearInterval(poll));
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||actor()&&session?.user?.id&&session.user.id!==actor()){disconnected=true;epoch++;serial++;feedSerial++;staffSerial++;staffBox.textContent='';node('staff-signup-modal')?.classList.add('hidden');state=null;grants={};feed=[];feedLoaded=false;dialog.close();for(const n of d.querySelectorAll('.staff-account-dialog[open]'))n.close();apply();}});
  apply();
 }
 root.IronVaultStaffAccess={installAdmin,installReports,definitions};
})(globalThis);
