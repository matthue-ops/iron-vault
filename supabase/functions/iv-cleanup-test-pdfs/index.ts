import {createClient as createScopedClient} from 'https://esm.sh/@supabase/supabase-js@2.49.8';
import {serve,actor,role,admin,limit} from '../_shared/runtime.ts';
export async function cleanupTestPDFs(req:Request,input:Record<string,unknown>){
 const user=await actor(req),binding=await role(user.id);
 if(binding.role!=='super_admin'||binding.tenant_id!==null)throw Error('Not authorized.');
 if(input.confirmation!=='DELETE TEST SERVICE PDFS')throw Error('Type DELETE TEST SERVICE PDFS to confirm.');
 await limit('test-pdf-cleanup:'+user.id,30,3600);
 const jwt=req.headers.get('authorization')||'';
 const {data,error}=await createScopedClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:jwt}},auth:{autoRefreshToken:false,persistSession:false}}).rpc('iv_provider_console',{p_action:'cleanup_check',p_data:{}});
 if(error||!data?.allowed)throw Error('Test PDF cleanup is unavailable. Apply 038 and keep existing gyms marked Test.');
 const bucket=admin.storage.from('iv-service-documents');
 const listed=await bucket.list('documents',{limit:100,sortBy:{column:'name',order:'asc'}});
 if(listed.error){if(String(listed.error.statusCode)==='404')return{complete:true,removed:0};throw Error('Cannot inspect the PDF bucket.');}
 if(listed.data.some(file=>!file.id||!/^[a-f0-9-]{36}\.pdf$/i.test(file.name)))throw Error('Unexpected bucket item; review Storage manually.');
 const paths=listed.data.map(file=>'documents/'+file.name);
 if(paths.length){const removed=await bucket.remove(paths);if(removed.error)throw Error('PDF deletion failed; retry the cleanup.');}
 const next=await bucket.list('documents',{limit:1});if(next.error)throw Error('Verify Storage cleanup manually.');
 if(next.data.length)return{complete:false,removed:paths.length,message:'More test PDFs remain. Run again.'};
 const root=await bucket.list('',{limit:10});if(root.error||root.data.length)throw Error('Review unexpected remaining bucket items manually.');
 const deleted=await admin.storage.deleteBucket('iv-service-documents');if(deleted.error)throw Error('Files removed; remove the empty iv-service-documents bucket in Storage.');
 return {complete:true,removed:paths.length,message:'Test PDF files and bucket removed. Run manual SQL 039 next.'};
}
// Only fixed, non-sensitive cleanup guidance is returned; provider/SDK errors remain generic.
serve(async(req,input)=>{
 try{return await cleanupTestPDFs(req,input);}catch(error){
  const message=error instanceof Error?error.message:'';
  const safe=['Type DELETE TEST SERVICE PDFS to confirm.','Test PDF cleanup is unavailable. Apply 038 and keep existing gyms marked Test.','Cannot inspect the PDF bucket.','Unexpected bucket item; review Storage manually.','PDF deletion failed; retry the cleanup.','Verify Storage cleanup manually.','Review unexpected remaining bucket items manually.','Files removed; remove the empty iv-service-documents bucket in Storage.'];
  if(safe.includes(message))return {error:message};throw error;
 }
});
