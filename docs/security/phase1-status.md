# Phase 1 implementation status

This is a **draft prerequisite/session foundation**, not the completed Phase 1 security release. Do not deploy it as a remediation for the reported public ALL policies or RPC grants. Main baseline: de6de04. Earlier unverified application/SQL/Edge Function drafts are preserved in stash `4032323` and excluded from this branch.

## Implemented without assuming new database objects

- Shared browser role resolution calls Supabase getUser and reads the existing iv_user_roles fields already used by main. It does not accept browser roles, another user's rows, unscoped branch roles or ambiguous tenant/member bindings. Global Super Admin access is explicit.
- Both master entry points use one Auth-backed session controller. The root embedded-credential bypass is removed; private master data loads after role verification and is checked again before rendering. Logout, denied access and Auth-identity changes clear private UI/cache state.
- Admin initialization no longer defaults an absent role to admin. It verifies a role before tenant discovery, derives UI role from the verified binding, and scopes tenant/roster queries. Private roster/tenant caches are not a fallback for denial or empty results in these paths.
- Public member login only queries selected branding fields and no longer downloads/caches a member roster or retains superseded browser-password authentication handlers.
- Member profile data reads bind member ID and tenant to the verified role; branding queries are scoped and limited to branding fields. Member logout calls Supabase signOut and clears private state.
- Existing helper wrappers on member login, admin, profile and reports now use shared role resolution. This is a UI/session gate, not the still-pending database authorization implementation.
- Camera/upload QR admissions now call the reviewed existing iv_checkin RPC instead of bulk-upserting profiles; Manila date validation replaces the UTC comparison. This does not implement signed passes or strengthen the RPC body.
- Added a dependency-free Node security/regression suite. `npm test` completed successfully: 53 passed, 0 failed, 0 skipped. These are mocked SDK/controller, syntax and SQL text/contract checks, not database integration tests. SQL/PLpgSQL syntax parsing also passed with pglast 8.7 without SQL execution. No hosted-database tests have been run.

## Changed files and purpose

| Files | Purpose |
| --- | --- |
| assets/auth-session.js | Shared verified-identity/role resolution and scoped application-state cleanup/sign-out. |
| assets/super-admin-session.js | Shared guarded session/controller behavior for both master entry points. |
| index.html, gym/index.html | Install the shared master controller and remove embedded-credential/browser-only login handlers. |
| gym/admin.html | Fail-closed initialization, verified UI role, scoped private reads and no denied-query cache fallback. |
| gym/memberlogin.html | Shared roles, selected public branding and removal of obsolete roster/password handlers. |
| gym/memberprofile.html | Shared roles, member/tenant-bound reads, scoped branding and actual Supabase logout. |
| gym/reports.html | Shared role helper only; report permissions/query restructuring are blocked pending database evidence. |
| tests/*.test.cjs, package.json | Native Node role, session, actual-controller and syntax regressions. |
| .gitignore | Keep local dependencies and .env secrets out of commits. |
| docs/security/*.md | Target architecture, prerequisites, migration/reset manifest and test/release gates. |
| supabase/inspection/*.sql | SELECT-only missing-summary, authority/history-table and trigger/schema dependency inspection for manual execution. |
| supabase/migrations/*.sql and README.md | Two reviewed, grant-only non-destructive migrations with drift/privilege guards, manual order and recovery notes; neither applied. |
| tests/fixtures/inspection-function-contract.json | Non-secret exact function signatures and definition fingerprints from the supplied CSV; no raw exports or account details. |

## Blocked work and known risks

All 11 supplied 2A–4F CSVs were reviewed. Exact policies, grants and eight function definitions are now known at that snapshot; see inspection-review-20261101.md. The first summary result in each of 4A/4E is missing. Role/history-table authorization, types/constraints/indexes/trigger attachments, deployed Edge Functions and Auth settings remain missing. The two narrow ACL files are evidence-backed; broader replacements remain blocked. No old draft is treated as deployed evidence.

Unrestricted direct API access, definer safety, database-side report permission/revocation, independent branch identity provisioning, wallet/ledger atomicity/idempotency, signed passes, retained-history member deletion, protected import/restore and existing legacy plaintext credential storage are **not fixed by this stage**. Reports still retain their legacy load/render order and role-only staff check; they must not be treated as implementing the newly required explicit staff report permission. Financial mutation paths and backend deletion semantics have not been rewritten. Existing live SQL/RLS remains unchanged; the prepared files have not been applied.

Sessions retain the current Supabase storage configuration until Auth callback requirements are supplied. Browser Back/profile restoration re-enters the verified initialization gates and cached views are hidden until authorization completes. Hosted callback/session behavior and every mutation path still require final backend enforcement and integration tests. Multiple memberships without an explicit tenant selection fail closed rather than selecting an arbitrary role. A Super Admin row with a non-null tenant is treated as invalid global authority until the actual assignments are reviewed; current account compatibility must be checked before activation. Existing tenant link resolution and branding must be tested against the eventual public-branding interface/RLS before release.

Two non-destructive grant-only migrations are prepared for manual review, in supabase/migrations/README.md order. No speculative policy/financial/identity replacement or destructive reset SQL was generated. See migrations-and-verification.md for ordered proposed deliverables and the separate optional reset procedure. No SQL, Supabase account operation, deployment or merge was executed.

## Next input

Supply only the specifically missing summary/dependency results, redacted deployed Edge Function source and the checklist values in supabase-prerequisites.md. Do not rerun the complete supplied 2A–4F exports. The branch-independent account and normal-deletion/reporting decisions are already recorded and will not be asked again. Continue affected implementation after those exact dependencies are established.
