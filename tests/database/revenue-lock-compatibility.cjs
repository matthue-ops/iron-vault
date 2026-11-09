/* Disposable local PostgreSQL only; no connection to Supabase. */
const {PGlite}=require(process.env.PGLITE_MODULE||'@electric-sql/pglite'),fs=require('node:fs'),assert=require('node:assert/strict');
function extract(file,name){const s=fs.readFileSync(file,'utf8'),start=s.indexOf('FUNCTION '+name+'(');return 'CREATE OR REPLACE '+s.slice(start,s.indexOf('$fn$;',start)+6);}
assert.equal(fs.readFileSync('supabase/manual/revenue_today_lock_compatibility.sql','utf8'),fs.readFileSync('supabase/migrations/202611090050_revenue_today_lock_compatibility.sql','utf8'));
(async()=>{const db=new PGlite();try{await db.exec(`CREATE SCHEMA ironvault_private;CREATE SCHEMA auth;
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 CREATE TABLE public.iv_user_roles(user_id uuid,tenant_id text,role text,enabled boolean,disabled_at timestamptz);
 CREATE TABLE public.iv_financial_transactions(tenant_id text,kind text,amount numeric,created_at timestamptz);
 CREATE FUNCTION ironvault_private.staff_has_permission(t text,p text) RETURNS boolean LANGUAGE sql STABLE AS $$SELECT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=auth.uid() AND tenant_id=t AND role='owner' AND enabled AND disabled_at IS NULL) OR (p='revenue_today' AND coalesce(current_setting('test.staff_allowed',true)='yes',false))$$;
 CREATE FUNCTION ironvault_private.subscription_today() RETURNS date LANGUAGE sql STABLE AS $$SELECT (now() AT TIME ZONE 'Asia/Manila')::date$$;
 CREATE FUNCTION ironvault_private.subscription_require(text,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF current_setting('test.subscription_denied',true)='yes' THEN RAISE EXCEPTION 'Subscription denied';END IF;END$$;
 INSERT INTO public.iv_user_roles VALUES('11111111-1111-4111-8111-111111111111','g','owner',true,null),('22222222-2222-4222-8222-222222222222','g','staff',true,null);
 INSERT INTO public.iv_financial_transactions VALUES('g','plan_cash',90,now()),('g','plan_wallet',10,now()),('g','topup',300,now()),('g','refund_cash',20,now()),('other','plan_cash',999,now()),('g','plan_cash',500,now()-interval '2 days');`);
 await db.exec(extract('supabase/migrations/202611070041_staff_access_targeted_announcements.sql','ironvault_private.staff_require'));
 await db.exec(extract('supabase/migrations/202611080046_pilot_topup_reviews_ui.sql','public.iv_revenue_today'));
 await db.exec("SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false)");
 // PostgREST uses a read-only transaction for the original STABLE RPC.
 await db.exec('BEGIN READ ONLY');await assert.rejects(db.query("SELECT public.iv_revenue_today('g')"),/SELECT FOR SHARE|read-only/i);await db.exec('ROLLBACK');
 const before=await db.query("SELECT prosrc,prosecdef,proacl FROM pg_proc WHERE oid='public.iv_revenue_today(text)'::regprocedure");
 await db.exec(fs.readFileSync('supabase/manual/revenue_today_lock_compatibility.sql','utf8'));
 const after=await db.query("SELECT prosrc,prosecdef,proacl,provolatile FROM pg_proc WHERE oid='public.iv_revenue_today(text)'::regprocedure");assert.equal(after.rows[0].provolatile,'v');for(const key of ['prosrc','prosecdef','proacl'])assert.deepEqual(after.rows[0][key],before.rows[0][key]);
 const result=await db.query("SELECT public.iv_revenue_today('g') AS result");assert.equal(Number(result.rows[0].result.amount),100);assert.equal(result.rows[0].result.tenant_id,'g');
 await assert.rejects(db.query("SELECT public.iv_revenue_today('other')"),/Permission required/);
 await db.exec("SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false)");await assert.rejects(db.query("SELECT public.iv_revenue_today('g')"),/Permission required/);
 await db.exec("SELECT set_config('test.staff_allowed','yes',false)");assert.equal(Number((await db.query("SELECT public.iv_revenue_today('g') AS result")).rows[0].result.amount),100);
 await db.exec("SELECT set_config('test.subscription_denied','yes',false)");await assert.rejects(db.query("SELECT public.iv_revenue_today('g')"),/Subscription denied/);
 assert.equal((await db.query('SELECT count(*) AS n FROM public.iv_financial_transactions')).rows[0].n,6);
 console.log('050: original PostgREST read-only failure reproduced; correction preserves body/grants, totals, tenant/permission and subscription gates.');
 }finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
