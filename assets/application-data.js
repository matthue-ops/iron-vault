/* Read compatibility views; write only explicitly scoped application RPCs. */
(function(root){
 'use strict';
 const installed=new WeakSet();
 const argument=value=>encodeURIComponent(String(value)).replace(/'/g,'%27');
 const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function member(m){return {id:m.id,tenant_id:m.tenant_id??m.tenantId,name:m.name,email:m.email,phone:m.phone??'',avatar:m.avatar??null,
  classification:m.classification??'Regular',discount_percentage:m.discount_percentage??m.discountPercentage??0,
  card_barcode:m.card_barcode??m.cardBarcode??'',status:m.status??'PENDING'};}
 function gym(g){return {id:g.id,gym_name:g.gym_name??g.gymName,owner_name:g.owner_name??g.ownerName,
  logo:g.logo??'',pricing:g.pricing,status:g.status};}
 async function call(client,name,args){const {data,error}=await client.rpc(name,args);if(error)throw new Error(error.message||'Change was not saved.');return data;}
 async function saveMembers(client,records){return call(client,'iv_save_member_profiles',{p_records:records.map(member)});}
 async function saveGyms(client,records){return call(client,'iv_save_gym_settings',{p_records:records.map(gym)});}
 async function loadMaster(client){
  const results=await Promise.all([client.from('owners').select('*'),client.from('members').select('*')]);
  for(const [index,result] of results.entries()){
   if(result.error||!Array.isArray(result.data)){
    const label=index===0?'gym directory':'member directory';
    const reason=result.error?.message||'The server returned an invalid response.';
    const code=result.error?.code?' ['+result.error.code+']':'';
    const error=new Error('Could not load '+label+code+': '+reason);error.code='DATA_LOAD_FAILED';throw error;
   }
  }
  return {owners:results[0].data.map(o=>({id:o.id,displayCode:o.display_code||o.id,gymName:o.gym_name,ownerName:o.owner_name,email:o.email,
   token:o.token,portalSlug:o.portal_slug||null,logo:o.logo,status:o.status,pricing:o.pricing,staff:o.staff||[],auditLogs:o.audit_logs||[],dateCreated:o.date_created})),
   members:results[1].data.map(m=>({id:m.id,displayCode:m.display_code||m.id,tenantId:m.tenant_id,tenantToken:m.tenant_token,name:m.name,email:m.email,phone:m.phone,
    classification:m.classification,discountPercentage:m.discount_percentage,plan:m.plan,cardBarcode:m.card_barcode,
    walletBalance:m.wallet_balance,amount:m.amount,scansUsed:m.scans_used,lastScannedDate:m.last_scanned_date,
    expirationDate:m.expiration_date,status:m.status,dateJoined:m.date_joined,avatar:m.avatar}))};
 }
 function install(client){
  if(installed.has(client))return client;installed.add(client);
  root.localStorage?.removeItem('ironvault_owners_db');root.localStorage?.removeItem('ironvault_members_db');
  const original=client.from.bind(client);
  client.from=function(table){
   if(!['owners','members'].includes(table))return original(table);
   const view=table==='owners'?'iv_gyms':'iv_members';
   const relation={};
   function read(selectArgs){
    const steps=[];let promise;
    const q={then(resolve,reject){promise??=(async()=>{
     const exact=steps.some(([k,args])=>k==='single'||k==='maybeSingle'||k==='limit'||k==='range'||(k==='eq'&&(args[0]==='id'||(table==='owners'&&['token','portal_slug'].includes(args[0])))));
     const rows=[];let cursor;
     for(let page=0;page<10000;page++){
      let query=original(view).select(...selectArgs);for(const [method,args] of steps)query=query[method](...args);
      if(!exact){query=query.order('id',{ascending:true}).limit(100);if(cursor)query=query.gt('id',cursor);}
      const result=await query;if(result.error||exact)return result;
      if(!Array.isArray(result.data))return result;
      if(!result.data.length)return {...result,data:rows};
      rows.push(...result.data);const last=result.data.at(-1).id;
      if(typeof last!=='string'||last===cursor)throw Error('Roster pagination could not advance.');cursor=last;
     }
     throw Error('Dataset too large to load safely.');
    })();return promise.then(resolve,reject);}};
    for(const method of ['eq','neq','gt','gte','lt','lte','in','is','order','limit','range','single','maybeSingle'])q[method]=(...args)=>{steps.push([method,args]);return q;};
    return q;
   }

   function mutation(kind,value){
    const filters=[];let execution;
    const q={eq(k,v){filters.push([k,v]);return q},select(){return q},then(resolve,reject){
     execution??=(async()=>{
      try{
       const id=filters.find(([k])=>k==='id')?.[1];
       if(kind==='delete'){
        if(!id)throw Error('Select one record to deactivate.');
        await call(client,table==='owners'?'iv_deactivate_gym':'iv_deactivate_member',table==='owners'?{p_tenant:id}:{p_member_id:id});
       }else{
        const rows=Array.isArray(value)?value:[{...value,...(id?{id}:{})}];
        if(table==='owners')await saveGyms(client,rows);else await saveMembers(client,rows);
       }
       return {data:null,error:null};
      }catch(error){return {data:null,error:{message:error.message}};}
     })();return execution.then(resolve,reject);
    }};return q;
   }
   // Base writes are never sent to PostgREST, including old compatibility code.
   return new Proxy(relation,{get(target,key){
    if(key==='select')return (...args)=>read(args);
    if(['upsert','update','insert','delete'].includes(key))return value=>mutation(key,value);
    const v=target[key];return typeof v==='function'?v.bind(target):v;
   }});
  };
  return client;
 }
 root.IronVaultData=Object.freeze({install,saveMembers,saveGyms,call,escape,argument,member,gym,loadMaster});
 if(typeof module==='object'&&module.exports)module.exports=root.IronVaultData;
})(globalThis);
