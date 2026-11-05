const {test}=require('node:test');const assert=require('node:assert/strict');
const branch=require('../assets/branch-auth.js');
function fixture(){const values=new Map(),calls=[];const storage={getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};
 const client={auth:{getUser:async()=>({data:{user:{id:'operator'}}}),setSession:async session=>{calls.push({session});return{error:null}}},functions:{invoke:async(name,{body})=>{calls.push({name,body});return{data:{ok:true}}}}};
 return {client,storage,calls,values};}
test('provision retry keeps request ID without persisting passwords',async()=>{
 const f=fixture(),input={tenant_id:'gym',email:'test@example.invalid',name:'Test',password:'test-only'};
 f.client.functions.invoke=async(name,{body})=>{f.calls.push(body);return{error:{message:'Lost response'}}};
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',input));
 assert.ok([...f.values.values()].every(x=>!x.includes('test-only')));
 f.client.functions.invoke=async(name,{body})=>{f.calls.push(body);return{data:{ok:true}}};
 await branch.provision(f.client,f.storage,'iv-create-member',input);assert.equal(f.calls[0].request_id,f.calls[1].request_id);
});
test('provisioning cannot quietly alter an unresolved payload',async()=>{
 const f=fixture();f.client.functions.invoke=async()=>({error:{message:'Unknown result'}});
 const input={tenant_id:'gym',email:'test@example.invalid',name:'Test'};
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',input));
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',{...input,name:'Different'}),/original/);
});
test('branch login only installs an actual returned Supabase session and carries the selected gym',async()=>{
 const f=fixture();f.client.functions.invoke=async(name,{body})=>{f.calls.push({name,body});return{data:{session:{access_token:'test-access',refresh_token:'test-refresh'}}}};
 await branch.signIn(f.client,{gym_token:'gym-token',portal:'member',email:'test@example.invalid',password:'test-only'});
 assert.equal(f.calls[0].body.gym_token,'gym-token');assert.equal(f.calls[0].body.action,'signin');assert.equal(f.calls[1].session.access_token,'test-access');
});
test('an absent session or failed gateway never establishes browser-only login',async()=>{
 const f=fixture();await assert.rejects(branch.signIn(f.client,{}),/Sign-in not completed/);assert.equal(f.calls.filter(x=>x.session).length,0);
});

test('creation explains the eight-character minimum before storing a request or sending credentials',async()=>{
 const f=fixture();await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',{email:'member@example.invalid',password:'short'}),/^Error: At least 8 characters\.$/);
 assert.equal(f.calls.length,0);assert.equal(f.values.size,0);
});
test('sign-in keeps existing shorter passwords usable',async()=>{
 const f=fixture();f.client.functions.invoke=async(name,{body})=>{f.calls.push({name,body});return{data:{session:{access_token:'access',refresh_token:'refresh'}}}};
 await branch.signIn(f.client,{email:'member@example.invalid',password:'six123'});assert.equal(f.calls[0].body.password,'six123');assert.equal(f.calls[1].session.access_token,'access');
});

const blankWalkin={tenant_id:'gym',email:'',name:'First Person',phone:'09999999999',password:'test-only-password'};
test('distinct email-less walk-ins have independent pending requests and each retry retains its request ID',async()=>{
 const f=fixture();f.client.functions.invoke=async(name,{body})=>{f.calls.push(body);return{error:{message:'Unknown result'}}};
 const other={...blankWalkin,name:'Second Person',phone:'09888888888'};
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',blankWalkin),/Unknown result/);
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',other),/Unknown result/);
 assert.notEqual(f.calls[0].request_id,f.calls[1].request_id);
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',blankWalkin),/Unknown result/);
 assert.equal(f.calls[0].request_id,f.calls[2].request_id);assert.equal(f.values.size,2);
 assert.ok([...f.values].every(([key,value])=>!(key+value).includes(blankWalkin.password)));
});
test('successful walk-in clears only its own request while another uncertain request remains retryable',async()=>{
 const f=fixture();f.client.functions.invoke=async(name,{body})=>{f.calls.push(body);return{error:{message:'Unknown result'}}};
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',blankWalkin));const pending=[...f.values][0];
 f.client.functions.invoke=async(name,{body})=>{f.calls.push(body);return{data:{ok:true}}};
 await branch.provision(f.client,f.storage,'iv-create-member',{...blankWalkin,name:'Other'});
 assert.equal(f.values.size,1);assert.equal(f.values.get(pending[0]),pending[1]);
 await branch.provision(f.client,f.storage,'iv-create-member',blankWalkin);assert.equal(f.calls[0].request_id,f.calls[2].request_id);assert.equal(f.values.size,0);
});
test('pre-fix blank-email request is reused for an exact retry and does not block another person',async()=>{
 const f=fixture(),key='ironvault_provision:operator:iv-create-member:gym:';
 const {password,...safe}=blankWalkin;const saved=JSON.stringify({id:'legacy-request',payload:JSON.stringify(safe)});f.values.set(key,saved);
 await branch.provision(f.client,f.storage,'iv-create-member',{...blankWalkin,name:'Other'});
 assert.equal(f.values.get(key),saved);assert.notEqual(f.calls[0].body.request_id,'legacy-request');
 await branch.provision(f.client,f.storage,'iv-create-member',blankWalkin);assert.equal(f.calls[1].body.request_id,'legacy-request');assert.equal(f.values.has(key),false);
});
test('walk-in request isolation retains actor and gym boundaries',async()=>{
 const f=fixture();f.client.functions.invoke=async(name,{body})=>{f.calls.push(body);return{error:{message:'Unknown result'}}};
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',blankWalkin));
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',{...blankWalkin,tenant_id:'other-gym'}));
 f.client.auth.getUser=async()=>({data:{user:{id:'other-operator'}}});
 await assert.rejects(branch.provision(f.client,f.storage,'iv-create-member',blankWalkin));
 assert.equal(new Set(f.calls.map(c=>c.request_id)).size,3);
});
