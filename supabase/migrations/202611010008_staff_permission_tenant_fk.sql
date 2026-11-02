-- MANUAL REVIEW ONLY; requires confirmed 006. Additive integrity constraint.
-- T3/T4: public.owners(id) is PRIMARY KEY text. No existing row is rewritten.
-- Default NO ACTION prevents tenant deletion erasing permission/audit context.
-- Failure (including orphan permissions) aborts; return error, do not delete data.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$
BEGIN
 IF to_regclass('ironvault_private.staff_report_permissions') IS NULL THEN
  RAISE EXCEPTION 'Apply and confirm migration 006 first';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='ironvault_private.staff_report_permissions'::regclass
  AND conname='staff_report_permissions_tenant_fkey') THEN
  RAISE EXCEPTION 'Constraint already exists; verify prior application instead of overwriting';
 END IF;
END
$guard$;
ALTER TABLE ironvault_private.staff_report_permissions
 ADD CONSTRAINT staff_report_permissions_tenant_fkey
 FOREIGN KEY(tenant_id) REFERENCES public.owners(id) ON DELETE NO ACTION;
COMMIT;
SELECT conname,convalidated,pg_get_constraintdef(oid) AS definition FROM pg_constraint
WHERE conrelid='ironvault_private.staff_report_permissions'::regclass
 AND conname='staff_report_permissions_tenant_fkey';
-- Expected: validated=true, tenant_id references owners(id), no cascade.
-- Recovery: fix forward after review; no automatic constraint removal.
