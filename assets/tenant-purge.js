(function(root){
 'use strict';
 function install(app,client){
  const node=id=>root.document.getElementById(id);
  const invoke=body=>root.IronVaultBranchAuth.invoke(client,'iv-purge-tenant',body);
  let current=null,busy=false,generation=0,expectedActor=null;
  let pendingJobs=[],pendingActor=null,pendingSerial=0,pendingError='',sheet=null,lastPendingCheck=0;const knownNames=new Map();
  function clear(){generation++;current=null;expectedActor=null;
   if(node('purge-password'))node('purge-password').value='';
   if(node('purge-summary'))node('purge-summary').textContent='';
   node('tenant-purge-panel')?.classList.add('hidden');
  }
  client.auth.onAuthStateChange((event,session)=>{
   if(event==='SIGNED_OUT'||((expectedActor||pendingActor)&&session?.user?.id&&session.user.id!==(expectedActor||pendingActor))){clear();clearPending();}
  });
  app.openTenantPurge=async function(id,resume){
   try{
    const stamp=generation;const actor=await root.IronVaultAuth.requireRole(client,{roles:['super_admin']});expectedActor=actor.user_id;
    const review=resume?null:await invoke({action:'preview',tenant_id:id});
    const after=await root.IronVaultAuth.requireRole(client,{roles:['super_admin']});
    if(stamp!==generation||after.user_id!==actor.user_id)return;
    current={id,request:resume?.request_id||root.crypto.randomUUID(),review,resume:!!resume};
    if(review?.gym_name)knownNames.set(id,review.gym_name);
    node('purge-summary').textContent=resume?'Tenant '+id+' — application records already removed. Remaining Auth accounts: '+resume.remaining:
     review.gym_name+' ('+id+') · '+((review.is_test??app.providerTenants?.[id]?.is_test)?'TEST':'LIVE')+'\nMembers: '+review.members+'; accounts: '+review.accounts+
     '\nTransactions: '+review.transactions+'; attendance: '+review.attendance+'; activity: '+review.activity+'; sessions: '+review.sessions+
     '\nSubscription periods: '+(review.subscription_periods??'review required')+'; requests: '+(review.subscription_requests??'review required')+'; service acceptances: '+(review.service_acceptances??'review required')+'; notices: '+(review.notifications??'review required')+
     '\nOutstanding wallet credit: ₱'+review.wallet_credit+' across '+review.wallet_accounts+' accounts.';
    node('purge-confirm-label').textContent='Type PURGE '+id;
    node('purge-confirmation').value='';node('purge-password').value='';node('purge-error').textContent='';
    node('tenant-purge-panel').classList.remove('hidden');
   }catch(error){root.alert(error.message);}
  };
  app.closeTenantPurge=function(){if(busy)return;clear();};
  app.confirmTenantPurge=async function(event){
   event.preventDefault();if(busy||!current)return;
   if(node('purge-confirmation').value!=='PURGE '+current.id){node('purge-error').textContent='Type the exact confirmation shown above.';return;}
   const password=node('purge-password').value;if(!password){node('purge-error').textContent='Enter your Master password.';return;}
   const stamp=generation;busy=true;node('purge-submit').disabled=true;node('purge-error').textContent='';
   try{
    const result=await invoke({action:current.resume?'resume':'purge',tenant_id:current.id,request_id:current.request,
     confirmation:'PURGE '+current.id,review:current.review,password});
    if(stamp!==generation)return;busy=false;app.closeTenantPurge();
    await app.refreshPendingPurges();
    // Refresh failure must not imply the destructive operation was rolled back.
    try{await app.loadData();app.renderDashboard();}catch(_){root.alert('Purge response received. Refresh the dashboard to see the current list.');}
    root.alert(result.complete?'Tenant and its dedicated accounts permanently purged.'+(result.retained_accounts?' Shared accounts preserved: '+result.retained_accounts+'.':''):result.message);
   }catch(error){if(stamp!==generation)return;node('purge-error').textContent=error.message+' If records disappeared, open Pending cleanup to check account cleanup.';await app.refreshPendingPurges();}
   finally{node('purge-password').value='';busy=false;node('purge-submit').disabled=false;}
  };
  function clearPending(){lastPendingCheck=0;pendingSerial++;pendingJobs=[];pendingActor=null;pendingError='';knownNames.clear();sheet?.close();updateBadge();}
  function updateBadge(){
   const badge=node('pending-purge-badge');if(!badge)return;
   badge.hidden=!pendingJobs.length&&!pendingError;
   node('pending-purge-label').textContent=pendingError?'Check cleanup status':'Pending cleanup';
   node('pending-purge-count').textContent=String(pendingJobs.length);node('pending-purge-count').hidden=!!pendingError;
   badge.setAttribute('aria-label',pendingError?'Cleanup status unavailable. Retry.':'Pending account cleanup, '+pendingJobs.length+' '+(pendingJobs.length===1?'gym':'gyms'));
  }
  app.refreshPendingPurges=async function(){
   const serial=++pendingSerial,stamp=generation;
   try{
    const before=await root.IronVaultAuth.requireRole(client,{roles:['super_admin']});pendingActor=before.user_id;
    const jobs=await invoke({action:'list'});if(!Array.isArray(jobs))throw Error('Cleanup list is unavailable.');
    const after=await root.IronVaultAuth.requireRole(client,{roles:['super_admin']});
    if(serial!==pendingSerial||stamp!==generation||before.user_id!==after.user_id)return false;
    pendingJobs=jobs;pendingError='';lastPendingCheck=Date.now();updateBadge();return true;
   }catch(error){if(serial===pendingSerial&&stamp===generation){pendingError='Could not load account cleanup. Retry to check its status.';lastPendingCheck=Date.now();updateBadge();}return false;}
  };
  const originalLoad=app.loadData;
  if(typeof originalLoad==='function')app.loadData=async function(...args){try{const result=await originalLoad.apply(this,args);if(Date.now()-lastPendingCheck>=30000)await app.refreshPendingPurges();return result;}catch(error){clear();clearPending();throw error;}};
  function make(tag,text,cls){const element=root.document.createElement(tag);if(text!==undefined)element.textContent=text;if(cls)element.className=cls;return element;}
  app.resumeTenantPurges=async function(){
   sheet?.close();const dialog=make('dialog',undefined,'tenant-cleanup-dialog');sheet=dialog;dialog.setAttribute('aria-labelledby','tenant-cleanup-title');
   const head=make('header'),title=make('h2','Pending account cleanup'),close=make('button','Close');title.id='tenant-cleanup-title';close.type='button';close.onclick=()=>dialog.close();head.append(title,close);
   const body=make('div');body.setAttribute('aria-live','polite');dialog.append(head,make('p','Gym records have already been removed. Resume finishes dedicated login-account cleanup; it does not delete gym records again.'),body);
   dialog.addEventListener('close',()=>{dialog.remove();if(sheet===dialog)sheet=null;});root.document.body.appendChild(dialog);dialog.showModal();
   async function render(){
    body.textContent='Checking pending cleanup…';await app.refreshPendingPurges();if(sheet!==dialog||!dialog.open)return;
    body.textContent='';if(pendingError){body.appendChild(make('p',pendingError));const retry=make('button','Retry');retry.type='button';retry.onclick=render;body.appendChild(retry);return;}
    if(!pendingJobs.length){body.appendChild(make('p','No pending account cleanup.'));return;}
    for(const job of pendingJobs){const row=make('article',undefined,'tenant-cleanup-job'),details=make('div'),name=job.gym_name||knownNames.get(job.tenant_id)||app.owners?.find(g=>g.id===job.tenant_id)?.gymName||'Gym '+job.tenant_id;
     details.append(make('strong',name),make('p','Tenant: '+job.tenant_id),make('p',Number(job.remaining)>0?'Login accounts remaining: '+job.remaining:'Account deletion finished; final confirmation pending.'));
     const resume=make('button','Resume cleanup');resume.type='button';resume.onclick=()=>{dialog.close();app.openTenantPurge(job.tenant_id,job);};row.append(details,resume);body.appendChild(row);
    }
   }
   await render();
  };

 }
 root.IronVaultTenantPurge=Object.freeze({install});
})(globalThis);
