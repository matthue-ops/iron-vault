/* Modelled server outcomes exercise the real client retry state, not a live database. */
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function model(){let revision=0,balance=0,lost=false;const reviews=new Map(),receipts=new Map(),calls=[];
 function operator(actor){const store=new Map(),storage={getItem:k=>store.get(k)||null,setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)};
  const context={crypto,IronVaultAuth:{requireRole:async()=>({user_id:actor})}};vm.createContext(context);vm.runInContext(fs.readFileSync('assets/financial-requests.js','utf8'),context);
  const client={auth:{getUser:async()=>({data:{user:{id:actor}}})},rpc:async(name,args)=>{
   calls.push({actor,name,args});if(name==='iv_topup_review'){reviews.set(args.p_request,{actor,revision,balance,amount:args.p_amount});return {data:{request_id:args.p_request,member_id:args.p_member,amount:args.p_amount,wallet_before:balance,wallet_after:balance+args.p_amount}};}
   if(receipts.has(args.p_request_id))return {data:receipts.get(args.p_request_id)};
   const review=reviews.get(args.p_request_id);if(!review||review.actor!==actor||review.revision!==revision||review.balance!==balance)return {error:{code:'IV004',message:'Top-up review is out of date. Most recent top-up: PHP 100 by other operator.'}};
   balance+=args.p_amount;revision++;const result={request_id:args.p_request_id,wallet_balance:balance};receipts.set(args.p_request_id,result);
   if(lost){lost=false;throw Error('Response lost after commit');}return {data:result};
  }};const input={p_operation:'topup',p_member_id:'member',p_plan:null,p_amount:100,p_cash_amount:0};return {prepare:()=>context.IronVaultFinance.reviewTopup(client,storage,'gym','member',100),execute:()=>context.IronVaultFinance.execute(client,storage,'gym',input),cancel:r=>context.IronVaultFinance.cancelReview(storage,r),store};
 }
 return {operator,calls,receipts,balance:()=>balance,lose:()=>lost=true};
}
test('two operators review the same state: first succeeds, stale second is blocked, fresh separate payment works',async()=>{
 const server=model(),admin=server.operator('owner'),staff=server.operator('staff');await Promise.all([admin.prepare(),staff.prepare()]);await admin.execute();await assert.rejects(staff.execute(),/out of date/);assert.equal(server.balance(),100);assert.equal(server.receipts.size,1);assert.equal(staff.store.size,0);await staff.prepare();await staff.execute();assert.equal(server.balance(),200);assert.equal(server.receipts.size,2);
});
test('lost committed response reuses its receipt even after another operator changes the balance',async()=>{
 const server=model(),a=server.operator('owner'),b=server.operator('staff');await a.prepare();server.lose();await assert.rejects(a.execute(),/Response lost/);await b.prepare();await b.execute();const retry=await a.prepare();assert.equal(retry.retry,true);await a.execute();assert.equal(server.balance(),200);assert.equal(server.receipts.size,2);assert.equal(server.calls.filter(c=>c.actor==='owner'&&c.name==='iv_topup_review').length,1);
});
test('cancelling an unsubmitted review clears only that review, never an uncertain payment',async()=>{
 const server=model(),a=server.operator('owner');const review=await a.prepare();a.cancel(review);assert.equal(a.store.size,0);await a.prepare();server.lose();await assert.rejects(a.execute());a.cancel(review);assert.equal(a.store.size,1);assert.equal(server.receipts.size,1);
});
test('046 retains receipt replay before stale checks and exposes only aggregate revenue',()=>{
 const sql=fs.readFileSync('supabase/manual/pilot_topup_reviews_ui.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/migrations/202611080046_pilot_topup_reviews_ui.sql','utf8'));
 const write=sql.split('CREATE FUNCTION public.iv_financial_transaction')[1].split('-- Separate grant')[0];assert(write.indexOf('RETURN ironvault_private.financial_transaction_046_base')<write.indexOf('q.revision<>current_revision'));assert.match(write,/q.actor_id<>auth.uid\(\)/);assert.match(write,/q.tenant_id<>m.tenant_id/);assert.match(write,/FOR UPDATE/);assert.match(write,/ERRCODE='IV004'/);
 const metric=sql.split('CREATE FUNCTION public.iv_revenue_today')[1].split('-- Enrich sources')[0];assert.match(metric,/staff_require\(p_tenant,'revenue_today'\)/);assert.match(metric,/subscription_require\(p_tenant,'read'\)/);assert.doesNotMatch(metric,/iv_report_snapshot|jsonb_agg|plan_wallet.*topup/);assert.match(metric,/t.tenant_id=p_tenant/);
});
