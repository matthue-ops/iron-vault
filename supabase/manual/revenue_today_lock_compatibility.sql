-- MANUAL ONLY after 046. No amounts, grants, permission checks or financial records change.
-- PostgREST opens STABLE RPCs in read-only transactions. The existing staff_require
-- permission check uses SELECT FOR SHARE and must retain that authorization lock.
BEGIN;
DO $guard$ BEGIN
 IF to_regprocedure('public.iv_revenue_today(text)') IS NULL THEN
  RAISE EXCEPTION 'Apply migration 046 before this correction';
 END IF;
END $guard$;
ALTER FUNCTION public.iv_revenue_today(text) VOLATILE;
NOTIFY pgrst,'reload schema';
COMMIT;
