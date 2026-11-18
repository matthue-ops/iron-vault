/* CR80 artwork. Private files stay in memory; official export is authorized separately. */
(function(root){
 'use strict';
 const W=85.60,H=53.98,DPI=600,S=DPI/25.4,QR={x:56,y:18,size:26},libraries=new Map();
 function library(name,file){if(root[name])return Promise.resolve(root[name]);if(libraries.has(name))return libraries.get(name);const promise=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='/assets/vendor/'+file;s.onload=()=>root[name]?resolve(root[name]):reject(Error('Print library unavailable'));s.onerror=()=>reject(Error('Print library could not load'));document.head.append(s);}).catch(error=>{libraries.delete(name);throw error;});libraries.set(name,promise);return promise;}
 function canvas(){const c=document.createElement('canvas');c.width=Math.round(W*S);c.height=Math.round(H*S);c.setAttribute('role','img');return c;}
 async function image(client,ref){
  if(!ref)return null;let blob;const p=root.IronVaultProfileImages;
  const background=/^iv-background:([a-f0-9-]{36})$/.exec(ref);
  if(background){const {data,error}=await client.storage.from('iv-card-backgrounds').download(background[1]+'/background');if(error||!data)throw Error('Background unavailable');blob=data;}
  const member=p?.photoPath(ref),gym=p?.gymPath(ref);
  if(background){}
  else if(member||gym){const {data,error}=await client.storage.from(member?'iv-member-images':'iv-gym-images').download(member||gym);if(error||!data)throw Error('Image unavailable');blob=data;}
  else if(/^data:image\/(png|jpeg|webp);base64,[a-z0-9+/=\s]+$/i.test(ref)&&ref.length<1100000){blob=await (await fetch(ref)).blob();}
  else throw Error('Upload the image through the gym/member profile before production');
  if(blob.size>8*1024*1024)throw Error('Image too large');
  return root.createImageBitmap(blob);
 }
 function text(ctx,value,x,y,width,height,pt,min=pt,bold=false){
  value=String(value||'');if(!value)return false;
  for(let size=pt;size>=min;size-=.5){ctx.font=(bold?'700 ':'400 ')+(size*DPI/72)+'px Arial, sans-serif';const lines=[];let line='';
   for(const word of value.split(/\s+/)){const next=line?line+' '+word:word;if(ctx.measureText(next).width>width*S&&line){lines.push(line);line=word;}else line=next;}
   if(line)lines.push(line);const step=size*DPI/72*1.17;
   if(lines.length*step<=height*S&&lines.every(l=>ctx.measureText(l).width<=width*S)){ctx.textBaseline='top';lines.forEach((l,i)=>ctx.fillText(l,x*S,y*S+i*step));return true;}
  }return false;
 }
 function fitImage(ctx,img,x,y,w,h,cover=false){const factor=cover?Math.max(w*S/img.width,h*S/img.height):Math.min(w*S/img.width,h*S/img.height);ctx.save();ctx.beginPath();ctx.rect(x*S,y*S,w*S,h*S);ctx.clip();ctx.drawImage(img,x*S+(w*S-img.width*factor)/2,y*S+(h*S-img.height*factor)/2,img.width*factor,img.height*factor);ctx.restore();}
 function qr(ctx,matrix){const n=matrix.getModuleCount(),unit=QR.size*S/(n+8);ctx.fillStyle='#fff';ctx.fillRect(QR.x*S,QR.y*S,QR.size*S,QR.size*S);ctx.fillStyle='#000';for(let y=0;y<n;y++)for(let x=0;x<n;x++)if(matrix.isDark(y,x))ctx.fillRect(Math.round(QR.x*S+(x+4)*unit),Math.round(QR.y*S+(y+4)*unit),Math.ceil(unit),Math.ceil(unit));}
 async function render(data,client){
  if(!/^IVC1\|[0-9a-f-]{36}$/i.test(data.payload||''))throw Error('Current permanent card unavailable');
  await library('QRCode','qrcode.min.js');const holder=document.createElement('div');const code=new root.QRCode(holder,{text:data.payload,width:600,height:600,correctLevel:root.QRCode.CorrectLevel.H});const matrix=code._oQRCode;holder.replaceChildren();
  const front=canvas(),back=canvas(),issues=[],m=data.member,g=data.gym;let photo,logo;
  try{photo=await image(client,m.photo);if(!photo)issues.push('Member photo required');}catch(_){issues.push('Member photo unavailable — upload or retry before production');}
  try{logo=await image(client,g.logo);if(!logo)issues.push('Gym logo required');}catch(_){issues.push('Gym logo unavailable — upload or retry before production');}
  for(const [value,label] of [[m.name,'Member name'],[m.display_code,'Member number'],[g.name,'Gym name'],[g.address,'Gym address'],[g.email||g.phone,'Gym contact']])if(!String(value||'').trim())issues.push(label+' required');
  const design=data.design||{},colour=(value,fallback)=>/^#[0-9a-f]{6}$/i.test(value||'')?value:fallback,accent=colour(design.accent,colour(g.accent,'#0f766e')),primary=colour(design.primary,accent),dark=design.tone==='dark'||design.template==='premium';
  const ink=dark?'#ffffff':'#111827',muted=dark?'#e2e8f0':'#334155';
  for(const c of [front,back]){const ctx=c.getContext('2d'),side=c===front?'front':'back';ctx.fillStyle=dark?'#101827':'#ffffff';ctx.fillRect(0,0,c.width,c.height);
   if(design[side+'_background']){let bg;try{bg=await image(client,'iv-background:'+design[side+'_background']);const factor=Math.max(c.width/bg.width,c.height/bg.height),x=(c.width-bg.width*factor)*(Number(design[side+'_x']??50)/100),y=(c.height-bg.height*factor)*(Number(design[side+'_y']??50)/100);ctx.drawImage(bg,x,y,bg.width*factor,bg.height*factor);if(factor>2)issues.push(side+' background is below recommended 300 DPI');ctx.fillStyle=dark?'#101827':'#ffffff';ctx.globalAlpha=Math.max(.85,Number(design[side+'_overlay']??85)/100);ctx.fillRect(0,0,c.width,c.height);ctx.globalAlpha=1;}catch(_){issues.push(side+' background unavailable — refresh or reset before production');}finally{bg?.close();}}
   ctx.fillStyle=primary;if(design.template==='modern')ctx.fillRect(0,0,c.width,3.7*S);else ctx.fillRect(2.5*S,2.5*S,80.6*S,1.2*S);
   if(design.template==='premium'){ctx.save();ctx.strokeStyle=accent;ctx.globalAlpha=.12;for(let x=-c.height;x<c.width;x+=80){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x+c.height,c.height);ctx.stroke();}ctx.restore();}ctx.fillStyle=accent;ctx.fillRect(2.5*S,3.5*S,15*S,.5*S);}
  const f=front.getContext('2d');f.fillStyle=ink;
  if(logo)fitImage(f,logo,3.5,5,9,9);else{text(f,'Logo required',3.5,5,10,10,7);}
  if(!text(f,g.name||'Gym name required',15,5,66,6,12,9,true))issues.push('Gym name does not fit the card');
  f.fillStyle=muted;text(f,'MEMBERSHIP CARD',15,12,66,4,8);f.fillStyle=ink;
  if(photo)fitImage(f,photo,3.5,design.template==='modern'?19:20,design.template==='modern'?21.5:20,design.template==='modern'?21.5:20,true);else{f.fillStyle=dark?'#1e293b':'#f1f5f9';f.fillRect(3.5*S,20*S,20*S,20*S);f.fillStyle=ink;text(f,'Photo required',4.5,26,18,10,8);}
  if(photo&&Math.min(photo.width,photo.height)<(design.template==='modern'?254:236))issues.push('Member photo is below the recommended 300 DPI at print size');
  if(!text(f,m.name||'Member name required',26,19,28,15,11,9,true))issues.push('Member name does not fit the card');
  f.fillStyle=muted;text(f,'Member no.',26,35,28,3,7);f.fillStyle=ink;if(!text(f,m.display_code||'Number required',26,38,28,5,9,8,true))issues.push('Member number does not fit');
  qr(f,matrix);f.fillStyle=muted;if(!text(f,g.address||'Gym address required',3.5,45,78.5,6,7,7))issues.push('Gym address does not fit the front; review the public address');
  const b=back.getContext('2d');b.fillStyle=ink;text(b,'Found this card?',3.5,7,78.5,6,13,13,true);
  if(!text(b,'Please return it to '+(g.name||'[Gym name]')+'.',3.5,14,78.5,8,10,9,true))issues.push('Return instructions do not fit');
  if(!text(b,g.address||'Gym address required',3.5,24,78.5,7,8,7))issues.push('Gym address does not fit the back');
  if(!text(b,[g.phone,g.email].filter(Boolean).join(' · ')||'Gym contact required',3.5,32,78.5,6,8,7))issues.push('Gym contact information does not fit');
  b.fillStyle=muted;if(!text(b,'For the named member only. Entry requires a valid pass and staff verification. If lost, report this card to the gym immediately.',3.5,40,78.5,10,8,7))issues.push('Card instructions do not fit');
  photo?.close();logo?.close();front.setAttribute('aria-label','Physical ID front for '+m.name);back.setAttribute('aria-label','Physical ID back');
  return {front,back,matrix,issues:[...new Set(issues)],destroy(){for(const c of [front,back]){c.width=0;c.height=0;}}};
 }
 const png=c=>new Promise((resolve,reject)=>c.toBlob(b=>b?resolve(b):reject(Error('Card image could not be generated')),'image/png'));
 async function files(data,art){
  if(art.issues.length)throw Error('Resolve production requirements before downloading');
  const PDF=await library('PDFLib','pdf-lib.min.js'),Zip=await library('JSZip','jszip.min.js');
  const front=await png(art.front),back=await png(art.back),zip=new Zip();zip.file('front-600dpi.png',front);zip.file('back-600dpi.png',back);
  for(const bleed of [0,3]){const pdf=await PDF.PDFDocument.create();const scale=72/25.4;
   for(const [i,blob] of [front,back].entries()){const page=pdf.addPage([(W+2*bleed)*scale,(H+2*bleed)*scale]),image=await pdf.embedPng(await blob.arrayBuffer());page.drawImage(image,{x:bleed*scale,y:bleed*scale,width:W*scale,height:H*scale});page.setTrimBox(bleed*scale,bleed*scale,W*scale,H*scale);
    if(i===0){const n=art.matrix.getModuleCount(),unit=QR.size/(n+8);page.drawRectangle({x:(bleed+QR.x)*scale,y:(bleed+H-QR.y-QR.size)*scale,width:QR.size*scale,height:QR.size*scale,color:PDF.rgb(1,1,1)});
     for(let y=0;y<n;y++)for(let x=0;x<n;x++)if(art.matrix.isDark(y,x))page.drawRectangle({x:(bleed+QR.x+(x+4)*unit)*scale,y:(bleed+H-QR.y-(y+5)*unit)*scale,width:unit*scale,height:unit*scale,color:PDF.rgb(0,0,0)});
    }
   }zip.file(bleed?'card-production-3mm-bleed.pdf':'card-local-actual-size.pdf',await pdf.save());
  }
  zip.file('PRINT-INSTRUCTIONS.txt','CR80 membership card: 85.60 × 53.98 mm. Front/back PNG: 600 DPI.\nLocal PDF: print at actual size (100%); disable fit-to-page. Production PDF: 3 mm white bleed and exact TrimBox.\nBoth sides have the same top edge; do not mirror. Test duplex alignment and scan a physical proof before a batch.\nThis is a gym membership card, not a government ID. No expiry is printed.\nFiles cannot be recalled; a revoked QR will no longer grant entry. A file download does not mark the card issued.\n');
  return zip.generateAsync({type:'blob'});
 }
 async function qrFiles(payload){
  if(!/^IVC1\|[0-9a-f-]{36}$/i.test(payload||''))throw Error('Current permanent QR unavailable');
  await library('QRCode','qrcode.min.js');const holder=document.createElement('div'),code=new root.QRCode(holder,{text:payload,width:600,height:600,correctLevel:root.QRCode.CorrectLevel.H}),matrix=code._oQRCode,n=matrix.getModuleCount(),total=n+8,node=document.createElement('canvas');holder.replaceChildren();node.width=node.height=2048;const ctx=node.getContext('2d'),unit=Math.floor(2048/total),offset=Math.floor((2048-total*unit)/2);ctx.fillStyle='#fff';ctx.fillRect(0,0,2048,2048);ctx.fillStyle='#000';const paths=[];
  for(let y=0;y<n;y++)for(let x=0;x<n;x++)if(matrix.isDark(y,x)){ctx.fillRect(offset+(x+4)*unit,offset+(y+4)*unit,unit,unit);paths.push('M'+(x+4)+' '+(y+4)+'h1v1h-1z');}
  const svg='<svg xmlns="http://www.w3.org/2000/svg" width="2048" height="2048" viewBox="0 0 '+total+' '+total+'" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="white"/><path fill="black" d="'+paths.join('')+'"/></svg>';
  try{const Zip=await library('JSZip','jszip.min.js'),zip=new Zip();zip.file('member-qr-2048.png',await png(node));zip.file('member-qr.svg',svg);zip.file('QR-PRINT-NOTES.txt','Current permanent gym membership QR. Keep the white area and four-module quiet zone. Do not crop, stretch, recolour or place a logo over the QR.\nUse a minimum 26 mm square QR area for this credential and scan a physical proof before production. Keep files private. Saved copies cannot be recalled; revocation makes this QR invalid. Downloading does not issue a card or record entry.\n');return await zip.generateAsync({type:'blob'});}finally{node.width=node.height=0;}
 }
 root.IronVaultPhysicalCard=Object.freeze({render,files,qrFiles,width:W,height:H,dpi:DPI,qr:QR});
})(globalThis);
