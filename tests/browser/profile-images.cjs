/* Real browser image processing and signed-image DOM behavior, entirely mocked backend. */
const {chromium}=require('playwright'),fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});try{
const p=await browser.newPage({viewport:{width:390,height:850}});await p.route('https://images.test/**',r=>r.fulfill({contentType:'text/html',body:'<!doctype html><html><body><main><h1>Image processing preview</h1></main></body></html>'}));await p.goto('https://images.test/');await p.addScriptTag({path:'assets/profile-images.js'});
const result=await p.evaluate(async()=>{
 const input=document.createElement('canvas');input.width=1600;input.height=800;const c=input.getContext('2d');c.fillStyle='#10b981';c.fillRect(500,100,600,600);
 const raw=await new Promise(r=>input.toBlob(r,'image/png')),file=new File([raw],'logo.png',{type:'image/png'});
 const gym=await IronVaultProfileImages.prepare(file,'gym'),member=await IronVaultProfileImages.prepare(file,'member');window.preparedGym=gym;
 async function inspect(blob){const image=await createImageBitmap(blob),canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);const alpha=ctx.getImageData(0,0,1,1).data[3],center=Array.from(ctx.getImageData(image.width/2,image.height/2,1,1).data);const item={type:blob.type,bytes:blob.size,width:image.width,height:image.height,alpha,center};image.close();return item;}
 const stats={};for(const [name,blob]of gym.files)stats[name]=await inspect(blob);stats.member=await inspect(member.files.get('photo'));
 for(const [name,blob]of gym.files){const img=document.createElement('img');img.style.cssText='width:150px;height:150px;object-fit:contain;background:repeating-conic-gradient(#ddd 0% 25%,white 0% 50%) 0/16px 16px';img.alt=name;img.src=URL.createObjectURL(blob);document.querySelector('main').append(img);}
 let bad=false;try{await IronVaultProfileImages.prepare(new File(['<svg/>'],'bad.svg',{type:'image/svg+xml'}),'gym')}catch(_){bad=true}
 const big=new Uint8Array(24);big.set([137,80,78,71]);new DataView(big.buffer).setUint32(16,30000);new DataView(big.buffer).setUint32(20,30000);let dimensionsRejected=false;try{await IronVaultProfileImages.prepare(new File([big],'big.png',{type:'image/png'}),'gym')}catch(e){dimensionsRejected=/dimensions/.test(e.message)}
 return {stats,bad,dimensionsRejected};
});
const fallback=await p.evaluate(async()=>{
 const original=HTMLCanvasElement.prototype.toBlob;HTMLCanvasElement.prototype.toBlob=function(fn,type,quality){return original.call(this,fn,type==='image/webp'?'image/png':type,quality)};
 try{const canvas=document.createElement('canvas');canvas.width=800;canvas.height=800;const c=canvas.getContext('2d');c.fillStyle='#10b981';c.fillRect(200,200,400,400);const raw=await new Promise(r=>canvas.toBlob(r,'image/png')),file=new File([raw],'transparent.png',{type:'image/png'});const logo=await IronVaultProfileImages.prepare(file,'gym'),member=await IronVaultProfileImages.prepare(file,'member');const icon=await createImageBitmap(logo.files.get('icon-512.png'));const out=document.createElement('canvas');out.width=512;out.height=512;out.getContext('2d').drawImage(icon,0,0);const alpha=out.getContext('2d').getImageData(0,0,1,1).data[3];icon.close();return {logoType:logo.files.get('logo').type,memberType:member.files.get('photo').type,alpha};}finally{HTMLCanvasElement.prototype.toBlob=original;}
});assert.equal(fallback.logoType,'image/png');assert.equal(fallback.memberType,'image/jpeg');assert.equal(fallback.alpha,0);
assert.equal(result.stats['logo'].type,'image/webp');assert.equal(result.stats['logo'].width,512);assert.equal(result.stats['logo'].alpha,0);assert.equal(result.stats['icon-192.png'].width,192);assert.equal(result.stats['icon-512.png'].width,512);assert.equal(result.stats['icon-512.png'].alpha,0);assert.equal(result.stats['maskable-512.png'].alpha,255);assert.equal(result.stats.member.width,256);assert(result.stats.member.bytes<=65536);assert(result.stats['logo'].bytes<=131072);assert(result.bad);assert(result.dimensionsRejected);await p.screenshot({path:'/tmp/iv-profile-images-preview.png'});console.log('Raster resize, WebP caps, logo transparency, PNG icon dimensions, opaque maskable icon, SVG/pixel-limit rejection passed.');
await p.evaluate(()=>{
 window.authCallback=null;window.signedCalls=0;window.pendingSign=null;
 window.client={auth:{onAuthStateChange(fn){authCallback=fn}},storage:{from:()=>({createSignedUrl:async path=>{signedCalls++;if(window.delaySign)return new Promise(r=>pendingSign=r);return {data:{signedUrl:'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'}}}})}};
 IronVaultProfileImages.install({},client,'member');authCallback('INITIAL_SESSION',{user:{id:'member'}});
 const img=document.createElement('img');img.id='private';img.src='iv-photo:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';document.body.append(img);
});
await p.waitForFunction(()=>document.getElementById('private').src.startsWith('data:'));assert.equal(await p.evaluate(()=>signedCalls),1);
await p.evaluate(()=>{authCallback('SIGNED_IN',{user:{id:'member'}})});assert.equal(await p.locator('#private').getAttribute('src')!==null,true);
await p.evaluate(()=>{authCallback('SIGNED_OUT',null)});assert.equal(await p.locator('#private').getAttribute('src'),null);
await p.evaluate(()=>{window.delaySign=true;const image=document.createElement('img');image.id='late';image.src='iv-photo:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';document.body.append(image)});await p.waitForFunction(()=>!!pendingSign);await p.evaluate(()=>{authCallback('SIGNED_OUT',null);pendingSign({data:{signedUrl:'https://should-not-appear.invalid/photo'}})});await p.waitForTimeout(20);assert.equal(await p.locator('#late').getAttribute('src'),null);
console.log('Private references resolve only into DOM, same-user sign-in preserves photos, and sign-out/lost responses cannot reveal a late photo.');
// Export includes actual file bytes, not expiring links or storage references.
const backup=await p.evaluate(async()=>{
 const client={storage:{from:()=>({download:async()=>({data:new Blob(['embedded'],{type:'image/webp'}),error:null})})}};
 return IronVaultProfileImages.backupRows(client,[{id:'g',logo:'https://uarvhalocgyrikjbrloh.supabase.co/storage/v1/object/public/iv-gym-images/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/logo'}],[{id:'m',avatar:'iv-photo:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}]);
});assert.match(backup.owners[0].logo,/^data:image\/webp;base64,/);assert.match(backup.members[0].avatar,/^data:image\/webp;base64,/);console.log('Managed gym/member images are embedded in portable backup rows.');
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});
