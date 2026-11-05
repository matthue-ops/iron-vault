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
test('owner provisioning sends protected metadata, needs no mail and safely retries a partial job',async()=>{
 let created=0;let found=null;const calls=[];
 const client={auth:{admin:{createUser:async input=>{created++;calls.push(input);found='auth-id';return{data:{user:{id:found}}}},deleteUser:()=>{throw Error('No destructive cleanup permitted')}}}};
 let deliveryCalls=0;
 const c=load('supabase/functions/_shared/provision.ts',{admin:client,publicClient:()=>({auth:{signInWithPassword:async()=>({error:null})}}),
  actor:async()=>({id:'operator'}),role:async()=>({role:'super_admin',tenant_id:null}),digest:async value=>{calls.push({digest:value});return'a'.repeat(64)},mailReady:()=>false,limit:async()=>{},
  rpc:async(name,args)=>{calls.push({name,args});return name==='iv_find_created_account'?found:name==='iv_finish_branch_account'?{ok:true,member_id:'member'}:{}},
  sendVerification:async()=>{deliveryCalls++;throw Error('Mail must not run')}});
 const input={mode:'create',request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'Member',email:'same@example.invalid',password:'test-only-password'};
 const result=await c.provision(new Request('https://edge.example.invalid'),input,'tenant');
 assert.match(result.message,/Sign in now/);assert.match(result.message,/working inbox/);assert.equal(deliveryCalls,0);
 await c.provision(new Request('https://edge.example.invalid'),input,'tenant');assert.equal(created,1);
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
function contactFixture(verified=true,tenant='gym',accountRole='member',contactEmail='old@example.invalid'){
 const queues=[],mail=[];const hash=v=>require('node:crypto').createHash('sha256').update(v).digest('hex');
 const c=load('supabase/functions/_shared/contact.ts',{ensurePrivateIdentifier:async()=> 'private@accounts.ironvault.invalid',mailReady:()=>true,actor:async()=>({id:'owner'}),role:async()=>({role:'owner',tenant_id:'gym'}),
  admin:{auth:{admin:{generateLink:async()=>({data:{properties:{hashed_token:'replacement-not-mailed'}},error:null})}},from:()=>({select(){return this},eq(){return this},single:async()=>({data:{status:'ACTIVE'}})})},digest:async v=>hash(v),limit:async()=>{},site:'https://app.example.invalid',
  rpc:async(name,args)=>{if(name==='iv_branch_account_details')return{tenant_id:tenant,role:accountRole,verified,email:contactEmail,token:'gym-token'};queues.push(args);return null},
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
 const result=await c.provision(new Request('https://edge.example.invalid'),{request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'New Member',email:'test@example.invalid',password:'test-only-password',legal:{accepted:true,platform_version:'12345678-1234-4234-8234-123456789abc',gym_version:'22345678-1234-4234-8234-123456789abc'}},'member',true);
 assert.equal(result.ok,true);assert.match(result.message,/without email confirmation/);assert.match(result.message,/gym approval/);
});

function purgeFixture({binding={role:'super_admin',tenant_id:null},passwordOk=true,failDelete=false,sharedAccount=null}={}){
 const calls=[],deleted=[],pending=['account-a','account-b'];let handler,retained=0;
 const c=load('supabase/functions/iv-purge-tenant/index.ts',{
  serve:fn=>{handler=fn},actor:async()=>({id:'master',email:'master@example.invalid'}),role:async()=>binding,limit:async()=>{},
  publicClient:()=>({auth:{signInWithPassword:async()=>passwordOk?{data:{user:{id:'master'}}}:{data:{},error:{message:'Denied'}}}}),
  admin:{auth:{admin:{deleteUser:async id=>{deleted.push(id);return failDelete&&id==='account-b'?{error:{status:500,code:'unexpected_failure'}}:{error:null}}}}},
  rpc:async(name,args)=>{calls.push(args);assert.equal(name,'iv_tenant_purge_control');assert.equal(args.p_actor,'master');
   if(args.p_action==='preview')return{tenant_id:'gym',members:2};
   if(args.p_action==='check')return{eligible:args.p_user!==sharedAccount,shared:args.p_user===sharedAccount};
   if(args.p_action==='retain'){pending.splice(pending.indexOf(args.p_user),1);retained++;}
   if(args.p_action==='ack'){pending.splice(pending.indexOf(args.p_user),1);}
   if(args.p_action==='finish')return{complete:true,retained_accounts:retained};
   return{pending_users:[...pending],remaining:pending.length};}
 });
 return{run:body=>handler(new Request('https://edge.example.invalid'),body),calls,deleted,pending,setDeleteFailure:value=>{failDelete=value}};
}
const purgeInput={action:'purge',tenant_id:'gym',request_id:'12345678-1234-4234-8234-123456789abc',confirmation:'PURGE gym',password:'private-password',review:{members:2}};
test('tenant purge denies non-global administrators before any data or Auth action',async()=>{
 for(const binding of [{role:'owner',tenant_id:'gym'},{role:'staff',tenant_id:'gym'},{role:'member',tenant_id:'gym'},{role:'super_admin',tenant_id:'gym'}]){
  const f=purgeFixture({binding});await assert.rejects(f.run(purgeInput),/Not authorized/);assert.equal(f.calls.length,0);assert.equal(f.deleted.length,0);
 }
});
test('tenant purge requires exact confirmation and fresh Master password proof',async()=>{
 const f=purgeFixture();await assert.rejects(f.run({...purgeInput,confirmation:'gym'}),/Invalid request/);assert.equal(f.calls.length,0);
 const bad=purgeFixture({passwordOk:false});await assert.rejects(bad.run(purgeInput),/Sign in required/);assert.equal(bad.calls.length,0);assert.equal(bad.deleted.length,0);
});
test('purge preview performs no deletion and successful purge acknowledges every Auth deletion before finishing',async()=>{
 const f=purgeFixture();await f.run({action:'preview',tenant_id:'gym'});assert.equal(f.deleted.length,0);
 const result=await f.run(purgeInput);assert.equal(result.complete,true);assert.deepEqual(f.deleted,['account-a','account-b']);
 assert.deepEqual(f.calls.filter(x=>x.p_action==='ack').map(x=>x.p_user),f.deleted);
 assert.equal(f.calls.at(-1).p_action,'finish');assert.equal(JSON.stringify(f.calls).includes('private-password'),false);
});
test('failed Auth cleanup leaves a resumable purge and does not claim completion',async()=>{
 const f=purgeFixture({failDelete:true});const result=await f.run(purgeInput);
 assert.equal(result.complete,false);assert.equal(result.remaining,1);assert.equal(result.failed,1);
 assert.equal(f.calls.some(x=>x.p_action==='finish'),false);assert.deepEqual(f.pending,['account-b']);
 f.setDeleteFailure(false);assert.equal((await f.run({...purgeInput,action:'resume'})).complete,true);
 assert.equal(f.calls.filter(x=>x.p_action==='start').length,1);
});

test('purge preserves accounts still linked elsewhere instead of deleting their Auth identity',async()=>{
 const f=purgeFixture({sharedAccount:'account-a'});const result=await f.run(purgeInput);
 assert.equal(result.complete,true);assert.equal(result.retained_accounts,1);assert.deepEqual(f.deleted,['account-b']);
 assert.equal(f.calls.some(x=>x.p_action==='retain'&&x.p_user==='account-a'),true);
});

test('owner-created staff provisioning is independent of SMTP and sends no activation email',async()=>{
 const c=load('supabase/functions/_shared/provision.ts',{admin:{auth:{admin:{createUser:async()=>({data:{user:{id:'staff-auth'}}})}}},
 actor:async()=>({id:'owner'}),role:async()=>({role:'owner',tenant_id:'gym'}),digest:async()=> 'a'.repeat(64),mailReady:()=>false,limit:async()=>{},
 rpc:async name=>name==='iv_prepare_branch_account'?{}:name==='iv_find_created_account'?null:{ok:true},sendVerification:async()=>{throw Error('No staff email gate')}});
 const result=await c.provision(new Request('https://edge.example.invalid'),{mode:'staff',request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'Staff',email:'staff@example.invalid',password:'test-only-password'},'tenant');
 assert.equal(result.ok,true);assert.match(result.message,/Sign in now/);
});
test('owner can correct unverified staff contact without email delivery but verified staff still need both proofs',async()=>{
 const f=contactFixture(false,'gym','staff');f.c.mailReady=()=>false;
 const result=await f.c.changeContact(new Request('https://edge.example.invalid'),{new_email:'new@example.invalid'},'staff');
 assert.equal(result.pending,false);assert.equal(f.mail.length,0);assert.equal(f.queues[0].p_user,'staff');assert.equal(f.queues[0].p_actor,'owner');
 const verified=contactFixture(true,'gym','staff');await verified.c.changeContact(new Request('https://edge.example.invalid'),{new_email:'new@example.invalid'},'staff');assert.equal(verified.mail.length,2);
 const other=contactFixture(false,'other-gym','staff');await assert.rejects(other.c.changeContact(new Request('https://edge.example.invalid'),{new_email:'new@example.invalid'},'staff'),/Not authorized/);
});

test('branch sign-in accepts short member codes only in the member portal and keeps private Auth aliases internal',async()=>{
 let handler;const calls=[];
 load('supabase/functions/iv-branch-auth/index.ts',{serve:fn=>{handler=fn},limit:async()=>{},
 admin:{from:()=>({select(){return this},eq(){return this},single:async()=>({data:{id:'gym-a',status:'ACTIVE',token:'portal-token'}})})},
 rpc:async(name,args)=>{calls.push({name,args});return name==='iv_branch_identity'?[{user_id:'member-auth'}]:{auth_email:'private@accounts.ironvault.invalid'};},
 publicClient:()=>({auth:{signInWithPassword:async input=>{assert.equal(input.email,'private@accounts.ironvault.invalid');return{data:{session:{access_token:'test-access',refresh_token:'test-refresh'}}};}}}),ensurePrivateIdentifier:async()=>{}});
 const result=await handler(new Request('https://edge.example.invalid'),{action:'signin',gym_token:'portal-token',portal:'member',email:'MEM-0001',password:'private-password'});
 assert.equal(result.session.access_token,'test-access');assert.equal(calls[0].args.p_tenant,'gym-a');assert.equal(calls[0].args.p_email,'mem-0001');
 assert.equal(JSON.stringify(result).includes('accounts.ironvault'),false);
 await assert.rejects(handler(new Request('https://edge.example.invalid'),{action:'signin',gym_token:'portal-token',portal:'admin',email:'MEM-0001',password:'private-password'}),/Invalid request/);
});

function ownerSigninFixture({status='ACTIVE',identity=true,passwordOk=true}={}){
 let handler;const calls=[];
 load('supabase/functions/iv-branch-auth/index.ts',{serve:fn=>{handler=fn},limit:async()=>{},
 admin:{from:()=>({select(){return this},eq(key,value){calls.push({key,value});return this},single:async()=>({data:{id:'gym-a',status,token:'gym-token'}})})},
 rpc:async(name,args)=>{calls.push({name,args});return name==='iv_branch_identity'?(identity?[{user_id:'owner-auth',role:'owner'}]:[]):{auth_email:'private@accounts.ironvault.invalid',verified:false};},
 publicClient:()=>({auth:{signInWithPassword:async input=>{calls.push({passwordCheck:input});return passwordOk?{data:{session:{access_token:'test-access',refresh_token:'test-refresh'}}}:{data:{},error:{message:'Bad password'}};}}}),
 ensurePrivateIdentifier:async id=>{calls.push({rotate:id})}});
 return {calls,run:input=>handler(new Request('https://edge.example.invalid'),{action:'signin',gym_token:'gym-token',portal:'admin',email:'temporary@example.invalid',password:'test-password',...input})};
}
test('unconfirmed owner signs in by contact and password through a tenant-scoped enabled identity',async()=>{
 const f=ownerSigninFixture();const result=await f.run();assert.equal(result.session.access_token,'test-access');
 const lookup=f.calls.find(x=>x.name==='iv_branch_identity');assert.equal(lookup.args.p_tenant,'gym-a');
 assert.deepEqual(Array.from(lookup.args.p_roles),['owner','staff']);assert.equal(lookup.args.p_email,'temporary@example.invalid');
 assert.equal(f.calls.find(x=>x.passwordCheck).passwordCheck.password,'test-password');
 assert.equal(JSON.stringify(result).includes('private@'),false);
});
test('owner sign-in still rejects suspended/incomplete gyms, revoked or cross-tenant identities and wrong passwords',async()=>{
 for(const status of ['SUSPENDED','PROVISIONING','INACTIVE']){
  const f=ownerSigninFixture({status});await assert.rejects(f.run(),/Invalid request/);assert.equal(f.calls.some(x=>x.passwordCheck),false);
 }
 const missing=ownerSigninFixture({identity:false});await assert.rejects(missing.run(),/Invalid request/);assert.equal(missing.calls.some(x=>x.passwordCheck),false);
 const bad=ownerSigninFixture({passwordOk:false});await assert.rejects(bad.run(),/Invalid request/);assert.equal(bad.calls.some(x=>x.rotate),false);
 const invalid=ownerSigninFixture();await assert.rejects(invalid.run({email:'not-an-email'}),/Invalid request/);assert.equal(invalid.calls.some(x=>x.passwordCheck),false);
});
test('owner password recovery sends proof to the contact inbox and never returns a recovery token',async()=>{
 let handler;const sent=[];
 load('supabase/functions/iv-branch-auth/index.ts',{serve:fn=>{handler=fn},limit:async()=>{},mailReady:()=>true,site:'https://app.example.invalid',
 admin:{from:()=>({select(){return this},eq(){return this},single:async()=>({data:{id:'gym-a',status:'ACTIVE',token:'gym-token'}})}),
 auth:{admin:{generateLink:async()=>({data:{properties:{hashed_token:'inbox-proof'}}})}}},
 rpc:async name=>name==='iv_branch_identity'?[{user_id:'owner-auth'}]:{email:'temporary@example.invalid',gym_name:'Gym A'},
 ensurePrivateIdentifier:async()=> 'private@accounts.ironvault.invalid',sendMail:async(...args)=>sent.push(args)});
 const result=await handler(new Request('https://edge.example.invalid'),{action:'recovery',gym_token:'gym-token',portal:'admin',email:'temporary@example.invalid'});
 assert.equal(sent.length,1);assert.equal(sent[0][0],'temporary@example.invalid');assert.match(sent[0][2],/#iv_recovery=inbox-proof/);
 assert.equal(JSON.stringify(result).includes('inbox-proof'),false);assert.equal(result.session,undefined);
});

test('self-registration rejects missing or false legal acceptance before creating or preparing an account',async()=>{
 let calls=0;const c=load('supabase/functions/_shared/provision.ts',{admin:{auth:{admin:{createUser:()=>{calls++;throw Error('Must not create');}}}},digest:async()=> 'a'.repeat(64),limit:async()=>{},rpc:async()=>{calls++;throw Error('Must not prepare');}});
 const input={request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'Member',email:'test@example.invalid',password:'test-only-password'};
 for(const legal of [undefined,{accepted:false},{accepted:true,platform_version:'invalid',gym_version:'invalid'}])await assert.rejects(c.provision(new Request('https://edge.example.invalid'),{...input,legal},'member',true),/Read and accept/);
 assert.equal(calls,0);
});
test('self-registration carries only the exact accepted version pair into the protected provisioning payload',async()=>{
 const calls=[];const c=load('supabase/functions/_shared/provision.ts',{admin:{auth:{admin:{createUser:async()=>({data:{user:{id:'member-auth'}}})}}},digest:async()=> 'a'.repeat(64),limit:async()=>{},rpc:async(name,args)=>{calls.push({name,args});return name==='iv_prepare_branch_account'?{}:name==='iv_find_created_account'?null:{ok:true};}});
 const legal={accepted:true,platform_version:'12345678-1234-4234-8234-123456789ABC',gym_version:'22345678-1234-4234-8234-123456789ABC',extra:'must not persist'};
 await c.provision(new Request('https://edge.example.invalid'),{request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'Member',email:'test@example.invalid',password:'test-only-password',legal},'member',true);
 const saved=calls.find(x=>x.name==='iv_prepare_branch_account').args.p_payload.legal;assert.equal(saved.accepted,true);assert.equal(saved.platform_version,legal.platform_version.toLowerCase());assert.equal(saved.gym_version,legal.gym_version.toLowerCase());assert.equal('extra' in saved,false);
});

function optionalContactProvision(binding={role:'owner',tenant_id:'gym'}){
 const calls=[];let created=0;
 const c=load('supabase/functions/_shared/provision.ts',{actor:async()=>({id:'operator'}),role:async()=>binding,
 admin:{auth:{admin:{createUser:async()=>{created++;return{data:{user:{id:'member-auth'}}}}}}},digest:async()=> 'a'.repeat(64),limit:async()=>{},
 rpc:async(name,args)=>{calls.push({name,args});return name==='iv_prepare_branch_account'?{}:name==='iv_find_created_account'?null:{ok:true,member_id:'member'};}});
 return{c,calls,created:()=>created};
}
const walkinInput={request_id:'12345678-1234-4234-8234-123456789abc',tenant_id:'gym',name:'Walk In',phone:'09999999999',email:'',password:'test-only-password'};
test('operator-created walk-in accepts no email and still creates password-backed Auth with private alias',async()=>{
 const f=optionalContactProvision();const result=await f.c.provision(new Request('https://edge.example.invalid'),walkinInput,'member');
 assert.equal(f.created(),1);const args=f.calls.find(c=>c.name==='iv_prepare_branch_account').args;assert.equal(args.p_email,null);assert.match(args.p_alias,/@accounts.ironvault.invalid$/);assert.equal(args.p_actor,'operator');assert.match(result.message,/Member ID and password/);
});
test('optional walk-in contact does not weaken passwords, real email validation or operator gym authority',async()=>{
 for(const changes of [{password:''},{password:'short'},{email:'not-an-email'}]){const f=optionalContactProvision();await assert.rejects(f.c.provision(new Request('https://edge.example.invalid'),{...walkinInput,...changes},'member'),/Invalid request/);assert.equal(f.created(),0);}
 for(const binding of [{role:'owner',tenant_id:'other'},{role:'member',tenant_id:'gym'}]){const f=optionalContactProvision(binding);await assert.rejects(f.c.provision(new Request('https://edge.example.invalid'),walkinInput,'member'),/Not authorized/);assert.equal(f.created(),0);}
 const f=optionalContactProvision();await assert.rejects(f.c.provision(new Request('https://edge.example.invalid'),walkinInput,'member',true),/Invalid request/);assert.equal(f.created(),0);
});
test('walk-in with supplied real email retains that contact',async()=>{
 const f=optionalContactProvision();await f.c.provision(new Request('https://edge.example.invalid'),{...walkinInput,email:'Person@Example.invalid'},'member');assert.equal(f.calls.find(c=>c.name==='iv_prepare_branch_account').args.p_email,'person@example.invalid');
});

test('member with no contact can add a real email using only proof of that new inbox',async()=>{
 const f=contactFixture(false,'gym','member',null);f.c.actor=async()=>({id:'member'});f.c.role=async()=>({role:'member',tenant_id:'gym'});
 await f.c.changeContact(new Request('https://edge.example.invalid'),{new_email:'real@example.invalid'});
 assert.equal(f.mail.length,1);assert.equal(f.mail[0].to,'real@example.invalid');assert.equal(f.queues[0].p_kind,'correct_unverified');assert.equal(f.queues[0].p_base_email,null);assert.equal(f.queues[0].p_actor,'member');
});

test('Edge subscription denial is explicit without exposing SQL or private arguments',async()=>{
 const f=runtime();f.client.rpc=async()=>({error:{code:'IV003',message:'private backend detail'}});
 await assert.rejects(f.c.rpc('iv_prepare_branch_account',{p_email:'private@example.invalid'}),/^Error: Gym subscription access is unavailable\. Contact the registered gym owner\.$/);
});
