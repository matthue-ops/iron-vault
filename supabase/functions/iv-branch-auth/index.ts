import {ensurePrivateIdentifier} from '../_shared/identity.ts';
import {serve,actor,role,admin,publicClient,rpc,digest,limit,sendMail,sendVerification,mailReady,site} from '../_shared/runtime.ts';
import {provision} from '../_shared/provision.ts';
import {changeContact} from '../_shared/contact.ts';
serve(async(req,input)=>{
 const action=String(input.action||'');
 if(action==='confirm'){
  const token=String(input.token||'');if(!/^[0-9a-f-]{72}$/i.test(token))throw Error('Invalid request.');
  await limit('confirmation:'+await digest(token),3,3600);
  const complete=await rpc('iv_confirm_email_action',{p_hash:await digest(token)});
  return {ok:true,message:complete?'Email verified. You can sign in when the gym is active; new member registrations may still need approval.':'This address is confirmed. Confirm the other email address to finish the change.'};
 }
 if(action==='own_recovery'){
  const user=await actor(req),r=await role(user.id);
  if(!['owner','staff'].includes(r.role)||!r.tenant_id)throw Error('Not authorized.');
  await limit('own-recovery:'+user.id,5,3600);
  const info=await rpc('iv_branch_account_details',{p_user:user.id});
  const {data:gym,error:badGym}=await admin.from('owners').select('id,token,status').eq('id',r.tenant_id).single();
  if(badGym||!gym||gym.status!=='ACTIVE'||!info.email)throw Error('Not authorized.');
  if(!mailReady())throw Error('Email delivery is not configured.');
  const authEmail=await ensurePrivateIdentifier(user.id);
  const {data,error}=await admin.auth.admin.generateLink({type:'recovery',email:authEmail});
  if(error||!data.properties?.hashed_token)throw Error('Email delivery failed.');
  // Recheck authorization before sending; no caller-supplied recipient is used.
  const after=await role(user.id);if(after.tenant_id!==r.tenant_id||after.role!==r.role)throw Error('Not authorized.');
  const link=site+'/gym/login.html?key='+encodeURIComponent(gym.token)+'#iv_recovery='+encodeURIComponent(data.properties.hashed_token);
  await sendMail(info.email,'Reset your gym account password',link);
  return {ok:true,message:'Password reset instructions were sent to your account email.'};
 }
 if(action==='email_change')return changeContact(req,input);
 if(action==='admin_email_change'){
  const user=await actor(req),r=await role(user.id);if(r.role!=='super_admin')throw Error('Not authorized.');
  const {data,error}=await admin.from('iv_user_roles').select('user_id').eq('tenant_id',String(input.tenant_id||'')).eq('role','owner').single();
  if(error||!data)throw Error('Invalid request.');return changeContact(req,input,data.user_id);
 }
 if(action==='staff_email_change'){
  const user=await actor(req),r=await role(user.id);
  const {data:staff,error}=await admin.from('iv_user_roles').select('user_id,tenant_id').eq('user_id',String(input.user_id||'')).eq('role','staff').single();
  if(error||!staff||!((r.role==='super_admin'&&r.tenant_id===null)||(r.role==='owner'&&r.tenant_id===staff.tenant_id)))throw Error('Not authorized.');
  return changeContact(req,input,staff.user_id);
 }
 if(!['signin','signup','recovery','resend'].includes(action))throw Error('Invalid request.');
 const token=String(input.gym_token||'');
 const {data:gym,error}=await admin.from('owners').select('id,token,status').eq('token',token).single();
 if(error||!gym||(gym.status!=='ACTIVE'&&!(action==='resend'&&gym.status==='PROVISIONING')))throw Error('Invalid request.');
 const email=String(input.email||'').trim().toLowerCase();
 const memberCode=action==='signin'&&input.portal!=='admin'&&/^mem-[a-z0-9-]{4,80}$/i.test(email);
 if((!memberCode&&!/^[^\s@<>,;:"()\\]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z0-9-]{2,63}$/.test(email))||email.length>254)throw Error('Invalid request.');
 const roles=input.portal==='admin'?['owner','staff']:['member'];
 await limit(action+':'+gym.id+':'+email,action==='signin'?20:5,action==='signin'?600:3600);
 if(action==='signup')return provision(req,{...input,tenant_id:gym.id},'member',true);
 if(action==='signin'){
  const rows=await rpc('iv_branch_identity',{p_tenant:gym.id,p_roles:roles,p_email:email});
  // Generic outcome for missing, disabled, verification-gated or ambiguous identities.
  if(!Array.isArray(rows)||rows.length!==1)throw Error('Invalid request.');
  const info=await rpc('iv_branch_account_details',{p_user:rows[0].user_id});
  const password=String(input.password||'');if(password.length<1||password.length>128)throw Error('Invalid request.');
  const {data,error}=await publicClient().auth.signInWithPassword({email:info.auth_email,password});
  if(error||!data.session)throw Error('Invalid request.');
  await ensurePrivateIdentifier(rows[0].user_id);
  return {session:{access_token:data.session.access_token,refresh_token:data.session.refresh_token}};
 }
 const message='If this account is eligible, an email will arrive shortly.';
 const rows=await rpc(action==='resend'?'iv_lookup_branch_account':'iv_branch_identity',{p_tenant:gym.id,p_roles:roles,p_email:email});
 if(!Array.isArray(rows)||rows.length!==1)return {ok:true,message};
 try{
  if(action==='resend')await sendVerification(rows[0].user_id);
  else{
   if(!mailReady())return {ok:true,message};
   const info=await rpc('iv_branch_account_details',{p_user:rows[0].user_id});
   if(!info.email)return {ok:true,message};
   const authEmail=await ensurePrivateIdentifier(rows[0].user_id);
   const {data,error}=await admin.auth.admin.generateLink({type:'recovery',email:authEmail});
   if(error||!data.properties?.hashed_token)throw Error('Email delivery failed.');
   const link=site+'/gym/memberlogin.html?key='+encodeURIComponent(gym.token)+'#iv_recovery='+encodeURIComponent(data.properties.hashed_token);
   await sendMail(info.email,'Reset your '+String(info.gym_name).replace(/[\r\n]/g,' ')+' gym password',link);
  }
 }catch(_){console.error('Branch email delivery failed; inspect provider configuration.');}
 return {ok:true,message};
});
