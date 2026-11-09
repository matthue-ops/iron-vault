-- MANUAL ONLY after 047 (keep 048 installed when using its subscription frontend).
-- Narrow exceptions to the presentation batch: owner preset saving; provider membership pricing read-only.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_profile_images(text,jsonb)') IS NULL OR to_regprocedure('public.iv_staff_pricing(text,jsonb)') IS NULL OR to_regprocedure('public.iv_set_gym_accent(text,text)') IS NULL THEN RAISE EXCEPTION 'Apply 047 and prerequisites first';END IF;
 IF to_regprocedure('public.iv_set_gym_preset(text,text)') IS NOT NULL THEN RAISE EXCEPTION '049 already installed; do not reapply';END IF;
END $guard$;
CREATE FUNCTION public.iv_set_gym_preset(p_tenant text,p_preset text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE chosen text;BEGIN
 chosen:=CASE p_preset WHEN 'emerald' THEN '#10b981' WHEN 'blue' THEN '#60a5fa' WHEN 'violet' THEN '#a78bfa' WHEN 'teal' THEN '#2dd4bf' WHEN 'amber' THEN '#fbbf24' END;
 IF chosen IS NULL THEN RAISE EXCEPTION 'Choose one of the five gym presets' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.iv_user_roles r WHERE r.user_id=auth.uid() AND r.enabled AND r.disabled_at IS NULL AND
 ((r.role='super_admin' AND r.tenant_id IS NULL) OR (r.role='owner' AND r.tenant_id=p_tenant AND EXISTS(SELECT 1 FROM ironvault_private.gym_subscriptions s WHERE s.tenant_id=p_tenant AND s.owner_id=r.user_id))) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registered gym owner or Provider required' USING ERRCODE='42501';END IF;
 UPDATE public.owners SET accent_color=chosen WHERE id=p_tenant AND (status='ACTIVE' OR ironvault_private.subscription_super());
 IF NOT FOUND THEN RAISE EXCEPTION 'Gym unavailable';END IF;
 RETURN chosen;
END $fn$;
ALTER FUNCTION public.iv_save_gym_settings(jsonb) RENAME TO save_gym_settings_049_base;
ALTER FUNCTION public.save_gym_settings_049_base(jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_save_gym_settings(p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb;gym public.owners%ROWTYPE;clean jsonb:='[]';provider boolean:=ironvault_private.subscription_super();BEGIN
 IF p_records IS NULL OR jsonb_typeof(p_records)<>'array' OR jsonb_array_length(p_records)>100 THEN RAISE EXCEPTION 'Invalid gym batch';END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_records) LOOP
  IF provider THEN
   SELECT * INTO STRICT gym FROM public.owners WHERE id=item->>'id' FOR UPDATE;
   IF item ? 'pricing' AND item->'pricing' IS DISTINCT FROM gym.pricing THEN RAISE EXCEPTION 'Gym membership pricing is view-only for Provider; the gym owner manages its rates' USING ERRCODE='42501';END IF;
   item:=item-'pricing';
  END IF;
  clean:=clean||jsonb_build_array(item);
 END LOOP;
 PERFORM ironvault_private.save_gym_settings_049_base(clean);
END $fn$;
ALTER FUNCTION public.iv_staff_pricing(text,jsonb) RENAME TO staff_pricing_049_base;
ALTER FUNCTION public.staff_pricing_049_base(text,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_staff_pricing(p_tenant text,p_pricing jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF ironvault_private.subscription_super() THEN RAISE EXCEPTION 'Provider membership pricing is view-only' USING ERRCODE='42501';END IF;
 PERFORM ironvault_private.staff_pricing_049_base(p_tenant,p_pricing);
END $fn$;
ALTER FUNCTION public.iv_restore_profiles(jsonb,jsonb) RENAME TO restore_profiles_049_base;
ALTER FUNCTION public.restore_profiles_049_base(jsonb,jsonb) SET SCHEMA ironvault_private;
CREATE FUNCTION public.iv_restore_profiles(p_gyms jsonb,p_members jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE cleaned jsonb;BEGIN
 IF ironvault_private.subscription_super() THEN
  IF p_gyms IS NULL OR jsonb_typeof(p_gyms)<>'array' THEN RAISE EXCEPTION 'Invalid gym restore';END IF;
  SELECT coalesce(jsonb_agg(value-'pricing'),'[]') INTO cleaned FROM jsonb_array_elements(p_gyms);
 ELSE cleaned:=p_gyms;END IF;
 -- Keep 047 image restore guards and all member/profile identity/financial protections.
 PERFORM ironvault_private.restore_profiles_049_base(cleaned,p_members);
END $fn$;
DO $acl$ DECLARE sig text;BEGIN
 FOREACH sig IN ARRAY ARRAY['public.iv_set_gym_preset(text,text)','public.iv_save_gym_settings(jsonb)','public.iv_staff_pricing(text,jsonb)','public.iv_restore_profiles(jsonb,jsonb)','ironvault_private.save_gym_settings_049_base(jsonb)','ironvault_private.staff_pricing_049_base(text,jsonb)','ironvault_private.restore_profiles_049_base(jsonb,jsonb)'] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',sig);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',sig);
 END LOOP;
END $acl$;
GRANT EXECUTE ON FUNCTION public.iv_set_gym_preset(text,text),public.iv_save_gym_settings(jsonb),public.iv_staff_pricing(text,jsonb),public.iv_restore_profiles(jsonb,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
