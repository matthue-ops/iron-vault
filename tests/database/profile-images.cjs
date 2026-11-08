/* Local PostgreSQL only. Set PGLITE_MODULE to a temporary installation; never uses Supabase. */
const {PGlite}=require(process.env.PGLITE_MODULE||'@electric-sql/pglite'),fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try{
await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;
CREATE SCHEMA auth;CREATE SCHEMA storage;CREATE SCHEMA ironvault_private;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth,storage TO authenticated,anon;GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,anon;
CREATE TABLE public.owners(id text PRIMARY KEY,logo text,status text DEFAULT 'ACTIVE');
CREATE TABLE public.members(id text PRIMARY KEY,tenant_id text,avatar text,status text DEFAULT 'ACTIVE');
CREATE TABLE public.iv_user_roles(user_id uuid,tenant_id text,member_id text,role text,enabled boolean DEFAULT true,disabled_at timestamptz);
CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
CREATE TABLE storage.objects(id uuid DEFAULT gen_random_uuid(),bucket_id text,name text,metadata jsonb,PRIMARY KEY(bucket_id,name));
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated,anon;
CREATE POLICY unrelated_permissive ON storage.objects FOR ALL TO authenticated,anon USING(true) WITH CHECK(true);
CREATE FUNCTION ironvault_private.subscription_require(text,text,uuid DEFAULT auth.uid()) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('test.subscription_denied',true)='yes' THEN RAISE EXCEPTION 'Subscription denied';END IF;END $$;
CREATE FUNCTION public.iv_topup_review(text,text,numeric,uuid) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION public.iv_save_member_profiles(p jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v jsonb;BEGIN FOR v IN SELECT value FROM jsonb_array_elements(p) LOOP
IF NOT ironvault_private.image_access(v->>'tenant_id',v->>'id','member',true) THEN RAISE EXCEPTION 'Not authorized';END IF;
UPDATE public.members SET avatar=CASE WHEN v?'avatar' THEN v->>'avatar' ELSE avatar END WHERE id=v->>'id';END LOOP;END $$;
CREATE FUNCTION public.iv_save_gym_settings(p jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v jsonb;BEGIN FOR v IN SELECT value FROM jsonb_array_elements(p) LOOP
IF NOT ironvault_private.image_access(v->>'id',NULL,'gym',true) THEN RAISE EXCEPTION 'Not authorized';END IF;
UPDATE public.owners SET logo=CASE WHEN v?'logo' THEN v->>'logo' ELSE logo END WHERE id=v->>'id';END LOOP;END $$;
CREATE FUNCTION public.iv_restore_profiles(p_gyms jsonb,p_members jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN PERFORM public.iv_save_gym_settings(p_gyms);PERFORM public.iv_save_member_profiles(p_members);END $$;
`);
await db.exec(fs.readFileSync('supabase/manual/optimized_profile_images.sql','utf8'));
console.log('047 migration compiles in local PostgreSQL.');
const users={member:'11111111-1111-4111-8111-111111111111',other:'22222222-2222-4222-8222-222222222222',owner:'33333333-3333-4333-8333-333333333333',staff:'44444444-4444-4444-8444-444444444444',master:'55555555-5555-4555-8555-555555555555'};
await db.exec(`INSERT INTO public.owners(id,logo) VALUES('g','old-logo'),('other','');INSERT INTO public.members(id,tenant_id,avatar) VALUES('m','g','old-photo'),('n','other','');`);
for(const [name,user]of Object.entries(users))await db.query('INSERT INTO public.iv_user_roles(user_id,tenant_id,member_id,role) VALUES($1,$2,$3,$4)',[user,name==='master'?null:name==='other'?'other':'g',name==='member'?'m':name==='other'?'n':null,name==='master'?'super_admin':name==='other'?'member':name]);
async function actor(name){await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[users[name]||'']);await db.exec(name==='anon'?'SET ROLE anon':'SET ROLE authenticated');}
async function rpc(action,payload={}){return (await db.query('SELECT public.iv_profile_images($1,$2) AS value',[action,payload])).rows[0].value;}
const req=(id,kind='member',expected='old-photo')=>({request_id:id,kind,tenant_id:'g',member_id:kind==='member'?'m':null,expected,checksum:'a'.repeat(64)});
const first='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',second='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
await actor('member');await rpc('reserve',req(first));await rpc('reserve',req(second));
await assert.rejects(()=>rpc('reserve',{...req(crypto.randomUUID()),tenant_id:'other',member_id:'n',expected:''}),/Not authorized/);
await assert.rejects(()=>rpc('reserve',req(crypto.randomUUID(),'gym','old-logo')),/Not authorized/);
await db.query('INSERT INTO storage.objects(bucket_id,name,metadata) VALUES($1,$2,$3)',['iv-member-images',first+'/photo',{size:20000,mimetype:'image/webp'}]);
await assert.rejects(()=>db.query('INSERT INTO storage.objects(bucket_id,name,metadata) VALUES($1,$2,$3)',['iv-member-images',first+'/evil.png',{size:2,mimetype:'image/png'}]),/row-level security/);
await rpc('commit',{request_id:first});assert.equal((await rpc('status',{request_id:first})).state,'active');await rpc('commit',{request_id:first});
assert.equal((await db.query('SELECT name FROM storage.objects')).rows.length,1);
assert.equal((await db.query('DELETE FROM storage.objects WHERE name=$1 RETURNING name',[first+'/photo'])).rows.length,0);
assert.equal((await db.query('UPDATE storage.objects SET metadata=$1 WHERE name=$2 RETURNING name',[{},first+'/photo'])).rows.length,0);
await actor('other');assert.equal((await db.query('SELECT name FROM storage.objects')).rows.length,0);await assert.rejects(()=>rpc('status',{request_id:first}),/Not authorized/);
await actor('owner');assert.equal((await db.query('SELECT name FROM storage.objects')).rows.length,1);await assert.rejects(()=>rpc('reserve',req(crypto.randomUUID())),/Not authorized/);
await actor('staff');assert.equal((await db.query('SELECT name FROM storage.objects')).rows.length,1);
await actor('anon');assert.equal((await db.query('SELECT name FROM storage.objects')).rows.length,0);await assert.rejects(()=>rpc('cleanup'),/permission denied/);
await actor('member');await db.query('INSERT INTO storage.objects(bucket_id,name,metadata) VALUES($1,$2,$3)',['iv-member-images',second+'/photo',{size:20000,mimetype:'image/webp'}]);await assert.rejects(()=>rpc('commit',{request_id:second}),/Photo changed/);
await assert.rejects(()=>db.query('SELECT public.iv_save_member_profiles($1)',[[{id:'m',tenant_id:'g',avatar:'stale-old-photo'}]]),/Photo changed/);
await rpc('cancel',{request_id:second});await db.query('DELETE FROM storage.objects WHERE name=$1',[second+'/photo']);await rpc('ack',{request_id:second});
console.log('Self/tenant/role boundaries, immutable files, active-delete denial, stale reviews and receipt replay passed.');
const third='cccccccc-cccc-4ccc-8ccc-cccccccccccc';await rpc('reserve',req(third,'member','iv-photo:'+first));await db.query('INSERT INTO storage.objects(bucket_id,name,metadata) VALUES($1,$2,$3)',['iv-member-images',third+'/photo',{size:20000,mimetype:'image/webp'}]);await rpc('commit',{request_id:third});
assert((await rpc('cleanup')).some(x=>x.id===first));await db.query('DELETE FROM storage.objects WHERE name=$1',[first+'/photo']);await rpc('ack',{request_id:first});
await db.exec('RESET ROLE');assert.equal((await db.query('SELECT avatar FROM public.members WHERE id=$1',['m'])).rows[0].avatar,'iv-photo:'+third);
await db.exec("UPDATE public.iv_user_roles SET enabled=false WHERE role='member' AND tenant_id='g'");await actor('member');assert.equal((await db.query('SELECT name FROM storage.objects')).rows.length,0);await assert.rejects(()=>rpc('reserve',req(crypto.randomUUID(),'member','iv-photo:'+third)),/Not authorized/);await db.exec('RESET ROLE');await db.exec("UPDATE public.iv_user_roles SET enabled=true WHERE tenant_id='g'");
const gymRequest='ffffffff-ffff-4fff-8fff-ffffffffffff';await actor('master');await rpc('reserve',req(gymRequest,'gym','old-logo'));
for(const name of ['logo','icon-192.png','icon-512.png','maskable-512.png'])await db.query('INSERT INTO storage.objects(bucket_id,name,metadata) VALUES($1,$2,$3)',['iv-gym-images',gymRequest+'/'+name,{size:30000,mimetype:name.endsWith('.png')?'image/png':'image/webp'}]);
await rpc('commit',{request_id:gymRequest});await db.exec('RESET ROLE');assert.match((await db.query("SELECT logo FROM public.owners WHERE id='g'")).rows[0].logo,/iv-gym-images/);
await actor('master');await db.query('SELECT public.iv_restore_profiles($1,$2)',[[{id:'g',logo:'embedded-backup-logo'}],[{id:'m',tenant_id:'g',avatar:'embedded-backup-photo'}]]);assert((await rpc('cleanup')).some(x=>x.id===gymRequest));
const jpeg='dddddddd-dddd-4ddd-8ddd-dddddddddddd';await actor('member');await rpc('reserve',req(jpeg,'member','embedded-backup-photo'));await db.query('INSERT INTO storage.objects(bucket_id,name,metadata) VALUES($1,$2,$3)',['iv-member-images',jpeg+'/photo',{size:22000,mimetype:'image/jpeg'}]);await rpc('commit',{request_id:jpeg});
await actor('master');const png='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';await rpc('reserve',req(png,'gym','embedded-backup-logo'));for(const name of ['logo','icon-192.png','icon-512.png','maskable-512.png'])await db.query('INSERT INTO storage.objects(bucket_id,name,metadata) VALUES($1,$2,$3)',['iv-gym-images',png+'/'+name,{size:22000,mimetype:'image/png'}]);await rpc('commit',{request_id:png});
console.log('JPEG photo and transparent PNG logo encoder fallbacks passed.');
await db.exec('RESET ROLE');await db.exec("DELETE FROM public.members WHERE id='m';DELETE FROM public.owners WHERE id='g'");await actor('master');assert((await rpc('cleanup')).length>0);
console.log('Replacement/cleanup, disabled accounts, public gym bundle, explicit restore and purge retirement passed.');
}finally{await db.close()}})().catch(e=>{console.error(e.message, e.code, 'position',e.position,'internal',e.internalQuery,'where',e.where,'query',e.query);process.exit(1)});
