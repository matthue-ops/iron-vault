-- MANUAL ONLY. Coordinated application/API/RLS cutover after 001-011 (004 optional).
-- Additive + behavior-changing. No existing row is deleted or financial value rewritten.
-- Existing enabled roles default true. Base tables become private; compatibility
-- views expose safe projections. Application profile saves cannot alter money,
-- plans, expiry, scans, Auth IDs, tenant links or credentials.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.financial_requests') IS NULL THEN RAISE EXCEPTION '010 required'; END IF;
 IF to_regclass('public.iv_gyms') IS NOT NULL OR to_regclass('public.iv_members') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.iv_user_roles'::regclass AND attname='enabled' AND NOT attisdropped) THEN
  RAISE EXCEPTION 'Cutover objects already exist; inspect prior application'; END IF;
 IF (SELECT count(*) FROM pg_policy WHERE polrelid='public.owners'::regclass)<>1
 OR (SELECT count(*) FROM pg_policy WHERE polrelid='public.members'::regclass)<>1 THEN
  RAISE EXCEPTION 'Owner/member policy baseline changed; review drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.owners'::regclass AND polname='Allow public access to owners' AND polcmd='*'
  AND pg_get_expr(polqual,polrelid)='true' AND pg_get_expr(polwithcheck,polrelid)='true')
 OR NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.members'::regclass AND polname='Allow public access to members' AND polcmd='*'
  AND pg_get_expr(polqual,polrelid)='true' AND pg_get_expr(polwithcheck,polrelid)='true') THEN
  RAISE EXCEPTION 'Expected public ALL policies differ from inspection'; END IF;
END $guard$;
ALTER TABLE public.iv_user_roles ADD COLUMN enabled boolean NOT NULL DEFAULT true;
ALTER TABLE public.iv_user_roles ADD COLUMN disabled_at timestamptz;
CREATE OR REPLACE FUNCTION public.iv_can_access(p_tenant text,p_roles text[] DEFAULT ARRAY['owner','staff']::text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND
 ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.tenant_id=p_tenant AND r.role=ANY(p_roles) AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'))));
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.is_gym_administrator(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT public.iv_can_access(p_tenant,ARRAY['owner']::text[]);
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.is_gym_administrator(p_tenant) OR EXISTS(
  SELECT 1 FROM public.iv_user_roles r JOIN ironvault_private.staff_report_permissions p ON p.user_id=r.user_id AND p.tenant_id=r.tenant_id
  WHERE r.user_id=auth.uid() AND r.enabled AND r.role='staff' AND r.tenant_id=p_tenant
   AND p.permission='financial_reports_read' AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE'));
$fn$;
ALTER POLICY iv_roles_read ON public.iv_user_roles USING
 (enabled AND (user_id=auth.uid() OR public.iv_can_access(tenant_id,ARRAY['owner']::text[])));
-- Every helper uses caller auth.uid(), never current_user (the definer).
CREATE FUNCTION ironvault_private.can_read_member(p_id text,p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.members m WHERE m.id=p_id AND m.tenant_id IS NOT DISTINCT FROM p_tenant)
 AND (public.iv_can_access(p_tenant) OR EXISTS(SELECT 1 FROM public.iv_user_roles r
 WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=p_id AND r.tenant_id=p_tenant
 AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE')));
$fn$;
CREATE FUNCTION public.iv_visible_gyms()
RETURNS TABLE(id text,gym_name text,token text,logo text,status text,pricing jsonb,date_created timestamptz,created_at timestamptz,
 owner_name text,email text,password text,staff jsonb,audit_logs jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $visible$

 SELECT g.id,g.gym_name,g.token,g.logo,g.status,jsonb_build_object('day',g.pricing->'day','week',g.pricing->'week','month',g.pricing->'month','studentDiscount',g.pricing->'studentDiscount','seniorDiscount',g.pricing->'seniorDiscount'),g.date_created,g.created_at,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN g.owner_name ELSE NULL END AS owner_name,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN g.email ELSE NULL END AS email,
 NULL::text AS password,
 CASE WHEN public.iv_can_access(g.id,ARRAY['owner']::text[]) THEN
  coalesce((SELECT jsonb_agg(jsonb_build_object('name',s.value->>'name','email',s.value->>'email','auth_user_id',s.value->>'auth_user_id','dateCreated',s.value->>'dateCreated')) FROM jsonb_array_elements(coalesce(g.staff,'[]'::jsonb)) s
   WHERE EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.tenant_id=g.id AND r.disabled_at IS NULL AND r.role='staff'
    AND r.user_id::text=s.value->>'auth_user_id')),'[]'::jsonb) ELSE '[]'::jsonb END AS staff,
 '[]'::jsonb AS audit_logs
 FROM public.owners g WHERE g.status IN ('ACTIVE','PROVISIONING') OR public.iv_can_access(g.id);
$visible$;
CREATE VIEW public.iv_gyms WITH(security_barrier=true) AS SELECT * FROM public.iv_visible_gyms();
CREATE VIEW public.iv_members WITH(security_barrier=true) AS
 SELECT m.id,m.tenant_id,m.tenant_token,m.name,m.email,m.phone,NULL::text AS password,
 m.classification,m.discount_percentage,m.plan,m.card_barcode,m.wallet_balance,
 CASE WHEN ironvault_private.can_read_financial_reports(m.tenant_id) OR EXISTS(
  SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member' AND r.member_id=m.id AND r.tenant_id=m.tenant_id)
 THEN m.amount ELSE NULL END AS amount,
 m.scans_used,m.last_scanned_date,m.expiration_date,m.status,m.date_joined,m.avatar,m.created_at
 FROM public.members m WHERE ironvault_private.can_read_member(m.id,m.tenant_id);
ALTER VIEW public.iv_gyms OWNER TO postgres;
ALTER VIEW public.iv_members OWNER TO postgres;
REVOKE ALL ON public.iv_gyms,public.iv_members FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.iv_gyms TO anon,authenticated;
GRANT SELECT ON public.iv_members TO authenticated;
CREATE FUNCTION public.iv_save_member_profiles(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; m public.members%ROWTYPE; tenant text; operator boolean; owner_access boolean; discount numeric;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>500 THEN RAISE EXCEPTION 'Invalid profile batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO m FROM public.members WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Create member accounts through registration; restore cannot create financial records'; END IF;
  tenant:=m.tenant_id;operator:=public.iv_can_access(tenant);owner_access:=public.iv_can_access(tenant,ARRAY['owner']::text[]);
  IF NOT operator AND NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled
   AND r.role='member' AND r.member_id=m.id AND r.tenant_id=tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=tenant AND g.status='ACTIVE')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF item ? 'tenant_id' AND item->>'tenant_id' IS DISTINCT FROM tenant THEN RAISE EXCEPTION 'Cannot move membership'; END IF;
  IF length(coalesce(item->>'name',m.name)) NOT BETWEEN 1 AND 160 OR length(coalesce(item->>'phone',''))>50
   OR length(coalesce(item->>'avatar',''))>750000 THEN RAISE EXCEPTION 'Invalid profile fields'; END IF;
  IF item ? 'email' AND lower(btrim(item->>'email')) IS DISTINCT FROM lower(btrim(m.email)) THEN
   RAISE EXCEPTION 'Contact email changes require verification'; END IF;
  -- Names/phone/avatar are personal edits. Operators additionally manage approval,
  -- classification and card IDs; only gym administrators change a discount.
  IF operator AND item ? 'status' AND item->>'status' NOT IN ('ACTIVE','PENDING','INACTIVE') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF operator AND item ? 'classification' AND item->>'classification' NOT IN ('Regular','Student','Senior') THEN RAISE EXCEPTION 'Invalid classification'; END IF;
  IF operator AND NOT owner_access AND m.status='INACTIVE' AND item->>'status'='ACTIVE' THEN RAISE EXCEPTION 'Gym administrator required to restore inactive membership'; END IF;
  discount:=coalesce(m.discount_percentage,0);
  IF operator AND item ? 'classification' AND item->>'classification' IS DISTINCT FROM m.classification THEN
   SELECT CASE WHEN item->>'classification'='Student' THEN (g.pricing->>'studentDiscount')::numeric
    WHEN item->>'classification'='Senior' THEN (g.pricing->>'seniorDiscount')::numeric ELSE 0 END
   INTO discount FROM public.owners g WHERE g.id=tenant;
  END IF;
  IF owner_access AND item ? 'discount_percentage' THEN
   discount:=(item->>'discount_percentage')::numeric;
   IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  END IF;
  IF discount IS NULL OR discount::text IN ('NaN','Infinity','-Infinity') OR discount<0 OR discount>100 THEN RAISE EXCEPTION 'Invalid configured member discount'; END IF;
  UPDATE public.members SET name=coalesce(item->>'name',name),phone=CASE WHEN item ? 'phone' THEN item->>'phone' ELSE phone END,
   avatar=CASE WHEN item ? 'avatar' THEN item->>'avatar' ELSE avatar END,
   status=CASE WHEN operator THEN coalesce(item->>'status',status) ELSE status END,
   classification=CASE WHEN operator THEN coalesce(item->>'classification',classification) ELSE classification END,
   card_barcode=CASE WHEN operator AND item ? 'card_barcode' THEN item->>'card_barcode' ELSE card_barcode END,
   discount_percentage=discount WHERE id=m.id;
  INSERT INTO public.iv_activity_logs(tenant_id,actor_id,event,details) VALUES(tenant,auth.uid(),'Member profile updated',m.id);
 END LOOP;
END $fn$;
CREATE FUNCTION public.iv_save_gym_settings(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; gym public.owners%ROWTYPE; key text; price numeric; super boolean;
BEGIN
 IF auth.uid() IS NULL OR p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>100 THEN RAISE EXCEPTION 'Invalid gym batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  SELECT * INTO gym FROM public.owners WHERE id=item->>'id' FOR UPDATE;
  IF NOT FOUND OR NOT public.iv_can_access(gym.id,ARRAY['owner']::text[]) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  super:=public.iv_can_access(NULL,ARRAY[]::text[]);
  IF length(coalesce(item->>'gym_name',gym.gym_name)) NOT BETWEEN 1 AND 160
   OR length(coalesce(item->>'owner_name',gym.owner_name)) NOT BETWEEN 1 AND 160
   OR length(coalesce(item->>'logo',''))>750000 THEN RAISE EXCEPTION 'Invalid branding'; END IF;
  IF item ? 'pricing' THEN
   FOREACH key IN ARRAY ARRAY['day','week','month','studentDiscount','seniorDiscount'] LOOP
    price:=(item->'pricing'->>key)::numeric;
    IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<0
     OR (key NOT LIKE '%Discount' AND price<=0) OR price>(CASE WHEN key LIKE '%Discount' THEN 100 ELSE 10000000 END) OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid pricing'; END IF;
   END LOOP;
  END IF;
  IF super AND item ? 'status' AND item->>'status' IS DISTINCT FROM gym.status AND item->>'status' NOT IN ('ACTIVE','SUSPENDED') THEN RAISE EXCEPTION 'Invalid gym status'; END IF;
  UPDATE public.owners SET gym_name=coalesce(item->>'gym_name',gym_name),owner_name=coalesce(item->>'owner_name',owner_name),
   logo=CASE WHEN item ? 'logo' THEN item->>'logo' ELSE logo END,
   pricing=CASE WHEN item ? 'pricing' THEN item->'pricing' ELSE pricing END,
   status=CASE WHEN super THEN coalesce(item->>'status',status) ELSE status END WHERE id=gym.id;
  -- Email, Auth, staff JSON, credentials, tenant IDs and tokens are never patched.
 END LOOP;
END $fn$;
CREATE FUNCTION public.iv_deactivate_member(p_member_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE m public.members%ROWTYPE;
BEGIN
 SELECT * INTO m FROM public.members WHERE id=p_member_id FOR UPDATE;
 IF NOT FOUND OR NOT public.iv_can_access(m.tenant_id,ARRAY['owner']::text[]) THEN RAISE EXCEPTION 'Gym administrator required'; END IF;
 IF coalesce(m.wallet_balance,0)<>0 THEN RAISE EXCEPTION 'Settle wallet balance before deactivation'; END IF;
 UPDATE public.members SET status='INACTIVE' WHERE id=m.id;
 UPDATE public.iv_user_roles SET enabled=false,disabled_at=now() WHERE member_id=m.id AND tenant_id=m.tenant_id;
 PERFORM public.iv_log_event(m.tenant_id,'Member deactivated',m.id);
END $fn$;
CREATE FUNCTION public.iv_deactivate_gym(p_tenant text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT public.iv_can_access(NULL,ARRAY[]::text[]) THEN RAISE EXCEPTION 'Super Admin required'; END IF;
 IF EXISTS(SELECT 1 FROM public.members WHERE tenant_id=p_tenant AND coalesce(wallet_balance,0)<>0) THEN RAISE EXCEPTION 'Settle gym wallet liabilities first'; END IF;
 UPDATE public.owners SET status='SUSPENDED' WHERE id=p_tenant;
 PERFORM public.iv_log_event(p_tenant,'Gym suspended','Records and history retained');
END $fn$;
CREATE FUNCTION public.iv_revoke_staff(p_tenant text,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT public.iv_can_access(p_tenant,ARRAY['owner']::text[]) OR auth.uid()=p_user THEN RAISE EXCEPTION 'Not authorized'; END IF;
 UPDATE public.iv_user_roles SET enabled=false,disabled_at=now() WHERE user_id=p_user AND tenant_id=p_tenant AND role='staff';
 IF NOT FOUND THEN RAISE EXCEPTION 'Staff link not found'; END IF;
 PERFORM public.iv_log_event(p_tenant,'Staff access revoked',p_user::text);
END $fn$;
ALTER POLICY iv_financial_read ON public.iv_financial_transactions USING (
 ironvault_private.can_read_financial_reports(tenant_id) OR EXISTS(SELECT 1 FROM public.iv_user_roles r
 WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member'
 AND r.member_id=public.iv_financial_transactions.member_id AND r.tenant_id=public.iv_financial_transactions.tenant_id
 AND ironvault_private.can_read_member(r.member_id,r.tenant_id)));
ALTER POLICY iv_attendance_read ON public.iv_attendance_logs USING (
 public.iv_can_access(tenant_id) OR EXISTS(SELECT 1 FROM public.iv_user_roles r
 WHERE r.user_id=auth.uid() AND r.enabled AND r.role='member'
 AND r.member_id=public.iv_attendance_logs.member_id AND r.tenant_id=public.iv_attendance_logs.tenant_id
 AND ironvault_private.can_read_member(r.member_id,r.tenant_id)));
-- Remove the known public ALL policies; no permissive compatibility fallback.
DROP POLICY "Allow public access to owners" ON public.owners;
DROP POLICY "Allow public access to members" ON public.members;
REVOKE ALL ON public.owners,public.members FROM PUBLIC,anon,authenticated;
DO $columns$
DECLARE item record; signature text;
BEGIN
 FOR item IN SELECT c.relname,a.attname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='public' AND c.relname IN ('owners','members') AND a.attnum>0 AND NOT a.attisdropped LOOP
  EXECUTE format('REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.%I FROM PUBLIC,anon,authenticated',item.attname,item.attname,item.attname,item.attname,item.relname);
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['public.iv_visible_gyms()','ironvault_private.can_read_member(text,text)',
 'public.iv_save_member_profiles(jsonb)','public.iv_save_gym_settings(jsonb)','public.iv_deactivate_member(text)',
 'public.iv_deactivate_gym(text)','public.iv_revoke_staff(text,uuid)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated,service_role',signature);
 END LOOP;
END $columns$;
GRANT EXECUTE ON FUNCTION public.iv_visible_gyms() TO anon;
-- Only this scoped branding projection is intentionally anonymously callable.
-- Views run as postgres to read private base tables but explicitly evaluate auth.uid
-- and current enabled role rows. Never change these to unrestricted SELECT * views.
DO $verify$
DECLARE t text; r text;
BEGIN
 FOREACH t IN ARRAY ARRAY['public.owners','public.members'] LOOP
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_any_column_privilege(r,t,'SELECT') OR has_any_column_privilege(r,t,'UPDATE')
    OR has_any_column_privilege(r,t,'INSERT') OR has_table_privilege(r,t,'DELETE') OR has_table_privilege(r,t,'TRUNCATE') THEN
    RAISE EXCEPTION 'Inherited base privilege remains on % for %',t,r; END IF;
  END LOOP;
 END LOOP;
END $verify$;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT tablename,policyname,cmd FROM pg_policies WHERE schemaname='public' AND tablename IN ('owners','members');
-- Expect no public base policies; SELECT through scoped safe views only. On error
-- ROLLBACK; never restore public ALL. Existing records/password columns remain.
