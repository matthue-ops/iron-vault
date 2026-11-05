import {PDFDocument,PDFDict,PDFArray,PDFName} from 'https://esm.sh/pdf-lib@1.17.1';
import {admin,actor,role,site} from '../_shared/runtime.ts';
const MAX_FILE=5*1024*1024,MAX_BODY=MAX_FILE+65536;
const origins=new Set((Deno.env.get('CORS_ORIGINS')||site).split(',').map(value=>new URL(value.trim()).origin));
const hashBytes=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
export async function validatePDF(bytes:Uint8Array){
 if(!bytes.length||bytes.length>MAX_FILE||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-'||!new TextDecoder().decode(bytes.slice(-2048)).includes('%%EOF'))throw Error('Upload a complete PDF no larger than 5 MB.');
 let pdf,pages;try{pdf=await PDFDocument.load(bytes,{ignoreEncryption:false,updateMetadata:false,throwOnInvalidObject:true});pages=pdf.getPageCount();}catch(_){throw Error('The PDF is damaged or password-protected. Export an unencrypted PDF and try again.');}
 if(pdf.isEncrypted||pages<1||pages>100)throw Error('Use an unencrypted PDF with 1–100 pages.');
 const visited=new Set();const blocked=new Set(['JavaScript','JS','OpenAction','AA','Launch','EmbeddedFiles','EmbeddedFile','XFA','RichMedia','SubmitForm','ImportData','GoToR','Sound','Movie','RichMediaContent']);
 function inspect(object:any){if(!object||visited.has(object))return;visited.add(object);if(object instanceof PDFDict){for(const [key,value] of object.entries()){if(blocked.has(key.decodeText())||(value instanceof PDFName&&blocked.has(value.decodeText())))throw Error('PDFs with scripts, embedded attachments or active actions are not accepted. Export a plain PDF.');if(key.decodeText()==='URI'&&typeof value.decodeText==='function'&&/^(javascript|data|file|vbscript):/i.test(value.decodeText().trim()))throw Error('PDFs with scripts, embedded attachments or active actions are not accepted. Export a plain PDF.');inspect(value);}}else if(object instanceof PDFArray){for(let i=0;i<object.size();i++)inspect(object.get(i));}else if(object.dict)inspect(object.dict);}
 for(const [,object] of pdf.context.enumerateIndirectObjects())inspect(object);
 return {pages,sha256:await hashBytes(bytes)};
}
async function boundedRequest(req:Request){
 const length=Number(req.headers.get('content-length')||0);if(length>MAX_BODY)throw Error('Upload a complete PDF no larger than 5 MB.');
 const reader=req.body?.getReader();if(!reader)throw Error('Choose a PDF file.');const chunks:Uint8Array[]=[];let total=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>MAX_BODY){await reader.cancel();throw Error('Upload a complete PDF no larger than 5 MB.');}chunks.push(value);}}finally{reader.releaseLock();}
 const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return new Request(req.url,{method:'POST',headers:{'content-type':req.headers.get('content-type')||''},body:bytes});
}
export async function uploadPDF(req:Request){
 const user=await actor(req),binding=await role(user.id);if(binding.role!=='super_admin'||binding.tenant_id!==null)throw Error('Only the Service Provider administrator can upload documents.');
 const bounded=await boundedRequest(req);let form;try{form=await bounded.formData();}catch(_){throw Error('Choose a PDF file.');}
 const file=form.get('file'),id=String(form.get('request_id')||'');if(!(file instanceof File)||!/^\w{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id)||!id.match(/^[a-f0-9-]+$/i))throw Error('Choose a PDF file and retry the upload.');
 const bytes=new Uint8Array(await file.arrayBuffer()),verified=await validatePDF(bytes),path='documents/'+id.toLowerCase()+'.pdf';
 const store=admin.storage.from('iv-service-documents');
 const {error}=await store.upload(path,bytes,{contentType:'application/pdf',cacheControl:'3600',upsert:false});
 if(error){
  if(!['409','400'].includes(String(error.statusCode)))throw Error('Private PDF upload failed. Retry with the same file.');
  const previous=await store.download(path);if(previous.error||!previous.data||previous.data.size>MAX_FILE||await hashBytes(new Uint8Array(await previous.data.arrayBuffer()))!==verified.sha256)throw Error('Upload request already belongs to another file. Choose the PDF again.');
 }
 const registered=await admin.rpc('iv_service_pdf_register',{p_actor:user.id,p_id:id.toLowerCase(),p_name:file.name.slice(0,180)||'Document.pdf',p_hash:verified.sha256,p_size:bytes.length,p_pages:verified.pages});
 if(registered.error){console.error('PDF registration failed',registered.error.code||'unknown');throw Error('PDF uploaded but verification could not be recorded. Retry the same file.');}
 return {file:registered.data};
}
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'',headers={'Content-Type':'application/json','Vary':'Origin',...(origins.has(origin)?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'}:{})};
 if(origin&&!origins.has(origin))return new Response(JSON.stringify({error:'Origin denied.'}),{status:403,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return new Response(JSON.stringify({error:'Use POST.'}),{status:405,headers});
 try{return new Response(JSON.stringify(await uploadPDF(req)),{headers});}catch(error){const message=error instanceof Error?error.message:'PDF upload failed.';const safe=/^(Upload |The PDF |Use an unencrypted |PDFs with |Choose a PDF |Only the Service Provider |Private PDF |PDF uploaded |Upload request |Sign in required\.|Not authorized\.)/.test(message)?message:'PDF upload failed. Contact the Service Provider.';return new Response(JSON.stringify({error:safe}),{status:400,headers});}
});
