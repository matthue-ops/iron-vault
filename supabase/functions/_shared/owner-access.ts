import {admin,publicClient,rpc} from './runtime.ts';
export async function sharedOwnerCredential(userId:string){
 const info=await rpc('iv_owner_account_service',{p_action:'credential',p_data:{user_id:userId}});
 return info?.shared?info:null;
}
export async function ownerBranchSession(actorId:string,tenantId:string){
 const target=await rpc('iv_owner_account_service',{p_action:'target',p_data:{actor_id:actorId,tenant_id:tenantId}});
 const {data:link,error:linkError}=await admin.auth.admin.generateLink({type:'magiclink',email:target.auth_email});
 if(linkError||!link.properties?.hashed_token)throw Error('Operation could not be completed.');
 const {data,error}=await publicClient().auth.verifyOtp({token_hash:link.properties.hashed_token,type:'magiclink'});
 if(error||!data.session||data.user?.id!==target.user_id)throw Error('Not authorized.');
 const after=await rpc('iv_owner_account_service',{p_action:'target',p_data:{actor_id:actorId,tenant_id:tenantId}});
 if(after.user_id!==target.user_id)throw Error('Not authorized.');
 return {gym:target.gym,session:{access_token:data.session.access_token,refresh_token:data.session.refresh_token}};
}
