import {admin,digest} from './runtime.ts';
// Preserve Auth IDs/passwords while retiring real-email credential identifiers.
// Recovery/contact changes cannot leave an obsolete address as a reset route.
export async function ensurePrivateIdentifier(userId:string){
 const {data,error}=await admin.auth.admin.getUserById(userId);if(error||!data.user?.email)throw Error('Operation could not be completed.');
 const user=data.user!,metadata={...user.app_metadata};
 let alias=user.email!;
 if(alias.endsWith('@accounts.ironvault.invalid')&&!metadata.iv_alias_rotation_pending)return alias;
 if(!alias.endsWith('@accounts.ironvault.invalid')){
  alias=await digest(userId+'\0'+crypto.randomUUID())+'@accounts.ironvault.invalid';
  const updated=await admin.auth.admin.updateUserById(userId,{email:alias,email_confirm:true,app_metadata:{...metadata,iv_alias_rotation_pending:true}});
  if(updated.error)throw Error('Operation could not be completed.');
 }
 // Supported Auth call replaces the old recovery token; no link is sent to alias.
 // Keep a protected retry marker until this step and its acknowledgement succeed.
 const invalidation=await admin.auth.admin.generateLink({type:'recovery',email:alias});
 if(invalidation.error)throw Error('Operation could not be completed.');
 const completed=await admin.auth.admin.updateUserById(userId,{app_metadata:{...metadata,iv_alias_rotation_pending:false,iv_branch_alias_version:1}});
 if(completed.error)throw Error('Operation could not be completed.');
 return alias;
}
