(function(root){
 'use strict';
 const LIMIT=10*1024*1024,TOTAL=20*1024*1024;
 const columns={gyms:['id','gym','owner','email','status','day','week','month'],members:['id','tenant','name','email','phone','status','plan','wallet','expiry'],staff:['tenant','name','email'],activity:['tenant','date','actor','action','details']};
 const scalar=value=>typeof value==='string'||typeof value==='number'||typeof value==='boolean'?String(value):'';
 const field=(row,...names)=>{for(const name of names)if(row[name]!==undefined&&row[name]!==null)return scalar(row[name]);return '';};
 function array(value){if(!Array.isArray(value)||value.length>20000||value.some(row=>!row||typeof row!=='object'||Array.isArray(row)))throw Error('Expected an export array of at most 20,000 records.');return value;}
 function normalize(gyms,members){
  const result={gyms:[],members:[],staff:[],activity:[]};let count=0;
  const add=(kind,row)=>{if(++count>50000)throw Error('Export contains too many records to view.');result[kind].push(row);};
  for(const g of array(gyms)){
   const tenant=field(g,'id'),pricing=g.pricing&&typeof g.pricing==='object'?g.pricing:{};
   add('gyms',{id:tenant,gym:field(g,'gymName','gym_name'),owner:field(g,'ownerName','owner_name'),email:field(g,'email'),status:field(g,'status'),day:field(pricing,'day'),week:field(pricing,'week'),month:field(pricing,'month')});
   for(const s of array(g.staff||[]))add('staff',{tenant,name:field(s,'name'),email:field(s,'email')});
   for(const a of array(g.auditLogs||g.audit_logs||[]))add('activity',{tenant,date:field(a,'date','timestamp','created_at'),actor:field(a,'actor','user','staffName'),action:field(a,'action','event'),details:field(a,'details','description')});
  }
  for(const m of array(members))add('members',{id:field(m,'id'),tenant:field(m,'tenantId','tenant_id'),name:field(m,'name'),email:field(m,'email'),phone:field(m,'phone'),status:field(m,'status'),plan:field(m,'plan'),wallet:field(m,'walletBalance','wallet_balance'),expiry:field(m,'expirationDate','expiration_date')});
  if(Object.values(result).reduce((n,rows)=>n+rows.length,0)>50000)throw Error('Export contains too many records to view.');
  return result;
 }
 async function readEntry(entry,budget){
  if(!entry||entry.dir)throw Error('Missing export file.');
  return new Promise((resolve,reject)=>{
   const chunks=[];let size=0,done=false;
   const stream=entry.internalStream('uint8array');
   stream.on('data',chunk=>{
    if(done)return;size+=chunk.length;budget.bytes+=chunk.length;
    if(size>LIMIT||budget.bytes>TOTAL){done=true;stream.pause();reject(Error('Expanded export is too large (10 MB per file, 20 MB total).'));return;}
    chunks.push(chunk);
   });
   stream.on('error',error=>{if(!done){done=true;reject(Error('Could not read the ZIP export.'));}});
   stream.on('end',()=>{if(done)return;done=true;const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}try{resolve(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch(_){reject(Error('Export text is not valid UTF-8.'));}});
   stream.resume();
  });
 }
 async function readFile(file,zipLibrary){
  if(!file||file.size>TOTAL)throw Error('Choose an export no larger than 20 MB.');
  let gyms=[],members=[];
  if(file.name.toLowerCase().endsWith('.zip')){
   if(!zipLibrary)throw Error('ZIP reader did not load. Reload this page and try again.');
   const zip=await zipLibrary.loadAsync(file),budget={bytes:0};
   if(Object.keys(zip.files).length>100)throw Error('ZIP contains too many files.');
   const gymFiles=['tenant_owner_export.json','ironvault_owners_export.json'].filter(n=>zip.file(n));
   const memberFiles=['tenant_members_export.json','ironvault_members_export.json'].filter(n=>zip.file(n));
   if(gymFiles.length>1||memberFiles.length>1)throw Error('ZIP contains ambiguous export files.');
   if(!gymFiles.length&&!memberFiles.length)throw Error('No supported Iron Vault export files found.');
   if(gymFiles.length)gyms=JSON.parse(await readEntry(zip.file(gymFiles[0]),budget));
   if(memberFiles.length)members=JSON.parse(await readEntry(zip.file(memberFiles[0]),budget));
  }else if(file.name.toLowerCase().endsWith('.json')){
   if(file.size>LIMIT)throw Error('JSON export must be smaller than 10 MB.');
   const rows=array(JSON.parse(await file.text()));
   if(rows.some(r=>'gymName' in r||'gym_name' in r)||/owner/i.test(file.name))gyms=rows;else members=rows;
  }else throw Error('Choose an Iron Vault ZIP or JSON export.');
  return normalize(gyms,members);
 }
 function selectRows(data,kind,query,tenant){
  const needle=query.trim().toLowerCase();return (data[kind]||[]).filter(row=>(!tenant||(kind==='gyms'?row.id:row.tenant)===tenant)&&(!needle||Object.values(row).some(value=>value.toLowerCase().includes(needle))));
 }
 function install(document){
  const node=id=>document.getElementById(id);let data=null,page=0,version=0;const pageSize=100;
  function reset(){version++;data=null;page=0;node('viewer-file').value='';node('viewer-search').value='';node('viewer-error').textContent='';node('viewer-results').hidden=true;node('viewer-head').replaceChildren();node('viewer-body').replaceChildren();node('viewer-summary').textContent='';node('viewer-source').textContent='';node('viewer-tenant').replaceChildren();}
  function render(){
   if(!data)return;const kind=node('viewer-kind').value,rows=selectRows(data,kind,node('viewer-search').value,node('viewer-tenant').value),keys=columns[kind];
   page=Math.min(page,Math.max(0,Math.ceil(rows.length/pageSize)-1));
   const heading=document.createElement('tr');for(const key of keys){const th=document.createElement('th');th.textContent=key==='wallet'?'Exported wallet credit':key;heading.appendChild(th);}node('viewer-head').replaceChildren(heading);
   node('viewer-body').replaceChildren();for(const row of rows.slice(page*pageSize,(page+1)*pageSize)){const tr=document.createElement('tr');for(const key of keys){const td=document.createElement('td');td.textContent=row[key];tr.appendChild(td);}node('viewer-body').appendChild(tr);}
   node('viewer-page').textContent=rows.length?'Showing '+(page*pageSize+1)+'–'+Math.min((page+1)*pageSize,rows.length)+' of '+rows.length:'No matching records';
   node('viewer-prev').disabled=page===0;node('viewer-next').disabled=(page+1)*pageSize>=rows.length;
  }
  node('viewer-file').addEventListener('change',async event=>{
   const file=event.target.files?.[0];if(!file)return;reset();const stamp=version;node('viewer-error').textContent='Reading export…';
   try{
    const result=await readFile(file,root.JSZip);if(stamp!==version)return;data=result;
    node('viewer-source').textContent=file.name;node('viewer-error').textContent='';node('viewer-summary').textContent=data.gyms.length+' gyms · '+data.members.length+' members · '+data.staff.length+' staff entries · '+data.activity.length+' activity entries';
    const all=document.createElement('option');all.value='';all.textContent='All gyms';node('viewer-tenant').appendChild(all);
    const names=new Map(data.gyms.map(g=>[g.id,g.gym||g.id]));for(const member of data.members)if(member.tenant&&!names.has(member.tenant))names.set(member.tenant,member.tenant);
    for(const [id,name] of names){const option=document.createElement('option');option.value=id;option.textContent=name+' ('+id+')';node('viewer-tenant').appendChild(option);}
    node('viewer-kind').value=data.members.length?'members':'gyms';node('viewer-results').hidden=false;render();
   }catch(error){if(stamp===version)node('viewer-error').textContent=error instanceof SyntaxError?'The export contains invalid JSON.':error.message;}
  });
  for(const id of ['viewer-kind','viewer-tenant'])node(id).addEventListener('change',()=>{page=0;render();});
  node('viewer-search').addEventListener('input',()=>{page=0;render();});
  node('viewer-prev').addEventListener('click',()=>{page--;render();});node('viewer-next').addEventListener('click',()=>{page++;render();});node('viewer-clear').addEventListener('click',reset);
 }
 root.IronVaultExportViewer=Object.freeze({normalize,readFile,readEntry,selectRows,install});
 if(typeof module==='object'&&module.exports)module.exports=root.IronVaultExportViewer;
})(globalThis);
