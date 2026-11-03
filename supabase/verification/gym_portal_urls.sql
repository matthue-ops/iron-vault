-- USER-RUN, READ-ONLY. After migration 026. No writes or function invocations.
-- The first result lists assigned URL names. All following checks should return 0 rows.
SELECT g.id,g.gym_name,l.slug FROM public.owners g
 LEFT JOIN public.iv_gym_portal_links l ON l.tenant_id=g.id ORDER BY g.id;
SELECT g.id FROM public.owners g LEFT JOIN public.iv_gym_portal_links l ON l.tenant_id=g.id WHERE l.tenant_id IS NULL;
SELECT slug,count(*) FROM public.iv_gym_portal_links GROUP BY slug HAVING count(*)>1;
SELECT tenant_id,count(*) FROM public.iv_gym_portal_links GROUP BY tenant_id HAVING count(*)>1;
SELECT tenant_id,slug FROM public.iv_gym_portal_links
 WHERE slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' OR length(slug)>96
 OR slug IN ('gym','assets','api','docs','supabase','tests','index','favicon','robots','sitemap','login','logout','admin','memberlogin','memberprofile','reports','health');
