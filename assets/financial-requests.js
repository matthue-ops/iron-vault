/* Stable request IDs survive transient failures and page reloads in this tab. */
(function(root){
 'use strict';
 const inflight=new Map();
 async function reviewTopup(client,storage,tenantId,memberId,amount){
  const role=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff','super_admin'],tenantId,allowGlobalSuperAdmin:true}),key='ironvault_financial_request:'+role.user_id+':'+tenantId;
  const payload=JSON.stringify({p_operation:'topup',p_member_id:memberId,p_plan:null,p_amount:Number(amount),p_cash_amount:0});
  let saved=JSON.parse(storage.getItem(key)||'null');
  if(saved&&saved.payload!==payload){if(saved.stage!=='review')throw Object.assign(Error('Retry the unresolved payment before starting a different payment.'),{uncertain:true});storage.removeItem(key);saved=null;}
  if(saved&&saved.stage!=='review')return {retry:true,request_id:saved.requestId};
  if(!saved){saved={payload,requestId:root.crypto.randomUUID(),stage:'review'};storage.setItem(key,JSON.stringify(saved));}
  try{
   const {data,error}=await client.rpc('iv_topup_review',{p_tenant:tenantId,p_member:memberId,p_amount:Number(amount),p_request:saved.requestId});
   if(error)throw Error(['PGRST202','42883'].includes(error.code)?'Top-up review safeguards are not installed. Ask the Provider to apply migration 046.':error.message);
   if(data?.request_id!==saved.requestId||data.member_id!==memberId||Number(data.amount)!==Number(amount))throw Error('Top-up review was not confirmed.');
   const after=await client.auth.getUser();if(after.error||after.data?.user?.id!==role.user_id)throw Error('Account changed.');
   return {...data,storageKey:key};
  }catch(error){const current=JSON.parse(storage.getItem(key)||'null');if(current?.requestId===saved.requestId&&current.stage==='review')storage.removeItem(key);throw error;}
 }
 function cancelReview(storage,review){if(!review?.storageKey)return;const saved=JSON.parse(storage.getItem(review.storageKey)||'null');if(saved?.requestId===review.request_id&&saved.stage==='review')storage.removeItem(review.storageKey);}
 async function pending(client,storage,tenantId){
  const role=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff','super_admin','member'],tenantId,allowGlobalSuperAdmin:true});
  const value=JSON.parse(storage.getItem('ironvault_financial_request:'+role.user_id+':'+tenantId)||'null');
  return value&&value.stage!=='review'?JSON.parse(value.payload):null;
 }
 async function execute(client,storage,tenantId,input){
  const role=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff','super_admin','member'],tenantId,allowGlobalSuperAdmin:true});
  const key='ironvault_financial_request:'+role.user_id+':'+tenantId;
  if(inflight.has(key))throw new Error('A payment is already being processed.');
  inflight.set(key,true);
  try{
   const payload=JSON.stringify({p_operation:input.p_operation,p_member_id:input.p_member_id,p_plan:input.p_plan??null,p_amount:input.p_amount,p_cash_amount:input.p_cash_amount});
   let pending=JSON.parse(storage.getItem(key)||'null');
   // An abandoned review has never submitted a payment and may be replaced.
   if(pending?.stage==='review'&&pending.payload!==payload){storage.removeItem(key);pending=null;}
   const wasUnresolved=!!pending&&pending.stage!=='review';
   if(pending&&pending.payload!==payload)throw Object.assign(new Error('Retry the unresolved payment before starting a different payment.'),{uncertain:true});
   if(!pending){pending={payload,requestId:root.crypto.randomUUID()};storage.setItem(key,JSON.stringify(pending));}
   pending.stage='submitted';storage.setItem(key,JSON.stringify(pending));
   let response;
   try{response=await client.rpc('iv_financial_transaction',{...JSON.parse(payload),p_request_id:pending.requestId});}
   catch(error){throw Object.assign(new Error(error?.message||'Payment response not confirmed.'),{uncertain:true});}
   const {data,error}=response||{};
   if(error){
    // Only a first-attempt definitive rejection proves this request never committed.
    // A later rejection cannot resolve an earlier unknown outcome.
    const definitive=/^(P0001|22\w{3}|23\w{3}|IV002|IV003|IV004|42501)$/.test(error.code||'');
    if(definitive&&!wasUnresolved)storage.removeItem(key);
    throw Object.assign(new Error((error.message||'Payment not confirmed.')+(wasUnresolved?' The earlier transaction outcome remains unresolved. Keep this request and retry the same payment after access is restored; do not create a replacement.':'')),{code:error.code,uncertain:wasUnresolved||!definitive});
   }
   if(!data||data.request_id!==pending.requestId)throw Object.assign(new Error('Payment response not confirmed. Retry the same payment.'),{uncertain:true});
   try{const {data:identity,error:identityError}=await client.auth.getUser();if(identityError||identity?.user?.id!==role.user_id)throw Error('Account changed. Reopen the original account to confirm this payment.');}
   catch(error){throw Object.assign(new Error(error?.message||'Payment identity not confirmed.'),{uncertain:true});}
   storage.removeItem(key);return data;
  }finally{inflight.delete(key);}
 }
 root.IronVaultFinance=Object.freeze({execute,pending,reviewTopup,cancelReview});
 if(typeof module==='object'&&module.exports)module.exports=root.IronVaultFinance;
})(globalThis);
