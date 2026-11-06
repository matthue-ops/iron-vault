/* Tenant-scoped read only; phone sales card uses the same money rules as Reports. */
(function(root){
 'use strict';
 function install(app,client){
  if(!root.matchMedia)return;
  const d=root.document,media=root.matchMedia('(max-width:639px)'),value=d.getElementById('stat-revenue'),label=value?.previousElementSibling;if(!value||!label)return;
  const originalLabel=label.textContent,R=root.IronVaultReports;let generation=0,busy=false,last=0,loadedDay='',identity='',timer=null,cached='—',attemptDay='',signedOut=false;
  function currentKey(){return [app.currentTenantId,app.authenticatedRole?.user_id,app.authenticatedRole?.role].join(':');}
  function reset(){generation++;last=0;loadedDay='';identity='';attemptDay='';cached='—';value.textContent='—';value.removeAttribute('title');}
  async function refresh(force=false){
   if(signedOut||!media.matches||d.hidden||!app.currentTenantId||!app.authenticatedRole?.user_id||d.body.classList.contains('iv-auth-pending')||d.getElementById('revenue-metric-card').classList.contains('hidden'))return;
   const day=R.date(new Date()),key=currentKey();if(key!==identity){reset();identity=key;}
   label.textContent='Revenue Today';label.title='Membership sales today, Philippine time. Cash and wallet pass payments; wallet top-ups are not added again.';
   if(loadedDay!==day)value.textContent='…';
   if(busy||(!force&&day===attemptDay&&Date.now()-last<60000))return;attemptDay=day;last=Date.now();
   const stamp=generation,tenant=app.currentTenantId;busy=true;
   try{
    const before=await root.IronVaultAuth.requireFinancialReport(client,tenant);
    if(before.user_id!==app.authenticatedRole.user_id)throw Error('Account changed.');
    const {data,error}=await client.rpc('iv_report_snapshot',{p_tenant:tenant,p_start:day,p_end:day});if(error||!Array.isArray(data?.financial))throw Error(error?.message||'Today’s transactions are unavailable.');
    const after=await root.IronVaultAuth.requireFinancialReport(client,tenant);
    if(stamp!==generation||currentKey()!==key||after.user_id!==before.user_id||!media.matches)return;
    const rows=data.financial;if(rows.some(row=>row.tenant_id!==tenant))throw Error('Transaction scope mismatch.');
    const result=R.analyze({financial:rows,attendance:[],members:[],purchases:[]},day,day);if(result.invalid)throw Error('Some transaction amounts need review in Reports.');
    cached=R.money(result.grossSales);value.textContent=cached;value.title='Membership sales for '+day+' · Philippine time';loadedDay=day;last=Date.now();
   }catch(error){if(stamp===generation&&currentKey()===key&&media.matches){cached='—';value.textContent=cached;value.title=error.message;loadedDay='';last=Date.now();}}
   finally{busy=false;}
  }
  const stats=app.updateStats;app.updateStats=function(){const result=stats.apply(this,arguments);if(media.matches){label.textContent='Revenue Today';value.textContent=loadedDay===R.date(new Date())?cached:'—';void refresh();}return result;};
  const financial=app.refreshFinancialReportAccess;app.refreshFinancialReportAccess=async function(){const allowed=await financial.apply(this,arguments);if(media.matches){if(allowed)void refresh();else reset();}return allowed;};
  for(const name of ['confirmPlanSelection','addModalCredits']){const operation=app[name];if(typeof operation==='function')app[name]=async function(){try{return await operation.apply(this,arguments);}finally{last=0;void refresh(true);}};}
  function mode(){reset();if(media.matches){label.textContent='Revenue Today';void refresh(true);}else{label.textContent=originalLabel;app.updateStats();}}
  media.addEventListener('change',mode);d.addEventListener('visibilitychange',()=>{if(!d.hidden)void refresh();});
  client.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'){signedOut=true;reset();}else if(event==='SIGNED_IN'){signedOut=false;}});
  timer=root.setInterval(()=>{void refresh();},60000);root.addEventListener('pagehide',()=>{root.clearInterval(timer);timer=null;});root.addEventListener('pageshow',()=>{if(!timer)timer=root.setInterval(()=>{void refresh();},60000);void refresh();});
  mode();
 }
 root.IronVaultPhoneRevenue={install};
})(globalThis);
