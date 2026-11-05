import {ensurePrivateIdentifier} from './identity.ts';
import {actor,role,admin,rpc,digest,limit,sendMail,mailReady,site} from './runtime.ts';
export async function changeContact(req:Request,input:any,targetUser?:string){
 const user=await actor(req);const r=await role(user.id);const target=targetUser||user.id;
 const info=await rpc('iv_branch_account_details',{p_user:target});
 if(!info||(!targetUser&&target!==user.id))throw Error('Not authorized.');
 if(target!==user.id&&!(r.role==='super_admin'||(r.role==='owner'&&r.tenant_id===info.tenant_id)))throw Error('Not authorized.');
 if(target!==user.id&&r.role!=='super_admin'){const {data:gym,error}=await admin.from('owners').select('status').eq('id',info.tenant_id).single();if(error||gym?.status!=='ACTIVE')throw Error('Not authorized.');}
 const email=String(input.new_email||'').trim().toLowerCase();
 if(!/^[^\s@<>,;:"()\\]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z0-9-]{2,63}$/.test(email)||email.length>254||email===info.email)throw Error('Invalid request.');
 await limit('email-change:'+target,5,3600);
 const authEmail=await ensurePrivateIdentifier(target);
 if(target!==user.id&&info.role==='staff'&&!info.verified){
  // Replace any previously issued recovery token before changing its delivery address.
  const {error}=await admin.auth.admin.generateLink({type:'recovery',email:authEmail});
  if(error)throw Error('Operation could not be completed.');
  await rpc('iv_correct_unverified_staff_contact',{p_actor:user.id,p_user:target,p_email:email});
  return {ok:true,pending:false,message:'Staff contact email updated. Password recovery will use this address; the email remains unverified.'};
 }
 if(!mailReady())throw Error('Email delivery is not configured.');
 const group=crypto.randomUUID();
 const correction=!info.email||(target!==user.id&&!info.verified);
 const deliveries=correction?[['correct_unverified',email]]:[['change_old',info.email],['change_new',email]];
 for(const [kind,to] of deliveries){
  const token=crypto.randomUUID()+crypto.randomUUID();
  await rpc('iv_queue_contact_change',{p_actor:user.id,p_user:target,p_hash:await digest(token),p_kind:kind,p_group:group,p_new_email:email,p_base_email:info.email||null});
  await sendMail(to,'Confirm your Iron Vault contact email change',site+'/gym/memberlogin.html?key='+encodeURIComponent(info.token)+'#iv_verify='+token);
 }
 return {ok:true,pending:true,message:correction?'Confirm the corrected new email address to activate this unverified account.':'Confirm both the old and new email addresses to complete the change.'};
}
