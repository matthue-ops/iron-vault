# Migration, reset and release gates

Status: blocked on the existing CSVs, deployed backend source and Auth configuration. **There are no executable database-change migrations in this branch.** Creating speculative replacements from the earlier drafts would violate the instruction to stop affected work rather than guess.

## Proposed files in manual execution order

Exact SQL, prerequisites, verification and recovery sections will be written after evidence review. These names are a manifest, not scripts that have been created or applied.

| Order | Proposed separate file | Classification and gate |
| --- | --- | --- |
| 0 | OPTIONAL_DESTRUCTIVE_test_data_reset.sql | Optional, destructive, never a prerequisite by default; exact selected fixtures and dependencies must be approved. |
| 1 | phase1_01_identity_tenant_and_transaction_foundations.sql | Normally additive; mappings, validated constraints/indexes, exact-money and idempotency foundations as needed. Existing columns/types may require an explicitly described migration. |
| 2 | phase1_02_authorization_helpers.sql | Behavior-changing; authoritative tenant/role/explicit report-permission checks, safe owners/search_path, prevention of self-grant and policy recursion. |
| 3 | phase1_03_financial_attendance_and_account_operations.sql | Behavior-changing; reviewed existing RPC overloads, atomic ledger/wallet/entitlements, attendance and privacy-preserving membership deletion. |
| 4 | phase1_04_rls_and_table_grants.sql | Behavior-changing; replace exact broad policies, protect private rows and financial columns, expose only public branding. Requires compatible application/backend operations. |
| 5 | phase1_05_rpc_execution_grants.sql | Behavior-changing; review effective PUBLIC/anon/authenticated privileges, revoke unnecessary execution and retain deliberately callable helpers/RPCs. |
| 6 | phase1_06_role_bootstrap_and_test_fixtures.sql | Explicitly scoped data creation after intended Auth identities exist; never hardcoded account credentials or direct reconstruction of managed auth tables. |
| 7 | phase1_07_read_only_verification.sql | SELECT-only verification of configured invariants, counts and reconciliation. |
| Later, optional | OPTIONAL_DESTRUCTIVE_retire_legacy_fields.sql | Destructive; only after application references and consumers are removed, with a separately reviewed target list. |

Foundations and secure operations can be prepared in an isolated development project, followed by a coordinated app/backend/RLS cutover. Do not leave permissive public ALL policies as a compatibility fallback. Do not apply a restrictive grant change before the replacement legitimate workflow is verified. Rollback must not silently reopen unrestricted access.

Each actual migration must document purpose, exact prerequisites/order, additive/behavior-changing/destructive status, existing-data effects, manual verification queries and safe recovery limitations. Successful manual execution must be confirmed by the owner before dependent app changes are activated. Agent tests are never evidence that a migration reached Supabase.

## Optional selective test-data reset procedure

Not executable in this stage; no deletion or reset is authorized here. Disposable-data status permits proposing a selective reset, not running it.

1. Review the supplied schema/trigger/Edge Function evidence and identify which fixtures actually block a sound schema. Prefer replacing authorization boundaries over a full project rebuild.
2. Publish an exact target manifest: project, tenant/member/Auth identity IDs or tightly bounded fixture criteria, affected tables/dependencies, expected counts and financial effects. Do not use broad unqualified TRUNCATE/CASCADE against an unknown schema.
3. Keep normal application deletion separate: it preserves historical financial records. A test reset may erase those test histories only if the selected destructive scope is explicitly approved.
4. The owner chooses whether to retain a fixture export/backup for reproducibility and explicitly approves the destructive target list before execution.
5. Provide separate, versioned reset SQL and any supported Auth-admin steps. The owner executes the approved operations. Never recreate auth.users/auth.identities directly through SQL or delete a whole Supabase project without documented justification.
6. Confirm resulting counts/reconciliation, recreate test accounts through supported Auth administration, then assign roles using the reviewed bootstrap procedure.

## Deployment/verification checklist (not authorization to deploy)

- [ ] Receive/review existing 2A–4F exports; reconcile exact policy names, RPC overloads and grants.
- [ ] Review trigger/schema dependencies and the deployed three Edge Functions.
- [ ] Verify Auth callbacks/email delivery and finalize implementation of private branch identities.
- [ ] Review staff report permission administration, revocation and all protected query paths.
- [ ] Implement ledger-safe normal member deletion and an explicit wallet-settlement rule.
- [ ] Produce actual SQL files and per-file verification/recovery instructions.
- [ ] Run local automated and approved integration tests; distinguish mocks from database evidence.
- [ ] Owner executes approved SQL manually and returns confirmation/errors; no assumed deployment.
- [ ] Verify real signup, confirmation, recovery, administrator/staff/member workflows, reports and authorized backups/restores.
- [ ] Validate deny paths through direct API calls, not just hidden controls.
- [ ] Reconcile wallet totals and historical ledger totals before/after deletion and retries.
- [ ] Review the PR, then explicitly authorize merge/deployment separately.

## Security and regression test matrix

Automated tests currently use Node's built-in runner, mocked SDKs and the actual HTML controller scripts. Run `npm test` with Node 24+. No dependency installation, database access, SQL execution or Supabase credentials are required. These tests do not establish RLS or RPC safety.

| Area | Integration cases still required after backend implementation |
| --- | --- |
| Four roles | Valid access for each intended portal; invalid/missing/expired sessions denied; browser role spoofing never changes database authority. |
| Staff report permission | Ordinary staff can transact without reading financial reports; administrator grant enables only that gym; self-grant/cross-tenant grant denied; revocation blocks the next report/API request. |
| Tenant isolation | Altered URL, tenant ID, member ID, request body, role hint and RPC argument denied; global Super Admin behavior tested separately. |
| Branch identities | Same email/different passwords at gyms A/B; same password also allowed; duplicate A registration denied; A recovery/email change/deletion does not affect B. |
| Money | Manipulated amounts/prices/discounts/tenant, non-positive/overflow/fractional amounts, insufficient funds, exact retries and changed-payload retries. |
| Concurrency | Simultaneous wallet purchases/top-ups, simultaneous same-key requests, rollback on ledger/entitlement failure, no negative balance or duplicate financial entry. |
| Attendance | Pending/inactive/no-plan/expired members denied; wrong tenant and forged/replayed passes denied; simultaneous scans; manual/camera/upload parity; Manila midnight boundaries. |
| Deletion | Access revoked; unnecessary profile data anonymized; historical amounts/dates/types/tenant retained; reports include deleted memberships; wallet liabilities resolved explicitly; financial history cannot be edited by ordinary clients. |
| Sessions | Refresh, browser Back, sign-out failure, same-user refresh events, cross-tab user changes and role revocation; no private-cache fallback. |
| Features | Branding/pricing, staff CRUD, approval, profile/avatar, sales, reports, authorized import/export/restore and tenant lifecycle; no credentials in exports. |

Do not execute integration cases against the owner's Supabase project until the affected implementation, fixtures and test actions are explicitly authorized. Concurrent/financial/deletion tests can mutate data and require a deliberate test target.
