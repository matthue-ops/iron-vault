const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const images=require('../assets/profile-images.js');
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
function fixture({lostCommit=false,failUpload=false,failCleanup=false}={}){
 const calls=[],objects=new Map();let state=null,ref=null;
 const client={rpc:async(name,args)=>{assert.equal(name,'iv_profile_images');calls.push(args.p_action);const p=args.p_payload;
  if(args.p_action==='reserve'){state='pending';return {data:{id:p.request_id,state},error:null};}
  if(args.p_action==='commit'){state='active';ref='iv-photo:'+p.request_id;if(lostCommit)return {error:{message:'Lost response'}};return {data:{state,reference:ref},error:null};}
  if(args.p_action==='status')return {data:{state,reference:ref},error:null};
  if(args.p_action==='cancel'){state='retired';return {data:{state},error:null};}
  if(args.p_action==='cleanup'){if(failCleanup)return {error:{message:'offline'}};return {data:[],error:null};}
  return {data:{},error:null};},storage:{from:()=>({upload:async(path,file,options)=>{assert.equal(options.upsert,false);if(failUpload)return {error:{message:'Upload rejected'}};objects.set(path,file);return {error:null}},remove:async()=>({error:null})})}};
 return {client,calls,objects};
}
const prepared={checksum:'a'.repeat(64),files:new Map([['photo',new Blob(['test'],{type:'image/webp'})]])};
test('profile references accept only managed private tokens and the configured public gym bucket',()=>{
 assert.equal(images.photoPath('iv-photo:'+id),id+'/photo');assert.equal(images.photoPath('https://evil.test/photo'),null);assert.equal(images.photoPath('iv-photo:../../bad'),null);
 assert.equal(images.gymPath('https://uarvhalocgyrikjbrloh.supabase.co/storage/v1/object/public/iv-gym-images/'+id+'/logo'),id+'/logo');
 assert.equal(images.gymPath('https://evil.test/storage/v1/object/public/iv-gym-images/'+id+'/logo'),null);
});
test('image save stages immutable files then attaches, without rewriting the member profile',async()=>{
 const f=fixture(),result=await images.save(f.client,{kind:'member',tenantId:'g',memberId:'m',expected:'old',prepared});assert.match(result.reference,/^iv-photo:/);assert.deepEqual(f.calls,['reserve','commit','cleanup']);assert.equal(f.objects.size,1);
});
test('lost committed response resolves the same request receipt instead of uploading again',async()=>{
 const f=fixture({lostCommit:true}),result=await images.save(f.client,{kind:'member',tenantId:'g',memberId:'m',expected:'old',prepared});assert.match(result.reference,/^iv-photo:/);assert.deepEqual(f.calls,['reserve','commit','status','cleanup']);assert.equal(f.objects.size,1);
});
test('failed upload cancels the staged replacement and never attempts attachment',async()=>{
 const f=fixture({failUpload:true});await assert.rejects(()=>images.save(f.client,{kind:'member',tenantId:'g',memberId:'m',expected:'old',prepared}),/Upload rejected/);assert.deepEqual(f.calls,['reserve','status','cancel','cleanup']);assert.equal(f.objects.size,0);
});
test('cleanup failure is a pending cleanup note, not a failed successfully saved photo',async()=>{
 const f=fixture({failCleanup:true}),result=await images.save(f.client,{kind:'member',tenantId:'g',memberId:'m',expected:'old',prepared});assert.equal(result.cleanupPending,true);assert.match(result.reference,/^iv-photo:/);
});
test('input dimension checks reject non-raster content before any decode/upload',()=>{
 assert.throws(()=>images.dimensions(new TextEncoder().encode('<svg onload="evil()"></svg>').buffer),/valid PNG/);
 const b=new Uint8Array(24);b.set([137,80,78,71]);new DataView(b.buffer).setUint32(16,512);new DataView(b.buffer).setUint32(20,256);assert.deepEqual(images.dimensions(b.buffer),[512,256]);
});
test('047 migration copies are identical and never delete storage metadata or rewrite financial tables',()=>{
 const sql=fs.readFileSync('supabase/manual/optimized_profile_images.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/migrations/202611080047_optimized_profile_images.sql','utf8'));
 assert.doesNotMatch(sql,/DELETE FROM storage\.objects|UPDATE public\.(iv_transactions|iv_attendance_logs)|DROP TABLE|DROP COLUMN/i);
 assert.match(sql,/AS RESTRICTIVE FOR UPDATE/);assert.match(sql,/md5\(coalesce\(current_value,''\)\)<>img.base_hash/);assert.match(sql,/p_action='ack'/);
});
test('app manifest uses versioned gym logo icons and rejects arbitrary icon URLs',async()=>{
 const {onRequest}=await import('data:text/javascript;base64,'+Buffer.from(fs.readFileSync('functions/[[path]].js','utf8')).toString('base64'));
 const manifest=async image=>(await onRequest({request:new Request('https://demo.test/gym-app.webmanifest?gym=g&key=public&image='+encodeURIComponent(image)),env:{}})).json();
 const data=await manifest(id);assert.equal(data.icons.length,3);assert.equal(data.icons[0].purpose,'any');assert.equal(data.icons[2].purpose,'maskable');assert(data.icons.every(i=>i.src.includes('/'+id+'/')));
 assert((await manifest('https://evil.test/icon.png')).icons.every(i=>i.src.startsWith('/assets/')));
});
test('member upload keeps the old photo on failure and blocks a second submission while saving',async()=>{
 const vm=require('node:vm');let finish,calls=0,fail=false,rendered=0;const alerts=[];
 const root={IronVaultProfileImages:{save:async()=>{calls++;await new Promise(r=>finish=r);if(fail)throw Error('offline');return {reference:'iv-photo:'+id}}},document:{getElementById:()=>({})}};
 vm.runInNewContext(fs.readFileSync('assets/application-workflows.js','utf8'),root);
 const app={currentMember:{id:'m',tenantId:'g',avatar:'old'},renderProfile(){rendered++},showAlert:(text,ok)=>alerts.push({text,ok})};root.IronVaultWorkflows.install(app,{},'member');
 const input={files:[{}],disabled:false,value:'selected'};const first=app.handleAvatarUpload({target:input});await app.handleAvatarUpload({target:input});assert.equal(calls,1);assert.equal(input.disabled,true);assert.equal(app.currentMember.avatar,'old');fail=true;finish();await first;assert.equal(app.currentMember.avatar,'old');assert.equal(input.disabled,false);assert.equal(rendered,0);assert.equal(alerts.at(-1).ok,false);
 fail=false;const second=app.handleAvatarUpload({target:input});finish();await second;assert.equal(app.currentMember.avatar,'iv-photo:'+id);assert.equal(rendered,1);assert.equal(alerts.at(-1).ok,true);
});
