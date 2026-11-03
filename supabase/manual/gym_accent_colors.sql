-- MANUAL ONLY, after 027. No financial or membership data is changed.
BEGIN;
ALTER TABLE public.owners ADD COLUMN IF NOT EXISTS accent_color text NOT NULL DEFAULT '#10b981'
 CHECK(accent_color ~ '^#[0-9a-fA-F]{6}$');
-- Existing base-table privileges remain restricted. Only the dedicated RPC writes this field.
REVOKE UPDATE(accent_color) ON public.owners FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE VIEW public.iv_gyms WITH(security_barrier=true) AS
 SELECT visible.*,g.display_code,links.slug AS portal_slug,g.accent_color
 FROM public.iv_visible_gyms() visible JOIN public.owners g ON g.id=visible.id
 LEFT JOIN public.iv_gym_portal_links links ON links.tenant_id=visible.id;
ALTER VIEW public.iv_gyms OWNER TO postgres;
GRANT SELECT ON public.iv_gyms TO anon,authenticated;
CREATE OR REPLACE FUNCTION public.iv_set_gym_accent(p_tenant text,p_color text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid()
  AND r.role='super_admin' AND r.tenant_id IS NULL AND r.enabled AND r.disabled_at IS NULL) THEN
  RAISE EXCEPTION 'Only Super Admin can change gym colors' USING ERRCODE='42501';
 END IF;
 IF p_color IS NULL OR p_color !~ '^#[0-9a-fA-F]{6}$' THEN
  RAISE EXCEPTION 'Choose a six-digit hex color' USING ERRCODE='22023';
 END IF;
 UPDATE public.owners SET accent_color=lower(p_color) WHERE id=p_tenant;
 IF NOT FOUND THEN RAISE EXCEPTION 'Gym not found' USING ERRCODE='22023'; END IF;
 -- The existing owners change trigger emits the gym live-update signal.
 RETURN lower(p_color);
END $fn$;
ALTER FUNCTION public.iv_set_gym_accent(text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.iv_set_gym_accent(text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.iv_set_gym_accent(text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
