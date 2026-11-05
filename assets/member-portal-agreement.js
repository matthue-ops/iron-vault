/* Read-only profile access is independent of explicit, versioned portal agreement. */
(function(root){
 'use strict';
 const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
 function install(app,client){
  const d=root.document,node=id=>d.getElementById(id);
  let status=null,error=null,epoch=0,pending=null,lastChecked=0,timer=null,deferred=null,unread=0,shownPair='',accepting=false;
  function context(){const r=app.authenticatedRole,m=app.currentMember;if(!r?.user_id||!m||r.member_id!==m.id||r.tenant_id!==m.tenantId||d.body.classList.contains('iv-auth-pending'))return null;return {user:r.user_id,member:m.id,tenant:m.tenantId};}
  const same=(a,b)=>!!a&&!!b&&a.user===b.user&&a.member===b.member&&a.tenant===b.tenant;
  const statusScope=s=>s?{user:s.user_id,member:s.member_id,tenant:s.tenant_id}:null;
  const approved=()=>app.currentMember?.status==='ACTIVE';
  const allowed=()=>approved()&&!error&&status?.accepted===true&&same(context(),statusScope(status));
  const ready=()=>same(context(),statusScope(status))&&uuid(status?.platform_version)&&uuid(status?.gym_version);
  function link(kind,p,g){return '/gym/'+kind+'.html?'+new URLSearchParams({key:app.currentMember?.tenantToken||'',platform:p,gym:g});}
  function message(){return app.currentMember?.status==='PENDING'?'Awaiting gym approval. You can view your profile and review Terms & Privacy; QR passes and purchases become available after approval and agreement.':error?'Terms verification is unavailable. You can view your profile; staff can assist with gym entry.':!status?'Checking your Terms & Privacy agreement…':!ready()?'Your gym must publish its Terms & Privacy details before member QR passes and pass purchases can be used.':allowed()?'You have agreed to the current Terms and Privacy Notice.':'Review and agree to unlock QR passes and membership purchases. Staff-assisted entry remains available.';}
  function render(){
   const locked=!allowed();
   if(node('member-approval-notice'))node('member-approval-notice').hidden=app.currentMember?.status!=='PENDING';
   for(const id of ['member-qr-legal-help','member-plan-legal-help'])if(node(id))node(id).textContent=app.currentMember?.status==='PENDING'?'Awaiting gym approval. Terms acceptance does not approve membership.':'Review Terms & Privacy from the bell or menu to unlock this feature.';
   for(const id of ['btn-generate-qr','plan-card-daypass','plan-card-week','plan-card-month']){const el=node(id);el?.setAttribute('aria-disabled',String(locked));el?.classList.toggle('member-legal-locked',locked);}
   for(const id of ['member-qr-legal-help','member-plan-legal-help'])if(node(id))node(id).hidden=!locked;
   if(locked){node('qr-wrapper')?.classList.add('hidden');node('qr-wrapper')?.classList.remove('flex');if(node('qrcode-container'))node('qrcode-container').textContent='';}
   if(node('member-legal-state'))node('member-legal-state').textContent=message();
   if(node('member-legal-notice'))node('member-legal-notice').hidden=!locked;
   if(node('member-legal-notice-text'))node('member-legal-notice-text').textContent=message();
   const receipt=same(context(),statusScope(status))?status?.acceptance:null;if(node('member-accepted-record'))node('member-accepted-record').hidden=!receipt;
   if(receipt){node('member-accepted-date').textContent='Agreed '+new Intl.DateTimeFormat('en-PH',{timeZone:'Asia/Manila',dateStyle:'medium',timeStyle:'short'}).format(new Date(receipt.accepted_at))+' · Manila time';node('member-accepted-terms').href=link('terms',receipt.platform_version,receipt.gym_version);node('member-accepted-privacy').href=link('privacy',receipt.platform_version,receipt.gym_version);}
   if(!receipt){node('member-accepted-date').textContent='';node('member-accepted-terms').href='';node('member-accepted-privacy').href='';}
   const pair=(status?.platform_version||'')+'|'+(status?.gym_version||'');if(pair!==shownPair){node('member-legal-checkbox').checked=false;shownPair=pair;}
   node('member-current-documents').hidden=allowed()||!ready();node('member-legal-checkbox').disabled=!!error||accepting;
   node('member-legal-agree').disabled=!!error||accepting||!ready();
   if(ready()){node('member-terms-link').href=link('terms',status.platform_version,status.gym_version);node('member-privacy-link').href=link('privacy',status.platform_version,status.gym_version);}
   app.renderLegalNotice();
  }
  app.renderLegalNotice=function(count){if(Number.isFinite(count))unread=count;const ctx=context();if(!ctx)return;const legal=allowed()?0:1,total=unread+legal,bell=node('member-notices-bell');bell.hidden=false;node('member-notices-count').textContent=total?String(total):'';bell.setAttribute('data-unread',String(total>0));bell.setAttribute('aria-label','Notifications'+(total?', '+total+' unread':'')+(legal?', review Terms and Privacy':''));if(node('member-legal-notice'))node('member-legal-notice').hidden=!legal;};
  app.hasLegalNotice=()=>!!context()&&!allowed();
  async function verify(scope){if(!same(scope,context()))throw Error('Account changed.');const {data,error}=await client.auth.getUser();if(error||data?.user?.id!==scope.user||!same(scope,context()))throw Error('Account changed.');}
  function validate(data,scope){
   if(!same(scope,statusScope(data))||typeof data.accepted!=='boolean'||(data.platform_version!=null&&!uuid(data.platform_version))||(data.gym_version!=null&&!uuid(data.gym_version)))throw Error('Invalid agreement status.');
   const a=data.acceptance;if(a&&(!uuid(a.platform_version)||!uuid(a.gym_version)||!Number.isFinite(Date.parse(a.accepted_at))))throw Error('Invalid acceptance record.');
   if(data.accepted&&(!a||a.platform_version!==data.platform_version||a.gym_version!==data.gym_version))throw Error('Invalid current acceptance.');return data;
  }
  async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error)throw Error(error.message||'Agreement request failed.');return data;}
  async function refresh(force=false){
   const scope=context();if(!scope)return false;if(pending)return pending;if(!force&&Date.now()-lastChecked<1000)return allowed();
   const stamp=epoch;let task;task=(async()=>{try{await verify(scope);const reply=await rpc('iv_member_legal_status');await verify(scope);if(stamp!==epoch||!same(scope,context()))return false;status=validate(reply,scope);error=null;lastChecked=Date.now();render();return allowed();}catch(e){if(stamp===epoch&&same(scope,context())){error=e.message;lastChecked=Date.now();render();}return false;}finally{if(pending===task)pending=null;}})();pending=task;return task;
  }
  app.refreshMemberLegal=refresh;
  app.openMemberTerms=async function(){app.closeMemberAnnouncements?.();node('member-account-menu').open=false;node('member-legal-checkbox').checked=false;render();if(!node('member-terms-dialog').open)node('member-terms-dialog').showModal();await refresh(true);};
  node('member-legal-retry').onclick=()=>refresh(true);
  node('member-legal-agree').onclick=async()=>{
   if(accepting||!context()||!ready())return;if(!node('member-legal-checkbox').checked){node('member-legal-state').textContent='Read both documents and tick the agreement before continuing.';return;}
   const scope=context(),stamp=epoch,p=status.platform_version,g=status.gym_version;accepting=true;render();
   try{await verify(scope);const reply=await rpc('iv_member_legal_accept',{p_platform:p,p_gym:g});await verify(scope);if(stamp!==epoch||!same(scope,context()))return;status=validate(reply,scope);error=null;lastChecked=Date.now();node('member-legal-checkbox').checked=false;}
   catch(e){if(stamp===epoch&&same(scope,context())){await refresh(true);if(stamp===epoch)node('member-legal-state').textContent=e.message;}}
   finally{if(stamp===epoch){accepting=false;render();}}
  };
  for(const name of ['selectPlan','generateDailyQR']){const original=app[name];app[name]=async function(){const scope=context();if(!scope||!await refresh(true)||!same(scope,context())){await this.openMemberTerms();return;}return original.apply(this,arguments);};}
  for(const id of ['plan-card-daypass','plan-card-week','plan-card-month']){const el=node(id);el?.setAttribute('role','button');if(el){el.tabIndex=0;el.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();el.click();}};}}
  const openNotices=app.openMemberAnnouncements;app.openMemberAnnouncements=async function(){await refresh(true);return openNotices.apply(this,arguments);};
  for(const name of ['handleProfileUpdate','handleAvatarUpload']){const original=app[name];if(typeof original==='function')app[name]=async function(...args){if(!approved()){this.showAlert('Awaiting gym approval; your profile is read-only.',false);return;}return original.apply(this,args);};}
  function clear(){epoch++;status=null;error=null;pending=null;lastChecked=0;shownPair='';accepting=false;unread=0;if(timer!=null)root.clearTimeout?.(timer);if(deferred!=null)root.clearTimeout?.(deferred);timer=null;deferred=null;node('member-legal-checkbox').checked=false;for(const id of ['member-settings-dialog','member-terms-dialog'])if(node(id)?.open)node(id).close();node('member-account-menu').open=false;render();}
  function tick(){if(!d.hidden&&root.navigator?.onLine!==false)void refresh(true);timer=root.setTimeout(tick,20000);}
  const init=app.init;app.init=async function(){clear();const result=await init.apply(this,arguments);if(context()){await refresh(true);timer=root.setTimeout(tick,20000);}return result;};
  const originalRender=app.renderProfile;app.renderProfile=function(){const result=originalRender.apply(this,arguments);render();if(context()&&deferred==null)deferred=root.setTimeout(()=>{deferred=null;void refresh(true);},1000);return result;};
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||(app.authenticatedRole?.user_id&&session?.user?.id&&session.user.id!==app.authenticatedRole.user_id))clear();});
  root.addEventListener?.('focus',()=>{if(!d.hidden)void refresh(true);});root.addEventListener?.('online',()=>void refresh(true));d.addEventListener?.('visibilitychange',()=>{if(!d.hidden)void refresh(true);});root.addEventListener?.('pagehide',clear);
  render();
 }
 root.IronVaultMemberPortalAgreement={install};
})(globalThis);
