/* Disposable embedded PostgreSQL, synthetic data only. Never connects to Supabase. */
const {PGlite}=require(process.env.PGLITE_MODULE||'@electric-sql/pglite'),fs=require('node:fs'),assert=require('node:assert/strict');
const sql=fs.readFileSync('supabase/migrations/202611090048_provider_subscription_control.sql','utf8'),baseline=fs.readFileSync('supabase/migrations/202611050035_gym_subscriptions.sql','utf8');
function extract(name){const start=baseline.indexOf('CREATE OR REPLACE FUNCTION '+name+'(');assert(start>=0);return baseline.slice(start,baseline.indexOf('$fn$;',start)+6);}
const createFixture=async()=>{const db=new PGlite();try{
 await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;
 CREATE SCHEMA auth;CREATE SCHEMA storage;CREATE SCHEMA ironvault_private;GRANT USAGE ON SCHEMA auth,storage,ironvault_private TO authenticated,anon;
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$SELECT current_setting('request.jwt.claim.role',true)$$;
 CREATE TABLE public.owners(id text PRIMARY KEY,gym_name text,owner_name text,status text DEFAULT 'ACTIVE');
 CREATE TABLE public.iv_user_roles(user_id uuid,tenant_id text,role text,enabled boolean DEFAULT true,disabled_at timestamptz);
 CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 CREATE TABLE storage.objects(bucket_id text,name text,metadata jsonb,PRIMARY KEY(bucket_id,name));ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated,anon;CREATE POLICY unrelated_permissive ON storage.objects FOR ALL TO authenticated,anon USING(true) WITH CHECK(true);
 CREATE TABLE ironvault_private.gym_subscriptions(tenant_id text PRIMARY KEY REFERENCES public.owners(id),owner_id uuid,pilot_used boolean DEFAULT false,next_plan text,is_test boolean DEFAULT false);
 CREATE TABLE ironvault_private.service_versions(id uuid PRIMARY KEY,data jsonb,terms_text text,privacy_text text,dpa_text text,effective_date date,published_at timestamptz DEFAULT now(),retired boolean DEFAULT false,document_format text DEFAULT 'text');
 CREATE TABLE ironvault_private.service_acceptances(tenant_id text,owner_id uuid,version_id uuid,accepted_at timestamptz DEFAULT now(),PRIMARY KEY(tenant_id,owner_id,version_id));
 CREATE TABLE ironvault_private.legal_settings(scope text PRIMARY KEY,current_version uuid);
 CREATE TABLE ironvault_private.subscription_requests(id uuid PRIMARY KEY,tenant_id text,owner_id uuid,kind text,quote jsonb,confirmed_at timestamptz DEFAULT now(),approved_at timestamptz,approved_by uuid,cancelled_at timestamptz,payment_reference text);
 CREATE TABLE ironvault_private.subscription_periods(id uuid PRIMARY KEY,tenant_id text REFERENCES ironvault_private.gym_subscriptions(tenant_id),kind text,plan text,access_from date,start_date date,end_date date,grace_days integer,version_id uuid,policy jsonb,amount numeric(12,2),reference text,approved_by uuid,approved_at timestamptz DEFAULT now(),CHECK(end_date>=start_date),CHECK(access_from<=start_date));
 CREATE TABLE ironvault_private.subscription_events(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,tenant_id text,actor_id uuid,action text,data jsonb,created_at timestamptz DEFAULT now());
 CREATE TABLE ironvault_private.owner_notifications(tenant_id text,owner_id uuid,notice_key text,title text,message text,available_at timestamptz,read_at timestamptz,superseded_at timestamptz,resolved_at timestamptz,PRIMARY KEY(tenant_id,notice_key));
 CREATE TABLE ironvault_private.provider_notices(notice_key text PRIMARY KEY,tenant_id text,title text,message text,available_at timestamptz DEFAULT now(),resolved_at timestamptz);
 CREATE TABLE ironvault_private.payment_verifications(request_id uuid PRIMARY KEY,status text,eligible boolean);
 CREATE TABLE ironvault_private.verification_intervals(id uuid,ended_at timestamptz);
 CREATE TABLE ironvault_private.provider_reminder_jobs(id uuid,state text,lease_until timestamptz);
 CREATE FUNCTION public.iv_profile_images(text,jsonb) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
 CREATE FUNCTION ironvault_private.subscription_today() RETURNS date LANGUAGE sql STABLE AS $$SELECT coalesce(nullif(current_setting('test.day',true),''),'2026-11-09')::date$$;
 CREATE FUNCTION ironvault_private.subscription_state_043_base(text) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
 CREATE FUNCTION ironvault_private.owner_agreement_valid(t text,o uuid,v uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$SELECT EXISTS(SELECT 1 FROM ironvault_private.service_acceptances WHERE tenant_id=t AND owner_id=o AND version_id=v)$$;
 CREATE FUNCTION public.iv_subscription_portal(text,text,jsonb) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
 `);
 for(const name of ['ironvault_private.subscription_super','ironvault_private.subscription_owner','ironvault_private.service_current','ironvault_private.service_parameters','ironvault_private.subscription_notice'])await db.exec(extract(name));
 const users={provider:'11111111-1111-4111-8111-111111111111',owner:'22222222-2222-4222-8222-222222222222',other:'33333333-3333-4333-8333-333333333333',staff:'44444444-4444-4444-8444-444444444444'},version='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 await db.query("INSERT INTO public.owners VALUES('gym-a','First Gym','Owner A','ACTIVE'),('gym-b','Second Gym','Owner B','ACTIVE')");
 await db.query('INSERT INTO ironvault_private.gym_subscriptions(tenant_id,owner_id) VALUES($1,$2),($3,$4)',['gym-a',users.owner,'gym-b',users.other]);
 for(const [name,user]of Object.entries(users))await db.query('INSERT INTO public.iv_user_roles(user_id,tenant_id,role) VALUES($1,$2,$3)',[user,name==='provider'?null:name==='other'?'gym-b':'gym-a',name==='provider'?'super_admin':name==='staff'?'staff':'owner']);
 const policy={dashboard_price:900,portal_price:1500,paid_days:30,grace_days:7,pilot_days:14,export_days:30,retention_days:90};
 await db.query("INSERT INTO ironvault_private.service_versions(id,data,effective_date) VALUES($1,$2,'2026-01-01')",[version,JSON.stringify({...policy,provider_name:'Iron Vault Ph',brand:'Iron Vault'})]);
 await db.query("INSERT INTO ironvault_private.service_acceptances(tenant_id,owner_id,version_id) VALUES('gym-a',$1,$2),('gym-b',$3,$2)",[users.owner,version,users.other]);await db.query("INSERT INTO ironvault_private.legal_settings VALUES('gym-a',$1),('gym-b',$1),('platform',$1)",[version]);
 // Existing approved and pending legacy records are imported without duplicate collections.
 const histPeriod='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',legacyPending='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 await db.query("INSERT INTO public.owners VALUES('gym-c','Historical Gym','Owner C','ACTIVE')");await db.query("INSERT INTO ironvault_private.gym_subscriptions(tenant_id,owner_id) VALUES('gym-c',$1)",[users.other]);
 await db.query("INSERT INTO ironvault_private.subscription_periods(id,tenant_id,kind,plan,access_from,start_date,end_date,grace_days,version_id,policy,amount,approved_by) VALUES($1,'gym-c','paid','dashboard','2026-01-01','2026-01-01','2026-01-30',7,$2,$3,900,$4)",[histPeriod,version,JSON.stringify(policy),users.provider]);
 await db.query("INSERT INTO ironvault_private.subscription_requests(id,tenant_id,owner_id,kind,quote,approved_at,approved_by) VALUES($1,'gym-c',$2,'payment',$3,'2025-12-31',$4)",[histPeriod,users.other,JSON.stringify({plan:'dashboard',amount:900,start_date:'2026-01-01',end_date:'2026-01-30'}),users.provider]);
 await db.query("INSERT INTO ironvault_private.subscription_requests(id,tenant_id,owner_id,kind,quote) VALUES($1,'gym-c',$2,'payment',$3)",[legacyPending,users.other,JSON.stringify({plan:'portal',amount:1500})]);
 await db.exec(sql);console.log('048 compiled in disposable local PostgreSQL.');
 return {db,users,version,policy};}catch(error){await db.close();throw error;}};
module.exports={createFixture};
