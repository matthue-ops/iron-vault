/* Real 054/055/056 SQL, disposable PGlite and synthetic accounts only. */
const fs=require('node:fs'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),{PGlite}=require(process.env.PGLITE_MODULE||'@electric-sql/pglite');
function extract(file,name){const s=fs.readFileSync(file,'utf8'),i=s.search(new RegExp('CREATE(?: OR REPLACE)? FUNCTION '+name.replaceAll('.','\\.')+'\\('));assert(i>=0,name);return s.slice(i,s.indexOf('$fn$;',i)+6);}
(async()=>{const db=new PGlite();try{
// Reuse the established 055 fixture setup, without its historical workflow assertions.
const prior=fs.readFileSync('tests/database/physical-membership-ids.cjs','utf8'),start=prior.indexOf('const old='),end=prior.indexOf('const ids=');assert(start>=0&&end>start);await new (Object.getPrototypeOf(async function(){}).constructor)('db','fs','assert','extract',prior.slice(start,end))(db,fs,assert,extract);
const ids={owner:'11111111-1111-4111-8111-111111111111',staff:'22222222-2222-4222-8222-222222222222',member:'33333333-3333-4333-8333-333333333333',provider:'44444444-4444-4444-8444-444444444444',other:'55555555-5555-4555-8555-555555555555'};
const q=async(s,a=[])=>(await db.query(s,a)).rows[0];async function actor(n){await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[ids[n]||'']);await db.exec('SET ROLE authenticated');}
const query=async(action,data={},t='a')=>(await q('SELECT public.iv_physical_ids($1,$2,$3) r',[t,action,data])).r;
const action=async(type,data,t='a')=>(await q('SELECT public.iv_physical_id_action($1,$2,$3) r',[t,type,data])).r;
const op=(card,extra={})=>({operation_id:randomUUID(),member_id:'one',card_id:card.card_id,...extra});
async function admin(s){await db.exec('RESET ROLE');await db.exec(s);await actor('owner');}
const protectedNames=['public.iv_verify_entry_qr(text,text,boolean)','public.iv_approve_entry_qr(text,text)','public.iv_checkin(text,text)','public.iv_issue_member_pass(text)','ironvault_private.record_admission(text,text)','public.iv_staff_access(text,text,uuid,jsonb)','public.iv_member_announcements(text,text,jsonb)','public.iv_account_announcements(text,text,jsonb)','public.iv_provider_console(text,jsonb)'];
const defs=(await db.query('SELECT oid,pg_get_functiondef(oid) definition FROM pg_proc WHERE oid=ANY($1::regprocedure[]) ORDER BY oid',[protectedNames])).rows;
const tokens=(await db.query('SELECT token,revoked_at,version FROM ironvault_private.member_cards ORDER BY token')).rows;
const sql=fs.readFileSync('supabase/migrations/202611180056_physical_id_workflow.sql','utf8');assert.equal(sql,fs.readFileSync('supabase/manual/physical_id_workflow.sql','utf8'));await db.exec(sql);
assert.deepEqual((await db.query('SELECT token,revoked_at,version FROM ironvault_private.member_cards ORDER BY token')).rows,tokens);assert.deepEqual((await db.query('SELECT oid,pg_get_functiondef(oid) definition FROM pg_proc WHERE oid=ANY($1::regprocedure[]) ORDER BY oid',[protectedNames])).rows,defs);

await db.exec(`CREATE SCHEMA storage;CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);CREATE TABLE storage.objects(id uuid DEFAULT gen_random_uuid(),bucket_id text,name text);ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;GRANT USAGE ON SCHEMA storage TO authenticated;GRANT SELECT,INSERT,DELETE,UPDATE ON storage.objects TO authenticated;`);
const appearance=fs.readFileSync('supabase/migrations/202611180057_physical_id_appearance.sql','utf8');assert.equal(appearance,fs.readFileSync('supabase/manual/physical_id_appearance.sql','utf8'));await db.exec(appearance);
const design=async(a,d={},t='a')=>(await q('SELECT public.iv_physical_id_design($1,$2,$3) r',[t,a,d])).r;
await actor('owner');const original=await query('preview',{member_id:'one'});assert.equal(original.permissions.design,true);assert.equal(original.design_revision,0);
const file=await design('reserve');await db.query("INSERT INTO storage.objects(bucket_id,name) VALUES('iv-card-backgrounds',$1)",[file.id+'/background']);
const value={template:'premium',tone:'dark',primary:'#123456',accent:'#ffcc00',front_background:file.id,front_x:20,front_y:70,front_overlay:85};const saved=await design('save',{revision:0,design:value});assert.equal(saved.revision,1);assert.deepEqual(await design('save',{revision:0,design:value}),saved);
await assert.rejects(()=>design('save',{revision:0,design:{...value,template:'modern'}}),/changed/);
const current=await query('preview',{member_id:'one'});assert.equal(current.payload,original.payload);assert.equal(current.version,original.version);assert.deepEqual(current.design,value);assert.notEqual(current.snapshot_hash,original.snapshot_hash);
await assert.rejects(()=>action('download_direct',op(original,{snapshot_hash:original.snapshot_hash,appearance_version:4})),/changed|obsolete/);await action('download_direct',op(current,{snapshot_hash:current.snapshot_hash,appearance_version:4}));
await assert.rejects(()=>design('save',{revision:1,design:{...value,front_background:randomUUID()}}),/Background/);await assert.rejects(()=>design('save',{revision:1,design:{...value,front_x:-1}}),/position/);await assert.rejects(()=>design('save',{revision:1,design:{...value,payload:'evil'}}),/Unsupported/);
for(const who of ['member','staff','provider','other']){await actor(who);await assert.rejects(()=>design('get'),/permission/);if(who!=='other'){const c=await query('preview',{member_id:'one'});assert.equal(c.permissions.design,false);assert.equal(c.payload,original.payload);}const rows=await db.query("SELECT name FROM storage.objects WHERE bucket_id='iv-card-backgrounds'");assert.equal(rows.rows.length,who==='other'?0:1);}
await actor('other');await assert.rejects(()=>design('save',{revision:0,design:value},'b'),/Background/);await assert.rejects(()=>db.query("INSERT INTO storage.objects(bucket_id,name) VALUES('iv-card-backgrounds',$1)",[file.id+'/background']),/policy/);
await actor('owner');await db.query("DELETE FROM storage.objects WHERE bucket_id='iv-card-backgrounds'");assert.equal((await db.query("SELECT * FROM storage.objects")).rows.length,1);
await assert.rejects(()=>action('download_direct',op(current,{snapshot_hash:current.snapshot_hash})),/Refresh/);
await design('save',{revision:1,design:{...value,template:'modern'}});await assert.rejects(()=>action('download_direct',op(current,{snapshot_hash:current.snapshot_hash,appearance_version:4})),/changed|obsolete/);
await db.exec('RESET ROLE');assert.deepEqual((await db.query('SELECT token,revoked_at,version FROM ironvault_private.member_cards ORDER BY token')).rows,tokens);assert.deepEqual((await db.query('SELECT oid,pg_get_functiondef(oid) definition FROM pg_proc WHERE oid=ANY($1::regprocedure[]) ORDER BY oid',[protectedNames])).rows,defs);
console.log('PASS Stage 4 actual SQL: owner-only saves, scoped private backgrounds, revision/retry safety, unchanged credentials and protected functions, stale export rejection.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
