/* Raster processing + authenticated image storage. No private image is persisted in browser storage. */
(function(root){
 'use strict';
 const PRIVATE=/^iv-photo:([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/;
 const PUBLIC=/^https:\/\/uarvhalocgyrikjbrloh\.supabase\.co\/storage\/v1\/object\/public\/iv-gym-images\/([a-f0-9-]{36})\/logo$/;
 const installed=new WeakSet(),signed=new Map();let epoch=0;
 function photoPath(value){const match=PRIVATE.exec(String(value||''));return match?match[1]+'/photo':null;}
 function gymPath(value){const match=PUBLIC.exec(String(value||''));return match?match[1]+'/logo':null;}
 function dimensions(bytes){
  const b=new Uint8Array(bytes),v=new DataView(b.buffer,b.byteOffset,b.byteLength),str=(i,n)=>String.fromCharCode(...b.slice(i,i+n));
  if(b.length>=24&&b[0]===137&&str(1,3)==='PNG')return [v.getUint32(16),v.getUint32(20)];
  if(b.length>=10&&/^GIF8[79]a$/.test(str(0,6)))return [v.getUint16(6,true),v.getUint16(8,true)];
  if(b.length>=30&&str(0,4)==='RIFF'&&str(8,4)==='WEBP'){
   const type=str(12,4),le24=i=>b[i]+(b[i+1]<<8)+(b[i+2]<<16);
   if(type==='VP8X')return [le24(24)+1,le24(27)+1];
   if(type==='VP8 '&&b[23]===157&&b[24]===1&&b[25]===42)return [v.getUint16(26,true)&16383,v.getUint16(28,true)&16383];
   if(type==='VP8L'&&b[20]===47){const bits=v.getUint32(21,true);return [(bits&16383)+1,((bits>>>14)&16383)+1];}
  }
  if(b.length>=4&&b[0]===255&&b[1]===216){
   let i=2;while(i+4<=b.length){if(b[i++]!==255)break;while(b[i]===255)i++;const marker=b[i++];if(marker===217||marker===218)break;if(marker===1||(marker>=208&&marker<=215))continue;
    if(i+2>b.length)break;const length=v.getUint16(i);if(length<2||i+length>b.length)break;
    if([192,193,194,195,197,198,199,201,202,203,205,206,207].includes(marker)&&length>=7)return [v.getUint16(i+5),v.getUint16(i+3)];i+=length;
   }
  }
  throw Error('Choose a valid PNG, JPEG, WebP or GIF image.');
 }
 function canvas(size){const node=root.document.createElement('canvas');node.width=size;node.height=size;return node;}
 function draw(ctx,image,size,mode='contain',ratio=1){
  const w=image.width||image.naturalWidth,h=image.height||image.naturalHeight;
  const scale=(mode==='cover'?Math.max(size/w,size/h):Math.min(size*ratio/w,size*ratio/h));
  ctx.drawImage(image,(size-w*scale)/2,(size-h*scale)/2,w*scale,h*scale);
 }
 function blob(node,type,quality){return new Promise((resolve,reject)=>node.toBlob(value=>value?resolve(value):reject(Error('Could not process this image.')),type,quality));}
 async function decode(file){
  if(root.createImageBitmap)return root.createImageBitmap(file,{imageOrientation:'from-image'});
  const url=root.URL.createObjectURL(file);try{return await new Promise((resolve,reject)=>{const image=new root.Image();image.onload=()=>resolve(image);image.onerror=()=>reject(Error('Could not read this image.'));image.src=url;});}finally{root.URL.revokeObjectURL(url);}
 }
 async function prepare(file,kind){
  if(!['gym','member'].includes(kind)||!file||file.size<=0||file.size>8*1024*1024)throw Error('Choose an image no larger than 8 MB.');
  const [width,height]=dimensions(await file.arrayBuffer());
  if(!width||!height||width>8192||height>8192||width*height>24000000)throw Error('Image dimensions are too large. Choose an image of 24 megapixels or less.');
  let image;try{
   image=await decode(file);const size=kind==='member'?256:512,node=canvas(size);draw(node.getContext('2d'),image,size,kind==='member'?'cover':'contain');
   const target=kind==='member'?40960:102400,limit=kind==='member'?65536:131072;let optimized,type='image/webp';
   for(const quality of [.84,.74,.64,.52,.42]){
    optimized=await blob(node,type,quality);
    if(type==='image/webp'&&optimized.type!=='image/webp'){
     const pixels=node.getContext('2d').getImageData(0,0,size,size).data;let transparent=false;
     for(let i=3;i<pixels.length;i+=4)if(pixels[i]<255){transparent=true;break;}
     type=kind==='gym'&&transparent?'image/png':'image/jpeg';
     if(type==='image/jpeg'&&transparent){const ctx=node.getContext('2d');ctx.globalCompositeOperation='destination-over';ctx.fillStyle='#090d16';ctx.fillRect(0,0,size,size);ctx.globalCompositeOperation='source-over';}
     optimized=await blob(node,type,quality);
    }
    if(type==='image/png'||optimized.size<=target)break;
   }
   if(optimized.size>limit)throw Error('This image is too detailed to save at the required size. Please choose a simpler image.');
   const files=new Map([[kind==='member'?'photo':'logo',optimized]]);
   if(kind==='gym'){
    for(const pixels of [192,512]){const icon=canvas(pixels);draw(icon.getContext('2d'),node,pixels,'contain',.9);files.set('icon-'+pixels+'.png',await blob(icon,'image/png'));}
    const mask=canvas(512),ctx=mask.getContext('2d');ctx.fillStyle='#090d16';ctx.fillRect(0,0,512,512);draw(ctx,node,512,'contain',.55);files.set('maskable-512.png',await blob(mask,'image/png'));
    if([...files.values()].some(value=>value.size>524288))throw Error('The generated logo icon is too large. Choose a simpler logo.');
   }
   const digest=await root.crypto.subtle.digest('SHA-256',await optimized.arrayBuffer());
   return {files,checksum:Array.from(new Uint8Array(digest),n=>n.toString(16).padStart(2,'0')).join(''),width:size,height:size,bytes:optimized.size};
  }finally{image?.close?.();}
 }
 async function rpc(client,action,payload={}){const {data,error}=await client.rpc('iv_profile_images',{p_action:action,p_payload:payload});if(error){if(['PGRST202','42883'].includes(error.code))throw Error('Photo storage is not installed yet. Ask the provider to apply migration 047.');throw Error(error.message||'Image operation failed.');}return data;}
 async function cleanup(client){
  const queue=await rpc(client,'cleanup');let pending=false;
  for(const job of queue||[]){
   try{const {error}=await client.storage.from(job.bucket).remove(job.files);if(error)throw error;await rpc(client,'ack',{request_id:job.id});}catch(_){pending=true;}
  }
  return pending||(queue||[]).length===20;
 }
 async function save(client,{kind,tenantId,memberId=null,expected='',file,prepared}){
  const image=prepared||await prepare(file,kind),id=root.crypto.randomUUID(),bucket=kind==='gym'?'iv-gym-images':'iv-member-images';let attempted=false,result;
  try{
   result=await rpc(client,'reserve',{request_id:id,tenant_id:tenantId,member_id:memberId,kind,expected:expected||'',checksum:image.checksum});
   if(result.state!=='pending')throw Error('Image request is no longer available. Refresh and try again.');
   for(const [name,value]of image.files){const {error}=await client.storage.from(bucket).upload(id+'/'+name,value,{contentType:value.type,cacheControl:kind==='gym'?'31536000':'0',upsert:false});if(error)throw Error(error.message||'Image upload failed.');}
   attempted=true;result=await rpc(client,'commit',{request_id:id});
  }catch(error){
   let status;try{status=await rpc(client,'status',{request_id:id});}catch(_){}
   if(status?.state==='active'){result=status;}
   else{
    if(status?.state==='pending'){try{await rpc(client,'cancel',{request_id:id});await cleanup(client);}catch(_){}}
    if(attempted&&!status)throw Error('The photo save could not be confirmed. Refresh the profile to check it before uploading again.');
    throw error;
   }
  }
  if(result?.state!=='active')throw Error('The photo was not saved. Refresh and try again.');
  let cleanupPending=false;try{cleanupPending=await cleanup(client);}catch(_){cleanupPending=true;}
  return {reference:result.reference,cleanupPending};
 }
 async function sign(client,path){
  const cached=signed.get(path);if(cached&&cached.until>Date.now())return cached.promise;
  const promise=(async()=>{const {data,error}=await client.storage.from('iv-member-images').createSignedUrl(path,120);if(error||!data?.signedUrl)throw Error('Photo unavailable.');return data.signedUrl;})();
  signed.set(path,{until:Date.now()+90000,promise});try{return await promise;}catch(error){signed.delete(path);throw error;}
 }
 function display(client,node){
  if(node.tagName!=='IMG')return;
  const ref=node.getAttribute('src'),path=photoPath(ref);if(!path)return;
  const ticket=epoch;node.dataset.ivPhotoRef=ref;node.removeAttribute('src');node.setAttribute('aria-busy','true');
  sign(client,path).then(url=>{if(ticket!==epoch||!node.isConnected||node.dataset.ivPhotoRef!==ref||node.getAttribute('src'))return;node.dataset.ivPhotoUrl=url;node.src=url;}).catch(()=>{if(ticket===epoch&&node.dataset.ivPhotoRef===ref)node.alt='Profile photo unavailable';}).finally(()=>node.removeAttribute('aria-busy'));
 }
 function scan(client,parent=root.document){for(const node of parent.querySelectorAll('img'))display(client,node);if(parent.tagName==='IMG')display(client,parent);}
 async function embedded(client,value){
  const privatePath=photoPath(value),publicPath=gymPath(value);if(!privatePath&&!publicPath)return value;
  const {data,error}=await client.storage.from(privatePath?'iv-member-images':'iv-gym-images').download(privatePath||publicPath);if(error||!data)throw Error('A profile image could not be included. Backup cancelled; refresh and try again.');
  return new Promise((resolve,reject)=>{const reader=new root.FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error('Could not read backup image.'));reader.readAsDataURL(data);});
 }
 async function backupRows(client,gyms,members){
  const owners=[],people=[];for(const gym of gyms)owners.push({...gym,logo:await embedded(client,gym.logo)});for(const member of members)people.push({...member,avatar:await embedded(client,member.avatar)});
  return {owners,members:people};
 }
 function install(app,client,kind){
  if(installed.has(client)||typeof root.MutationObserver!=='function')return;installed.add(client);
  const observer=new root.MutationObserver(records=>{for(const record of records){if(record.type==='attributes')display(client,record.target);else for(const node of record.addedNodes)if(node.nodeType===1)scan(client,node);}});
  observer.observe(root.document.body,{subtree:true,childList:true,attributes:true,attributeFilter:['src']});scan(client);
  const refresh=()=>{for(const node of root.document.querySelectorAll('img[data-iv-photo-ref]')){const ref=node.dataset.ivPhotoRef,src=node.getAttribute('src');if(!src||src===node.dataset.ivPhotoUrl){node.setAttribute('src',ref);display(client,node);}else{delete node.dataset.ivPhotoRef;delete node.dataset.ivPhotoUrl;}}};
  let timer=root.setInterval(refresh,60000),identity=null;
  client.auth.onAuthStateChange((event,session)=>{const id=session?.user?.id;if(event==='INITIAL_SESSION'||event==='SIGNED_IN'&&!identity){identity=id;return;}if(event==='SIGNED_OUT'||event==='SIGNED_IN'&&id!==identity){identity=id||null;epoch++;signed.clear();for(const node of root.document.querySelectorAll('img[data-iv-photo-ref]')){node.removeAttribute('src');delete node.dataset.ivPhotoRef;delete node.dataset.ivPhotoUrl;}}});
  root.addEventListener('pagehide',()=>{root.clearInterval(timer);signed.clear();});
  root.addEventListener('pageshow',event=>{if(event.persisted){refresh();root.clearInterval(timer);timer=root.setInterval(refresh,60000);}});
  if(kind==='master'){
   let exporting=false;
   async function exportZip(tenant){if(exporting)return;exporting=true;try{
    const gyms=tenant?app.owners.filter(g=>g.id===tenant):app.owners,members=tenant?app.members.filter(m=>m.tenantId===tenant):app.members;if(tenant&&!gyms.length)throw Error('Select a gym first.');
    const data=await backupRows(client,gyms,members),ownersText=JSON.stringify(data.owners,null,2),membersText=JSON.stringify(data.members,null,2);
    if(new TextEncoder().encode(ownersText).length>10000000||new TextEncoder().encode(membersText).length>10000000)throw Error('Backup exceeds the existing 10 MB restore limit. Use a smaller gym-specific backup.');
    const zip=new root.JSZip();zip.file(tenant?'tenant_owner_export.json':'ironvault_owners_export.json',ownersText);zip.file(tenant?'tenant_members_export.json':'ironvault_members_export.json',membersText);
    const content=await zip.generateAsync({type:'blob'});if(content.size>10000000)throw Error('Backup exceeds the existing 10 MB restore limit.');
    const link=root.document.createElement('a'),url=root.URL.createObjectURL(content);link.href=url;link.download=(tenant?gyms[0].gymName.replace(/[^a-zA-Z0-9]/g,'_'):'IronVault')+'_Backup_'+new Date().toISOString().slice(0,10)+'.zip';root.document.body.append(link);link.click();link.remove();root.setTimeout(()=>root.URL.revokeObjectURL(url),30000);
   }catch(error){root.alert(error.message);}finally{exporting=false;}}
   app.exportDataToZip=()=>exportZip();app.exportTenantZip=()=>exportZip(app.currentInspectOwnerId);
  }
  // Retry durable cleanup after authenticated loads/restores/purges, not on every live poll.
  let cleanupTimer;
  function scheduleCleanup(){root.clearTimeout(cleanupTimer);cleanupTimer=root.setTimeout(async()=>{try{const {data,error}=await client.auth.getUser();if(!error&&data?.user)await cleanup(client);}catch(_){}},1000);}
  for(const name of ['init','loadData']){const original=app[name];if(typeof original==='function')app[name]=async function(...args){const result=await original.apply(this,args);scheduleCleanup();return result;};}
 }
 const api=Object.freeze({prepare,save,cleanup,install,photoPath,gymPath,dimensions,backupRows});root.IronVaultProfileImages=api;
 if(typeof module==='object'&&module.exports)module.exports=api;
})(globalThis);
