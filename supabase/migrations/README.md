# Manual Phase 1 migration review

Prepared from supplied 2A–4F and M1–M7 inspections. **Not executed or assumed applied.** Only the owner executes approved files in the intended Supabase SQL Editor. Preserve every existing account, balance and history row. No reset or rebuild is needed or included. This package does not complete Phase 1; see [current findings](../../docs/security/inspection-review-m1-m7-20261101.md).

| Order | File suffix (all prefixed 20261101) | Scope |
| --- | --- | --- |
| 1 | 0001_restrict_table_truncate.sql | Non-destructive, behavior-changing: revoke API TRUNCATE on owners/members. |
| 2 | 0002_restrict_function_execution.sql | Non-destructive, behavior-changing: remove PUBLIC/anon execution on eight reviewed exact functions; retain authenticated ordinary RPCs and service-role rights. Definition fingerprints abort on drift. |
| 3 | 0003_restrict_postgres_public_defaults.sql | Non-destructive future defaults only: remove explicit public-schema API function/table defaults for postgres. Existing objects and managed schemas unchanged. |
| 4, optional | 0004_restrict_supabase_admin_public_defaults.sql | Same narrow defaults for supabase_admin, only if executor authority and platform compatibility are established. Never grant yourself managed-role membership. |
| 5 | 0005_protect_role_and_history_grants.sql | Non-destructive, behavior-changing: remove direct API writes/TRUNCATE and column grants on five role/history tables; retain authenticated SELECT and existing definer RPC writers. |
| 6 | 0006_staff_financial_report_permissions.sql | Additive private schema/table and explicit administrator-controlled permission RPCs. No legacy data changed. Requires 005; reserved namespace and reviewed audit function checked. |
| 7 | 0007_fix_financial_attendance_rls.sql | Non-destructive, behavior-changing: correct two member/tenant correlations; require explicit staff financial permission while retaining staff attendance. Requires 005/006 and exact normalized M4 policy baseline. |

## Dependencies and execution

Before approval, inspect the complete SQL files. Return the SELECT-only `../inspection/phase1_remaining_prerequisites.sql` results for executor/default-creator capability and namespace compatibility. Initial/M/T inspections are completed; exact T1/T3/T4/T5 exports are not accessible here. Use the single current evidence/progress checklist in docs/security/phase1-status.md; do not rerun completed inspections. Deployed Edge/Auth evidence still gates broader work.

003 and 004 are independent of urgent 005–007; optional 004 must not delay the RLS fix. Run each approved file separately, once, in order; do not concatenate all files. If any transaction fails, issue ROLLBACK and return the exact error. Do not bypass definition, owner, privilege or namespace guards. A failed later file does not undo an earlier committed file. New private objects in 006 have explicit RLS and per-object grants; the existing ensure_rls trigger is preserved. No default privileges outside public or existing function bodies are modified.

**Important PostgreSQL limitation:** revoking schema-specific function defaults does not cancel global/built-in PUBLIC EXECUTE. Every future CREATE FUNCTION migration must explicitly REVOKE PUBLIC/anon and grant only intended roles in the same transaction. Do not globally alter postgres/supabase_admin defaults across Supabase-managed schemas as a workaround. Existing ordinary authenticated RPC execution remains intact.

Return each file's final verification result and confirmation of commit. 001 should show no API TRUNCATE; 002 anon=false, authenticated=true for six ordinary functions and false for two trigger-only functions; 003/004 no targeted public-schema API defaults; 005 authenticated SELECT only with no direct API writes; 006 no anon execution and only intended authenticated helpers/APIs; 007 both correlated policies. Catalog verification does not exercise RPC bodies or prove end-to-end isolation.

Do not release the new report/permission UI until 005–007 are manually applied and confirmed, followed by approved integration tests. Missing permission APIs fail closed. Permission grants initially empty; there are currently no staff bindings. Preserve the seven existing accounts. Prepare a user-controlled staff fixture later to test grant/revoke rather than resetting accounts. UI hiding does not replace RLS.

## Verification and recovery

Follow the authorized API identity matrix in the findings document: member/tenant isolation, owner/global administrator, staff denied/granted/revoked, direct write denial, ordinary RPC regression, logout and identity changes. Do not test TRUNCATE by truncating a table. SQL Editor/service credentials bypass important RLS checks and cannot substitute for authenticated client tests.

No data rollback is necessary because existing records are unchanged. If compatibility fails after commit, prepare a narrow reviewed fix forward; never automatically restore public access, the tautological policies, direct role writes or broad defaults. Preserve platform/service privileges while investigating failures.

Local checks: 75 Node tests passed; pglast 8.7 parsed all SQL files and contained SQL/PLpgSQL bodies without executing SQL. Hosted RLS, migration privileges and RPC behavior remain untested. No Supabase SQL, account operation, merge or deployment was performed.

Local Chromium checks with mocked Supabase and external requests passed: granted staff can render ledger totals, ungranted staff are denied, and revocation blocks printing. No Supabase endpoint was contacted.

## T dependency follow-up (prepared, not applied)

T1/T3/T4/T5 exports are received and fully reviewed; T2 succeeded with zero rows. P1 is closed in the single progress document; older references to unavailable T exports are superseded.

8. `202611010008_staff_permission_tenant_fk.sql`: additive validated tenant FK for the new permission table, after confirmed 006; no cascade, legacy row rewrite or data deletion. An orphan aborts the transaction.
9. `202611010009_member_tenant_contact_uniqueness.sql`: behavior-changing, non-destructive unique index on tenant plus normalized contact email; cross-gym reuse remains valid. No Auth accounts are changed. Existing normalized duplicates or conflicting index name abort safely. Uses transactional CREATE INDEX with a write lock: schedule appropriately. Not a replacement for branch-aware Auth identity implementation.

Each file includes its metadata verification; return results and commit confirmation. On error ROLLBACK and return the error without bypassing guards or deleting records. No file was executed. Preserve all existing request, Auth, role and email indexes.
