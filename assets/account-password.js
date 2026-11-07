/* Own-account change only; no caller-supplied email, user target or credential storage. */
(function(root){
 'use strict';
 async function change(client,{tenantId,userId,currentPassword,password,confirmation,createVerifier,isCurrent=()=>true}){
  if(!currentPassword)throw Error('Enter your current password.');
  if(password.length<8||password.length>128)throw Error('Use a new password of 8 to 128 characters.');
  if(password!==confirmation)throw Error('The new passwords do not match.');
  const check=()=>{if(!isCurrent())throw Error('Account changed. Sign in again before changing your password.');};
  const options={roles:['owner','staff'],tenantId};check();
  const before=await root.IronVaultAuth.requireRole(client,options);
  const {data,error}=await client.auth.getUser();check();
  if(error||before.user_id!==userId||data?.user?.id!==userId||!data.user.email)throw Error('Sign in again before changing your password.');
  if(typeof createVerifier!=='function')throw Error('Password change is unavailable. Use the email reset link.');
  // A non-persistent isolated session cannot log this browser back in after logout.
  const verifier=createVerifier();
  try{
   const verified=await verifier.auth.signInWithPassword({email:data.user.email,password:currentPassword});check();
   if(verified.error)throw Error('Current password is incorrect.');
   if(verified.data?.user?.id!==userId)throw Error('Account changed. Password was not updated.');
   const after=await root.IronVaultAuth.requireRole(client,options);check();
   if(after.user_id!==userId)throw Error('Account changed. Password was not updated.');
   const changed=await verifier.auth.updateUser({password});
   if(changed.error||changed.data?.user?.id!==userId)throw Error('Password change was not confirmed. Check whether the new password works before repeating.');
   check();return true;
  }finally{try{await verifier.auth.signOut({scope:'local'});}catch(_){/* No persistent session or refresh timer exists on this client. */}}
 }
 root.IronVaultAccountPassword=Object.freeze({change});
 if(typeof module==='object'&&module.exports)module.exports=root.IronVaultAccountPassword;
})(globalThis);
