-- STAGE ONE, MANUAL ONLY. No member-facing access yet. Safe to reapply this exact file.
-- Adds only announcement storage/APIs; existing accounts, balances and plans stay intact.
-- Notices follow an already-authorized whole-tenant purge; ordinary Remove archives only.
BEGIN;
CREATE TABLE IF NOT EXISTS public.iv_announcements (
 id uuid PRIMARY KEY,
 tenant_id text NOT NULL REFERENCES public.owners(id) ON DELETE CASCADE,
 title text NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 160),
 body text NOT NULL CHECK(length(btrim(body)) BETWEEN 1 AND 4000),
 starts_at timestamptz NOT NULL CHECK(isfinite(starts_at)),
 ends_at timestamptz NOT NULL CHECK(isfinite(ends_at)),
 pinned boolean NOT NULL DEFAULT false,
 archived_at timestamptz,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE NO ACTION,
 updated_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE NO ACTION,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(ends_at>starts_at)
);
ALTER TABLE public.iv_announcements OWNER TO postgres;
ALTER TABLE public.iv_announcements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.iv_announcements FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS iv_announcements_tenant_schedule ON public.iv_announcements(tenant_id,archived_at,pinned DESC,starts_at DESC,id);

CREATE OR REPLACE FUNCTION public.iv_list_announcements(p_tenant text,p_state text DEFAULT 'all',p_page integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE can_manage boolean; items jsonb; total bigint;
BEGIN
 IF auth.uid() IS NULL OR p_state IS NULL OR p_state NOT IN ('all','current','scheduled','expired','archived')
  OR p_page IS NULL OR p_page<0 OR p_page>100000 THEN RAISE EXCEPTION 'Invalid announcement request'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles r JOIN public.owners g ON g.id=r.tenant_id
  WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.role IN ('owner','staff')
   AND r.enabled AND r.disabled_at IS NULL AND g.status='ACTIVE') THEN RAISE EXCEPTION 'Announcements access denied'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant
  AND r.role='owner' AND r.enabled AND r.disabled_at IS NULL) INTO can_manage;
 IF p_state='archived' AND NOT can_manage THEN RAISE EXCEPTION 'Owner access required'; END IF;
 SELECT count(*) INTO total FROM public.iv_announcements a WHERE a.tenant_id=p_tenant
  AND CASE p_state WHEN 'archived' THEN a.archived_at IS NOT NULL
   ELSE a.archived_at IS NULL AND CASE p_state WHEN 'current' THEN a.starts_at<=now() AND a.ends_at>now()
    WHEN 'scheduled' THEN a.starts_at>now() WHEN 'expired' THEN a.ends_at<=now() ELSE true END END;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.pinned DESC,x.starts_at DESC,x.id),'[]'::jsonb) INTO items
 FROM (SELECT a.id,a.tenant_id,a.title,a.body,a.starts_at,a.ends_at,a.pinned,a.archived_at,a.version,a.created_at,a.updated_at
  FROM public.iv_announcements a WHERE a.tenant_id=p_tenant
   AND CASE p_state WHEN 'archived' THEN a.archived_at IS NOT NULL
    ELSE a.archived_at IS NULL AND CASE p_state WHEN 'current' THEN a.starts_at<=now() AND a.ends_at>now()
     WHEN 'scheduled' THEN a.starts_at>now() WHEN 'expired' THEN a.ends_at<=now() ELSE true END END
  ORDER BY a.pinned DESC,a.starts_at DESC,a.id LIMIT 20 OFFSET p_page*20) x;
 RETURN jsonb_build_object('items',items,'total',total,'page',p_page,'page_size',20,'can_manage',can_manage,'server_now',now());
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_save_announcement(p_tenant text,p_id uuid,p_title text,p_body text,
 p_starts_at timestamptz,p_ends_at timestamptz,p_pinned boolean,p_expected_version integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE notice public.iv_announcements%ROWTYPE; inserted boolean:=false;
BEGIN
 -- Lock current authority and gym state for the duration of this write.
 PERFORM 1 FROM public.iv_user_roles r JOIN public.owners g ON g.id=r.tenant_id
 WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.role='owner'
  AND r.enabled AND r.disabled_at IS NULL AND g.status='ACTIVE' FOR SHARE OF r,g;
 IF NOT FOUND THEN RAISE EXCEPTION 'Owner access required'; END IF;
 IF p_id IS NULL OR p_title IS NULL OR length(btrim(p_title)) NOT BETWEEN 1 AND 160
  OR p_body IS NULL OR length(btrim(p_body)) NOT BETWEEN 1 AND 4000 THEN RAISE EXCEPTION 'Title and message are required (160 and 4000 characters maximum)'; END IF;
 IF p_starts_at IS NULL OR p_ends_at IS NULL OR NOT isfinite(p_starts_at) OR NOT isfinite(p_ends_at)
  OR p_ends_at<=p_starts_at OR p_pinned IS NULL THEN RAISE EXCEPTION 'End time must be after start time'; END IF;
 IF p_expected_version IS NULL THEN
  INSERT INTO public.iv_announcements(id,tenant_id,title,body,starts_at,ends_at,pinned,created_by,updated_by)
   VALUES(p_id,p_tenant,btrim(p_title),btrim(p_body),p_starts_at,p_ends_at,p_pinned,auth.uid(),auth.uid())
   ON CONFLICT(id) DO NOTHING RETURNING * INTO notice;
  inserted:=FOUND;
  IF NOT inserted THEN
   SELECT * INTO notice FROM public.iv_announcements WHERE id=p_id AND tenant_id=p_tenant FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Announcement request conflict. Reload the list'; END IF;
   -- Exact create retry succeeds without another notice or another audit entry.
   IF notice.created_by=auth.uid() AND notice.version=1 AND notice.archived_at IS NULL
    AND notice.title=btrim(p_title) AND notice.body=btrim(p_body) AND notice.starts_at=p_starts_at
    AND notice.ends_at=p_ends_at AND notice.pinned=p_pinned THEN RETURN to_jsonb(notice); END IF;
   RAISE EXCEPTION 'Announcement already exists or changed. Reload the list';
  END IF;
 ELSE
  SELECT * INTO notice FROM public.iv_announcements WHERE id=p_id AND tenant_id=p_tenant FOR UPDATE;
  IF NOT FOUND OR notice.archived_at IS NOT NULL THEN RAISE EXCEPTION 'Announcement unavailable'; END IF;
  IF notice.version<>p_expected_version THEN RAISE EXCEPTION 'Announcement changed. Reload and reopen Edit before saving'; END IF;
  IF notice.title=btrim(p_title) AND notice.body=btrim(p_body) AND notice.starts_at=p_starts_at
   AND notice.ends_at=p_ends_at AND notice.pinned=p_pinned THEN RETURN to_jsonb(notice); END IF;
  UPDATE public.iv_announcements SET title=btrim(p_title),body=btrim(p_body),starts_at=p_starts_at,ends_at=p_ends_at,
   pinned=p_pinned,version=version+1,updated_by=auth.uid(),updated_at=now() WHERE id=p_id AND tenant_id=p_tenant RETURNING * INTO notice;
 END IF;
 PERFORM public.iv_log_event(p_tenant,CASE WHEN inserted THEN 'Announcement created' ELSE 'Announcement updated' END,notice.title);
 RETURN to_jsonb(notice);
END $fn$;

CREATE OR REPLACE FUNCTION public.iv_archive_announcement(p_tenant text,p_id uuid,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE notice public.iv_announcements%ROWTYPE;
BEGIN
 PERFORM 1 FROM public.iv_user_roles r JOIN public.owners g ON g.id=r.tenant_id
 WHERE r.user_id=auth.uid() AND r.tenant_id=p_tenant AND r.role='owner'
  AND r.enabled AND r.disabled_at IS NULL AND g.status='ACTIVE' FOR SHARE OF r,g;
 IF NOT FOUND THEN RAISE EXCEPTION 'Owner access required'; END IF;
 SELECT * INTO notice FROM public.iv_announcements WHERE id=p_id AND tenant_id=p_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Announcement unavailable'; END IF;
 IF notice.archived_at IS NOT NULL THEN RETURN to_jsonb(notice); END IF;
 IF p_expected_version IS NULL OR notice.version<>p_expected_version THEN RAISE EXCEPTION 'Announcement changed. Reload before removing'; END IF;
 UPDATE public.iv_announcements SET archived_at=now(),updated_at=now(),updated_by=auth.uid(),version=version+1
  WHERE id=p_id AND tenant_id=p_tenant RETURNING * INTO notice;
 PERFORM public.iv_log_event(p_tenant,'Announcement removed',notice.title);
 RETURN to_jsonb(notice);
END $fn$;
ALTER FUNCTION public.iv_list_announcements(text,text,integer) OWNER TO postgres;
ALTER FUNCTION public.iv_save_announcement(text,uuid,text,text,timestamptz,timestamptz,boolean,integer) OWNER TO postgres;
ALTER FUNCTION public.iv_archive_announcement(text,uuid,integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.iv_list_announcements(text,text,integer),
 public.iv_save_announcement(text,uuid,text,text,timestamptz,timestamptz,boolean,integer),
 public.iv_archive_announcement(text,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_list_announcements(text,text,integer),
 public.iv_save_announcement(text,uuid,text,text,timestamptz,timestamptz,boolean,integer),
 public.iv_archive_announcement(text,uuid,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
