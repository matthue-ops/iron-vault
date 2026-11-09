/* Revenue Today uses an aggregate-only RPC and its own server-enforced grant. */
(function(root){
 'use strict';
 function install(app,client){
  if(!root.matchMedia)return;
  const d=root.document,media=root.matchMedia('(max-width:639px)'),value=d.getElementById('stat-revenue'),label=value?.previousElementSibling;if(!value||!label)return;
  const R=root.IronVaultReports;let generation=0,busy=false,last=0,loadedDay='',identity='',timer=null,inFlightGeneration=null,queued=false,cached='—',attemptDay='',signedOut=false;
  function currentKey(){return [app.currentTenantId,app.authenticatedRole?.user_id,app.authenticatedRole?.role].join(':');}
  function reset(){generation++;last=0;loadedDay='';identity='';attemptDay='';cached='—';value.textContent='—';value.removeAttribute('title');value.removeAttribute('data-error');}
  async function refresh(force=false){
   if(signedOut||d.hidden||!app.currentTenantId||!app.authenticatedRole?.user_id||d.body.classList.contains('iv-auth-pending')||d.getElementById('revenue-metric-card').classList.contains('hidden'))return;
   const day=R.date(new Date()),key=currentKey();if(key!==identity){reset();identity=key;}
   label.textContent='Revenue Today';label.title='Membership sales today, Philippine time. Cash and wallet pass payments; wallet top-ups are not added again.';
   if(busy){if(inFlightGeneration!==generation)queued=true;return;}
   if(!force&&day===attemptDay&&Date.now()-last<60000)return;attemptDay=day;last=Date.now();
   if(loadedDay!==day)value.textContent='…';
   const stamp=generation,tenant=app.currentTenantId;busy=true;inFlightGeneration=stamp;
   try{
    const before=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});
    if(before.user_id!==app.authenticatedRole.user_id)throw Error('Account changed.');
    const {data,error}=await client.rpc('iv_revenue_today',{p_tenant:tenant});if(error)throw Error(error.message||'Revenue unavailable. Apply migration 046 before using this metric.');
    const after=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:tenant});
    if(stamp!==generation||currentKey()!==key||after.user_id!==before.user_id)return;
    if(data?.tenant_id!==tenant||data.day!==day||R.cents(data.amount)===null||R.cents(data.amount)<0n)throw Error('Revenue response unavailable.');
    const result={grossSales:R.cents(data.amount)};
    cached=R.money(result.grossSales);value.removeAttribute('data-error');value.textContent=cached;value.style.fontSize=cached.length>12?'11px':cached.length>9?'13px':'16px';value.title='Membership sales for '+day+' · Philippine time';loadedDay=day;last=Date.now();
   }catch(error){if(stamp===generation&&currentKey()===key){cached='Retry';value.textContent=cached;value.setAttribute('data-error','true');value.title=error.message;loadedDay='';last=Date.now();}}
   finally{busy=false;inFlightGeneration=null;if(queued){queued=false;if(!signedOut)void refresh(true);}}
  }
  const stats=app.updateStats;app.updateStats=function(){const result=stats.apply(this,arguments);label.textContent='Revenue Today';value.textContent=loadedDay===R.date(new Date())||value.getAttribute?.('data-error')?cached:'—';void refresh();return result;};
  const financial=app.refreshFinancialReportAccess;app.refreshFinancialReportAccess=async function(){const allowed=await financial.apply(this,arguments);if(app.authenticatedRole?.role==='owner'||app.staffPermissions?.revenue_today===true)void refresh();return allowed;};
  for(const name of ['confirmPlanSelection','addModalCredits']){const operation=app[name];if(typeof operation==='function')app[name]=async function(){try{return await operation.apply(this,arguments);}finally{last=0;void refresh(true);}};}
  function mode(){reset();label.textContent='Revenue Today';void refresh(true);}
  media.addEventListener('change',mode);d.addEventListener('visibilitychange',()=>{if(!d.hidden)void refresh();});
  client.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'){signedOut=true;reset();}else if(event==='SIGNED_IN'){signedOut=false;}});
  timer=root.setInterval(()=>{void refresh();},60000);root.addEventListener('pagehide',()=>{root.clearInterval(timer);timer=null;});root.addEventListener('pageshow',()=>{if(!timer)timer=root.setInterval(()=>{void refresh();},60000);void refresh();});
  const init=app.init;if(typeof init==='function')app.init=async function(){const result=await init.apply(this,arguments);await refresh(true);return result;};
  value.setAttribute?.('role','button');value.setAttribute?.('tabindex','0');value.setAttribute?.('aria-label','Revenue Today. Activate to refresh or view a loading error.');
  async function retry(){if(value.getAttribute?.('data-error'))root.alert?.('Revenue could not be loaded: '+value.title);await refresh(true);}
  value.addEventListener?.('click',retry);value.addEventListener?.('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();void retry();}});
  app.hideRevenueToday=reset;app.refreshRevenueToday=()=>refresh(true);mode();
 }
 root.IronVaultPhoneRevenue={install};
})(globalThis);
