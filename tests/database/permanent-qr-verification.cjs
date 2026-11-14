/* Disposable embedded PostgreSQL and synthetic accounts only. No live service. */
const fs=require('node:fs'),assert=require('node:assert/strict');
const {PGlite}=require(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const path='supabase/migrations/202611140054_permanent_qr_verification.sql';
const sql=fs.readFileSync(path,'utf8');
function extract(file,name){const s=fs.readFileSync(file,'utf8');const i=s.search(new RegExp('CREATE(?: OR REPLACE)? FUNCTION '+name.replaceAll('.','\\.')+'\\('));assert(i>=0,name);return s.slice(i,s.indexOf('$fn$;',i)+6);}
(async()=>{const db=new PGlite();try{
await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE SCHEMA auth;CREATE SCHEMA ironvault_private;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
CREATE TABLE public.owners(id text PRIMARY KEY,status text DEFAULT 'ACTIVE',portal boolean DEFAULT true);
CREATE TABLE public.members(id text PRIMARY KEY,tenant_id text REFERENCES public.owners,name text,display_code text,avatar text,status text DEFAULT 'ACTIVE',plan text DEFAULT '1-Month Unlimited',expiration_date text,scans_used integer DEFAULT 0,last_scanned_date text,legal boolean DEFAULT true,wallet_balance numeric DEFAULT 500);
CREATE TABLE public.iv_user_roles(user_id uuid,tenant_id text,member_id text,role text,enabled boolean DEFAULT true,disabled_at timestamptz);
CREATE TABLE ironvault_private.staff_access(tenant_id text,user_id uuid,state text);
CREATE TABLE public.iv_attendance_logs(id bigint GENERATED ALWAYS AS IDENTITY,tenant_id text,member_id text,method text,actor_id uuid,created_at timestamptz);
CREATE TABLE ironvault_private.daily_passes(token uuid PRIMARY KEY DEFAULT gen_random_uuid(),member_id text,tenant_id text,business_day date,expires_at timestamptz,used_at timestamptz,UNIQUE(member_id,business_day));
CREATE FUNCTION public.iv_gym_usage(text) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION public.iv_can_access(t text) RETURNS boolean LANGUAGE sql AS $$SELECT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND tenant_id=t AND role IN ('owner','staff') AND enabled AND disabled_at IS NULL)$$;
CREATE FUNCTION ironvault_private.is_own_membership(m text,t text) RETURNS boolean LANGUAGE sql AS $$SELECT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND tenant_id=t AND member_id=m AND role='member' AND enabled AND disabled_at IS NULL)$$;
CREATE FUNCTION ironvault_private.subscription_require(t text,f text,a uuid DEFAULT auth.uid()) RETURNS void LANGUAGE plpgsql STABLE AS $$BEGIN IF NOT EXISTS(SELECT 1 FROM public.owners WHERE id=t AND status='ACTIVE' AND portal) THEN RAISE EXCEPTION 'Subscription unavailable';END IF;END$$;
CREATE FUNCTION ironvault_private.member_legal_current(m text) RETURNS boolean LANGUAGE sql AS $$SELECT legal FROM public.members WHERE id=m$$;
CREATE FUNCTION ironvault_private.require_current_member_legal(m text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF NOT ironvault_private.member_legal_current(m) THEN RAISE EXCEPTION 'Agreement required';END IF;END$$;
GRANT USAGE ON SCHEMA auth TO authenticated;GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
INSERT INTO public.owners(id) VALUES('a'),('b');
INSERT INTO public.members(id,tenant_id,name,display_code,expiration_date) VALUES('one','a','Alex','MEM-0001',((now() AT TIME ZONE 'Asia/Manila')::date+30)::text),('two','b','Other','MEM-0002',((now() AT TIME ZONE 'Asia/Manila')::date+30)::text);
INSERT INTO public.iv_user_roles(user_id,tenant_id,member_id,role) VALUES
('11111111-1111-4111-8111-111111111111','a',NULL,'owner'),('22222222-2222-4222-8222-222222222222','a',NULL,'staff'),('33333333-3333-4333-8333-333333333333','a','one','member');`);
const baseline='supabase/migrations/202611010013_member_wallet_and_daily_passes.sql';
for(const n of ['ironvault_private.valid_entitlement','ironvault_private.record_admission'])await db.exec(extract(baseline,n));
await db.exec(extract('supabase/migrations/202611050032_member_portal_agreement.sql','public.iv_issue_member_pass'));
await db.exec(extract('supabase/migrations/202611070041_staff_access_targeted_announcements.sql','public.iv_checkin'));
// Permission helper for the unmodified manual check-in function.
await db.exec(`CREATE FUNCTION ironvault_private.staff_require(t text,p text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF NOT public.iv_can_access(t) THEN RAISE EXCEPTION 'Denied';END IF;END$$;`);
assert.equal(sql,fs.readFileSync('supabase/manual/permanent_qr_verification.sql','utf8'));await db.exec(sql);
const ids={owner:'11111111-1111-4111-8111-111111111111',staff:'22222222-2222-4222-8222-222222222222',member:'33333333-3333-4333-8333-333333333333'};
async function actor(name){await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[ids[name]||'']);await db.exec('SET ROLE authenticated');}
async function q(s,a=[]){return (await db.query(s,a)).rows[0];}
async function verify(payload,t='a',lookup=false){return (await q('SELECT public.iv_verify_entry_qr($1,$2,$3) result',[payload,t,lookup])).result;}
async function approve(payload,t='a'){return (await q('SELECT public.iv_approve_entry_qr($1,$2) result',[payload,t])).result;}
async function admin(s){await db.exec('RESET ROLE');await db.exec(s);await actor('owner');}
const card='IVC1|'+(await q("SELECT token FROM ironvault_private.member_cards WHERE member_id='one'")).token;
const other='IVC1|'+(await q("SELECT token FROM ironvault_private.member_cards WHERE member_id='two'")).token;
await actor('owner');assert.equal((await verify(card)).reason,'READY');
await db.exec('BEGIN READ ONLY');assert.equal((await verify(card,'a',true)).member.id,'one');await db.exec('COMMIT');
assert.equal((await verify(other)).reason,'INVALID_CARD_FOR_GYM');assert.equal((await verify(other)).member,undefined);
await assert.rejects(()=>verify(other,'b'),/Gym staff access/);assert.equal((await verify('MEM-0001')).valid,false);
await actor('member');assert.equal((await q("SELECT public.iv_member_card('one','a') result")).result.payload,card);await assert.rejects(()=>verify(card),/Gym staff access/);
await assert.rejects(()=>q("SELECT public.iv_member_card('two','b')"),/Gym staff access/);
const daily=(await q("SELECT public.iv_issue_member_pass('one') result")).result.payload;
await actor('owner');await assert.rejects(()=>q('SELECT public.iv_redeem_member_pass($1,$2)',[daily.split('|')[1],'a']),/Refresh/);
// Eligibility changing after a successful preview must still fail at approval.
assert.equal((await verify(card)).eligible,true);
await admin("UPDATE public.members SET expiration_date='2000-01-01' WHERE id='one'");
await assert.rejects(()=>approve(card),/EXPIRED_PASS/);
await admin("UPDATE public.members SET expiration_date=((now() AT TIME ZONE 'Asia/Manila')::date+30)::text WHERE id='one'");
await approve(card);assert.equal((await verify(daily)).reason,'ALREADY_ENTERED');await assert.rejects(()=>approve(daily),/no longer valid/);await assert.rejects(()=>approve(card),/ALREADY_ENTERED/);
await admin("UPDATE public.members SET last_scanned_date=NULL,scans_used=0 WHERE id='one';DELETE FROM public.iv_attendance_logs;UPDATE ironvault_private.daily_passes SET used_at=NULL;");
await approve(daily);assert.equal((await verify(card)).reason,'ALREADY_ENTERED');
await admin("UPDATE public.members SET last_scanned_date=NULL,scans_used=0 WHERE id='one';DELETE FROM public.iv_attendance_logs;UPDATE ironvault_private.daily_passes SET used_at=NULL;");
await q("SELECT public.iv_checkin('one','manual')");assert.equal((await verify(card)).reason,'ALREADY_ENTERED');await assert.rejects(()=>approve(card),/ALREADY_ENTERED/);
await admin("UPDATE public.members SET last_scanned_date=NULL,scans_used=0,expiration_date='2000-01-01' WHERE id='one';DELETE FROM public.iv_attendance_logs;UPDATE ironvault_private.daily_passes SET used_at=NULL;");
assert.equal((await verify(card)).reason,'EXPIRED_PASS');await assert.rejects(()=>approve(card),/EXPIRED_PASS/);
await admin("UPDATE public.members SET plan='Not Selected' WHERE id='one'");assert.equal((await verify(card)).reason,'NO_ACTIVE_PASS');
await admin("UPDATE public.members SET plan='1-Month Unlimited',expiration_date=((now() AT TIME ZONE 'Asia/Manila')::date+1)::text,legal=false WHERE id='one'");assert.equal((await verify(card)).reason,'AGREEMENT_REQUIRED');await assert.rejects(()=>approve(card),/AGREEMENT_REQUIRED/);
await admin("UPDATE public.members SET legal=true WHERE id='one';UPDATE ironvault_private.member_cards SET revoked_at=now() WHERE member_id='one';");assert.equal((await verify(card)).reason,'CARD_REVOKED');assert.equal((await verify(card)).member,undefined);await assert.rejects(()=>approve(card),/no longer valid/);
// Generated QR is still available while a permanent card is disabled.
await approve(daily);
// Replacement credentials cannot reset the used daily allowance.
await db.exec('RESET ROLE');await db.exec("INSERT INTO ironvault_private.member_cards(member_id,tenant_id) VALUES('one','a')");
const replacement='IVC1|'+(await q("SELECT token FROM ironvault_private.member_cards WHERE member_id='one' AND revoked_at IS NULL")).token;
await actor('owner');assert.equal((await verify(replacement)).reason,'ALREADY_ENTERED');assert.equal((await verify(card)).reason,'CARD_REVOKED');
await assert.rejects(()=>approve(replacement),/ALREADY_ENTERED/);
await admin("UPDATE public.iv_user_roles SET enabled=false WHERE role='staff';");await actor('staff');await assert.rejects(()=>verify(card),/Gym staff access/);
await admin("UPDATE public.owners SET portal=false WHERE id='a'");await assert.rejects(()=>verify(daily),/Subscription/);
await db.exec('RESET ROLE;SET ROLE anon');await assert.rejects(()=>verify(daily),/permission denied/);
await db.exec('RESET ROLE;SET ROLE authenticated');await assert.rejects(()=>q('SELECT * FROM ironvault_private.member_cards'),/permission denied/);
await db.exec('RESET ROLE');assert.equal((await q("SELECT wallet_balance FROM public.members WHERE id='one'")).wallet_balance,'500');
await db.exec("INSERT INTO public.members(id,tenant_id,name,display_code) VALUES('three','a','New','MEM-0003')");assert.equal((await q("SELECT count(*)::int n FROM ironvault_private.member_cards WHERE member_id='three'")).n,1);
console.log('PASS: real SQL compiles; scoped/private credentials, automatic issuance, read-only lookup, generated/card/manual shared allowance, revocation, eligibility recheck, legal/subscription/role checks, replay denial and unchanged wallet.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
