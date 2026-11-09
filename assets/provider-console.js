/* Provider-only UI. All access, audience and tag checks are enforced by scoped server RPCs. */
(function(root){
 'use strict';
 function install(app,client,ui){
  const {call,run,modal,element,button,openBilling,serviceEditor,settingsEditor}=ui,d=root.document;
  let state=null,filter='all',timer=null,identity=null;
  const controls=element('div',null,'provider-header-actions');controls.hidden=true;
  const bell=button('',()=>run(notifications));bell.id='provider-notification-bell';bell.title='Notifications';
  const icon=element('i');icon.className='fa-solid fa-bell';icon.setAttribute('aria-hidden','true');const badge=element('span','','owner-notification-count');badge.hidden=true;bell.append(icon,element('span','Notifications','owner-notification-label'),badge);
  const menu=element('details',null,'provider-menu'),summary=element('summary');summary.setAttribute('aria-label','Provider menu');const bars=element('i');bars.className='fa-solid fa-bars';bars.setAttribute('aria-hidden','true');summary.appendChild(bars);
  const cleanupAction=button('Remove test service PDFs',()=>run(cleanup));
  const choices=element('div',null,'provider-menu-panel');const platform=element('details',null,'provider-subscription-menu');platform.append(element('summary','Platform Details'),button('Provider Details',()=>app.openLegalSettings()),button('Service Agreement Settings',()=>run(serviceEditor)));choices.append(platform,button('Tenant announcements',()=>run(announcements)),button('Test-data cleanup',()=>run(()=>root.IronVaultProviderAgreements.cleanup(app,client,ui))),cleanupAction);
  if(root.IronVaultSubscriptionManagement){const subscription=element('details',null,'provider-subscription-menu'),heading=element('summary','Subscription');subscription.append(heading,button('Plan prices & settings',()=>run(settingsEditor)),button('Pending subscriptions',()=>root.IronVaultSubscriptionManagement.queue(client,openBilling)),button('Payment options',()=>root.IronVaultSubscriptionManagement.paymentMethods(client)),button('Subscription reports',()=>root.IronVaultSubscriptionManagement.reports(client)));choices.append(subscription);}
  for(const entry of choices.querySelectorAll('.provider-subscription-menu>button')){const bullet=element('span','•','provider-menu-bullet');bullet.setAttribute('aria-hidden','true');entry.prepend(bullet);}
  const logout=d.getElementById('btn-super-logout');if(logout)choices.appendChild(logout);
  menu.append(summary,choices);controls.append(bell,menu);d.querySelector('body>header>div')?.appendChild(controls);
  d.addEventListener('click',event=>{if(!menu.contains(event.target)||event.target.closest('.provider-menu-panel button'))menu.open=false;});d.addEventListener('keydown',event=>{if(event.key==='Escape')menu.open=false;});
  async function consoleCall(action='get',data={}){return call('iv_provider_console',{p_action:action,p_data:data});}
  function showCount(count){badge.hidden=!count;badge.textContent=String(count);bell.dataset.unread=String(count>0);bell.setAttribute('aria-label','Notifications'+(count?', '+count+' unread':''));}
  function update(data){state=data;cleanupAction.hidden=!data.pdf_cleanup_pending;app.providerTenants=Object.fromEntries(data.tenants.map(t=>[t.tenant_id,t]));const count=data.notices.filter(n=>!n.read_at&&!n.resolved_at).length;showCount(count);controls.hidden=false;}
  const originalLoad=app.loadData;
  app.loadData=async function(...args){try{const result=await originalLoad.apply(this,args);const auth=await client.auth.getUser();identity=auth.data?.user?.id;update(await consoleCall());if(!timer)timer=root.setTimeout(tick,60000);return result;}catch(error){state=null;app.providerTenants={};controls.hidden=true;if(timer)root.clearTimeout(timer);timer=null;throw error;}};
  const originalRender=app.renderDashboard;
  app.renderDashboard=function(...args){const result=originalRender.apply(this,args);if(state){d.getElementById('stat-gyms').textContent=state.live_totals.gyms;d.getElementById('stat-members').textContent=state.live_totals.members;}return result;};
  const filterRow=element('div',null,'tenant-filter-toolbar'),filterGroup=element('div',null,'tenant-filter-group'),filterButtons=new Map(),filterCounts=new Map();
  filterGroup.setAttribute('role','group');filterGroup.setAttribute('aria-label','Filter gyms');
  function updateFilters(owners){
   const counts={all:owners.length,live:owners.filter(o=>!app.providerTenants?.[o.id]?.is_test).length,test:owners.filter(o=>app.providerTenants?.[o.id]?.is_test).length};
   for(const [key,control] of filterButtons){control.setAttribute('aria-pressed',String(filter===key));filterCounts.get(key).textContent=String(counts[key]);}
   return counts;
  }
  for(const [key,label] of [['all','All'],['live','Live'],['test','Test']]){
   const control=button('',()=>{filter=key;app.renderOwnersTable();}),count=element('span','0','tenant-filter-count');
   control.dataset.tenantFilter=key;control.setAttribute('aria-controls','owners-tbody');control.setAttribute('aria-pressed',String(key==='all'));control.append(element('span',label),count);
   control.addEventListener('keydown',event=>{const keys=['all','live','test'];if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;event.preventDefault();const index=event.key==='Home'?0:event.key==='End'?2:(keys.indexOf(key)+(event.key==='ArrowRight'?1:2))%3;filterButtons.get(keys[index]).click();filterButtons.get(keys[index]).focus();});
   filterButtons.set(key,control);filterCounts.set(key,count);filterGroup.appendChild(control);
  }
  const originalRows=app.renderOwnersTable;
  app.renderOwnersTable=function(...args){
   const all=this.owners,counts=updateFilters(all);if(state)this.owners=all.filter(o=>filter==='all'||(filter==='test')===!!this.providerTenants[o.id]?.is_test);
   try{const result=originalRows.apply(this,args);if(!this.owners.length){const cell=d.getElementById('owners-tbody')?.querySelector('td');if(cell)cell.textContent=filter==='live'?(counts.test?'No Live gyms yet. Select Test to view your test gyms.':'No Live gyms yet.'):filter==='test'?'No Test gyms yet. Select All to view registered gyms.':'No gyms registered yet.';}return result;}finally{this.owners=all;}
  };
  filterRow.append(filterGroup,element('p','Live totals exclude Test gyms.','tenant-filter-help'));d.getElementById('dash-content-tenants')?.prepend(filterRow);
  async function notifications(){update(await consoleCall());const target=modal('Provider notifications'),content=element('section');target.append(content);const rows=state.notices.map(n=>({...n,title:n.title+(state.tenants.find(t=>t.tenant_id===n.tenant_id)?' — '+state.tenants.find(t=>t.tenant_id===n.tenant_id).name:''),id:n.notice_key,body:n.message,unread:!n.read_at&&!n.resolved_at,noticeSource:'provider',detailLabel:n.tenant_id?'Review gym':false}));root.IronVaultNoticeViews.render(content,rows,{onRead:async n=>{update(await consoleCall('read',{key:n.notice_key}));},onOpen:async n=>{if(n.tenant_id)await openBilling(n.tenant_id);}});}
  async function announcements(){
   update(await consoleCall());const target=modal('Tenant announcements');target.appendChild(element('p','Sent only to registered owner accounts. Use Service Agreement Settings for formal price or agreement notices.','iv-sub-muted'));
   const title=element('input'),message=element('textarea'),audience=element('select'),when=element('input');title.maxLength=160;message.maxLength=5000;when.type='datetime-local';
   for(const [value,label] of [['live','All Live gyms'],['selected','Selected gyms']]){const option=element('option',label);option.value=value;audience.appendChild(option);}
   for(const [label,input] of [['Title',title],['Message',message],['Audience',audience],['Schedule (Philippine time; blank = now)',when]]){input.setAttribute('aria-label',label);const wrap=element('label',null,'iv-sub-field');wrap.append(element('span',label),input);target.appendChild(wrap);}
   const recipients=element('div');recipients.hidden=true;const checked=new Map();for(const gym of state.tenants){const label=element('label',null,'iv-sub-check'),box=element('input');box.type='checkbox';checked.set(gym.tenant_id,box);label.append(box,element('span',gym.name+(gym.is_test?' · TEST':'')));recipients.appendChild(label);}audience.onchange=()=>{recipients.hidden=audience.value!=='selected';};target.appendChild(recipients);
   target.appendChild(button('Publish announcement',()=>run(async()=>{const payload={title:title.value.trim(),message:message.value.trim(),audience:audience.value,tenants:audience.value==='selected'?[...checked].filter(([,box])=>box.checked).map(([id])=>id).sort():[],available_at:when.value?new Date(when.value+':00+08:00').toISOString():null};if(!payload.title||!payload.message)throw Error('Enter a title and message.');if(!root.confirm('Publish this announcement to the selected registered owners?'))return;const key='iv_announcement:'+JSON.stringify(payload);let id=root.sessionStorage.getItem(key);if(!id){id=root.crypto.randomUUID();root.sessionStorage.setItem(key,id);}update(await consoleCall('announce',{...payload,request_id:id}));root.sessionStorage.removeItem(key);await announcements();}),'primary'));
   target.appendChild(element('h3','Delivery and read history','iv-sub-heading'));for(const a of state.announcements){const card=element('article',null,'iv-sub-notice');card.append(element('h3',a.title),element('p',a.message));for(const delivery of a.delivery){const gym=state.tenants.find(t=>t.tenant_id===delivery.tenant_id);card.appendChild(element('p',(gym?.name||delivery.tenant_id)+' — '+(delivery.read_at?'Read':new Date(a.available_at)>new Date()?'Scheduled':'Unread')));}target.appendChild(card);}
  }
  async function cleanup(){const target=modal('Remove test service PDFs');target.appendChild(element('p','One-time test cleanup only. This permanently deletes uploaded service PDFs. Apply SQL 038 first; all existing gyms must still be Test. After files are removed, run SQL 039 to remove PDF versions and test acceptances while preserving subscription amounts and dates. No backup is created.'));const input=element('input'),label=element('label',null,'iv-sub-field');label.append(element('span','Type DELETE TEST SERVICE PDFS'),input);target.append(label,button('Delete test service PDFs',()=>run(async()=>{if(input.value!=='DELETE TEST SERVICE PDFS')throw Error('Type the exact confirmation.');const {data,error}=await client.functions.invoke('iv-cleanup-test-pdfs',{body:{confirmation:input.value}});if(error||data?.error)throw Error(data?.error||'Cleanup failed; check the deployed cleanup function.');target.appendChild(element('p',data.message||'Batch removed. Run cleanup again if more files remain.','iv-sub-summary'));}), 'primary'));}
  app.refreshProviderConsole=async()=>update(await consoleCall());
  app.setTenantTag=id=>run(async()=>{const gym=app.providerTenants[id];if(!gym)throw Error('Reload tenant details first.');if(!root.confirm('Change '+gym.name+' to '+(gym.is_test?'Live':'Test')+'? This does not change permissions or delete records.'))return;update(await consoleCall('tag',{tenant_id:id,is_test:!gym.is_test}));app.renderDashboard();});
  // Poll only after authorized load and only while the Provider dashboard is visible.
  async function tick(){if(state&&!d.hidden&&!d.getElementById('super-dashboard')?.classList.contains('hidden')){try{const data=await consoleCall('badge');showCount(data.unread);}catch(_){/* Next authorized reload surfaces errors. */}}timer=state?root.setTimeout(tick,60000):null;}
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||(identity&&session?.user?.id&&session.user.id!==identity)){identity=null;state=null;app.providerTenants={};controls.hidden=true;if(timer)root.clearTimeout(timer);timer=null;}});
 }
 root.IronVaultProviderConsole={install};
})(globalThis);
