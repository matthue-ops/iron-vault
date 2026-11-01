import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.49.8';
export const site=(Deno.env.get('APP_URL')||'https://ironvaultph.vercel.app').replace(/\/$/,'');
const originSet=new Set((Deno.env.get('CORS_ORIGINS')||site).split(',').map(x=>new URL(x.trim()).origin));
const url=Deno.env.get('SUPABASE_URL')!;
const key=Deno.env.get('SUPABASE_ANON_KEY')!;
export const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{autoRefreshToken:false,persistSession:false}});
export function publicClient(){return createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});}
export async function rpc(name:string,args:Record<string,unknown>){const {data,error}=await admin.rpc(name,args);if(error)throw Error('Operation could not be completed.');return data;}
export async function actor(req:Request){
 const match=/^Bearer\s+(.+)$/i.exec(req.headers.get('authorization')||'');
 if(!match)throw Error('Sign in required.');
 const {data,error}=await publicClient().auth.getUser(match[1]);if(error||!data.user)throw Error('Sign in required.');return data.user;
}
export async function role(user:string){const {data,error}=await admin.from('iv_user_roles').select('role,tenant_id,member_id,enabled').eq('user_id',user).single();if(error||!data?.enabled)throw Error('Not authorized.');return data;}
export async function digest(value:string){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))),n=>n.toString(16).padStart(2,'0')).join('');}
export async function limit(bucket:string,max=15,seconds=600){if(!await rpc('iv_auth_rate_limit',{p_bucket:await digest(bucket),p_limit:max,p_seconds:seconds}))throw Error('Too many attempts. Please try later.');}
export function mailReady(){return Boolean((Deno.env.get('BREVO_API_KEY')&&(Deno.env.get('SMTP_FROM')||Deno.env.get('MAIL_FROM')))||(Deno.env.get('SMTP_USER')&&Deno.env.get('SMTP_PASSWORD')&&Deno.env.get('SMTP_FROM')));}
export async function sendMail(to:string,subject:string,link:string){
 if(!mailReady())throw Error('Email delivery is not configured.');
 const from=Deno.env.get('SMTP_FROM')||Deno.env.get('MAIL_FROM');if(!from)throw Error('Sender is not configured.');
 const text=subject+'\n\nOpen this link in your browser:\n'+link+'\n\nIf you did not request this, ignore this email.';
 if(Deno.env.get('BREVO_API_KEY')){
  const response=await fetch('https://api.brevo.com/v3/smtp/email',{method:'POST',headers:{'api-key':Deno.env.get('BREVO_API_KEY')!,'Content-Type':'application/json'},body:JSON.stringify({sender:{email:from,name:'Iron Vault'},to:[{email:to}],subject,textContent:text})});
  if(!response.ok)throw Error('Email delivery failed.');
 }else{
  const {default:nodemailer}=await import('npm:nodemailer@6.10.1');
  const port=Number(Deno.env.get('SMTP_PORT')||587);
  const transport=nodemailer.createTransport({host:Deno.env.get('SMTP_HOST')||'smtp-relay.brevo.com',port,secure:port===465,
   requireTLS:true,tls:{rejectUnauthorized:true},auth:{user:Deno.env.get('SMTP_USER'),pass:Deno.env.get('SMTP_PASSWORD')}});
  try{await transport.sendMail({from,to,subject,text});}finally{transport.close();}
 }
}
export async function sendVerification(userId:string){
 const info=await rpc('iv_branch_account_details',{p_user:userId});if(!info)throw Error('Account unavailable.');
 const token=crypto.randomUUID()+crypto.randomUUID();const hash=await digest(token);
 await rpc('iv_queue_email_action',{p_user:userId,p_hash:hash,p_kind:'verify',p_group:crypto.randomUUID(),p_new_email:null});
 await sendMail(info.email,'Verify your '+String(info.gym_name).replace(/[\r\n]/g,' ')+' gym account',site+'/gym/memberlogin.html?key='+encodeURIComponent(info.token)+'#iv_verify='+token);
}
export function serve(handler:(req:Request,input:any)=>Promise<unknown>){
 Deno.serve(async req=>{
  const origin=req.headers.get('origin');const allowed=!origin||originSet.has(origin);
  const headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',
   'Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
  if(origin&&allowed)headers['Access-Control-Allow-Origin']=origin;
  if(!allowed)return new Response(JSON.stringify({error:'Origin not allowed.'}),{status:403,headers});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return new Response(JSON.stringify({error:'POST required.'}),{status:405,headers});
  try{
   if(Number(req.headers.get('content-length')||0)>1000000)throw Error('Request too large.');
   const reader=req.body?.getReader();let bytes=0;const chunks:Uint8Array[]=[];
   if(reader){while(true){const part=await reader.read();if(part.done)break;bytes+=part.value.length;if(bytes>1000000){await reader.cancel();throw Error('Request too large.');}chunks.push(part.value);}}
   const raw=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){raw.set(chunk,offset);offset+=chunk.length;}const text=new TextDecoder().decode(raw);
   const input=JSON.parse(text);if(!input||typeof input!=='object'||Array.isArray(input))throw Error('Invalid request.');
   return new Response(JSON.stringify(await handler(req,input)),{status:200,headers});
  }catch(error){
   // Never echo Supabase provider errors, account aliases, tokens or credentials.
   const message=error instanceof Error?error.message:'Request failed.';
   const safe=/^(Sign in required\.|Not authorized\.|Too many attempts\. Please try later\.|Email delivery is not configured\.|Sender is not configured\.|Email delivery failed\.|Invalid request\.|Request too large\.)$/.test(message)?message:'Request could not be completed. Check your details or contact the gym.';
   const status=message==='Sign in required.'?401:message==='Not authorized.'?403:message.startsWith('Too many')?429:message.includes('delivery')||message.includes('configured')?503:400;
   return new Response(JSON.stringify({error:safe}),{status,headers});
  }
 });
}
