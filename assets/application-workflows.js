/* Working controllers on top of scoped RPCs. No raw record/credential writes. */
(function(root){
 'use strict';
 function install(app,client,kind){
  const value=id=>root.document.getElementById(id).value;
  async function provision(name,body){return root.IronVaultBranchAuth.provision(client,root.sessionStorage,name,body);}
  const staffRevisions=new WeakMap();
  async function recoverStaff(owner,index){
   const staff=owner?.staff?.[index];if(!staff?.auth_user_id)return;
   if(!root.confirm('Send password recovery to '+staff.email+'? A working inbox is required.'))return;
   try{const result=await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'recovery',portal:'admin',gym_token:owner.token,email:staff.email});root.alert(result.message);}catch(error){root.alert(error.message);}
  }
  function renderStaff(owner,containerId,onRevoke,onEdit){
   const container=root.document.getElementById(containerId);if(!container)return;container.textContent='';
   const revision=(staffRevisions.get(container)||0)+1;staffRevisions.set(container,revision);const statuses=new Map();
   if(owner)root.IronVaultStaffReports?.render(client,owner.id,containerId==='existing-staff-list'?'staff-report-permissions':'inspect-report-permissions');
   if(!owner?.staff?.length){container.textContent='No staff accounts registered.';return;}
   for(const [index,staff] of owner.staff.entries()){
    const row=root.document.createElement('details');row.className='p-3 rounded-xl bg-slate-900 text-xs';
    const summary=root.document.createElement('summary');summary.className='iv-staff-summary';
    const label=root.document.createElement('span');label.textContent=staff.name+' · Staff';summary.appendChild(label);
    const status=root.document.createElement('span');status.className='iv-staff-status';status.textContent=staff.auth_user_id?'Checking access…':'Account link unavailable';summary.appendChild(status);statuses.set(staff.auth_user_id,status);row.appendChild(summary);
    const panel=root.document.createElement('div');panel.className='iv-staff-details';
    const email=root.document.createElement('p');email.textContent='Email: '+staff.email;panel.appendChild(email);
    const permission=root.document.createElement('div');permission.dataset.staffId=staff.auth_user_id||'';permission.dataset.staffTenant=owner.id;permission.textContent='Report permission unavailable.';panel.appendChild(permission);
    function action(label,callback){const button=root.document.createElement('button');button.type='button';button.textContent=label;button.onclick=callback;button.disabled=!staff.auth_user_id;panel.appendChild(button);}
    if(onEdit)action('Edit name / email',()=>onEdit(index));
    action('Send password recovery',()=>recoverStaff(owner,index));action('Deactivate access',()=>onRevoke(index));
    const note=root.document.createElement('p');note.textContent='Recovery requires a working inbox. Deactivation retains history.';panel.appendChild(note);
    row.appendChild(panel);container.appendChild(row);
   }
   (async()=>{
    try{
     const actor=await root.IronVaultAuth.requireRole(client,{roles:['super_admin','owner'],tenantId:owner.id,allowGlobalSuperAdmin:true});
     const {data,error}=await client.from('iv_user_roles').select('user_id,enabled,disabled_at').eq('tenant_id',owner.id).eq('role','staff');
     if(error||!Array.isArray(data))throw Error('Status unavailable');
     const current=await root.IronVaultAuth.requireRole(client,{roles:['super_admin','owner'],tenantId:owner.id,allowGlobalSuperAdmin:true});
     if(current.user_id!==actor.user_id)throw Error('Status unavailable');
     if(staffRevisions.get(container)!==revision)return;
     for(const [id,node] of statuses){const binding=data.find(r=>r.user_id===id);node.textContent=!binding?'No enabled access':binding.disabled_at?'Deactivated':owner.status!=='ACTIVE'?'Gym inactive':binding.enabled?'Active':'Access disabled';}
    }catch(error){if(staffRevisions.get(container)===revision)for(const node of statuses.values())node.textContent='Status unavailable';}
   })();
  }

  if(kind==='admin'){
   app.processScannedCode=async function(value){
    const match=/^IV1\|([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.exec(String(value));
    if(!match){this.showScanResult(false,'ACCESS DENIED','Generate a new daily pass from your member profile.');return;}
    let entry;
    try{
     await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:this.currentTenantId});
     entry=await root.IronVaultData.call(client,'iv_redeem_member_pass',{p_token:match[1],p_tenant:this.currentTenantId});
    }catch(error){this.showScanResult(false,'ACCESS DENIED',error.message);return;}
    let note='Entry recorded.';
    try{await this.loadMembers();}catch(error){note+=' Refresh the roster to see the entry.';}
    this.showScanResult(true,'ENTRY RECORDED',note);this.pauseScannerAfterSuccess();
   };
   app.logoutAdmin=async function(){
    const token=this.matchedOwnerRecord?.token;root.document.body?.classList.add('iv-auth-pending');
    try{await client.rpc('iv_staff_event',{p_tenant:this.currentTenantId,p_event:'logout'});}catch(_){}
    try{await root.IronVaultAuth.signOut(client,root.sessionStorage,root.localStorage);}
    catch(error){root.alert(error.message);return;}
    this.members=[];this.allMembersSystem=[];root.location.replace('login.html'+(token?'?key='+encodeURIComponent(token):''));
   };
   app.saveMembers=async function(){
    const records=this.activeModalMemberId?this.members.filter(m=>m.id===this.activeModalMemberId):this.members;
    await root.IronVaultData.saveMembers(client,records);this.updateStats();
   };
   app.quickApproveMember=async function(id){const m=this.members.find(x=>x.id===id);if(!m)return;
    await root.IronVaultData.saveMembers(client,[{...m,status:'ACTIVE'}]);await this.loadMembers();root.alert('Member approved. Email confirmation is optional for sign-in.');
   };
   app.approvePendingMember=async function(){if(await this.quickApproveMember(this.activeModalMemberId)===false)return;if(this.activeModalMemberId)this.openProfileModal(this.activeModalMemberId);};
   app.logAudit=async function(event,details){try{await root.IronVaultData.call(client,'iv_log_event',{p_tenant:this.currentTenantId,p_event:String(event),p_details:String(details)});}catch(error){console.error('Activity log unavailable');}};
   app.deleteMember=async function(id){
    try{
     await root.IronVaultAuth.requireRole(client,{roles:['owner'],tenantId:this.currentTenantId});
     const member=this.members.find(m=>m.id===id);if(!member)throw Error('Member unavailable. Refresh the roster.');
     const balance=Number(member.walletBalance??0);
     if(!Number.isFinite(balance)||balance!==0)throw Error('Settle the member wallet balance before removing this membership.');
     if(!root.confirm('Remove '+member.name+' ('+(member.displayCode||member.id)+') from this gym? Access will be deactivated; financial and attendance history will be retained.'))return;
     await root.IronVaultData.call(client,'iv_deactivate_member',{p_member_id:id});
     member.status='INACTIVE';let refreshNote='';
     try{await this.loadMembers();}catch(_){refreshNote=' Refresh the dashboard to reload the roster.';}
     this.searchManualCheckIn();root.alert('Member removed from active lists. History retained.'+refreshNote);
    }catch(error){root.alert(error.message);}
   };
   app.handleStaffSignup=async function(event){event.preventDefault();
    const value=id=>root.document.getElementById(id).value;
    try{
     const result=await provision('provision-gym-tenant',{mode:'staff',tenantId:this.currentTenantId,
      name:value('staff-reg-name').trim(),email:value('staff-reg-email').trim(),password:value('staff-reg-password')});
     event.target.reset();await this.openStaffSignupModal();this.switchStaffTab('list');root.alert(result.message);
    }catch(error){root.alert(error.message);}
   };
   app.renderExistingStaffList=function(){renderStaff(this.matchedOwnerRecord,'existing-staff-list',index=>this.deleteStaff(index),index=>this.saveStaffEdit(index));};
   app.saveStaffEdit=async function(index){
    const staff=this.matchedOwnerRecord?.staff?.[index];if(!staff?.auth_user_id)return;
    const name=root.prompt('Staff name',staff.name);if(!name)return;
    try{await root.IronVaultData.call(client,'iv_update_staff_name',{p_tenant:this.currentTenantId,p_user:staff.auth_user_id,p_name:name.trim()});
     const email=root.prompt('Staff contact email (used for password recovery)',staff.email);
     if(email!==null&&email.trim().toLowerCase()!==staff.email.toLowerCase()){
      const result=await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'staff_email_change',user_id:staff.auth_user_id,new_email:email.trim().toLowerCase()});
      root.alert(result.message);
     }
     // Password recovery has its own explicit action in staff details.
     await this.openStaffSignupModal();this.switchStaffTab('list');
    }catch(error){root.alert(error.message);}
   };
   app.handleAdminAddMember=async function(event){event.preventDefault();
    try{const result=await provision('iv-create-member',{tenant_id:this.currentTenantId,name:value('new-member-name').trim(),email:value('new-member-email').trim(),phone:value('new-member-phone').trim(),password:value('new-member-password')});
     await root.IronVaultData.saveMembers(client,[{id:result.member_id,tenantId:this.currentTenantId,name:value('new-member-name').trim(),phone:value('new-member-phone').trim(),classification:value('new-member-classification'),discountPercentage:Number(value('new-member-discount')),status:'ACTIVE'}]);
     this.closeAddMemberModal();await this.loadMembers();root.alert(result.message+' Buy a plan through the desk sale when required.');
    }catch(error){root.alert(error.message);}
   };
   app.sendMemberPasswordReset=async function(){const m=this.members.find(x=>x.id===this.activeModalMemberId);if(!m)return;
    try{if(!m.email)throw Error('Add and verify a contact email before requesting email recovery.');const result=await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'recovery',gym_token:this.matchedOwnerRecord?.token,email:m.email,portal:'member'});root.alert(result.message);}catch(error){root.alert(error.message);}
   };
   app.deleteStaff=async function(index){
    const staff=this.matchedOwnerRecord?.staff?.[index];if(!staff?.auth_user_id)return root.alert('Staff account link unavailable.');
    if(!root.confirm('Revoke this staff account’s gym access? History will remain.'))return;
    try{await root.IronVaultData.call(client,'iv_revoke_staff',{p_tenant:this.currentTenantId,p_user:staff.auth_user_id});await this.openStaffSignupModal();this.switchStaffTab('list');}
    catch(error){root.alert(error.message);}
   };
   app.toggleStaffAdminPrivilege=async function(){root.alert('Open staff details to manage report access. Staff accounts retain their assigned role.');};
  }else if(kind==='master'){
   root.IronVaultTenantPurge.install(app,client);
   app.sendOwnerRecovery=async function(id){const gym=this.owners.find(g=>g.id===id);if(!gym)return;
    try{const result=await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:gym.status==='PROVISIONING'?'resend':'recovery',portal:'admin',gym_token:gym.token,email:gym.email});root.alert(result.message);}catch(error){root.alert(error.message);}
   };
   app.sendMemberRecovery=async function(id){const m=this.members.find(x=>x.id===id),gym=this.owners.find(g=>g.id===m?.tenantId);if(!m||!gym)return;
    try{const result=await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'recovery',portal:'member',gym_token:gym.token,email:m.email});root.alert(result.message);}catch(error){root.alert(error.message);}
   };
   app.renderInspectStaffList=function(owner){renderStaff(owner,'inspect-staff-list',index=>this.handleInspectDeleteStaff(index),index=>this.handleInspectEditStaff(index));};
   app.handleInspectEditStaff=async function(index){
    const gym=this.owners.find(x=>x.id===this.currentInspectOwnerId),staff=gym?.staff?.[index];if(!staff?.auth_user_id)return;
    const name=root.prompt('Staff name',staff.name);if(!name)return;
    try{await root.IronVaultData.call(client,'iv_update_staff_name',{p_tenant:gym.id,p_user:staff.auth_user_id,p_name:name.trim()});
     const email=root.prompt('Staff contact email (used for password recovery)',staff.email);
     if(email!==null&&email.trim().toLowerCase()!==staff.email.toLowerCase()){
      const result=await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'staff_email_change',user_id:staff.auth_user_id,new_email:email.trim().toLowerCase()});root.alert(result.message);
     }
     await this.loadData();this.renderInspectStaffList(this.owners.find(x=>x.id===gym.id));
    }catch(error){root.alert(error.message);}
   };
   app.handleInspectDeleteStaff=async function(index){
    const gym=this.owners.find(x=>x.id===this.currentInspectOwnerId),staff=gym?.staff?.[index];if(!staff?.auth_user_id)return;
    if(!root.confirm('Revoke this staff account’s access?'))return;
    try{await root.IronVaultData.call(client,'iv_revoke_staff',{p_tenant:gym.id,p_user:staff.auth_user_id});await this.loadData();this.renderInspectStaffList(this.owners.find(x=>x.id===gym.id));}catch(error){root.alert(error.message);}
   };
   app.handleRegisterOwner=async function(event){event.preventDefault();if(this.gymRegistrationBusy)return;this.gymRegistrationBusy=true;const button=event.target.querySelector('button[type="submit"]');button.disabled=true;
    try{
     const file=root.document.getElementById('reg-gym-logo').files?.[0];const logo='';
     const prepared=file?await root.IronVaultProfileImages.prepare(file,'gym'):null;
     const staff={name:value('reg-staff-name').trim(),email:value('reg-staff-email').trim(),password:value('reg-staff-pass')};
     if((staff.name||staff.email||staff.password)&&!(staff.name&&staff.email&&staff.password))throw Error('Complete all staff fields or leave them blank.');
     const result=await provision('provision-gym-tenant',{mode:'create',gymName:value('reg-gym-name').trim(),ownerName:value('reg-owner-name').trim(),email:value('reg-owner-email').trim(),password:value('reg-owner-pass'),logo,
      pricing:{day:Number(value('reg-price-day')),week:Number(value('reg-price-week')),month:Number(value('reg-price-month')),studentDiscount:Number(value('reg-discount-student')),seniorDiscount:Number(value('reg-discount-senior'))}});
     let note='';
     if(prepared){try{const image=await root.IronVaultProfileImages.save(client,{kind:'gym',tenantId:result.tenantId,expected:'',prepared});if(image.cleanupPending)note+=' Previous image cleanup will retry later.';}catch(error){note+=' Gym created; logo setup needs a retry from Edit gym. '+error.message;}}
     // Successful owner provisioning activates the gym before optional staff creation.
     // A staff failure leaves the completed gym intact for a separate retry.
     if(staff.name){try{await provision('provision-gym-tenant',{mode:'staff',tenantId:result.tenantId,...staff});}catch(error){note+=' Gym created; staff setup needs a retry from View Branch. '+error.message;}}
     await this.loadData();this.renderDashboard();event.target.reset();root.alert(result.message+note);
    }catch(error){root.alert(error.message);}finally{button.disabled=false;this.gymRegistrationBusy=false;}
   };
   app.handleUpdateOwner=async function(event){event.preventDefault();if(this.gymSettingsBusy)return;const id=value('edit-owner-id'),gym=this.owners.find(g=>g.id===id);if(!gym)return;this.gymSettingsBusy=true;const button=event.target.querySelector('button[type="submit"]');if(button)button.disabled=true;
    try{
     const logo=gym.logo||'',file=root.document.getElementById('edit-gym-logo').files?.[0];
     const prepared=file?await root.IronVaultProfileImages.prepare(file,'gym'):null;
     const email=value('edit-owner-email').trim().toLowerCase();let pending=false;
     if(email!==gym.email.toLowerCase()){await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'admin_email_change',tenant_id:id,new_email:email});pending=true;}
     await root.IronVaultData.saveGyms(client,[{id,gymName:value('edit-gym-name').trim(),ownerName:value('edit-owner-name').trim(),logo,
      pricing:{day:Number(value('edit-price-day')),week:Number(value('edit-price-week')),month:Number(value('edit-price-month')),studentDiscount:Number(value('edit-discount-student')),seniorDiscount:Number(value('edit-discount-senior'))}}]);
     let note='';if(prepared){try{const image=await root.IronVaultProfileImages.save(client,{kind:'gym',tenantId:id,expected:logo,prepared});if(image.cleanupPending)note=' Previous image cleanup will retry later.';}catch(error){note=' Settings saved, but the logo was not confirmed. Refresh and retry the logo if needed. '+error.message;}}
     await this.loadData();this.renderDashboard();this.closeEditModal();root.alert((pending?'Gym saved. Confirm both addresses to finish the owner email change.':'Gym settings saved.')+note);
    }catch(error){root.alert(error.message);}finally{this.gymSettingsBusy=false;if(button)button.disabled=false;}
   };
   app.handleInspectAddStaff=async function(event){event.preventDefault();try{
    const result=await provision('provision-gym-tenant',{mode:'staff',tenantId:this.currentInspectOwnerId,name:value('inspect-new-staff-name').trim(),email:value('inspect-new-staff-email').trim(),password:value('inspect-new-staff-pass')});
    await this.loadData();this.renderInspectStaffList(this.owners.find(x=>x.id===this.currentInspectOwnerId));event.target.reset();root.alert(result.message);
   }catch(error){root.alert(error.message);}};

   async function importZip(file,tenant){
    if(file.size>10000000)throw Error('Backup must be smaller than 10 MB.');
    const zip=await root.JSZip.loadAsync(file);
    const get=async names=>{const entry=names.map(n=>zip.file(n)).find(Boolean);if(!entry)return [];const text=await entry.async('string');if(text.length>10000000)throw Error('Backup entry too large.');const result=JSON.parse(text);if(!Array.isArray(result))throw Error('Invalid backup array.');return result;};
    const gyms=await get(tenant?['tenant_owner_export.json']:['ironvault_owners_export.json']);
    const members=await get(tenant?['tenant_members_export.json']:['ironvault_members_export.json']);
    if(tenant&&(gyms.some(g=>g.id!==tenant)||members.some(m=>(m.tenantId||m.tenant_id)!==tenant)))throw Error('Backup belongs to a different gym.');
    if(!gyms.length&&!members.length)throw Error('Backup has no supported profile files.');
    if(!root.confirm('Restore branding and existing member profiles? Wallets, purchases, accounts, roles and history will remain unchanged.'))return;
    await root.IronVaultData.call(client,'iv_restore_profiles',{p_gyms:gyms.map(root.IronVaultData.gym),p_members:members.map(root.IronVaultData.member)});
    await app.loadData();app.renderDashboard();root.alert('Branding and existing profiles restored. Financial records and account credentials were preserved.');
   }
   app.importTenantZip=async function(event){const file=event.target.files?.[0];if(!file)return;try{await importZip(file,this.currentInspectOwnerId);}catch(error){root.alert('Restore not completed: '+error.message);}finally{event.target.value='';}};
   app.importDataFromFile=async function(event){const file=event.target.files?.[0];if(!file)return;
    try{if(file.name.toLowerCase().endsWith('.zip'))await importZip(file);
     else{if(file.size>10000000)throw Error('Backup too large.');const members=JSON.parse(await file.text());if(!Array.isArray(members))throw Error('Invalid profile file.');
      if(!root.confirm('Restore existing profiles only, preserving all financial history and accounts?'))return;
      await root.IronVaultData.call(client,'iv_restore_profiles',{p_gyms:[],p_members:members.map(root.IronVaultData.member)});await this.loadData();this.renderDashboard();root.alert('Existing profiles restored; financial records preserved.');}}
    catch(error){root.alert('Restore not completed: '+error.message);}finally{event.target.value='';}
   };
   app.saveOwners=async function(){await root.IronVaultData.saveGyms(client,this.owners);};
   app.processScannedCode=async function(value){
    const match=/^IV1\|([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.exec(String(value));
    if(!match){this.showScanResult(false,'ACCESS DENIED','Generate a new daily pass from your member profile.');return;}
    let entry;
    try{
     await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:this.currentTenantId});
     entry=await root.IronVaultData.call(client,'iv_redeem_member_pass',{p_token:match[1],p_tenant:this.currentTenantId});
    }catch(error){this.showScanResult(false,'ACCESS DENIED',error.message);return;}
    let note='Entry recorded.';
    try{await this.loadMembers();}catch(error){note+=' Refresh the roster to see the entry.';}
    this.showScanResult(true,'ENTRY RECORDED',note);this.pauseScannerAfterSuccess();
   };
   app.logoutAdmin=async function(){
    const token=this.matchedOwnerRecord?.token;root.document.body?.classList.add('iv-auth-pending');
    try{await client.rpc('iv_staff_event',{p_tenant:this.currentTenantId,p_event:'logout'});}catch(_){}
    try{await root.IronVaultAuth.signOut(client,root.sessionStorage,root.localStorage);}
    catch(error){root.alert(error.message);return;}
    this.members=[];this.allMembersSystem=[];root.location.replace('login.html'+(token?'?key='+encodeURIComponent(token):''));
   };
   app.saveMembers=async function(){await root.IronVaultData.saveMembers(client,this.members);};
   app.deleteOwner=async function(id){
    if(!root.confirm('Suspend this gym? Accounts, memberships and history will be retained.'))return;
    try{await root.IronVaultData.call(client,'iv_deactivate_gym',{p_tenant:id});await this.loadData();this.renderDashboard();}
    catch(error){root.alert(error.message);}
   };
  }else if(kind==='member'){
   app.handleProfileUpdate=async function(event){event.preventDefault();if(!this.currentMember)return;
    try{
     const {data,error}=await client.auth.getUser();if(error||!data.user)throw Error('Sign in required.');
     const email=value('edit-email').trim().toLowerCase(),password=value('edit-password');
     if(password){if(password.length<8||!value('edit-current-password'))throw Error('At least 8 characters. Enter your current password to confirm the change.');
      const checked=await client.auth.signInWithPassword({email:data.user.email,password:value('edit-current-password')});if(checked.error)throw Error('Current password is incorrect.');
      const changed=await client.auth.updateUser({password});if(changed.error)throw Error('Password change failed.');}
     let pending=false;
     if(email!==String(this.currentMember.email||'').toLowerCase()){
      await root.IronVaultBranchAuth.invoke(client,'iv-branch-auth',{action:'email_change',new_email:email});pending=true;
     }
     this.currentMember.name=value('edit-name').trim();this.currentMember.phone=value('edit-phone').trim();await this.saveData();this.renderProfile();
     root.document.getElementById('edit-password').value='';root.document.getElementById('edit-current-password').value='';
     this.showAlert(pending?'Profile saved. Confirm both email addresses to complete the contact change.':'Profile saved.',true);
    }catch(error){this.showAlert(error.message,false);}
   };
   app.selectPlan=async function(plan){
    const m=this.currentMember;if(!m)return;
    try{
     const pending=await root.IronVaultFinance.pending(client,root.sessionStorage,m.tenantId);
     let price;
     if(pending){if(pending.p_operation!=='purchase'||pending.p_member_id!==m.id||pending.p_plan!==plan)throw Error('Retry the unresolved payment first.');price=pending.p_amount;}
     else{const quote=await root.IronVaultData.call(client,'iv_quote_plan',{p_member_id:m.id,p_plan:plan});price=Number(quote.price);}
     if(!(this.confirmAction?await this.confirmAction('Use '+price+' wallet credits for '+plan+'?'):root.confirm('Use '+price+' wallet credits for '+plan+'?')))return;
     const outcome=await root.IronVaultFinance.execute(client,root.sessionStorage,m.tenantId,{p_operation:'purchase',p_member_id:m.id,p_plan:plan,p_amount:price,p_cash_amount:0});
     m.walletBalance=Number(outcome.wallet_balance);m.plan=plan;m.expirationDate=outcome.expiration_date;
     if(this.authenticatedRole){try{await this.loadData();await this.checkSession();}catch(_){}}
     this.renderProfile();
     this.showAlert('Subscription recorded. Your wallet balance is '+outcome.wallet_balance+'.',true);
    }catch(error){this.showAlert(error.message,false);}
   };
   app.generateDailyQR=async function(){
    if(!this.currentMember)return;
    try{
     const ticket=await root.IronVaultData.call(client,'iv_issue_member_pass',{p_member_id:this.currentMember.id});
     const container=root.document.getElementById('qrcode-container');container.innerHTML='';
     new root.QRCode(container,{text:ticket.payload,width:200,height:200,colorDark:'#000000',colorLight:'#ffffff',correctLevel:root.QRCode.CorrectLevel.H});
     root.document.getElementById('qr-date-badge').innerText='Date: '+ticket.business_day;
     root.document.getElementById('qr-wrapper').classList.remove('hidden');root.document.getElementById('qr-wrapper').classList.add('flex');
    }catch(error){this.showAlert(error.message,false);}
   };
   app.handleAvatarUpload=async function(event){const file=event.target.files?.[0],member=this.currentMember;if(!file||!member||this.profileImageBusy)return;
    this.profileImageBusy=true;event.target.disabled=true;
    try{const result=await root.IronVaultProfileImages.save(client,{kind:'member',tenantId:member.tenantId,memberId:member.id,expected:member.avatar||'',file});
     if(this.currentMember?.id===member.id){this.currentMember.avatar=result.reference;this.renderProfile();this.showAlert('Profile photo saved.'+(result.cleanupPending?' Previous photo cleanup will retry later.':''),true);}
    }catch(error){this.showAlert(error.message,false);}finally{this.profileImageBusy=false;event.target.disabled=false;event.target.value='';}
   };
   app.saveData=async function(){
    if(!this.currentMember)return;
    const m=this.currentMember;
    // Self-service never submits email, discounts, status, money or entitlements.
    await root.IronVaultData.call(client,'iv_save_member_profiles',{p_records:[{id:m.id,tenant_id:m.tenantId,name:m.name,phone:m.phone||'',avatar:m.avatar||null}]});
   };
  }
  const guarded=kind==='admin'?['handleSaveMemberDetails','quickApproveMember','approvePendingMember']:kind==='master'?['toggleOwnerStatus']:[];
  for(const name of guarded){const original=app[name];if(typeof original!=='function')continue;
   app[name]=async function(...args){try{return await original.apply(this,args);}catch(error){root.alert('Change was not saved: '+error.message);return false;}};
  }
 }
 root.IronVaultWorkflows=Object.freeze({install});
})(globalThis);
