import {serve,actor,admin,publicClient,rpc,role,digest,limit} from '../_shared/runtime.ts';
import {ensurePrivateIdentifier} from '../_shared/identity.ts';
import {ownerBranchSession,sharedOwnerCredential} from '../_shared/owner-access.ts';
serve(async(req,input)=>{
 const action=String(input.action||'');
 if(action==='register'){
  const email=String(input.email||'').trim().toLowerCase(),password=String(input.password||''),request=String(input.request_id||'').toLowerCase();
  if(!/^[a-f0-9-]{36}$/i.test(request)||!email||password.length<8||password.length>128||input.accepted!==true)throw Error('Invalid request.');
  await limit('gym-register-email:'+email,5,3600);await limit('gym-register-ip:'+(req.headers.get('x-forwarded-for')||'unknown').split(',')[0],10,3600);await limit('gym-register-global',100,3600);
  const existing=await rpc('iv_owner_account_service',{p_action:'lookup',p_data:{email}});
  // Same-job completed retries remain allowed; new requests cannot silently merge an existing owner.
  const alias=await digest('gym-registration\0'+request)+'@accounts.ironvault.invalid';
  const payload={gym_name:String(input.gym_name||'').trim(),name:String(input.owner_name||'').trim(),address:String(input.address||'').trim(),phone:String(input.phone||'').trim(),accepted:true,legal_version:String(input.legal_version||'').toLowerCase(),pricing:{day:100,week:600,month:2000,studentDiscount:20,seniorDiscount:20}};
  if(Array.isArray(existing)&&existing.length){const found=await rpc('iv_find_created_account',{p_request:request});if(!found)throw Error('Invalid request.');}
  const prepared=await rpc('iv_gym_registration_service',{p_action:'prepare',p_data:{request_id:request,email,alias,payload}});
  if(prepared.needs_legal_review)return {ok:false,needs_legal_review:true,message:'Registration terms changed. Review the current documents before submitting again.'};
  let userId=prepared.completed_user||await rpc('iv_find_created_account',{p_request:request});
  if(userId&&!prepared.completed_user){const proof=await publicClient().auth.signInWithPassword({email:alias,password});if(proof.error||proof.data?.user?.id!==userId)throw Error('Invalid request.');}
  if(!userId){const created=await admin.auth.admin.createUser({email:alias,password,email_confirm:true,app_metadata:{iv_provision_request:request},user_metadata:{name:payload.name}});if(created.error||!created.data.user)throw Error('Operation could not be completed.');userId=created.data.user.id;}
  const result=await rpc('iv_gym_registration_service',{p_action:'finish',p_data:{request_id:request,user_id:userId}});
  return {ok:true,gym:result.gym,message:'Gym registered. Sign in to complete setup. Your pilot still requires provider approval.'};
 }
 if(action==='login'){
  const email=String(input.email||'').trim().toLowerCase(),password=String(input.password||'');if(!email||email.length>254||!password||password.length>128)throw Error('Invalid request.');
  await limit('owner-login:'+email,20,600);
  const choices=await rpc('iv_owner_account_service',{p_action:'lookup',p_data:{email,gym_token:String(input.gym_token||'')}});
  if(!Array.isArray(choices)||choices.length!==1)throw Error('Invalid request.');
  const auth=await publicClient().auth.signInWithPassword({email:choices[0].auth_email,password});if(auth.error||!auth.data.session||auth.data.user?.id!==choices[0].account_user)throw Error('Invalid request.');
  await ensurePrivateIdentifier(choices[0].account_user);
  // Ephemeral root session is used only by the registration chooser; each destination receives its own gym session.
  return {session:{access_token:auth.data.session.access_token,refresh_token:auth.data.session.refresh_token}};
 }
 const user=await actor(req);await limit('owner-service:'+user.id,30,600);
 if(action==='switch'){return ownerBranchSession(user.id,String(input.tenant_id||''));}
 if(action==='approve_branch'){
  const r=await role(user.id);if(r.role!=='super_admin'||r.tenant_id!==null||input.reviewed!==true)throw Error('Not authorized.');
  const id=String(input.id||'').toLowerCase();if(!/^[a-f0-9-]{36}$/i.test(id))throw Error('Invalid request.');
  const alias=await digest('gym-branch\0'+id)+'@accounts.ironvault.invalid';
  const prepared=await rpc('iv_owner_account_service',{p_action:'prepare_branch',p_data:{actor_id:user.id,id,revision:input.revision,reviewed:true,alias}});
  if(prepared.status==='cancelled')return {ok:true,message:'This branch registration was removed. The application is cancelled; no pilot was activated.'};
  if(prepared.status==='approved')return {ok:true,message:'Branch already approved. Its pilot still requires separate approval.',gym:prepared.gym};
  await ensurePrivateIdentifier(prepared.account_user);
  let authId=prepared.completed_user||await rpc('iv_find_created_account',{p_request:id});
  if(!authId){const created=await admin.auth.admin.createUser({email:prepared.alias,password:crypto.randomUUID()+crypto.randomUUID(),email_confirm:true,app_metadata:{iv_provision_request:id},user_metadata:{name:prepared.owner_name}});if(created.error||!created.data.user)throw Error('Operation could not be completed.');authId=created.data.user.id;}
  const result=await rpc('iv_owner_account_service',{p_action:'finish_branch',p_data:{actor_id:user.id,id,user_id:authId}});
  if(result.status==='cancelled')return {ok:true,message:'This branch registration was removed. The application is cancelled; no pilot was activated.'};
  return {ok:true,gym:result.gym,message:'Branch approved and linked. Setup, agreements and pilot approval remain separate.'};
 }
 if(action==='password'){
  const r=await role(user.id);if(r.role!=='owner'||input.expected_user_id!==user.id)throw Error('Not authorized.');
  const info=await sharedOwnerCredential(user.id);if(!info)throw Error('Invalid request.');
  const current=String(input.current_password||''),password=String(input.password||'');if(!current||current.length>128||password.length<8||password.length>128)throw Error('Invalid request.');
  const proof=await publicClient().auth.signInWithPassword({email:info.auth_email,password:current});if(proof.error||proof.data?.user?.id!==info.account_user)throw Error('Invalid request.');
  const after=await sharedOwnerCredential(user.id);if(!after||after.account_user!==info.account_user)throw Error('Not authorized.');
  const changed=await admin.auth.admin.updateUserById(info.account_user,{password});if(changed.error||changed.data?.user?.id!==info.account_user)throw Error('Operation could not be completed.');
  return {ok:true,message:'Owner password updated for your linked gyms. Existing access restrictions remain.'};
 }
 throw Error('Invalid request.');
});
