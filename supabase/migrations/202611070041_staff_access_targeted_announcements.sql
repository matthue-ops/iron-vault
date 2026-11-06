-- MANUAL ONLY, after 040. Never run by the agent.
-- Adds scoped permissions and announcement delivery; preserves account/history rows.
BEGIN;
CREATE TABLE IF NOT EXISTS ironvault_private.staff_access (
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','suspended','removed')),
 permissions jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(permissions)='object'),
 updated_by uuid,updated_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(tenant_id,user_id)
);
-- Preserve currently working desk/report access; new staff privileges start ungranted.
INSERT INTO ironvault_private.staff_access(tenant_id,user_id,state,permissions)
 SELECT r.tenant_id,r.user_id,CASE WHEN r.enabled AND r.disabled_at IS NULL THEN 'active' ELSE 'suspended' END,
 jsonb_build_object('manual_checkin',true,'reports_read',EXISTS(SELECT 1 FROM ironvault_private.staff_report_permissions p WHERE p.tenant_id=r.tenant_id AND p.user_id=r.user_id),'reports_export',false)
 FROM public.iv_user_roles r WHERE r.role='staff' ON CONFLICT DO NOTHING;
CREATE OR REPLACE FUNCTION ironvault_private.staff_has_permission(p_tenant text,p_permission text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.subscription_super() OR ironvault_private.subscription_owner(p_tenant) OR EXISTS(
 SELECT 1 FROM public.iv_user_roles r JOIN ironvault_private.staff_access a ON a.tenant_id=r.tenant_id AND a.user_id=r.user_id
 JOIN public.owners g ON g.id=r.tenant_id WHERE r.tenant_id=p_tenant AND r.user_id=auth.uid() AND r.role='staff'
 AND r.enabled AND r.disabled_at IS NULL AND a.state='active' AND g.status='ACTIVE' AND a.permissions->>p_permission='true');
$fn$;
CREATE OR REPLACE FUNCTION ironvault_private.staff_require(p_tenant text,p_permission text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 PERFORM 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
 ((r.tenant_id=p_tenant AND r.role IN ('owner','staff')) OR (r.role='super_admin' AND r.tenant_id IS NULL)) FOR SHARE;
 IF NOT FOUND OR NOT ironvault_private.staff_has_permission(p_tenant,p_permission) THEN RAISE EXCEPTION 'Permission required: %',p_permission USING ERRCODE='42501';END IF;
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_staff_access(p_tenant text,p_action text DEFAULT 'mine',p_user uuid DEFAULT NULL,p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE row_access ironvault_private.staff_access%ROWTYPE;actor_role text;key text;perms jsonb;result jsonb;
BEGIN
 SELECT r.role INTO actor_role FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
 ((r.tenant_id=p_tenant AND r.role IN ('owner','staff')) OR (r.role='super_admin' AND r.tenant_id IS NULL)) LIMIT 1;
 IF actor_role IS NULL THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501';END IF;
 IF p_action='mine' THEN
  SELECT * INTO row_access FROM ironvault_private.staff_access WHERE tenant_id=p_tenant AND user_id=auth.uid();
  RETURN jsonb_build_object('role',actor_role,'state',coalesce(row_access.state,'active'),'permissions',CASE WHEN actor_role IN ('owner','super_admin') THEN '{"manual_checkin":true,"reports_read":true,"reports_export":true,"announcements_manage":true,"pricing_manage":true,"subscription_read":true}'::jsonb ELSE coalesce(row_access.permissions,'{}') END);
 END IF;
 IF actor_role NOT IN ('owner','super_admin') OR (actor_role='owner' AND NOT ironvault_private.subscription_owner(p_tenant)) THEN RAISE EXCEPTION 'Registered owner required' USING ERRCODE='42501';END IF;
 IF p_action IN ('permissions','suspend','reactivate','remove') THEN
  IF p_user IS NULL OR p_user=auth.uid() THEN RAISE EXCEPTION 'Choose a staff account';END IF;
  PERFORM 1 FROM public.iv_user_roles r WHERE r.tenant_id=p_tenant AND r.user_id=p_user AND r.role='staff' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Staff account unavailable';END IF;
  INSERT INTO ironvault_private.staff_access(tenant_id,user_id) VALUES(p_tenant,p_user) ON CONFLICT DO NOTHING;
  SELECT * INTO STRICT row_access FROM ironvault_private.staff_access WHERE tenant_id=p_tenant AND user_id=p_user FOR UPDATE;
  IF row_access.state='removed' THEN RAISE EXCEPTION 'Staff was removed; create a new authorized engagement instead';END IF;
  IF p_action='permissions' THEN
   perms:=p_data->'permissions';IF perms IS NULL OR jsonb_typeof(perms)<>'object' THEN RAISE EXCEPTION 'Choose explicit permissions';END IF;
   FOR key IN SELECT jsonb_object_keys(perms) LOOP
    IF NOT key=ANY(ARRAY['manual_checkin','reports_read','reports_export','announcements_manage','pricing_manage','subscription_read']) OR jsonb_typeof(perms->key)<>'boolean' THEN RAISE EXCEPTION 'Invalid permission';END IF;
   END LOOP;
   IF perms->>'reports_export'='true' AND perms->>'reports_read' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Report export requires report viewing';END IF;
   UPDATE ironvault_private.staff_access SET permissions=perms,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE tenant_id=p_tenant AND user_id=p_user;
   DELETE FROM ironvault_private.staff_report_permissions WHERE tenant_id=p_tenant AND user_id=p_user;
   IF perms->>'reports_read'='true' THEN INSERT INTO ironvault_private.staff_report_permissions(tenant_id,user_id,permission,granted_by) VALUES(p_tenant,p_user,'financial_reports_read',auth.uid());END IF;
  ELSE
   UPDATE ironvault_private.staff_access SET state=CASE p_action WHEN 'suspend' THEN 'suspended' WHEN 'remove' THEN 'removed' ELSE 'active' END,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE tenant_id=p_tenant AND user_id=p_user;
   UPDATE public.iv_user_roles SET enabled=p_action='reactivate',disabled_at=CASE WHEN p_action='reactivate' THEN NULL ELSE clock_timestamp() END WHERE tenant_id=p_tenant AND user_id=p_user AND role='staff';
  END IF;
  PERFORM public.iv_log_event(p_tenant,'Staff access '||p_action,p_user::text);
 ELSIF p_action<>'list' THEN RAISE EXCEPTION 'Invalid staff action';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',r.user_id,'name',coalesce((SELECT x->>'name' FROM public.owners g CROSS JOIN LATERAL jsonb_array_elements(coalesce(g.staff,'[]')) x WHERE g.id=p_tenant AND x->>'auth_user_id'=r.user_id::text LIMIT 1),'Staff account'),'email',b.contact_email,'state',coalesce(a.state,CASE WHEN r.enabled AND r.disabled_at IS NULL THEN 'active' ELSE 'suspended' END),'permissions',coalesce(a.permissions,'{}')) ORDER BY r.user_id),'[]') INTO result
 FROM public.iv_user_roles r LEFT JOIN ironvault_private.staff_access a ON a.user_id=r.user_id AND a.tenant_id=r.tenant_id
 LEFT JOIN ironvault_private.branch_accounts b ON b.user_id=r.user_id AND b.tenant_id=r.tenant_id AND b.role='staff'
 WHERE r.tenant_id=p_tenant AND r.role='staff';
 RETURN jsonb_build_object('staff',result);
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_revoke_staff(p_tenant text,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN PERFORM public.iv_staff_access(p_tenant,'suspend',p_user);END $fn$;
CREATE OR REPLACE FUNCTION public.iv_set_staff_financial_report_access(p_tenant text,p_user uuid,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE perms jsonb;
BEGIN
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'Choose a permission state';END IF;
 SELECT permissions INTO perms FROM ironvault_private.staff_access WHERE tenant_id=p_tenant AND user_id=p_user;
 perms:=coalesce(perms,'{}')||jsonb_build_object('reports_read',p_enabled);
 IF NOT p_enabled THEN perms:=perms||'{"reports_export":false}'::jsonb;END IF;
 PERFORM public.iv_staff_access(p_tenant,'permissions',p_user,jsonb_build_object('permissions',perms));
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.can_read_financial_reports(p_tenant text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT ironvault_private.subscription_super() OR ((ironvault_private.subscription_state(p_tenant)->>'read')::boolean AND ironvault_private.subscription_owner(p_tenant)) OR
 ((ironvault_private.subscription_state(p_tenant)->>'operations')::boolean AND ironvault_private.staff_has_permission(p_tenant,'reports_read'));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_checkin(p_member_id text,p_method text)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE tenant text;
BEGIN
 SELECT tenant_id INTO STRICT tenant FROM public.members WHERE id=p_member_id;
 PERFORM ironvault_private.staff_require(tenant,'manual_checkin');
 IF p_method IS DISTINCT FROM 'manual' THEN RAISE EXCEPTION 'QR admission requires a server-issued pass';END IF;
 RETURN ironvault_private.record_admission(p_member_id,'manual');
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_staff_pricing(p_tenant text,p_pricing jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE key text;price numeric;
BEGIN
 PERFORM ironvault_private.staff_require(p_tenant,'pricing_manage');PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 IF p_pricing IS NULL OR jsonb_typeof(p_pricing)<>'object' THEN RAISE EXCEPTION 'Pricing required';END IF;
 FOREACH key IN ARRAY ARRAY['day','week','month','studentDiscount','seniorDiscount'] LOOP
  price:=(p_pricing->>key)::numeric;
  IF price IS NULL OR price::text IN ('NaN','Infinity','-Infinity') OR price<0 OR (key NOT LIKE '%Discount' AND price<=0) OR price>(CASE WHEN key LIKE '%Discount' THEN 100 ELSE 10000000 END) OR price<>round(price,2) THEN RAISE EXCEPTION 'Invalid price or discount';END IF;
 END LOOP;
 UPDATE public.owners SET pricing=p_pricing WHERE id=p_tenant;
 PERFORM public.iv_log_event(p_tenant,'Membership pricing updated','Rates and default discounts updated');
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_staff_subscription_view(p_tenant text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT ironvault_private.staff_has_permission(p_tenant,'subscription_read') THEN RAISE EXCEPTION 'Subscription viewing is not permitted' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('state',ironvault_private.subscription_state(p_tenant),'periods',coalesce((SELECT jsonb_agg(jsonb_build_object('kind',kind,'plan',plan,'start_date',start_date,'end_date',end_date,'amount',amount,'approved_at',approved_at) ORDER BY start_date DESC) FROM ironvault_private.subscription_periods WHERE tenant_id=p_tenant),'[]'::jsonb));
END $fn$;
-- Targeted notices: existing publications remain member notices. All targets are private.
ALTER TABLE public.iv_announcements ADD COLUMN IF NOT EXISTS audience text NOT NULL DEFAULT 'members' CHECK(audience IN ('everyone','members','staff','selected'));
CREATE TABLE IF NOT EXISTS ironvault_private.announcement_targets (
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 announcement_id uuid NOT NULL REFERENCES public.iv_announcements(id) ON DELETE CASCADE,
 recipient_key text NOT NULL,PRIMARY KEY(announcement_id,recipient_key)
);
CREATE TABLE IF NOT EXISTS ironvault_private.account_announcement_reads (
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 announcement_id uuid NOT NULL REFERENCES public.iv_announcements(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 revision text NOT NULL,read_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(announcement_id,user_id,revision)
);
CREATE OR REPLACE FUNCTION ironvault_private.announcement_recipients(p_tenant text,p_audience text,p_selected jsonb DEFAULT '[]')
RETURNS TABLE(recipient_key text,name text,kind text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 WITH eligible AS (
 SELECT 'm:'||m.id AS recipient_key,m.name,'member'::text AS kind FROM public.members m WHERE m.tenant_id=p_tenant AND m.status='ACTIVE'
 UNION ALL SELECT 'u:'||r.user_id::text,coalesce((SELECT x->>'name' FROM public.owners g CROSS JOIN LATERAL jsonb_array_elements(coalesce(g.staff,'[]')) x WHERE g.id=p_tenant AND x->>'auth_user_id'=r.user_id::text LIMIT 1),CASE WHEN r.role='owner' THEN 'Gym owner' ELSE 'Staff' END),r.role
 FROM public.iv_user_roles r WHERE r.tenant_id=p_tenant AND r.role IN ('owner','staff') AND r.enabled AND r.disabled_at IS NULL)
 SELECT e.* FROM eligible e WHERE p_audience='everyone' OR (p_audience='members' AND e.kind='member') OR (p_audience='staff' AND e.kind='staff') OR (p_audience='selected' AND p_selected ? e.recipient_key);
$fn$;
CREATE OR REPLACE FUNCTION public.iv_announcement_audience(p_tenant text,p_audience text DEFAULT 'everyone',p_selected jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb;
BEGIN
 IF NOT ironvault_private.staff_has_permission(p_tenant,'announcements_manage') THEN RAISE EXCEPTION 'Announcement management required';END IF;
 IF p_audience NOT IN ('everyone','members','staff','selected') OR p_selected IS NULL OR jsonb_typeof(p_selected)<>'array' THEN RAISE EXCEPTION 'Invalid audience';END IF;
 SELECT jsonb_build_object('count',count(*),'recipients',coalesce(jsonb_agg(jsonb_build_object('key',recipient_key,'name',name,'kind',kind) ORDER BY kind,name),'[]')) INTO result FROM ironvault_private.announcement_recipients(p_tenant,p_audience,p_selected);
 RETURN result;
END $fn$;

ALTER TABLE public.iv_announcements ADD COLUMN IF NOT EXISTS audience_selection jsonb NOT NULL DEFAULT '[]';
CREATE OR REPLACE FUNCTION public.iv_save_targeted_announcement(p_tenant text,p_id uuid,p_title text,p_body text,
 p_starts_at timestamptz,p_ends_at timestamptz,p_pinned boolean,p_expected_version integer DEFAULT NULL,p_audience text DEFAULT 'members',p_selected jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE notice public.iv_announcements%ROWTYPE; inserted boolean:=false;
BEGIN
 PERFORM ironvault_private.staff_require(p_tenant,'announcements_manage');
 PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 IF p_audience IS NULL OR p_audience NOT IN ('everyone','members','staff','selected') OR p_selected IS NULL OR jsonb_typeof(p_selected)<>'array' OR jsonb_array_length(p_selected)>5000 THEN RAISE EXCEPTION 'Choose a valid audience';END IF;
 IF NOT EXISTS(SELECT 1 FROM ironvault_private.announcement_recipients(p_tenant,p_audience,p_selected)) OR
 (p_audience='selected' AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_selected) x WHERE NOT EXISTS(SELECT 1 FROM ironvault_private.announcement_recipients(p_tenant,'everyone') r WHERE r.recipient_key=x))) THEN RAISE EXCEPTION 'Choose eligible recipients from this gym';END IF;
 IF p_id IS NULL OR p_title IS NULL OR length(btrim(p_title)) NOT BETWEEN 1 AND 160
  OR p_body IS NULL OR length(btrim(p_body)) NOT BETWEEN 1 AND 4000 THEN RAISE EXCEPTION 'Title and message are required (160 and 4000 characters maximum)'; END IF;
 IF p_starts_at IS NULL OR p_ends_at IS NULL OR NOT isfinite(p_starts_at) OR NOT isfinite(p_ends_at)
  OR p_ends_at<=p_starts_at OR p_pinned IS NULL THEN RAISE EXCEPTION 'End time must be after start time'; END IF;
 IF p_expected_version IS NULL THEN
  INSERT INTO public.iv_announcements(id,tenant_id,title,body,starts_at,ends_at,pinned,created_by,updated_by,audience,audience_selection)
   VALUES(p_id,p_tenant,btrim(p_title),btrim(p_body),p_starts_at,p_ends_at,p_pinned,auth.uid(),auth.uid(),p_audience,p_selected)
   ON CONFLICT(id) DO NOTHING RETURNING * INTO notice;
  inserted:=FOUND;
  IF NOT inserted THEN
   SELECT * INTO notice FROM public.iv_announcements WHERE id=p_id AND tenant_id=p_tenant FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Announcement request conflict. Reload the list'; END IF;
   -- Exact create retry succeeds without another notice or another audit entry.
   IF notice.created_by=auth.uid() AND notice.version=1 AND notice.archived_at IS NULL
    AND notice.title=btrim(p_title) AND notice.body=btrim(p_body) AND notice.starts_at=p_starts_at
    AND notice.ends_at=p_ends_at AND notice.pinned=p_pinned AND notice.audience=p_audience AND notice.audience_selection=p_selected THEN RETURN to_jsonb(notice); END IF;
   RAISE EXCEPTION 'Announcement already exists or changed. Reload the list';
  END IF;
 ELSE
  SELECT * INTO notice FROM public.iv_announcements WHERE id=p_id AND tenant_id=p_tenant FOR UPDATE;
  IF NOT FOUND OR notice.archived_at IS NOT NULL THEN RAISE EXCEPTION 'Announcement unavailable'; END IF;
  IF notice.version<>p_expected_version THEN RAISE EXCEPTION 'Announcement changed. Reload and reopen Edit before saving'; END IF;
  IF notice.title=btrim(p_title) AND notice.body=btrim(p_body) AND notice.starts_at=p_starts_at
   AND notice.ends_at=p_ends_at AND notice.pinned=p_pinned AND notice.audience=p_audience AND notice.audience_selection=p_selected THEN RETURN to_jsonb(notice); END IF;
  UPDATE public.iv_announcements SET title=btrim(p_title),body=btrim(p_body),starts_at=p_starts_at,ends_at=p_ends_at,
   pinned=p_pinned,audience=p_audience,audience_selection=p_selected,version=version+1,updated_by=auth.uid(),updated_at=now() WHERE id=p_id AND tenant_id=p_tenant RETURNING * INTO notice;
 END IF;
 DELETE FROM ironvault_private.announcement_targets WHERE announcement_id=p_id;
 INSERT INTO ironvault_private.announcement_targets(tenant_id,announcement_id,recipient_key) SELECT p_tenant,p_id,recipient_key FROM ironvault_private.announcement_recipients(p_tenant,p_audience,p_selected);
 PERFORM public.iv_log_event(p_tenant,CASE WHEN inserted THEN 'Announcement created' ELSE 'Announcement updated' END,notice.title);
 RETURN to_jsonb(notice);
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_archive_announcement(p_tenant text,p_id uuid,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE notice public.iv_announcements%ROWTYPE;
BEGIN
 PERFORM ironvault_private.staff_require(p_tenant,'announcements_manage');
 PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 SELECT * INTO notice FROM public.iv_announcements WHERE id=p_id AND tenant_id=p_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Announcement unavailable'; END IF;
 IF notice.archived_at IS NOT NULL THEN RETURN to_jsonb(notice); END IF;
 IF p_expected_version IS NULL OR notice.version<>p_expected_version THEN RAISE EXCEPTION 'Announcement changed. Reload before removing'; END IF;
 UPDATE public.iv_announcements SET archived_at=now(),updated_at=now(),updated_by=auth.uid(),version=version+1
  WHERE id=p_id AND tenant_id=p_tenant RETURNING * INTO notice;
 PERFORM public.iv_log_event(p_tenant,'Announcement removed',notice.title);
 RETURN to_jsonb(notice);
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_announcement_content_revision()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF (NEW.title,NEW.body,NEW.starts_at,NEW.ends_at,NEW.audience,NEW.audience_selection) IS DISTINCT FROM (OLD.title,OLD.body,OLD.starts_at,OLD.ends_at,OLD.audience,OLD.audience_selection) THEN NEW.content_revision:=OLD.content_revision+1;ELSE NEW.content_revision:=OLD.content_revision;END IF;RETURN NEW;
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.announcement_visible(p_id uuid,p_key text,p_member boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM ironvault_private.announcement_targets t WHERE t.announcement_id=p_id AND t.recipient_key=p_key) OR
 (p_member AND EXISTS(SELECT 1 FROM public.iv_announcements a WHERE a.id=p_id AND a.audience='members') AND NOT EXISTS(SELECT 1 FROM ironvault_private.announcement_targets t WHERE t.announcement_id=p_id));
$fn$;
CREATE OR REPLACE FUNCTION public.iv_member_announcements(p_tenant text,p_mode text DEFAULT 'list',p_read jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_member text; a record; v_revision text; was_read boolean; claimed boolean; result jsonb:='[]'::jsonb;
BEGIN
 PERFORM ironvault_private.subscription_require(p_tenant,'portal');
 IF p_mode IS NULL OR p_mode NOT IN ('list','claim','read') OR p_read IS NULL
  OR jsonb_typeof(p_read)<>'array' THEN RAISE EXCEPTION 'Invalid announcement request'; END IF;
 -- Locks keep account/gym revocation from racing this operation.
 SELECT m.id INTO v_member FROM public.iv_user_roles r JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
 JOIN public.owners g ON g.id=r.tenant_id
 WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.role='member'
  AND r.enabled AND r.disabled_at IS NULL AND m.status='ACTIVE' AND g.status='ACTIVE'
 FOR SHARE OF r,m,g;
 IF NOT FOUND THEN RAISE EXCEPTION 'Member announcement access denied'; END IF;
 FOR a IN SELECT n.* FROM public.iv_announcements n WHERE n.tenant_id=p_tenant
  AND ironvault_private.announcement_visible(n.id,'m:'||v_member,true) AND n.archived_at IS NULL AND n.starts_at<=now() AND n.ends_at>now()
  ORDER BY n.pinned DESC,n.starts_at DESC,n.id FOR SHARE OF n
 LOOP
  -- Pin changes are cosmetic. Text/schedule changes constitute a significant update.
  v_revision:=a.content_revision::text;
  SELECT EXISTS(SELECT 1 FROM public.iv_announcement_reads r WHERE r.announcement_id=a.id
   AND r.member_id=v_member AND r.revision=v_revision) INTO was_read;
  claimed:=false;
  IF (p_mode='claim' AND NOT was_read) OR (p_mode='read' AND EXISTS(
   SELECT 1 FROM jsonb_array_elements(p_read) x WHERE x->>'id'=a.id::text AND x->>'revision'=v_revision)) THEN
   INSERT INTO public.iv_announcement_reads(tenant_id,announcement_id,member_id,revision)
    VALUES(p_tenant,a.id,v_member,v_revision) ON CONFLICT DO NOTHING;
   claimed:=FOUND;
   was_read:=true;
  END IF;
  result:=result||jsonb_build_array(jsonb_build_object('id',a.id,'tenant_id',a.tenant_id,'title',a.title,
   'body',a.body,'starts_at',a.starts_at,'ends_at',a.ends_at,'pinned',a.pinned,'revision',v_revision,
   'unread',NOT was_read,'popup',p_mode='claim' AND claimed));
 END LOOP;
 RETURN jsonb_build_object('items',result,'server_now',now());
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_account_announcements(p_tenant text,p_mode text DEFAULT 'list',p_read jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE a record;items jsonb:='[]';was_read boolean;rev text;
BEGIN
 IF p_mode NOT IN ('list','read') OR p_mode IS NULL OR p_read IS NULL OR jsonb_typeof(p_read)<>'array' OR jsonb_array_length(p_read)>5000 THEN RAISE EXCEPTION 'Invalid request';END IF;
 PERFORM 1 FROM public.iv_user_roles r JOIN public.owners g ON g.id=r.tenant_id WHERE r.tenant_id=p_tenant AND r.user_id=auth.uid() AND r.role IN ('owner','staff') AND r.enabled AND r.disabled_at IS NULL AND g.status='ACTIVE' FOR SHARE OF r,g;
 IF NOT FOUND THEN RAISE EXCEPTION 'Account announcement access denied' USING ERRCODE='42501';END IF;
 FOR a IN SELECT n.* FROM public.iv_announcements n WHERE n.tenant_id=p_tenant AND n.archived_at IS NULL AND n.starts_at<=now() AND n.ends_at>now() AND ironvault_private.announcement_visible(n.id,'u:'||auth.uid()::text,false) ORDER BY n.pinned DESC,n.starts_at DESC,n.id FOR SHARE LOOP
  rev:=a.content_revision::text;
  IF p_mode='read' AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_read) x WHERE x->>'id'=a.id::text AND x->>'revision'=rev) THEN
   INSERT INTO ironvault_private.account_announcement_reads(tenant_id,announcement_id,user_id,revision) VALUES(p_tenant,a.id,auth.uid(),rev) ON CONFLICT DO NOTHING;
  END IF;
  SELECT EXISTS(SELECT 1 FROM ironvault_private.account_announcement_reads r WHERE r.announcement_id=a.id AND r.user_id=auth.uid() AND r.revision=rev) INTO was_read;
  items:=items||jsonb_build_array(jsonb_build_object('id',a.id,'tenant_id',p_tenant,'title',a.title,'body',a.body,'revision',rev,'unread',NOT was_read,'starts_at',a.starts_at,'ends_at',a.ends_at));
 END LOOP;
 RETURN jsonb_build_object('items',items,'server_now',now());
END $fn$;
CREATE OR REPLACE FUNCTION public.iv_list_announcements(p_tenant text,p_state text DEFAULT 'all',p_page integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE total bigint;items jsonb;can_manage boolean;
BEGIN
 IF p_state IS NULL OR p_state NOT IN ('all','current','scheduled','expired','archived') OR p_page IS NULL OR p_page<0 OR p_page>100000 THEN RAISE EXCEPTION 'Invalid request';END IF;
 can_manage:=ironvault_private.staff_has_permission(p_tenant,'announcements_manage');
 IF NOT can_manage THEN RAISE EXCEPTION 'Announcement management required' USING ERRCODE='42501';END IF;
 SELECT count(*) INTO total FROM public.iv_announcements a WHERE a.tenant_id=p_tenant AND CASE WHEN p_state='archived' THEN a.archived_at IS NOT NULL ELSE a.archived_at IS NULL AND CASE p_state WHEN 'current' THEN a.starts_at<=now() AND a.ends_at>now() WHEN 'scheduled' THEN a.starts_at>now() WHEN 'expired' THEN a.ends_at<=now() ELSE true END END;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.pinned DESC,x.starts_at DESC,x.id),'[]') INTO items FROM (
 SELECT a.*, (SELECT count(*) FROM ironvault_private.announcement_targets t WHERE t.announcement_id=a.id) AS recipient_count FROM public.iv_announcements a WHERE a.tenant_id=p_tenant AND CASE WHEN p_state='archived' THEN a.archived_at IS NOT NULL ELSE a.archived_at IS NULL AND CASE p_state WHEN 'current' THEN a.starts_at<=now() AND a.ends_at>now() WHEN 'scheduled' THEN a.starts_at>now() WHEN 'expired' THEN a.ends_at<=now() ELSE true END END ORDER BY a.pinned DESC,a.starts_at DESC,a.id LIMIT 20 OFFSET p_page*20) x;
 RETURN jsonb_build_object('items',items,'total',total,'can_manage',true,'server_now',now());
END $fn$;
-- Pinning is cosmetic: keep the frozen audience and its content revision unchanged.
CREATE OR REPLACE FUNCTION public.iv_pin_targeted_announcement(p_tenant text,p_id uuid,p_pinned boolean,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE a public.iv_announcements%ROWTYPE;
BEGIN
 PERFORM ironvault_private.staff_require(p_tenant,'announcements_manage');PERFORM ironvault_private.subscription_require(p_tenant,'operations');
 SELECT * INTO a FROM public.iv_announcements WHERE id=p_id AND tenant_id=p_tenant FOR UPDATE;
 IF NOT FOUND OR a.archived_at IS NOT NULL OR a.version IS DISTINCT FROM p_expected_version OR p_pinned IS NULL THEN RAISE EXCEPTION 'Announcement changed. Reload the list';END IF;
 IF a.pinned IS DISTINCT FROM p_pinned THEN
  UPDATE public.iv_announcements SET pinned=p_pinned,version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=p_id AND tenant_id=p_tenant RETURNING * INTO a;
  PERFORM public.iv_log_event(p_tenant,'Announcement pin updated',a.title);
 END IF;
 RETURN to_jsonb(a);
END $fn$;
-- Keep private storage inaccessible directly, and grant only the reviewed RPCs.
DO $acl$ DECLARE tab text;f record;BEGIN
 FOREACH tab IN ARRAY ARRAY['staff_access','announcement_targets','account_announcement_reads'] LOOP
  EXECUTE format('ALTER TABLE ironvault_private.%I OWNER TO postgres',tab);
  EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',tab);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS sig,n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
 (n.nspname='ironvault_private' AND p.proname IN ('staff_has_permission','staff_require','announcement_recipients','announcement_visible')) OR
 (n.nspname='public' AND p.proname IN ('iv_staff_access','iv_revoke_staff','iv_set_staff_financial_report_access','iv_checkin','iv_staff_pricing','iv_staff_subscription_view','iv_announcement_audience','iv_save_targeted_announcement','iv_pin_targeted_announcement','iv_archive_announcement','iv_account_announcements','iv_list_announcements','iv_member_announcements','iv_announcement_content_revision')) LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',f.sig);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.sig);
  IF f.nspname='public' AND f.sig::text NOT LIKE '%iv_announcement_content_revision%' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig);END IF;
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
