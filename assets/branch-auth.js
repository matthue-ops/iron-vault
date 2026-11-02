(function(root){
 'use strict';
 async function invoke(client,name,body){
  const {data,error}=await client.functions.invoke(name,{body});
  if(error||data?.error){let message=data?.error||error?.message||'Request not completed.';
   try{if(error?.context?.json)message=(await error.context.json()).error||message;}catch(_){}
   throw Error(message);
  }return data;
 }
 async function provision(client,storage,name,body){
  if(typeof body.password==='string'&&body.password.length<8)throw Error('At least 8 characters.');
  const {data}=await client.auth.getUser();const actor=data?.user?.id||'public';
  const key='ironvault_provision:'+actor+':'+name+':'+(body.tenant_id||body.tenantId||body.gym_token||'new')+':'+String(body.email).trim().toLowerCase();
  body={...body,email:String(body.email||'').trim().toLowerCase()};
  const safe={...body};delete safe.password;delete safe.request_id;
  const payload=JSON.stringify(safe);let pending=JSON.parse(storage.getItem(key)||'null');
  if(pending&&pending.payload!==payload)throw Error('Retry the original account request before changing its details.');
  if(!pending){pending={id:root.crypto.randomUUID(),payload};storage.setItem(key,JSON.stringify(pending));}
  const result=await invoke(client,name,{...body,request_id:pending.id});
  storage.removeItem(key);return result;
 }
 async function signIn(client,body){
  const result=await invoke(client,'iv-branch-auth',{...body,action:'signin'});
  if(!result?.session?.access_token||!result.session.refresh_token)throw Error('Sign-in not completed.');
  const {error}=await client.auth.setSession(result.session);if(error)throw error;
 }
 function install(app,client){
  app.handleSignInSubmit=async function(event){event.preventDefault();try{
   await signIn(client,{gym_token:this.matchedOwnerRecord?.token,portal:'member',email:root.document.getElementById('signin-identifier').value,password:root.document.getElementById('signin-password').value});
   const role=await root.IronVaultAuth.requireRole(client,{roles:['member'],tenantId:this.currentTenantId});
   root.sessionStorage.setItem('ironvault_active_member',role.member_id);root.location.href='memberprofile.html';
  }catch(error){this.showAlert(error.message);}};
  app.handleAdminLoginSubmit=async function(event){event.preventDefault();try{
   await signIn(client,{gym_token:this.matchedOwnerRecord?.token,portal:'admin',email:root.document.getElementById('admin-login-email').value,password:root.document.getElementById('admin-login-password').value});
   const role=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff'],tenantId:this.currentTenantId});
   root.sessionStorage.setItem('ironvault_logged_user',root.document.getElementById('admin-login-email').value.trim().toLowerCase());
   root.sessionStorage.setItem('ironvault_active_tenant_id',role.tenant_id);root.sessionStorage.setItem('ironvault_active_role',role.role==='owner'?'admin':'staff');
   await client.rpc('iv_staff_event',{p_tenant:role.tenant_id,p_event:'login'});
   root.location.href='admin.html?key='+encodeURIComponent(this.matchedOwnerRecord.token);
  }catch(error){this.showAlert(error.message);}};
  app.handleSignUpSubmit=async function(event){event.preventDefault();const button=root.document.getElementById('btn-submit-signup');button.disabled=true;try{
   const val=id=>root.document.getElementById(id).value;
   const result=await provision(client,root.sessionStorage,'iv-branch-auth',{action:'signup',gym_token:this.matchedOwnerRecord?.token,
    name:val('signup-name').trim(),email:val('signup-email').trim(),phone:val('signup-phone').trim(),password:val('signup-password')});
   event.target.reset();this.switchTab('SIGNIN');this.showAlert(result.message,true);
  }catch(error){this.showAlert(error.message);}finally{button.disabled=false;}};
  app.handleForgotPassword=async function(event){event.preventDefault();try{
   const result=await invoke(client,'iv-branch-auth',{action:'recovery',gym_token:this.matchedOwnerRecord?.token,email:root.document.getElementById('signin-identifier').value,portal:'member'});this.showAlert(result.message,true);
  }catch(error){this.showAlert(error.message);}};
 }
 root.IronVaultBranchAuth=Object.freeze({invoke,provision,signIn,install});
 if(typeof module==='object'&&module.exports)module.exports=root.IronVaultBranchAuth;
})(globalThis);
