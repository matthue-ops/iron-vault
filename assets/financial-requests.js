/* Stable request IDs survive transient failures and page reloads in this tab. */
(function(root){
 'use strict';
 const inflight=new Map();
 async function pending(client,storage,tenantId){
  const role=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff','super_admin','member'],tenantId,allowGlobalSuperAdmin:true});
  const value=JSON.parse(storage.getItem('ironvault_financial_request:'+role.user_id+':'+tenantId)||'null');
  return value?JSON.parse(value.payload):null;
 }
 async function execute(client,storage,tenantId,input){
  const role=await root.IronVaultAuth.requireRole(client,{roles:['owner','staff','super_admin','member'],tenantId,allowGlobalSuperAdmin:true});
  const key='ironvault_financial_request:'+role.user_id+':'+tenantId;
  if(inflight.has(key))throw new Error('A payment is already being processed.');
  inflight.set(key,true);
  try{
   const payload=JSON.stringify({p_operation:input.p_operation,p_member_id:input.p_member_id,p_plan:input.p_plan??null,p_amount:input.p_amount,p_cash_amount:input.p_cash_amount});
   let pending=JSON.parse(storage.getItem(key)||'null');
   const wasUnresolved=!!pending;
   if(pending&&pending.payload!==payload)throw new Error('Retry the unresolved payment before starting a different payment.');
   if(!pending){pending={payload,requestId:root.crypto.randomUUID()};storage.setItem(key,JSON.stringify(pending));}
   const {data,error}=await client.rpc('iv_financial_transaction',{...JSON.parse(payload),p_request_id:pending.requestId});
   if(error){
    // Only a first-attempt definitive rejection proves this request never committed.
    // A later rejection cannot resolve an earlier unknown outcome.
    const definitive=/^(P0001|22\w{3}|23\w{3}|IV002|IV003|42501)$/.test(error.code||'');
    if(definitive&&!wasUnresolved)storage.removeItem(key);
    throw new Error((error.message||'Payment not confirmed.')+(wasUnresolved?' The earlier transaction outcome remains unresolved. Keep this request and retry the same payment after access is restored; do not create a replacement.':''));
   }
   if(!data||data.request_id!==pending.requestId)throw new Error('Payment response not confirmed. Retry the same payment.');
   const {data:identity,error:identityError}=await client.auth.getUser();
   if(identityError||identity?.user?.id!==role.user_id)throw new Error('Account changed. Reopen the original account to confirm this payment.');
   storage.removeItem(key);return data;
  }finally{inflight.delete(key);}
 }
 root.IronVaultFinance=Object.freeze({execute,pending});
 if(typeof module==='object'&&module.exports)module.exports=root.IronVaultFinance;
})(globalThis);
