(function(root){
 'use strict';
 function install(app,client){
  const node=id=>root.document.getElementById(id);
  const invoke=body=>root.IronVaultBranchAuth.invoke(client,'iv-purge-tenant',body);
  let current=null,busy=false,generation=0,expectedActor=null;
  function clear(){generation++;current=null;expectedActor=null;
   if(node('purge-password'))node('purge-password').value='';
   if(node('purge-summary'))node('purge-summary').textContent='';
   node('tenant-purge-panel')?.classList.add('hidden');
  }
  client.auth.onAuthStateChange((event,session)=>{
   if(event==='SIGNED_OUT'||(expectedActor&&session?.user?.id&&session.user.id!==expectedActor))clear();
  });
  app.openTenantPurge=async function(id,resume){
   try{
    const stamp=generation;const actor=await root.IronVaultAuth.requireRole(client,{roles:['super_admin']});expectedActor=actor.user_id;
    const review=resume?null:await invoke({action:'preview',tenant_id:id});
    const after=await root.IronVaultAuth.requireRole(client,{roles:['super_admin']});
    if(stamp!==generation||after.user_id!==actor.user_id)return;
    current={id,request:resume?.request_id||root.crypto.randomUUID(),review,resume:!!resume};
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
    // Refresh failure must not imply the destructive operation was rolled back.
    try{await app.loadData();app.renderDashboard();}catch(_){root.alert('Purge response received. Refresh the dashboard to see the current list.');}
    root.alert(result.complete?'Tenant and its dedicated accounts permanently purged.'+(result.retained_accounts?' Shared accounts preserved: '+result.retained_accounts+'.':''):result.message);
   }catch(error){if(stamp!==generation)return;node('purge-error').textContent=error.message+' If records disappeared, use Resume pending purges to check account cleanup.';}
   finally{node('purge-password').value='';busy=false;node('purge-submit').disabled=false;}
  };
  app.resumeTenantPurges=async function(){
   try{
    const jobs=await invoke({action:'list'});if(!jobs.length){root.alert('No pending tenant purges.');return;}
    const id=root.prompt('Enter the tenant ID to resume:\n'+jobs.map(j=>j.tenant_id+' ('+j.remaining+' accounts remaining)').join('\n'));
    if(id===null)return;const job=jobs.find(j=>j.tenant_id===id.trim());if(!job){root.alert('Choose a listed tenant ID.');return;}
    await app.openTenantPurge(job.tenant_id,job);
   }catch(error){root.alert(error.message);}
  };
 }
 root.IronVaultTenantPurge=Object.freeze({install});
})(globalThis);
