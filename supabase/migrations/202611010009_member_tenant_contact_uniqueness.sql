-- MANUAL REVIEW ONLY. Additive, behavior-changing uniqueness; no rows modified.
-- T4: members.tenant_id/email are text; T5 idx_members_email is NOT unique.
-- Preserve cross-gym email reuse and all existing Auth identities/financial rows.
-- Requires T3-T5 baseline and reviewed registration paths. This protects concurrent
-- duplicates; it does not implement independent branch Auth credentials.
-- Uses normalized contact email (trim + lowercase). Existing duplicate groups
-- abort safely. Do not delete/merge accounts to force this migration through.
-- Run in a coordinated maintenance window: CREATE INDEX takes a write-blocking lock.
-- Existing unscoped legacy rows are excluded; securing their lifecycle is separate.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$
BEGIN
 IF to_regclass('public.iv_members_tenant_contact_email_unique') IS NOT NULL THEN
  RAISE EXCEPTION 'Index name already exists; inspect prior application, do not replace';
 END IF;
 IF EXISTS(SELECT 1 FROM public.members WHERE tenant_id IS NOT NULL
  GROUP BY tenant_id,lower(btrim(email)) HAVING count(*)>1) THEN
  RAISE EXCEPTION 'Normalized duplicate emails within a gym; review affected records without deleting them';
 END IF;
END
$guard$;
CREATE UNIQUE INDEX iv_members_tenant_contact_email_unique
 ON public.members(tenant_id,lower(btrim(email))) WHERE tenant_id IS NOT NULL;
COMMIT;
SELECT indexname,indexdef FROM pg_indexes
WHERE schemaname='public' AND indexname='iv_members_tenant_contact_email_unique';
-- Expected: UNIQUE on tenant_id, lower(btrim(email)), excluding null tenants.
-- Keep existing idx_members_email and Auth/role/request unique indexes unchanged.
-- Recovery: reviewed fix forward; do not remove uniqueness to bypass registration errors.
