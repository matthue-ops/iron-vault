/* Scheduled server worker. Never invoked by a page; no financial or access decisions depend on mail. */
export type Job={id:string;token:string;request_id:string;tenant_id:string;submitted_at:string;day:string};
export async function runReminders(deps:{claim:()=>Promise<Job[]>;send:(job:Job)=>Promise<void>;finish:(job:Job,ok:boolean)=>Promise<void>}){
 const jobs=await deps.claim();let sent=0,uncertain=0;
 await Promise.all(jobs.map(async job=>{let ok=false;try{await deps.send(job);ok=true;sent++;}catch{uncertain++;}
  // Do not automatically resend an ambiguous delivery. A later daily job is independent.
  await deps.finish(job,ok);
 }));
 return {claimed:jobs.length,sent,needs_review:uncertain};
}
async function sameSecret(value:string,expected:string){const hash=async(s:string)=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)));const [a,b]=await Promise.all([hash(value),hash(expected)]);let different=0;for(let i=0;i<a.length;i++)different|=a[i]^b[i];return different===0;}
export async function handler(req:Request){
 const headers={'Content-Type':'application/json','Cache-Control':'no-store'};
 const response=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(req.method!=='POST')return response({error:'POST required'},405);
 if(req.headers.has('origin'))return response({error:'Scheduled worker only'},403);
 const secret=Deno.env.get('REMINDER_JOB_SECRET')||'';
 if(secret.length<32)return response({error:'Reminder worker is not configured'},503);
 if(!await sameSecret(req.headers.get('x-reminder-secret')||'',secret))return response({error:'Not authorized'},401);
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),mailKey=Deno.env.get('BREVO_API_KEY'),from=Deno.env.get('SMTP_FROM')||Deno.env.get('MAIL_FROM'),to=Deno.env.get('PROVIDER_NOTIFICATION_EMAIL'),app=Deno.env.get('APP_URL');
 if(!url||!key||!mailKey||!from||!to||!app)return response({error:'Reminder mail settings are incomplete'},503);
 const mailAddress=/^[^\s@]+@[^\s@]+\.[^\s@]+$/;if(!mailAddress.test(to)||!mailAddress.test(from))return response({error:'Invalid mail configuration'},503);
 let link:string;try{const parsed=new URL(app);if(parsed.protocol!=='https:')throw Error();link=parsed.origin+'/gym/';}catch{return response({error:'APP_URL must be HTTPS'},503);}
 const rpc=async(args:Record<string,unknown>)=>{const r=await fetch(url+'/rest/v1/rpc/iv_provider_reminder_jobs',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Reminder job storage unavailable');return r.json();};
 try{return response(await runReminders({claim:()=>rpc({p_action:'claim'}),send:async job=>{
  const r=await fetch('https://api.brevo.com/v3/smtp/email',{method:'POST',headers:{'api-key':mailKey,'Content-Type':'application/json'},body:JSON.stringify({sender:{email:from,name:'Iron Vault'},to:[{email:to}],subject:'Iron Vault: payment verification overdue',headers:{idempotencyKey:job.id},textContent:'A gym payment is awaiting your verification.\n\nGym reference: '+job.tenant_id+'\nRequest: '+job.request_id+'\nSubmitted: '+job.submitted_at+'\nReminder date (Philippine time): '+job.day+'\n\nReview payment and approve, return for correction or reject it in the Provider console:\n'+link+'\n\nDo not approve without verifying payment. Email delivery does not control gym access.'}),signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Mail delivery uncertain');
 },finish:(job,ok)=>rpc({p_action:ok?'complete':'uncertain',p_id:job.id,p_token:job.token})}));}catch{return response({error:'Reminder processing incomplete; inspect durable job states before retrying'},503);}
}
Deno.serve(handler);
