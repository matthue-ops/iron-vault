/* Owner-invoked isolated-target acceptance. NEVER included in npm test.
 * No SQL or deletion. Dedicated fixture transactions remain as audit history.
 * Hard-refuse the existing user's project to preserve its records.
 */
const {test}=require('node:test');const assert=require('node:assert/strict');
const url=process.env.IV_STAGING_URL,publicKey=process.env.IV_STAGING_ANON_KEY;
if(process.env.IV_ALLOW_STAGING_MUTATIONS!=='YES'||!url||!publicKey)throw Error('Explicit isolated staging target and mutation approval are required.');
const host=new URL(url).hostname;if(host==='uarvhalocgyrikjbrloh.supabase.co'||process.env.IV_STAGING_HOST_CONFIRM!==host)throw Error('Refusing existing project or unconfirmed staging target.');
async function request(path,token,method='GET',body){const r=await fetch(url+path,{method,headers:{apikey:publicKey,Authorization:'Bearer '+(token||publicKey),'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});let data;try{data=await r.json()}catch{data=null}return{status:r.status,data,ok:r.ok};}
async function login(prefix){const r=await request('/functions/v1/iv-branch-auth',null,'POST',{action:'signin',portal:'admin',gym_token:process.env[prefix+'_GYM_TOKEN'],email:process.env[prefix+'_EMAIL'],password:process.env[prefix+'_PASSWORD']});assert.equal(r.ok,true,'Staging login must succeed');assert.ok(r.data.session?.access_token);return r.data.session.access_token;}
test('actual API tenant isolation and concurrent financial receipts on dedicated staging fixtures',async()=>{
 const a=await login('IV_OWNER_A'),b=await login('IV_OWNER_B');const member=process.env.IV_MEMBER_A_ID,tenant=process.env.IV_TENANT_A_ID;assert.ok(member&&tenant);
 const before=await request('/rest/v1/iv_members?id=eq.'+encodeURIComponent(member)+'&select=id,wallet_balance',a);assert.equal(before.data?.length,1);
 const foreign=await request('/rest/v1/iv_members?id=eq.'+encodeURIComponent(member),b);assert.equal(foreign.ok,true);assert.equal(foreign.data?.length,0);
 const base=await request('/rest/v1/members?select=id',a);assert.equal(base.status,403);
 const forged=await request('/rest/v1/iv_user_roles',a,'POST',{user_id:crypto.randomUUID(),role:'super_admin',tenant_id:null});assert.equal(forged.status,403);
 const key=crypto.randomUUID(),payload={p_operation:'topup',p_member_id:member,p_plan:null,p_amount:1,p_cash_amount:0,p_request_id:key};
 const results=await Promise.all([request('/rest/v1/rpc/iv_financial_transaction',a,'POST',payload),request('/rest/v1/rpc/iv_financial_transaction',a,'POST',payload)]);
 assert.ok(results.every(r=>r.ok));assert.deepEqual(results[0].data,results[1].data);
 const after=await request('/rest/v1/iv_members?id=eq.'+encodeURIComponent(member)+'&select=wallet_balance',a);assert.equal(Number(after.data[0].wallet_balance),Number(before.data[0].wallet_balance)+1);
 const changed=await request('/rest/v1/rpc/iv_financial_transaction',a,'POST',{...payload,p_amount:2});assert.equal(changed.ok,false);
 const crossed=await request('/rest/v1/rpc/iv_financial_transaction',b,'POST',{...payload,p_request_id:crypto.randomUUID()});assert.equal(crossed.ok,false);
 const ledger=await request('/rest/v1/iv_financial_transactions?request_id=eq.'+key,a);assert.equal(ledger.data?.length,1);
});
