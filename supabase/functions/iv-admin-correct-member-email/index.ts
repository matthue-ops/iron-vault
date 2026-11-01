import {serve,actor,role,admin} from '../_shared/runtime.ts';
import {changeContact} from '../_shared/contact.ts';
serve(async(req,input)=>{
 const user=await actor(req),r=await role(user.id);
 const {data:m,error}=await admin.from('iv_user_roles').select('user_id,tenant_id').eq('role','member').eq('member_id',String(input.member_id||'')).eq('tenant_id',String(input.tenant_id||'')).single();
 if(error||!m?.user_id||!(r.role==='super_admin'||(r.role==='owner'&&r.tenant_id===m.tenant_id)))throw Error('Not authorized.');
 return changeContact(req,input,m.user_id);
});
