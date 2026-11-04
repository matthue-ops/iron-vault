const {test}=require('node:test');const assert=require('node:assert/strict');
require('../assets/auth-session.js');const finance=require('../assets/financial-requests.js');
function fixture(){
 const state=new Map(),calls=[];let actor='operator';
 const storage={getItem:k=>state.get(k)||null,setItem:(k,v)=>state.set(k,v),removeItem:k=>state.delete(k)};
 const client={auth:{getUser:async()=>({data:{user:{id:actor}}})},from:()=>({select(){return this},eq:async()=>({data:[{user_id:actor,tenant_id:'gym',role:'staff'}]})}),
 rpc:async(name,args)=>{calls.push(args);return {data:{request_id:args.p_request_id,wallet_balance:100}}}};
 const input={p_operation:'topup',p_member_id:'member',p_plan:null,p_amount:100,p_cash_amount:0};
 return {client,storage,calls,input,actor:value=>{actor=value}};
}
test('transport failure preserves request and exact payload across retry',async()=>{
 const f=fixture();const ok=f.client.rpc;f.client.rpc=async(name,args)=>{f.calls.push(args);throw Error('Lost response')};
 await assert.rejects(finance.execute(f.client,f.storage,'gym',f.input),/Lost/);
 const pending=await finance.pending(f.client,f.storage,'gym');assert.equal(pending.p_amount,100);
 f.client.rpc=ok;await finance.execute(f.client,f.storage,'gym',f.input);
 assert.equal(f.calls[0].p_request_id,f.calls[1].p_request_id);assert.equal(await finance.pending(f.client,f.storage,'gym'),null);
});
test('changed payment is blocked while an outcome is unresolved',async()=>{
 const f=fixture();f.client.rpc=async()=>({error:{message:'Timeout'}});
 await assert.rejects(finance.execute(f.client,f.storage,'gym',f.input));
 await assert.rejects(finance.execute(f.client,f.storage,'gym',{...f.input,p_amount:200}),/unresolved/);
});
test('database rejection rolls back and permits a corrected payment',async()=>{
 const f=fixture();f.client.rpc=async()=>({error:{code:'P0001',message:'Price changed'}});
 await assert.rejects(finance.execute(f.client,f.storage,'gym',f.input),/Price changed/);
 assert.equal(await finance.pending(f.client,f.storage,'gym'),null);
});
test('different actor cannot reuse an old receipt and response identity changes fail closed',async()=>{
 const f=fixture();const ok=f.client.rpc;
 f.client.rpc=async(...args)=>{const r=await ok(...args);f.actor('replacement');return r};
 await assert.rejects(finance.execute(f.client,f.storage,'gym',f.input),/Account changed/);
 assert.equal(await finance.pending(f.client,f.storage,'gym'),null);
 f.actor('operator');assert.equal((await finance.pending(f.client,f.storage,'gym')).p_member_id,'member');
});
test('overlapping requests in the same operator and gym cannot issue two RPCs',async()=>{
 const f=fixture();let release;f.client.rpc=(name,args)=>new Promise(resolve=>{f.calls.push(args);release=()=>resolve({data:{request_id:args.p_request_id}})});
 const first=finance.execute(f.client,f.storage,'gym',f.input);
 while(!release)await new Promise(resolve=>setImmediate(resolve));
 await assert.rejects(finance.execute(f.client,f.storage,'gym',f.input),/already/);
 release();await first;assert.equal(f.calls.length,1);
});
test('purchase retry preserves its original split even after a later quote would change wallet availability',async()=>{
 const f=fixture();const input={...f.input,p_operation:'purchase',p_plan:'1-Day Pass',p_cash_amount:50};
 f.client.rpc=async()=>{throw Error('Unknown outcome')};await assert.rejects(finance.execute(f.client,f.storage,'gym',input));
 const pending=await finance.pending(f.client,f.storage,'gym');assert.equal(pending.p_cash_amount,50);assert.equal(pending.p_amount,100);
});

test('financial SQL retains original signatures, binds receipts before mutation and uses server plan terms',()=>{
 const fs=require('node:fs');const sql=fs.readFileSync('supabase/migrations/202611010011_financial_transaction_api.sql','utf8');
 assert.ok(sql.indexOf('pg_advisory_xact_lock')<sql.indexOf('FOR UPDATE'));
 assert.ok(sql.indexOf('RETURN receipt.result')<sql.indexOf('UPDATE public.members SET wallet_balance'));
 assert.match(sql,/receipt\.actor_id<>actor.*receipt\.tenant_id<>m\.tenant_id.*receipt\.member_id<>m\.id.*receipt\.payload<>payload/);
 assert.match(sql,/price:=\(pricing->>key\)::numeric/);assert.match(sql,/discount:=coalesce\(m\.discount_percentage,0\)/);
 assert.match(sql,/IF p_amount<>price OR p_cash_amount>price/);
 assert.match(sql,/CASE WHEN wallet=0 THEN p_request_id ELSE NULL END/);
 assert.match(sql,/CREATE OR REPLACE FUNCTION public\.iv_topup/);assert.match(sql,/CREATE OR REPLACE FUNCTION public\.iv_purchase/);
 assert.match(sql,/p_expiration::text IS DISTINCT FROM outcome->>'expiration_date'/);
 assert.match(sql,/REVOKE ALL ON FUNCTION public\.iv_financial_transaction.*FROM PUBLIC,anon,authenticated,service_role/);
});
test('rolled-back agreement rejection permits a fresh purchase after reviewing terms',async()=>{
 const f=fixture(),ok=f.client.rpc;f.client.rpc=async()=>({error:{code:'IV002',message:'Review the current Terms'}});
 await assert.rejects(finance.execute(f.client,f.storage,'gym',{...f.input,p_operation:'purchase',p_plan:'1-Day Pass'}),/Terms/);assert.equal(await finance.pending(f.client,f.storage,'gym'),null);
 f.client.rpc=ok;await finance.execute(f.client,f.storage,'gym',{...f.input,p_operation:'purchase',p_plan:'1-Week Pass'});assert.equal(await finance.pending(f.client,f.storage,'gym'),null);
});
