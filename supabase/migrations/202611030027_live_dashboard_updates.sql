-- MANUAL ONLY after 026. Publish change identifiers only, never business-row payloads.
BEGIN;
CREATE TABLE IF NOT EXISTS public.iv_live_signals (
 kind text NOT NULL CHECK(kind IN ('member','gym','system')),
 entity_id text NOT NULL CHECK(length(entity_id)>0),
 tenant_id text REFERENCES public.owners(id) ON DELETE CASCADE,
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(kind,entity_id),
 CHECK((kind='system' AND entity_id='global' AND tenant_id IS NULL)
  OR (kind='gym' AND tenant_id IS NOT NULL AND entity_id=tenant_id)
  OR (kind='member' AND tenant_id IS NOT NULL))
);
ALTER TABLE public.iv_live_signals OWNER TO postgres;
ALTER TABLE public.iv_live_signals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.iv_live_signals FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.iv_live_signals TO authenticated;
CREATE INDEX IF NOT EXISTS iv_live_signals_tenant ON public.iv_live_signals(tenant_id);

CREATE OR REPLACE FUNCTION public.iv_can_read_live_signal(p_tenant text,p_kind text,p_entity text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
  ((r.role='super_admin' AND r.tenant_id IS NULL) OR
   (r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE') AND
    (r.role IN ('owner','staff') OR (r.role='member' AND (p_kind='gym' OR (p_kind='member' AND p_entity=r.member_id))
     AND EXISTS(SELECT 1 FROM public.members m WHERE m.id=r.member_id AND m.tenant_id=p_tenant AND m.status='ACTIVE'))))));
$fn$;
ALTER FUNCTION public.iv_can_read_live_signal(text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.iv_can_read_live_signal(text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_can_read_live_signal(text,text,text) TO authenticated;
DROP POLICY IF EXISTS iv_live_read ON public.iv_live_signals;
CREATE POLICY iv_live_read ON public.iv_live_signals FOR SELECT TO authenticated
 USING(public.iv_can_read_live_signal(tenant_id,kind,entity_id));

-- Tiny periodic checkpoint: catch missed events and recheck authorization without full roster downloads.
CREATE OR REPLACE FUNCTION public.iv_live_cursor(p_tenant text DEFAULT NULL,p_member text DEFAULT NULL,p_cursor text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE allowed boolean; checkpoint text; signals jsonb;
BEGIN
 IF p_tenant IS NULL THEN
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.role='super_admin'
   AND r.tenant_id IS NULL AND r.enabled AND r.disabled_at IS NULL) AND p_member IS NULL INTO allowed;
 ELSIF p_member IS NULL THEN
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL
   AND ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.role IN ('owner','staff') AND r.tenant_id=p_tenant
    AND EXISTS(SELECT 1 FROM public.owners g WHERE g.id=p_tenant AND g.status='ACTIVE')))) INTO allowed;
 ELSE
  SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r JOIN public.members m ON m.id=r.member_id AND m.tenant_id=r.tenant_id
   JOIN public.owners g ON g.id=r.tenant_id WHERE r.user_id=auth.uid() AND r.role='member'
    AND r.tenant_id=p_tenant AND r.member_id=p_member AND r.enabled AND r.disabled_at IS NULL
    AND m.status='ACTIVE' AND g.status='ACTIVE') INTO allowed;
 END IF;
 IF NOT coalesce(allowed,false) THEN RAISE EXCEPTION 'Live update access denied' USING ERRCODE='42501'; END IF;
 SELECT md5(coalesce(string_agg(s.kind||':'||s.entity_id||':'||s.revision::text,'|' ORDER BY s.kind,s.entity_id),'')),
  coalesce(jsonb_agg(jsonb_build_object('kind',s.kind,'entity_id',s.entity_id,'tenant_id',s.tenant_id,'revision',s.revision::text) ORDER BY s.kind,s.entity_id),'[]'::jsonb)
 INTO checkpoint,signals
 FROM public.iv_live_signals s WHERE p_tenant IS NULL OR
  (s.tenant_id=p_tenant AND (p_member IS NULL OR s.kind='gym' OR (s.kind='member' AND s.entity_id=p_member)));
 RETURN jsonb_build_object('cursor',checkpoint,'server_now',now(),'signals',CASE WHEN checkpoint IS DISTINCT FROM p_cursor THEN signals ELSE 'null'::jsonb END);
END $fn$;
ALTER FUNCTION public.iv_live_cursor(text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.iv_live_cursor(text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_live_cursor(text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION ironvault_private.emit_live_signal(p_kind text,p_entity text,p_tenant text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 INSERT INTO public.iv_live_signals AS current_signal(kind,entity_id,tenant_id) VALUES(p_kind,p_entity,p_tenant)
 ON CONFLICT(kind,entity_id) DO UPDATE SET tenant_id=excluded.tenant_id,
  revision=current_signal.revision+1,changed_at=clock_timestamp();
END $fn$;
ALTER FUNCTION ironvault_private.emit_live_signal(text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.emit_live_signal(text,text,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION ironvault_private.live_member_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF TG_OP='UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.owners WHERE id=OLD.tenant_id) THEN
   PERFORM ironvault_private.emit_live_signal('member',OLD.id,OLD.tenant_id);
  END IF;
  RETURN OLD;
 END IF;
 IF EXISTS(SELECT 1 FROM public.owners WHERE id=NEW.tenant_id) THEN
  PERFORM ironvault_private.emit_live_signal('member',NEW.id,NEW.tenant_id);
 END IF;
 IF TG_OP='UPDATE' AND OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
  AND EXISTS(SELECT 1 FROM public.owners WHERE id=OLD.tenant_id) THEN
  PERFORM ironvault_private.emit_live_signal('gym',OLD.tenant_id,OLD.tenant_id);
 END IF;
 RETURN NEW;
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.live_gym_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF TG_OP='UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
 IF TG_OP='DELETE' THEN
  PERFORM ironvault_private.emit_live_signal('system','global',NULL);
  RETURN OLD;
 END IF;
 IF EXISTS(SELECT 1 FROM public.owners WHERE id=NEW.id) THEN
  PERFORM ironvault_private.emit_live_signal('gym',NEW.id,NEW.id);
 END IF;
 RETURN NEW;
END $fn$;
CREATE OR REPLACE FUNCTION ironvault_private.live_access_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF TG_OP='UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
 IF TG_OP<>'INSERT' THEN
  IF OLD.tenant_id IS NULL THEN PERFORM ironvault_private.emit_live_signal('system','global',NULL);
  ELSIF EXISTS(SELECT 1 FROM public.owners WHERE id=OLD.tenant_id) THEN
   PERFORM ironvault_private.emit_live_signal('gym',OLD.tenant_id,OLD.tenant_id);
  END IF;
 END IF;
 IF TG_OP<>'DELETE' THEN
  IF NEW.tenant_id IS NULL THEN PERFORM ironvault_private.emit_live_signal('system','global',NULL);
  ELSIF EXISTS(SELECT 1 FROM public.owners WHERE id=NEW.tenant_id) THEN
   PERFORM ironvault_private.emit_live_signal('gym',NEW.tenant_id,NEW.tenant_id);
  END IF;
 END IF;
 RETURN NULL;
END $fn$;
ALTER FUNCTION ironvault_private.live_member_changed() OWNER TO postgres;
ALTER FUNCTION ironvault_private.live_gym_changed() OWNER TO postgres;
ALTER FUNCTION ironvault_private.live_access_changed() OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.live_member_changed(),ironvault_private.live_gym_changed(),ironvault_private.live_access_changed()
 FROM PUBLIC,anon,authenticated,service_role;
-- Defer signal locks until business statements finish, avoiding early gym-signal lock inversion.
DROP TRIGGER IF EXISTS iv_live_member_changed ON public.members;
CREATE CONSTRAINT TRIGGER iv_live_member_changed AFTER INSERT OR UPDATE OR DELETE ON public.members
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ironvault_private.live_member_changed();
DROP TRIGGER IF EXISTS iv_live_gym_changed ON public.owners;
CREATE CONSTRAINT TRIGGER iv_live_gym_changed AFTER INSERT OR UPDATE OR DELETE ON public.owners
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ironvault_private.live_gym_changed();
DROP TRIGGER IF EXISTS iv_live_role_changed ON public.iv_user_roles;
CREATE CONSTRAINT TRIGGER iv_live_role_changed AFTER INSERT OR UPDATE OR DELETE ON public.iv_user_roles
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ironvault_private.live_access_changed();
DROP TRIGGER IF EXISTS iv_live_permission_changed ON ironvault_private.staff_report_permissions;
CREATE CONSTRAINT TRIGGER iv_live_permission_changed AFTER INSERT OR UPDATE OR DELETE ON ironvault_private.staff_report_permissions
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ironvault_private.live_access_changed();
-- Seed only lightweight gym checkpoints; no historical/member data is rewritten.
INSERT INTO public.iv_live_signals(kind,entity_id,tenant_id)
 SELECT 'gym',id,id FROM public.owners ON CONFLICT DO NOTHING;
INSERT INTO public.iv_live_signals(kind,entity_id,tenant_id) VALUES('system','global',NULL) ON CONFLICT DO NOTHING;
DO $publication$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
  RAISE EXCEPTION 'Supabase Realtime publication is missing; review setup before installing';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime' AND puballtables) THEN
  RAISE EXCEPTION 'Publication includes all tables; review privacy configuration before installing';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime' AND NOT (pubinsert AND pubupdate)) THEN
  RAISE EXCEPTION 'Realtime publication must support INSERT and UPDATE events';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_publication_rel r JOIN pg_publication p ON p.oid=r.prpubid
  WHERE p.pubname='supabase_realtime' AND r.prrelid='public.iv_live_signals'::regclass) THEN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.iv_live_signals;
 END IF;
END $publication$;
NOTIFY pgrst,'reload schema';
COMMIT;
