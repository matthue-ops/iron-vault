import {serve,actor,role,publicClient,admin,rpc,limit} from '../_shared/runtime.ts';
serve(async(req,input)=>{
 const user=await actor(req),binding=await role(user.id);
 if(binding.role!=='super_admin'||binding.tenant_id!==null)throw Error('Not authorized.');
 const action=String(input.action||'');
 if(!['preview','purge','resume','list'].includes(action))throw Error('Invalid request.');
 const tenant=String(input.tenant_id||'');
 const control=(operation:string,extra:Record<string,unknown>={})=>rpc('iv_tenant_purge_control',{
  p_actor:user.id,p_action:operation,p_tenant:tenant||null,p_request:input.request_id||null,...extra});
 if(action==='list')return control('list');
 if(!tenant||tenant.length>160)throw Error('Invalid request.');
 if(action==='preview')return control('preview');
 if(input.confirmation!=='PURGE '+tenant||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(input.request_id||'')))throw Error('Invalid request.');
 await limit('tenant-purge:'+user.id,10,3600);
 const password=String(input.password||'');if(!user.email||!password||password.length>128)throw Error('Sign in required.');
 // Fresh password proof is independent of the existing access token. Never store it.
 const {data,error}=await publicClient().auth.signInWithPassword({email:user.email,password});
 if(error||data.user?.id!==user.id)throw Error('Sign in required.');
 let job=await control(action==='purge'?'start':'next',{p_review:input.review||null,p_confirmation:input.confirmation});
 if(job.complete)return job;
 let failed=0;
 // Bounded work. The durable job supports safe retries without repeating data deletion.
 for(const id of job.pending_users.slice(0,20)){
  const check=await control('check',{p_user:id});
  if(check.shared){job=await control('retain',{p_user:id});continue;}
  if(!check.eligible){failed++;continue;}
  const {error}=await admin.auth.admin.deleteUser(id);
  if(error&&error.status!==404){failed++;console.error('Iron Vault purge Auth deletion failed',/^[A-Za-z0-9_]{1,64}$/.test(error.code||'')?error.code:'unknown');continue;}
  job=await control('ack',{p_user:id});
 }
 job=await control('next');
 if(job.remaining===0)return control('finish');
 return {complete:false,remaining:job.remaining,failed,message:'Gym data purged. Auth cleanup remains; use Resume pending purges.'};
});
