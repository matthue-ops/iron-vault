-- MANUAL ONLY after 025. Add URL mappings, preserving all existing tenant IDs/tokens.
BEGIN;
CREATE TABLE IF NOT EXISTS public.iv_gym_portal_links (
 tenant_id text PRIMARY KEY REFERENCES public.owners(id) ON DELETE CASCADE,
 slug text NOT NULL UNIQUE CHECK(length(slug) BETWEEN 1 AND 96 AND slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.iv_gym_portal_links OWNER TO postgres;
ALTER TABLE public.iv_gym_portal_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.iv_gym_portal_links FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ironvault_private.assign_gym_portal_link(p_tenant text,p_name text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE base_name text; candidate text; existing text; suffix integer:=1;
BEGIN
 SELECT slug INTO existing FROM public.iv_gym_portal_links WHERE tenant_id=p_tenant;
 IF FOUND THEN RETURN existing; END IF;
 base_name:=btrim(left(regexp_replace(lower(coalesce(p_name,'')),'[^a-z0-9]+','-','g'),70),'-');
 IF base_name='' OR base_name=ANY(ARRAY['gym','assets','api','docs','supabase','tests','index','favicon','robots','sitemap','login','logout','admin','memberlogin','memberprofile','reports','health']) THEN base_name:='gym-branch'; END IF;
 LOOP
  candidate:=base_name||CASE WHEN suffix=1 THEN '' ELSE '-'||suffix::text END;
  INSERT INTO public.iv_gym_portal_links(tenant_id,slug) VALUES(p_tenant,candidate) ON CONFLICT DO NOTHING;
  IF FOUND THEN RETURN candidate; END IF;
  -- A concurrent creator/backfill for this same gym must retain its assigned name.
  SELECT slug INTO existing FROM public.iv_gym_portal_links WHERE tenant_id=p_tenant;
  IF FOUND THEN RETURN existing; END IF;
  suffix:=suffix+1;
  IF suffix>100000 THEN RAISE EXCEPTION 'Unable to allocate a unique gym URL'; END IF;
 END LOOP;
END $fn$;
ALTER FUNCTION ironvault_private.assign_gym_portal_link(text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.assign_gym_portal_link(text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ironvault_private.assign_new_gym_portal_link()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 PERFORM ironvault_private.assign_gym_portal_link(NEW.id,NEW.gym_name);
 RETURN NEW;
END $fn$;
ALTER FUNCTION ironvault_private.assign_new_gym_portal_link() OWNER TO postgres;
REVOKE ALL ON FUNCTION ironvault_private.assign_new_gym_portal_link() FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS iv_assign_gym_portal_link ON public.owners;
CREATE TRIGGER iv_assign_gym_portal_link AFTER INSERT ON public.owners
 FOR EACH ROW EXECUTE FUNCTION ironvault_private.assign_new_gym_portal_link();
DO $backfill$
DECLARE gym record;
BEGIN
 FOR gym IN SELECT id,gym_name FROM public.owners ORDER BY id LOOP
  PERFORM ironvault_private.assign_gym_portal_link(gym.id,gym.gym_name);
 END LOOP;
END $backfill$;

-- Preserve the existing safe projection and its exact column order; append only portal_slug.
CREATE OR REPLACE VIEW public.iv_gyms WITH(security_barrier=true) AS
 SELECT visible.*,g.display_code,links.slug AS portal_slug
 FROM public.iv_visible_gyms() visible JOIN public.owners g ON g.id=visible.id
 LEFT JOIN public.iv_gym_portal_links links ON links.tenant_id=visible.id;
ALTER VIEW public.iv_gyms OWNER TO postgres;
GRANT SELECT ON public.iv_gyms TO anon,authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
