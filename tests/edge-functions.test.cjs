const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs'),vm=require('node:vm');const {stripTypeScriptTypes}=require('node:module');
function load(file,injected={}){
 const context={Error,console:{error(){}},crypto,TextEncoder,TextDecoder,Uint8Array,URL,Request,Response,Set,JSON,Date,...injected};vm.createContext(context);
 const source=stripTypeScriptTypes(fs.readFileSync(file,'utf8'),{mode:'strip'}).replace(/^import .*?;\s*$/gm,'').replace(/^export /gm,'');
 vm.runInContext(source,context,{filename:file});return context;
}
function runtime(){
 const calls=[];const env={SUPABASE_URL:'https://project.example.invalid',SUPABASE_ANON_KEY:'test-public',SUPABASE_SERVICE_ROLE_KEY:'test-service',APP_URL:'https://app.example.invalid'};
 let handler;const client={rpc:async(name,args)=>{calls.push({name,args});return{data:true}},auth:{getUser:async()=>({data:{user:{id:'actor'}}})},from:()=>({select(){return this},eq(){return this},single:async()=>({data:{role:'owner',tenant_id:'gym',enabled:true}})})};
 const c=load('supabase/functions/_shared/runtime.ts',{createClient:()=>client,Deno:{env:{get:key=>env[key]},serve:fn=>{handler=fn}},fetch:async()=>new Response('',{status:202})});
 return {c,env,client,calls,handler:()=>handler};
}
test('Edge preflight allows only configured origins and performs no authenticated operation',async()=>{
 const f=runtime();let entered=0;f.c.serve(async()=>{entered++;return{ok:true}});
 const allowed=await f.handler()(new Request('https://edge.example.invalid',{method:'OPTIONS',headers:{origin:'https://app.example.invalid'}}));
 assert.equal(allowed.status,204);assert.equal(allowed.headers.get('access-control-allow-origin'),'https://app.example.invalid');
 const denied=await f.handler()(new Request('https://edge.example.invalid',{method:'POST',headers:{origin:'https://evil.example.invalid'},body:'{}'}));
 assert.equal(denied.status,403);assert.equal(entered,0);
});
test('Edge actor verification uses Supabase getUser and missing tokens never authorize',async()=>{
 const f=runtime();await assert.rejects(f.c.actor(new Request('https://edge.example.invalid')),/Sign in/);
 assert.equal((await f.c.actor(new Request('https://edge.example.invalid',{headers:{authorization:'Bearer test-only'}}))).id,'actor');
 f.client.auth.getUser=async()=>({data:{user:null},error:{message:'Expired'}});await assert.rejects(f.c.actor(new Request('https://edge.example.invalid',{headers:{authorization:'Bearer test-only'}})),/Sign in/);
});
test('disabled staff and unmapped users cannot use service-role provisioning authority',async()=>{
 const f=runtime();f.client.from=()=>({select(){return this},eq(){return this},single:async()=>({data:{role:'staff',enabled:false}})});
 await assert.rejects(f.c.role('actor'),/Not authorized/);
});
test('public gateway hides backend secrets and returns useful authentication status codes',async()=>{
 const f=runtime();f.c.serve(async()=>{throw Error('Internal service credentials must not leak')});
 let result=await f.handler()(new Request('https://edge.example.invalid',{method:'POST',body:'{}'}));assert.equal((await result.text()).includes('credentials'),false);
 f.c.serve(async()=>{throw Error('Sign in required.')});result=await f.handler()(new Request('https://edge.example.invalid',{method:'POST',body:'{}'}));assert.equal(result.status,401);
});
test('rate limits are persisted by a service-only RPC with hashed identifiers',async()=>{
 const f=runtime();await f.c.limit('signin:contact@example.invalid');assert.equal(f.calls[0].name,'iv_auth_rate_limit');assert.equal(f.calls[0].args.p_bucket.includes('@'),false);
 f.client.rpc=async()=>({data:false});await assert.rejects(f.c.limit('same'),/Too many/);
});
test('provisioning sends protected app metadata, never old signup flags, and retains partial jobs on mail failure',async()=>{
 let created=0;let found=null;const calls=[];
 const client={auth:{admin:{createUser:async input=>{created++;calls.push(input);found='auth-id';return{data:{user:{id:found}}}},deleteUser:()=>{throw Error('No destructive cleanup permitted')}}}};
 let deliveryFails=true;
 const c=load('supabase/functions/_shared/provision.ts',{admin:client,publicClient:()=>({auth:{signInWithPassword:async()=>({error:null})}}),
  actor:async()=>({id:'operator'}),role:async()=>({role:'owner',tenant_id:'gym'}),digest:async value=>{calls.push({digest:value});return'a'.repeat(64)},mailReady:()=>true,limit:async()=>{},
  rpc:async(name,args)=>{calls.push({name,args});return name==='iv_find_created_account'?found:name==='iv_finish_branch_account'?{ok:true,member_id:'member'}:{}},
  sendVerification:async()=>{if(deliveryFails)throw Error('Mail failed')}});
 const input={mode:'staff',request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'Member',email:'same@example.invalid',password:'test-only-password'};
 await assert.rejects(c.provision(new Request('https://edge.example.invalid'),input,'tenant'),/Mail failed/);
 deliveryFails=false;await c.provision(new Request('https://edge.example.invalid'),input,'tenant');assert.equal(created,1);
 const attributes=calls.find(x=>x.app_metadata);assert.equal(attributes.app_metadata.iv_provision_request,input.request_id);assert.equal(attributes.user_metadata.iv_member_signup,undefined);
 const prepare=calls.find(x=>x.name==='iv_prepare_branch_account');assert.equal(JSON.stringify(prepare.args.p_payload).includes(input.password),false);
});
test('branch alias input separates tenants, roles and provisioning requests',async()=>{
 const source=fs.readFileSync('supabase/functions/_shared/provision.ts','utf8');assert.match(source,/tenant\+'\\0'\+accountRole\+'\\0'\+email\+'\\0'\+request/);
});

test('legacy identifier rotation keeps the same Auth ID and never changes its password',async()=>{
 let user={id:'existing',email:'old@example.invalid',app_metadata:{provider:'email'}},fail=true;const updates=[];
 const c=load('supabase/functions/_shared/identity.ts',{digest:async()=> 'a'.repeat(64),admin:{auth:{admin:{
  getUserById:async id=>{assert.equal(id,'existing');return{data:{user}}},
  updateUserById:async(id,patch)=>{updates.push({id,patch});user={...user,...patch};return{data:{user}}},
  generateLink:async()=>({error:fail?{message:'Temporary failure'}:null})}}}});
 await assert.rejects(c.ensurePrivateIdentifier('existing'));
 assert.equal(user.app_metadata.iv_alias_rotation_pending,true);
 const alias=user.email;fail=false;assert.equal(await c.ensurePrivateIdentifier('existing'),alias);
 assert.equal(user.app_metadata.iv_alias_rotation_pending,false);assert.ok(updates.every(x=>x.id==='existing'&&!('password' in x.patch)));
});

test('completed provisioning retry never creates another Auth account or resets its credentials',async()=>{
 let finished=0;
 const c=load('supabase/functions/_shared/provision.ts',{admin:{auth:{admin:{createUser:()=>{throw Error('Must not recreate')}}}},
  publicClient:()=>({auth:{signInWithPassword:()=>{throw Error('Completed job must not require an old creation password')}}}),
  actor:async()=>({id:'owner'}),role:async()=>({role:'owner',tenant_id:'gym'}),digest:async()=> 'a'.repeat(64),mailReady:()=>true,limit:async()=>{},sendVerification:async()=>{},
  rpc:async(name)=>{if(name==='iv_prepare_branch_account')return{completed_user:'existing'};if(name==='iv_finish_branch_account'){finished++;return{ok:true,user_id:'existing',member_id:'member'}}throw Error('Unexpected '+name)}});
 const result=await c.provision(new Request('https://edge.example.invalid'),{request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'Member',email:'member@example.invalid',password:'test-only-password'},'member');
 assert.equal(result.member_id,'member');assert.equal(finished,1);
});
function contactFixture(verified=true,tenant='gym'){
 const queues=[],mail=[];const hash=v=>require('node:crypto').createHash('sha256').update(v).digest('hex');
 const c=load('supabase/functions/_shared/contact.ts',{ensurePrivateIdentifier:async()=>{},mailReady:()=>true,actor:async()=>({id:'owner'}),role:async()=>({role:'owner',tenant_id:'gym'}),
  admin:{from:()=>({select(){return this},eq(){return this},single:async()=>({data:{status:'ACTIVE'}})})},digest:async v=>hash(v),limit:async()=>{},site:'https://app.example.invalid',
  rpc:async(name,args)=>{if(name==='iv_branch_account_details')return{tenant_id:tenant,verified,email:'old@example.invalid',token:'gym-token'};queues.push(args);return null},
  sendMail:async(to,subject,link)=>{mail.push({to,subject,link})}});
 return {c,queues,mail};
}
test('verified contact correction requires separate proofs to old and new real addresses',async()=>{
 const f=contactFixture();await f.c.changeContact(new Request('https://edge.example.invalid'),{new_email:'new@example.invalid'},'member');
 assert.deepEqual(f.mail.map(x=>x.to),['old@example.invalid','new@example.invalid']);assert.equal(f.queues[0].p_group,f.queues[1].p_group);assert.notEqual(f.queues[0].p_hash,f.queues[1].p_hash);
 assert.ok(f.queues.every(x=>!JSON.stringify(x).includes('iv_verify=')));
});
test('an administrator can correct an unverified address using new-address proof without an impossible old-mailbox requirement',async()=>{
 const f=contactFixture(false);await f.c.changeContact(new Request('https://edge.example.invalid'),{new_email:'correct@example.invalid'},'member');
 assert.equal(f.mail.length,1);assert.equal(f.mail[0].to,'correct@example.invalid');assert.equal(f.queues[0].p_kind,'correct_unverified');
});
test('a gym owner cannot correct a different tenant contact',async()=>{
 const f=contactFixture(true,'other-gym');await assert.rejects(f.c.changeContact(new Request('https://edge.example.invalid'),{new_email:'new@example.invalid'},'member'),/Not authorized/);assert.equal(f.mail.length,0);assert.equal(f.queues.length,0);
});

test('RPC diagnostics identify the failed operation without logging private arguments or provider text',async()=>{
 const f=runtime(),logs=[];f.c.console.error=(...args)=>logs.push(args);
 f.client.rpc=async()=>({error:{code:'23505',message:'private-contact@example.invalid',details:'secret-token'}});
 await assert.rejects(f.c.rpc('iv_prepare_branch_account',{p_email:'private-contact@example.invalid',password:'secret-password'}),/Operation could not/);
 assert.deepEqual(logs,[['Iron Vault RPC failed','iv_prepare_branch_account','23505']]);
 f.client.rpc=async()=>({error:{code:'secret@email.invalid'}});
 await assert.rejects(f.c.rpc('iv_finish_branch_account',{}));assert.equal(logs[1][2],'unknown');
});

test('member signup succeeds without SMTP or confirmation and retains gym approval messaging',async()=>{
 const c=load('supabase/functions/_shared/provision.ts',{admin:{auth:{admin:{createUser:async()=>({data:{user:{id:'member-auth'}}})}}},
 digest:async()=> 'a'.repeat(64),mailReady:()=>false,limit:async()=>{},
 rpc:async name=>name==='iv_prepare_branch_account'?{}:name==='iv_find_created_account'?null:{ok:true},
 sendVerification:async()=>{throw Error('Member signup must not depend on mail')}});
 const result=await c.provision(new Request('https://edge.example.invalid'),{request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'New Member',email:'test@example.invalid',password:'test-only-password'},'member',true);
 assert.equal(result.ok,true);assert.match(result.message,/without email confirmation/);assert.match(result.message,/gym approval/);
});
