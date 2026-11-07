const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function fixture(role='staff'){
 let current=true;const calls=[];
 const context={IronVaultAuth:{requireRole:async(_,options)=>{calls.push(['role',options]);return {user_id:'own-user',role,tenant_id:'gym'};}}};vm.createContext(context);vm.runInContext(fs.readFileSync('assets/account-password.js','utf8'),context);
 const client={auth:{getUser:async()=>({data:{user:{id:'own-user',email:'private-alias@accounts.ironvault.invalid'}}}),signInWithPassword:async payload=>{calls.push(['reauth',payload]);return {data:{user:{id:'own-user'}}};},updateUser:async payload=>{calls.push(['update',payload]);return {data:{user:{id:'own-user'}}};}}};
 const input={tenantId:'gym',userId:'own-user',currentPassword:'current-test-only',password:'replacement-test-only',confirmation:'replacement-test-only',createVerifier:()=>({auth:{signInWithPassword:args=>client.auth.signInWithPassword(args),updateUser:args=>client.auth.updateUser(args),signOut:async()=>calls.push(['verification-signout'])}}),isCurrent:()=>current};
 return {calls,client,input,change:()=>context.IronVaultAccountPassword.change(client,input),leave:()=>current=false};
}
test('owner/staff change only their authenticated account after verifying current password',async()=>{
 for(const role of ['owner','staff']){const f=fixture(role);await f.change();const reauth=f.calls.find(c=>c[0]==='reauth')[1],update=f.calls.find(c=>c[0]==='update')[1];assert.equal(reauth.email,'private-alias@accounts.ironvault.invalid');assert.equal(reauth.password,f.input.currentPassword);assert.deepEqual(Object.keys(update),['password']);assert.equal(update.password,f.input.password);assert.equal(f.calls.filter(c=>c[0]==='role').length,2);}
});
test('mismatched or short passwords and missing current password do not call Auth',async()=>{
 for(const mutation of [f=>f.input.password='short',f=>f.input.confirmation='different',f=>f.input.currentPassword='']){const f=fixture();mutation(f);await assert.rejects(f.change());assert.equal(f.calls.length,0);}
});
test('incorrect current password cannot reach updateUser',async()=>{const f=fixture();f.client.auth.signInWithPassword=async()=>({error:{message:'Invalid credentials'}});await assert.rejects(f.change(),/Current password is incorrect/);assert(!f.calls.some(c=>c[0]==='update'));});
test('account switch or sign-out during reauthentication cannot update a password',async()=>{
 for(const switched of [true,false]){const f=fixture();f.client.auth.signInWithPassword=async()=>{if(!switched)f.leave();return {data:{user:{id:switched?'another-user':'own-user'}}};};await assert.rejects(f.change(),/Account changed/);assert(!f.calls.some(c=>c[0]==='update'));}
});
test('missing own identity fails before reauthentication',async()=>{const f=fixture();f.client.auth.getUser=async()=>({data:{user:{id:'someone-else'}}});await assert.rejects(f.change(),/Sign in again/);assert(!f.calls.some(c=>c[0]==='reauth'||c[0]==='update'));});
test('unconfirmed Auth update never reports password-change success',async()=>{const f=fixture();f.client.auth.updateUser=async()=>({error:{message:'Unavailable'}});await assert.rejects(f.change(),/not confirmed/);});
test('reauthentication and password update use an isolated session rather than replacing browser login',async()=>{
 const f=fixture();let updates=0,ended=0;
 f.client.auth.signInWithPassword=f.client.auth.updateUser=async()=>{throw Error('Main session must not be replaced');};
 f.input.createVerifier=()=>({auth:{signInWithPassword:async()=>({data:{user:{id:'own-user'}}}),updateUser:async()=>{updates++;return {data:{user:{id:'own-user'}}};},signOut:async({scope})=>{assert.equal(scope,'local');ended++;}}});
 await f.change();assert.equal(updates,1);assert.equal(ended,1);
});
