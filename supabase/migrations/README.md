# Manual privilege-hardening package

Prepared from the supplied 2A–4F inspection, reviewed 2026-11-01. **Not executed or assumed applied.** This is a narrow grant-only package, not complete Phase 1 and not a replacement for the remaining RLS/financial work. The CSV export timestamp was not supplied; migration 002 checks exact function-definition drift before changing privileges.

Only the owner runs approved SQL in the intended Supabase SQL Editor. Do not use these files to reset test data, rebuild a project, change accounts or deploy the application.

| Order | File | Classification | Purpose/data effects |
| --- | --- | --- | --- |
| 1 | 202611010001_restrict_table_truncate.sql | Behavior-changing privileges; non-destructive | Revoke unused TRUNCATE from PUBLIC/anon/authenticated on owners/members. Does not truncate or otherwise change rows, balances, history, CRUD policies or application schema. |
| 2 | 202611010002_restrict_function_execution.sql | Behavior-changing privileges; non-destructive | Revoke PUBLIC/anon EXECUTE on the eight reviewed exact signatures; also remove authenticated EXECUTE on the two trigger-only functions. Preserve authenticated ordinary RPC/helper calls and existing service-role execution. No function body, trigger attachment, row, Auth identity or schema structure is replaced. |

## Prerequisites and manual verification

1. Review inspection-review-20261101.md, the exact target project and the supplied definitions/ACL baseline. The branch still has security gaps and must not be deployed as a complete remediation. These grants do not fix unrestricted SELECT/INSERT/UPDATE/DELETE or the purchase/idempotency defects.
2. Review 001. If approved, execute it manually as the authorized database owner. Its transaction verifies no inherited API-role TRUNCATE remains. The final SELECT must show false for all four rows. Do not attempt a real TRUNCATE to test it.
3. Review 002. If approved, execute it after 001. Its preflight checks all eight pg_get_functiondef fingerprints and postgres ownership. Any mismatch or missing signature aborts. Do not edit the hash to force success; return the specific changed definition for review. MD5 is only a text-drift check, not a credential or authorization mechanism.
4. The 002 transaction verifies anon execution is false, authenticated execution is true for the six ordinary functions and false for the two trigger/event-trigger functions, and service_role execution stays true. It does not invoke the functions or exercise their bodies. Existing trigger invocation is distinct from normal EXECUTE grants; no triggers are detached.
5. If either transaction errors, issue ROLLBACK before another command and return the exact error. A failed transaction changes nothing. An earlier separately committed file is not undone by failure of the later file.
6. Return verification grids and confirmation of which file committed. Successful local tests/parsing are not confirmation of database application. Existing authenticated registration, top-up, purchase and admission flows still need approved integration tests; do not run financial/account-changing tests implicitly.

## Recovery considerations

No data rollback is needed because neither file changes records. After a successful commit, a proven compatibility problem requires a narrowly reviewed privilege correction. Do not automatically restore PUBLIC/anon execution or API-role TRUNCATE. The original CSVs are the ACL baseline; a wholesale reverse grant would recreate the unsafe configuration. Keep table policies/functions unchanged while investigating unexpected inherited grants or definition drift rather than weakening the assertions.

## Validation already performed

- `npm test`: 53 passed, 0 failed, 0 skipped, including text/contract checks for exact signatures, drift checks, retained grants, non-destructive scope and scanner/session regressions.
- PostgreSQL SQL and PL/pgSQL syntax parsing with pglast 8.7; parsing only, no SQL execution or database connection. Parsing cannot resolve live table dependencies or prove effective permissions/transaction behavior.
- No database-changing test suite or remote API operation against Supabase has been run.

Further schema, RLS, permission, financial and identity migrations will be separate files after the exact missing dependencies are supplied. Optional destructive resets remain a separate procedure and are not required by the current account-link counts.
