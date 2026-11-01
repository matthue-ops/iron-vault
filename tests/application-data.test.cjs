const {test}=require('node:test');const assert=require('node:assert/strict');
const data=require('../assets/application-data.js');
test('profile serialization cannot carry money, entitlement, credentials, Auth IDs or tenant tokens',()=>{
 const row=data.member({id:'m',tenantId:'g',name:'Test',email:'test@example.invalid',walletBalance:999,amount:999,plan:'forged',expirationDate:'2099-01-01',password:'placeholder',auth_user_id:'forged'});
 for(const key of ['wallet_balance','amount','plan','expiration_date','password','auth_user_id','tenant_token'])assert.equal(key in row,false,key);
});
test('owner serialization cannot grant roles, change email/token or restore JSON audit/credentials',()=>{
 const row=data.gym({id:'g',gymName:'Gym',staff:[{isAdmin:true}],password:'placeholder',email:'x',token:'forged',audit_logs:['fake']});
 for(const key of ['staff','password','email','token','audit_logs'])assert.equal(key in row,false);
});
test('legacy writes are routed to scoped RPCs and never sent to a base table',async()=>{
 const writes=[],reads=[];const client={from:name=>{reads.push(name);return{}},rpc:async(name,args)=>{writes.push({name,args});return{data:null,error:null}}};
 data.install(client);await client.from('members').upsert({id:'m',tenant_id:'g',name:'Member',wallet_balance:100});
 await client.from('members').delete().eq('id','m');
 assert.equal(reads.length,0);assert.equal(writes[0].name,'iv_save_member_profiles');assert.equal(writes[0].args.p_records[0].wallet_balance,undefined);
 assert.equal(writes[1].name,'iv_deactivate_member');
 const denied=await client.from('members').delete().eq('tenant_id','g');assert.match(denied.error.message,/Select one/);assert.equal(writes.length,2);
});
test('safe view reads keyset-page until empty even when API returns less than requested',async()=>{
 const calls=[];const rows=[{id:'a'},{id:'b'},{id:'c'}];
 const client={rpc:async()=>({}),from(table){calls.push(table);let cursor='';const q={select(){return q},order(){return q},limit(){return q},gt(k,v){cursor=v;return q},then(resolve){resolve({data:rows.filter(x=>x.id>cursor).slice(0,1),error:null})}};return q}};
 data.install(client);const result=await client.from('members').select('*');assert.equal(result.data.length,3);assert.equal(calls.length,4);assert.ok(calls.every(x=>x==='iv_members'));
});
test('HTML and executable argument escaping preserve names without enabling markup or quotes',()=>{
 assert.equal(data.escape('<img onerror="x">'), '&lt;img onerror=&quot;x&quot;&gt;');
 assert.equal(decodeURIComponent(data.argument("O'Brien")),"O'Brien");assert.equal(data.argument("O'Brien").includes("'"),false);
});
