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
