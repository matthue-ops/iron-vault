-- Optional read-only checks AFTER the user manually applies all of 047.
SELECT id,public,file_size_limit,allowed_mime_types FROM storage.buckets
 WHERE id IN ('iv-gym-images','iv-member-images') ORDER BY id;
SELECT to_regclass('ironvault_private.profile_images') AS reference_registry,
 to_regprocedure('public.iv_profile_images(text,jsonb)') AS image_api,
 to_regprocedure('public.iv_restore_profiles(jsonb,jsonb)') AS restore_wrapper,
 to_regprocedure('ironvault_private.restore_profiles_047_base(jsonb,jsonb)') AS original_restore_engine;
SELECT tablename,policyname,permissive,cmd,roles FROM pg_policies
 WHERE schemaname='storage' AND policyname LIKE 'iv_image_%' ORDER BY policyname;
SELECT t.tgname,t.tgenabled,c.relname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 WHERE t.tgname IN ('iv_member_image_guard','iv_gym_image_guard');
SELECT has_function_privilege('anon','public.iv_profile_images(text,jsonb)','EXECUTE') AS anonymous_image_api_should_be_false,
 has_table_privilege('authenticated','ironvault_private.profile_images','SELECT') AS direct_registry_read_should_be_false,
 has_function_privilege('authenticated','public.iv_profile_images(text,jsonb)','EXECUTE') AS authenticated_image_api_should_be_true;
-- No member names, private images, tokens, balances or credentials are selected.
