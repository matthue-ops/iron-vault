-- MANUAL ONLY after 060. Existing Auth IDs and per-gym roles stay in place.
BEGIN;
DO $guard$ BEGIN
 IF to_regclass('ironvault_private.gym_registration_requests') IS NULL THEN RAISE EXCEPTION 'Confirm 060 first';END IF;
 IF to_regclass('ironvault_private.owner_accounts') IS NOT NULL THEN RAISE EXCEPTION '061 already installed';END IF;
END $guard$;
CREATE TABLE ironvault_private.owner_accounts(user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,contact_email text NOT NULL,contact_verified boolean NOT NULL DEFAULT false,owner_name text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE ironvault_private.owner_gym_links(tenant_id text PRIMARY KEY REFERENCES public.owners(id) ON DELETE CASCADE,owner_user uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,account_user uuid NOT NULL REFERENCES ironvault_private.owner_accounts(user_id) ON DELETE CASCADE,approved_by uuid,approved_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE INDEX iv_owner_gym_account ON ironvault_private.owner_gym_links(account_user);
CREATE TABLE ironvault_private.gym_branch_applications(id uuid PRIMARY KEY,account_user uuid NOT NULL REFERENCES ironvault_private.owner_accounts(user_id) ON DELETE CASCADE,payload jsonb NOT NULL,fingerprint text NOT NULL,legal_version uuid NOT NULL REFERENCES ironvault_private.legal_versions(id),status text NOT NULL DEFAULT 'awaiting_review' CHECK(status IN ('awaiting_review','provisioning','approved','rejected','cancelled')),revision bigint NOT NULL DEFAULT 1,submitted_by uuid NOT NULL,reviewed_by uuid,review_note text,tenant_id text REFERENCES public.owners(id) ON DELETE SET NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE UNIQUE INDEX iv_branch_application_active ON ironvault_private.gym_branch_applications(account_user,fingerprint) WHERE status IN ('awaiting_review','provisioning');
INSERT INTO ironvault_private.owner_accounts(user_id,contact_email,contact_verified,owner_name) SELECT b.user_id,b.contact_email,b.contact_verified,coalesce(g.owner_name,'') FROM ironvault_private.branch_accounts b JOIN public.owners g ON g.id=b.tenant_id WHERE b.role='owner';
INSERT INTO ironvault_private.owner_gym_links(tenant_id,owner_user,account_user) SELECT tenant_id,user_id,user_id FROM ironvault_private.branch_accounts WHERE role='owner';
CREATE FUNCTION ironvault_private.owner_enrol_061() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.role='owner' THEN
  INSERT INTO ironvault_private.owner_accounts(user_id,contact_email,contact_verified,owner_name) VALUES(NEW.user_id,NEW.contact_email,NEW.contact_verified,(SELECT coalesce(owner_name,'') FROM public.owners WHERE id=NEW.tenant_id)) ON CONFLICT DO NOTHING;
  INSERT INTO ironvault_private.owner_gym_links(tenant_id,owner_user,account_user) VALUES(NEW.tenant_id,NEW.user_id,NEW.user_id) ON CONFLICT DO NOTHING;
 END IF;RETURN NEW;
END $fn$;
CREATE TRIGGER iv_owner_enrol_061 AFTER INSERT ON ironvault_private.branch_accounts FOR EACH ROW EXECUTE FUNCTION ironvault_private.owner_enrol_061();
CREATE FUNCTION ironvault_private.owner_cleanup_061() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 DELETE FROM ironvault_private.owner_accounts a WHERE a.user_id=OLD.account_user AND NOT EXISTS(SELECT 1 FROM ironvault_private.owner_gym_links WHERE account_user=a.user_id) AND NOT EXISTS(SELECT 1 FROM ironvault_private.gym_branch_applications WHERE account_user=a.user_id AND status IN ('awaiting_review','provisioning'));RETURN OLD;
END $fn$;
CREATE TRIGGER iv_owner_cleanup_061 AFTER DELETE ON ironvault_private.owner_gym_links FOR EACH ROW EXECUTE FUNCTION ironvault_private.owner_cleanup_061();
CREATE FUNCTION ironvault_private.owner_root_061(p_user uuid) RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_id uuid;
BEGIN
 SELECT account_user INTO root_id FROM ironvault_private.owner_gym_links l JOIN public.iv_user_roles r ON r.user_id=l.owner_user AND r.tenant_id=l.tenant_id AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL JOIN public.owners g ON g.id=l.tenant_id AND g.status='ACTIVE' WHERE l.owner_user=p_user;
 IF root_id IS NULL AND EXISTS(SELECT 1 FROM ironvault_private.owner_accounts a WHERE a.user_id=p_user AND EXISTS(SELECT 1 FROM ironvault_private.owner_gym_links l JOIN public.iv_user_roles r ON r.user_id=l.owner_user AND r.tenant_id=l.tenant_id AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL JOIN public.owners g ON g.id=l.tenant_id AND g.status='ACTIVE' WHERE l.account_user=a.user_id)) THEN root_id:=p_user;END IF;
 IF root_id IS NULL THEN RAISE EXCEPTION 'Owner access unavailable' USING ERRCODE='42501';END IF;RETURN root_id;
END $fn$;
CREATE FUNCTION public.iv_owner_branches(p_action text DEFAULT 'list',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_id uuid:=ironvault_private.owner_root_061(auth.uid());a ironvault_private.gym_branch_applications%ROWTYPE;application_payload jsonb;version_id uuid;request_key uuid;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>12000 THEN RAISE EXCEPTION 'Invalid branch request';END IF;
 IF p_action='apply' THEN
  version_id:=(p_data->>'legal_version')::uuid;request_key:=(p_data->>'request_id')::uuid;
  IF request_key IS NULL THEN RAISE EXCEPTION 'Retry identity required';END IF;
  application_payload:=jsonb_build_object('gym_name',btrim(p_data->>'gym_name'),'address',btrim(p_data->>'address'),'phone',btrim(coalesce(p_data->>'phone','')),'accepted',p_data->'accepted','legal_version',version_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(root_id::text,61));SELECT * INTO a FROM ironvault_private.gym_branch_applications WHERE id=request_key;
  IF a.id IS NOT NULL THEN IF a.account_user<>root_id OR a.payload<>application_payload THEN RAISE EXCEPTION 'Application retry differs from original';END IF;
  ELSE
   IF p_data->>'accepted' IS DISTINCT FROM 'true' OR length(coalesce(application_payload->>'gym_name','')) NOT BETWEEN 1 AND 160 OR length(coalesce(application_payload->>'address','')) NOT BETWEEN 3 AND 300 OR length(application_payload->>'phone')>50 OR NOT EXISTS(SELECT 1 FROM ironvault_private.legal_settings s WHERE s.scope='platform' AND s.current_version=version_id) THEN RAISE EXCEPTION 'Complete branch details and accept current registration documents';END IF;
   SELECT * INTO a FROM ironvault_private.gym_branch_applications WHERE account_user=root_id AND fingerprint=md5(jsonb_build_array(lower(application_payload->>'gym_name'),lower(application_payload->>'address'))::text) AND status IN ('awaiting_review','provisioning');
   IF a.id IS NOT NULL AND a.payload<>application_payload THEN RAISE EXCEPTION 'An active application already exists for this branch. Cancel it before submitting changes';END IF;
   IF a.id IS NULL THEN
    INSERT INTO ironvault_private.gym_branch_applications(id,account_user,payload,fingerprint,legal_version,submitted_by) VALUES(request_key,root_id,application_payload,md5(jsonb_build_array(lower(application_payload->>'gym_name'),lower(application_payload->>'address'))::text),version_id,auth.uid()) RETURNING * INTO a;
    INSERT INTO ironvault_private.provider_notices(notice_key,title,message) VALUES('branch:'||a.id,'Gym branch application','An existing owner submitted a branch application. Review it in Gym Registration.') ON CONFLICT DO NOTHING;
   END IF;
  END IF;
 ELSIF p_action='cancel' THEN
  SELECT * INTO a FROM ironvault_private.gym_branch_applications WHERE id=(p_data->>'id')::uuid AND account_user=root_id FOR UPDATE;
  IF a.id IS NULL OR a.status NOT IN ('awaiting_review','cancelled') THEN RAISE EXCEPTION 'Application can no longer be cancelled';END IF;
  IF a.status<>'cancelled' THEN IF a.revision IS DISTINCT FROM (p_data->>'revision')::bigint THEN RAISE EXCEPTION 'Application changed; refresh';END IF;UPDATE ironvault_private.gym_branch_applications SET status='cancelled',revision=revision+1,updated_at=clock_timestamp() WHERE id=a.id;UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE notice_key='branch:'||a.id;END IF;
 ELSIF p_action<>'list' THEN RAISE EXCEPTION 'Invalid owner action';END IF;
 RETURN jsonb_build_object('version',7,'shared',root_id<>auth.uid() OR (SELECT count(*) FROM ironvault_private.owner_gym_links WHERE account_user=root_id)>1,'gyms',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'name',g.gym_name,'token',g.token) ORDER BY g.gym_name) FROM ironvault_private.owner_gym_links l JOIN public.owners g ON g.id=l.tenant_id AND g.status='ACTIVE' JOIN public.iv_user_roles r ON r.user_id=l.owner_user AND r.tenant_id=l.tenant_id AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL WHERE l.account_user=root_id),'[]'),'applications',coalesce((SELECT jsonb_agg(to_jsonb(x)-'account_user'-'fingerprint'-'submitted_by'-'reviewed_by' ORDER BY x.created_at DESC) FROM (SELECT * FROM ironvault_private.gym_branch_applications WHERE account_user=root_id ORDER BY created_at DESC LIMIT 50) x),'[]'));
END $fn$;
CREATE FUNCTION public.iv_gym_branch_review(p_action text DEFAULT 'list',p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE a ironvault_private.gym_branch_applications%ROWTYPE;
BEGIN
 IF NOT ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Provider required' USING ERRCODE='42501';END IF;
 IF p_action='reject' THEN
  SELECT * INTO a FROM ironvault_private.gym_branch_applications WHERE id=(p_data->>'id')::uuid FOR UPDATE;
  IF a.status='rejected' THEN NULL;ELSE
   IF a.status IS DISTINCT FROM 'awaiting_review' OR a.revision IS DISTINCT FROM (p_data->>'revision')::bigint OR length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'Review changed or rejection reason missing';END IF;
   UPDATE ironvault_private.gym_branch_applications SET status='rejected',reviewed_by=auth.uid(),review_note=btrim(p_data->>'reason'),revision=revision+1,updated_at=clock_timestamp() WHERE id=a.id;
   INSERT INTO ironvault_private.owner_notifications(tenant_id,owner_id,notice_key,title,message,available_at) SELECT recipient.tenant_id,recipient.owner_user,'branch-rejected:'||a.id,'Branch application reviewed','Your application was not approved. Open Add Gym Branch to read the provider response.',clock_timestamp() FROM ironvault_private.owner_gym_links recipient WHERE recipient.account_user=a.account_user ON CONFLICT DO NOTHING;
   UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE notice_key='branch:'||a.id;
  END IF;
 ELSIF p_action<>'list' THEN RAISE EXCEPTION 'Invalid review action';END IF;
 RETURN jsonb_build_object('version',7,'items',coalesce((SELECT jsonb_agg((to_jsonb(x)-'account_user'-'fingerprint')||jsonb_build_object('owner_name',o.owner_name,'owner_email',o.contact_email) ORDER BY (x.status IN ('awaiting_review','provisioning')) DESC,x.created_at DESC) FROM (SELECT * FROM ironvault_private.gym_branch_applications ORDER BY (status IN ('awaiting_review','provisioning')) DESC,created_at DESC LIMIT 51 OFFSET least(greatest(coalesce((p_data->>'page')::integer,0),0),10000)*50) x JOIN ironvault_private.owner_accounts o ON o.user_id=x.account_user),'[]'));
END $fn$;
CREATE FUNCTION public.iv_owner_account_service(p_action text,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_id uuid;l ironvault_private.owner_gym_links%ROWTYPE;a ironvault_private.gym_branch_applications%ROWTYPE;j ironvault_private.gym_registration_requests%ROWTYPE;account ironvault_private.owner_accounts%ROWTYPE;actor_id uuid:=(p_data->>'actor_id')::uuid;payload jsonb;result jsonb;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::text)>15000 THEN RAISE EXCEPTION 'Invalid owner service request';END IF;
 IF p_action='lookup' THEN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('account_user',o.user_id,'auth_email',u.email)) FROM ironvault_private.owner_accounts o JOIN auth.users u ON u.id=o.user_id WHERE o.contact_email=lower(btrim(p_data->>'email')) AND EXISTS(SELECT 1 FROM ironvault_private.owner_gym_links z JOIN public.owners g ON g.id=z.tenant_id AND g.status='ACTIVE' JOIN public.iv_user_roles r ON r.user_id=z.owner_user AND r.tenant_id=z.tenant_id AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL WHERE z.account_user=o.user_id AND (nullif(p_data->>'gym_token','') IS NULL OR g.token=p_data->>'gym_token'))),'[]');
 ELSIF p_action='credential' THEN
  SELECT * INTO l FROM ironvault_private.owner_gym_links WHERE owner_user=(p_data->>'user_id')::uuid;
  IF l.tenant_id IS NULL THEN RETURN NULL;END IF;
  root_id:=ironvault_private.owner_root_061(l.owner_user);
  SELECT * INTO account FROM ironvault_private.owner_accounts WHERE user_id=root_id;
  RETURN jsonb_build_object('account_user',root_id,'email',account.contact_email,'auth_email',(SELECT email FROM auth.users WHERE id=root_id),'shared',root_id<>l.owner_user OR (SELECT count(*) FROM ironvault_private.owner_gym_links WHERE account_user=root_id)>1);
 ELSIF p_action='target' THEN
  root_id:=ironvault_private.owner_root_061(actor_id);
  SELECT * INTO l FROM ironvault_private.owner_gym_links WHERE account_user=root_id AND tenant_id=p_data->>'tenant_id';
  IF l.tenant_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.owners WHERE id=l.tenant_id AND status='ACTIVE') OR NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=l.owner_user AND tenant_id=l.tenant_id AND role='owner' AND enabled AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Branch access unavailable';END IF;
  RETURN jsonb_build_object('user_id',l.owner_user,'auth_email',(SELECT email FROM auth.users WHERE id=l.owner_user),'gym',(SELECT jsonb_build_object('id',id,'name',gym_name,'token',token) FROM public.owners WHERE id=l.tenant_id));
 ELSIF p_action IN ('prepare_branch','finish_branch') THEN
  IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles WHERE user_id=actor_id AND role='super_admin' AND tenant_id IS NULL AND enabled AND disabled_at IS NULL) THEN RAISE EXCEPTION 'Provider required';END IF;
  SELECT * INTO a FROM ironvault_private.gym_branch_applications WHERE id=(p_data->>'id')::uuid FOR UPDATE;
  IF a.id IS NULL THEN RAISE EXCEPTION 'Application unavailable';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(a.account_user::text,61));
  SELECT * INTO account FROM ironvault_private.owner_accounts WHERE user_id=a.account_user;
  IF a.status='approved' THEN RETURN jsonb_build_object('status','approved','gym',(SELECT jsonb_build_object('id',id,'name',gym_name,'token',token) FROM public.owners WHERE id=a.tenant_id));END IF;
  IF p_action='prepare_branch' THEN
   IF a.status='awaiting_review' THEN
    IF a.revision IS DISTINCT FROM (p_data->>'revision')::bigint OR p_data->>'reviewed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Review ownership, branch details and current application';END IF;
    payload:=a.payload||jsonb_build_object('name',coalesce((SELECT g.owner_name FROM ironvault_private.owner_gym_links z JOIN public.owners g ON g.id=z.tenant_id WHERE z.account_user=a.account_user AND length(btrim(coalesce(g.owner_name,'')))>0 ORDER BY (z.owner_user=a.submitted_by) DESC LIMIT 1),account.owner_name),'pricing',jsonb_build_object('day',100,'week',600,'month',2000,'studentDiscount',20,'seniorDiscount',20));
    result:=ironvault_private.prepare_registered_gym_060(a.id,account.contact_email,p_data->>'alias',payload,actor_id,'branch');
    IF result->>'needs_legal_review'='true' THEN RAISE EXCEPTION 'Registration terms changed. The owner must cancel and resubmit after reviewing current documents';END IF;
    UPDATE ironvault_private.gym_branch_applications SET status='provisioning',reviewed_by=actor_id,revision=revision+1,updated_at=clock_timestamp() WHERE id=a.id;
   ELSIF a.status<>'provisioning' OR a.reviewed_by<>actor_id THEN RAISE EXCEPTION 'Application changed or review authority differs';END IF;
   SELECT * INTO j FROM ironvault_private.gym_registration_requests WHERE id=a.id;
   IF j.id IS NULL THEN UPDATE ironvault_private.gym_branch_applications SET status='cancelled',revision=revision+1,review_note='This registration was explicitly removed. Submit a new application if needed.',updated_at=clock_timestamp() WHERE id=a.id;UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE notice_key='branch:'||a.id;RETURN jsonb_build_object('status','cancelled');END IF;
   RETURN jsonb_build_object('status','provisioning','request_id',j.id,'tenant_id',j.tenant_id,'alias',j.alias,'completed_user',j.completed_user,'account_user',a.account_user,'owner_name',j.payload->>'name');
  END IF;
  IF a.status<>'provisioning' OR a.reviewed_by<>actor_id THEN RAISE EXCEPTION 'Application changed';END IF;
  SELECT * INTO j FROM ironvault_private.gym_registration_requests WHERE id=a.id FOR UPDATE;
  IF j.id IS NULL THEN UPDATE ironvault_private.gym_branch_applications SET status='cancelled',revision=revision+1,review_note='This registration was explicitly removed. Submit a new application if needed.',updated_at=clock_timestamp() WHERE id=a.id;UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE notice_key='branch:'||a.id;RETURN jsonb_build_object('status','cancelled');END IF;
  IF EXISTS(SELECT 1 FROM ironvault_private.branch_accounts WHERE tenant_id=j.tenant_id AND role='staff' AND contact_email IN (j.contact_email,account.contact_email)) THEN RAISE EXCEPTION 'Owner email conflicts with a staff account in this branch';END IF;
  result:=public.iv_finish_branch_account(a.id,(p_data->>'user_id')::uuid);
  UPDATE ironvault_private.owner_gym_links SET account_user=a.account_user,approved_by=actor_id,approved_at=clock_timestamp() WHERE tenant_id=j.tenant_id AND owner_user=(p_data->>'user_id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'New branch owner binding unavailable';END IF;
  DELETE FROM ironvault_private.owner_accounts o WHERE o.user_id=(p_data->>'user_id')::uuid AND o.user_id<>a.account_user AND NOT EXISTS(SELECT 1 FROM ironvault_private.owner_gym_links WHERE account_user=o.user_id);
  UPDATE ironvault_private.branch_accounts SET contact_email=account.contact_email,contact_verified=account.contact_verified WHERE user_id=(p_data->>'user_id')::uuid;
  UPDATE ironvault_private.gym_registration_requests SET completed_user=(p_data->>'user_id')::uuid WHERE id=a.id;
  UPDATE ironvault_private.legal_settings SET draft=draft||jsonb_build_object('name',a.payload->>'gym_name','address',a.payload->>'address','phone',a.payload->>'phone') WHERE scope=j.tenant_id;
  UPDATE ironvault_private.gym_subscriptions SET is_test=false WHERE tenant_id=j.tenant_id;
  UPDATE ironvault_private.gym_branch_applications SET status='approved',tenant_id=j.tenant_id,revision=revision+1,updated_at=clock_timestamp() WHERE id=a.id;
  UPDATE ironvault_private.provider_notices SET resolved_at=clock_timestamp() WHERE notice_key='branch:'||a.id;
  INSERT INTO ironvault_private.owner_notifications(tenant_id,owner_id,notice_key,title,message,available_at) SELECT recipient.tenant_id,recipient.owner_user,'branch-approved:'||a.id,'Branch approved','Your branch is available in Switch Gym / Branch. Its setup, agreements and pilot approval remain separate.',clock_timestamp() FROM ironvault_private.owner_gym_links recipient WHERE recipient.account_user=a.account_user ON CONFLICT DO NOTHING;
  RETURN result||jsonb_build_object('status','approved','gym',(SELECT jsonb_build_object('id',id,'name',gym_name,'token',token) FROM public.owners WHERE id=j.tenant_id));
 END IF;RAISE EXCEPTION 'Unknown owner service action';
END $fn$;
CREATE FUNCTION ironvault_private.owner_contact_sync_061() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_id uuid;account ironvault_private.owner_accounts%ROWTYPE;
BEGIN
 IF NEW.role<>'owner' OR (OLD.contact_email IS NOT DISTINCT FROM NEW.contact_email AND OLD.contact_verified IS NOT DISTINCT FROM NEW.contact_verified) THEN RETURN NEW;END IF;
 SELECT account_user INTO root_id FROM ironvault_private.owner_gym_links WHERE owner_user=NEW.user_id;IF root_id IS NULL THEN RETURN NEW;END IF;
 SELECT * INTO account FROM ironvault_private.owner_accounts WHERE user_id=root_id FOR UPDATE;
 IF account.contact_email IS NOT DISTINCT FROM NEW.contact_email AND account.contact_verified IS NOT DISTINCT FROM NEW.contact_verified THEN RETURN NEW;END IF;
 IF EXISTS(SELECT 1 FROM ironvault_private.owner_gym_links l JOIN ironvault_private.branch_accounts b ON b.tenant_id=l.tenant_id AND b.role IN ('owner','staff') WHERE l.account_user=root_id AND b.contact_email=NEW.contact_email AND b.user_id<>l.owner_user) THEN RAISE EXCEPTION 'New owner email conflicts with an admin account in a linked branch';END IF;
 UPDATE ironvault_private.owner_accounts SET contact_email=NEW.contact_email,contact_verified=NEW.contact_verified WHERE user_id=root_id;
 UPDATE ironvault_private.branch_accounts b SET contact_email=NEW.contact_email,contact_verified=NEW.contact_verified WHERE EXISTS(SELECT 1 FROM ironvault_private.owner_gym_links l WHERE l.account_user=root_id AND l.owner_user=b.user_id) AND (b.contact_email IS DISTINCT FROM NEW.contact_email OR b.contact_verified IS DISTINCT FROM NEW.contact_verified);
 RETURN NEW;
END $fn$;
CREATE TRIGGER iv_owner_contact_sync_061 AFTER UPDATE OF contact_email,contact_verified ON ironvault_private.branch_accounts FOR EACH ROW EXECUTE FUNCTION ironvault_private.owner_contact_sync_061();
ALTER FUNCTION public.iv_confirm_email_action(text) RENAME TO confirm_email_action_061_base;
ALTER FUNCTION public.confirm_email_action_061_base(text) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_confirm_email_action(p_hash text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_id uuid;
BEGIN
 SELECT l.account_user INTO root_id FROM ironvault_private.email_actions e JOIN ironvault_private.owner_gym_links l ON l.owner_user=e.user_id WHERE e.token_hash=p_hash;
 IF root_id IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended(root_id::text,61));END IF;
 RETURN ironvault_private.confirm_email_action_061_base(p_hash);
END $fn$;
ALTER FUNCTION public.iv_owner_contact_recovery(text,jsonb) RENAME TO owner_contact_recovery_061_base;
ALTER FUNCTION public.owner_contact_recovery_061_base(text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_owner_contact_recovery(p_action text,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_id uuid;
BEGIN
 IF p_action IN ('inspect','confirm') THEN SELECT l.account_user INTO root_id FROM ironvault_private.owner_contact_recoveries q JOIN ironvault_private.owner_gym_links l ON l.owner_user=q.user_id WHERE q.token_hash=p_data->>'token_hash';IF root_id IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended(root_id::text,61));END IF;END IF;
 RETURN ironvault_private.owner_contact_recovery_061_base(p_action,p_data);
END $fn$;
DO $acl$ DECLARE f record;t text;BEGIN
 FOREACH t IN ARRAY ARRAY['owner_accounts','owner_gym_links','gym_branch_applications'] LOOP EXECUTE format('ALTER TABLE ironvault_private.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('REVOKE ALL ON ironvault_private.%I FROM PUBLIC,anon,authenticated,service_role',t);END LOOP;
 FOR f IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='ironvault_private' AND p.proname IN ('owner_enrol_061','owner_cleanup_061','owner_root_061','owner_contact_sync_061','confirm_email_action_061_base','owner_contact_recovery_061_base')) OR (n.nspname='public' AND p.proname IN ('iv_owner_branches','iv_gym_branch_review','iv_owner_account_service','iv_confirm_email_action','iv_owner_contact_recovery')) LOOP
 EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO postgres',f.nspname,f.proname,f.args);EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',f.nspname,f.proname,f.args);
 IF f.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO %I',f.nspname,f.proname,f.args,CASE WHEN f.proname IN ('iv_owner_branches','iv_gym_branch_review') THEN 'authenticated' ELSE 'service_role' END);END IF;
 END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';COMMIT;
