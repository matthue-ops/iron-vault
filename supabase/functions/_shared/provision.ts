import {admin,publicClient,rpc,role,actor,digest,limit} from './runtime.ts';
export async function provision(req:Request,input:any,kind:'member'|'tenant',publicSignup=false){
 const mode=kind==='member'?'member':input.mode;
 if(!['member','create','staff'].includes(mode))throw Error('Invalid request.');
 const user=publicSignup?null:await actor(req);
 const email=String(input.email||'').trim().toLowerCase(),optionalContact=kind==='member'&&!publicSignup&&!!user&&!email,password=String(input.password||''),name=String(input.name||input.ownerName||'').trim();
 if((!optionalContact&&!/^[^\s@<>,;:"()\\]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z0-9-]{2,63}$/.test(email))||email.length>254||password.length<8||password.length>128||!name||name.length>160)throw Error('Invalid request.');
 const request=String(input.request_id||'').toLowerCase();if(!/^[0-9a-f-]{36}$/i.test(request))throw Error('Invalid request.');
 const tenant=mode==='create'?'GYM-'+request.slice(0,8).toUpperCase():String(input.tenant_id||input.tenantId||'');
 if(!tenant)throw Error('Invalid request.');
 if(user){const r=await role(user.id);if(mode==='create'&&r.role!=='super_admin')throw Error('Not authorized.');
  if(r.role!=='super_admin'&&(r.tenant_id!==tenant||!['owner','staff'].includes(r.role)||(mode==='staff'&&r.role!=='owner')))throw Error('Not authorized.');}
 await limit('provision:'+tenant+':'+email,8,3600);
 if(publicSignup)await limit('signup-gym:'+tenant,100,3600);
 const accountRole=mode==='create'?'owner':mode==='staff'?'staff':'member';
 const alias=await digest(tenant+'\0'+accountRole+'\0'+email+'\0'+request)+'@accounts.ironvault.invalid';
 if(publicSignup&&(!input.legal||input.legal.accepted!==true||!['platform_version','gym_version'].every(k=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(input.legal[k]||'')))))throw Error('Read and accept the published Terms and Privacy Notice.');
 const payload={...(publicSignup?{legal:{accepted:true,platform_version:String(input.legal.platform_version).toLowerCase(),gym_version:String(input.legal.gym_version).toLowerCase()}}:{}),name,phone:String(input.phone||'').slice(0,50),...(mode==='create'?{gym_name:String(input.gymName||''),pricing:input.pricing,logo:String(input.logo||'')}: {})};
 const prepared=await rpc('iv_prepare_branch_account',{p_request:request,p_actor:user?.id||null,p_tenant:tenant,p_role:accountRole,p_email:optionalContact?null:email,p_alias:alias,p_payload:payload,p_new_gym:mode==='create'});
 let authId=prepared.completed_user||await rpc('iv_find_created_account',{p_request:request});
 if(authId&&!prepared.completed_user){const {error}=await publicClient().auth.signInWithPassword({email:alias,password});if(error)throw Error('Invalid request.');}
 else if(!authId){
  const {data,error}=await admin.auth.admin.createUser({email:alias,password,email_confirm:true,
   app_metadata:{iv_provision_request:request},user_metadata:{name}});
  if(error||!data.user){console.error('Iron Vault Auth create failed',/^[A-Za-z0-9_]{1,64}$/.test(error?.code||'')?error?.code:'unknown',error?.status||0);throw Error('Operation could not be completed.');}authId=data.user.id;
 }
 const result=await rpc('iv_finish_branch_account',{p_request:request,p_user:authId});
 // Provisioning never depends on contact email delivery. Recovery still requires inbox proof.
 // Retain jobs and identities for safe same-request retries; never delete as compensation.
 return {...result,email,role:accountRole,message:accountRole==='staff'?'Staff account created. Sign in now; the owner can correct an unverified contact email later.':accountRole==='member'?(optionalContact?'Account created. Sign in with the Member ID and password. Add and verify a contact email later to enable email recovery.':'Account created. You can sign in without email confirmation; gym approval may still be required.'):'Gym and owner account created. Sign in now with your contact email and password. A working inbox is required for password recovery.'};
}
