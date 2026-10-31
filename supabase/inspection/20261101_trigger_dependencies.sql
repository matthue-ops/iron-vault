-- SELECT-only inspection, for the owner to execute manually if these results
-- are not already among the existing exports. NOT a migration. Do not execute
-- application RPCs. Redact any embedded credentials from definitions before sharing.

-- T1: Triggers on the known application tables and auth.users.
WITH targets(schema_name, table_name) AS (
  VALUES ('auth','users'), ('public','owners'), ('public','members'),
    ('public','iv_user_roles'), ('public','iv_financial_transactions'),
    ('public','iv_attendance_logs'), ('public','iv_activity_logs'),
    ('public','iv_staff_sessions')
)
SELECT n.nspname AS table_schema, c.relname AS table_name,
  t.tgname AS trigger_name, t.tgenabled AS enabled_state,
  pg_get_triggerdef(t.oid, true) AS trigger_definition,
  pn.nspname AS function_schema, p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS function_arguments
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN targets target ON target.schema_name=n.nspname AND target.table_name=c.relname
JOIN pg_proc p ON p.oid=t.tgfoid
JOIN pg_namespace pn ON pn.oid=p.pronamespace
WHERE NOT t.tgisinternal
ORDER BY table_schema, table_name, trigger_name;

-- T2: Definitions of those trigger functions, not just SECURITY DEFINER routines.
WITH targets(schema_name, table_name) AS (
  VALUES ('auth','users'), ('public','owners'), ('public','members'),
    ('public','iv_user_roles'), ('public','iv_financial_transactions'),
    ('public','iv_attendance_logs'), ('public','iv_activity_logs'),
    ('public','iv_staff_sessions')
), functions AS (
  SELECT DISTINCT t.tgfoid AS oid
  FROM pg_trigger t
  JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN targets target ON target.schema_name=n.nspname AND target.table_name=c.relname
  WHERE NOT t.tgisinternal
)
SELECT pn.nspname AS function_schema, p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_functiondef(p.oid) AS definition
FROM functions f JOIN pg_proc p ON p.oid=f.oid
JOIN pg_namespace pn ON pn.oid=p.pronamespace
ORDER BY function_schema, function_name, arguments;

-- T3: Constraints on the known tables plus incoming foreign-key dependencies.
WITH targets AS (
  SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE (n.nspname='auth' AND c.relname='users') OR
    (n.nspname='public' AND c.relname IN ('owners','members','iv_user_roles',
      'iv_financial_transactions','iv_attendance_logs','iv_activity_logs','iv_staff_sessions'))
)
SELECT c.conrelid::regclass AS table_name, c.conname AS constraint_name,
  c.contype AS constraint_type, pg_get_constraintdef(c.oid,true) AS definition
FROM pg_constraint c
WHERE c.conrelid IN (SELECT oid FROM targets)
   OR c.confrelid IN (SELECT oid FROM targets)
ORDER BY table_name::text, constraint_name;

-- T4: Only if table-column/default exports were not already collected.
SELECT table_name,ordinal_position,column_name,data_type,udt_name,
  is_nullable,column_default,is_identity,is_generated
FROM information_schema.columns
WHERE table_schema='public' AND table_name IN ('owners','members','iv_user_roles',
  'iv_financial_transactions','iv_attendance_logs','iv_activity_logs','iv_staff_sessions')
ORDER BY table_name,ordinal_position;
