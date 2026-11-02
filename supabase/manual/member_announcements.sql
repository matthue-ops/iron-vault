-- MANUAL ONLY. Apply after 024. Adds read receipts; no existing financial/member data rewritten.
BEGIN;
ALTER TABLE public.iv_announcements ADD COLUMN IF NOT EXISTS content_revision bigint NOT NULL DEFAULT 1;
CREATE OR REPLACE FUNCTION public.iv_announcement_content_revision()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $rev$
BEGIN
 IF (NEW.title,NEW.body,NEW.starts_at,NEW.ends_at) IS DISTINCT FROM
    (OLD.title,OLD.body,OLD.starts_at,OLD.ends_at) THEN
  NEW.content_revision:=OLD.content_revision+1;
 ELSE NEW.content_revision:=OLD.content_revision;
 END IF;
 RETURN NEW;
END $rev$;
ALTER FUNCTION public.iv_announcement_content_revision() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.iv_announcement_content_revision() FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS iv_announcement_content_revision ON public.iv_announcements;
CREATE TRIGGER iv_announcement_content_revision BEFORE UPDATE ON public.iv_announcements
 FOR EACH ROW EXECUTE FUNCTION public.iv_announcement_content_revision();
CREATE TABLE IF NOT EXISTS public.iv_announcement_reads (
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 announcement_id uuid NOT NULL REFERENCES public.iv_announcements(id) ON DELETE CASCADE,
 member_id text NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
 revision text NOT NULL,
 read_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(announcement_id,member_id,revision)
);
ALTER TABLE public.iv_announcement_reads OWNER TO postgres;
ALTER TABLE public.iv_announcement_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.iv_announcement_reads FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS iv_announcement_reads_tenant ON public.iv_announcement_reads(tenant_id);

-- list: active feed; claim: atomically reserve unread popups across devices;
-- read: acknowledge only the supplied, displayed id/revision pairs.
CREATE OR REPLACE FUNCTION public.iv_member_announcements(p_tenant text,p_mode text DEFAULT 'list',p_read jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_member text; a record; v_revision text; was_read boolean; claimed boolean; result jsonb:='[]'::jsonb;
BEGIN
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
  AND n.archived_at IS NULL AND n.starts_at<=now() AND n.ends_at>now()
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
ALTER FUNCTION public.iv_member_announcements(text,text,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.iv_member_announcements(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_member_announcements(text,text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
