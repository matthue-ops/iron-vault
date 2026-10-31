# Phase 1 implementation status

Latest dependency update: the owner reports T1–T5 complete; T1/T2 summaries are recorded, while the actual T1/T3/T4/T5 files are unavailable here. Do not rerun inspections or infer the 43 constraints, 65 columns or 21 indexes. See [dependency review and next migration gates](trigger-schema-dependency-status.md). PR #2 must remain Draft; state verification is outstanding.

Prepared on security/phase1-auth-authorization for review in PR #2. **Incomplete; not deployed and no database migration applied or assumed applied.** Main baseline de6de04. Follow AGENTS.md. All existing accounts, balances, history and records remain untouched.

## Prepared application changes

Shared Supabase getUser/iv_user_roles authorization replaces embedded credentials and administrator defaults. Master, admin and member workflows verify roles and scope private reads; logout/identity changes clear private state. Public member login avoids downloading rosters. QR admission uses the existing reviewed iv_checkin RPC instead of bulk profile writes; the RPC body and signed-pass enforcement remain pending.

The M4-backed reporting changes now require a fresh backend financial permission before queries, render, print and cached credit display. Reports scope every query, reject arbitrary tenant/cache fallback and include ledger totals independently of absent member profiles. Owner/Super Admin controls list and grant/revoke scoped staff report access through the new audited RPCs. Ordinary staff can retain desk/check-in access without report access. Reports fail closed until the new APIs exist; coordinate 005–007 manual confirmation before application release. Client controls supplement RLS, never replace it.

Affected application files: assets/auth-session.js, assets/super-admin-session.js, assets/staff-report-permissions.js, index.html, gym/index.html, gym/admin.html, gym/memberlogin.html, gym/memberprofile.html and gym/reports.html. Native Node tests cover role/session/controllers, scanner, report permissions/revocation and safe permission controls. Current result: 75 passed, none failed/skipped. All 10 SQL files and contained SQL/PLpgSQL bodies parse with pglast 8.7; this does not execute SQL or establish hosted correctness.

## Prepared database changes

Seven separately reviewable files are documented in supabase/migrations/README.md. 001/002 narrow existing privileges; 003/004 harden only future public-schema defaults for postgres/optional supabase_admin; 005 protects role/history direct writes; 006 adds an isolated explicit staff report permission mechanism; 007 corrects financial/attendance cross-tenant policy errors. 004 depends on managed-creator authority and is optional, not a prerequisite to urgent 005–007. Global PUBLIC EXECUTE defaults still require explicit per-function revokes in every new migration. No existing data deletion, table/column removal, account reset or broad rebuild is included.

## Evidence and outstanding gates

All 2A–4F and M1–M7 exports are reviewed. M1 confirms seven confirmed password accounts; M2 no duplicate email within a tenant; M3 four members, two owners and one global Super Admin, no staff. M4 confirms the severe self-comparison policy defect; M6 event-trigger behavior is preserved; M7 defaults are handled narrowly. See inspection-review-m1-m7-20261101.md for evidence and the post-application identity test matrix.

Still required: T1–T5 types/constraints/indexes/trigger dependencies, targeted default-creator/executor compatibility results, deployed Edge Function bundles/helpers/JWT settings and non-secret Auth/SMTP/recovery/redirect/hooks configuration. Exact retrieval steps are in supabase-prerequisites.md. No older draft is treated as deployed truth; stash 4032323 remains excluded.

Owners/members public ALL policies, legacy credential columns, direct financial summaries/generic audit details, wallet/purchase amount validation and idempotency, full identity provisioning/branch-independent passwords, signed passes, secure import/restore and retained-history deletion are not fixed by this stage. Existing reporting row limits can still truncate large reports and require later pagination. Remaining backend definitions must be inspected before replacement. Existing test data gives no justification for a reset.

No SQL, live Supabase operation, deployment or merge was performed. Hosted integration is pending approval and manual migration confirmation; mock tests are not evidence of deployed RLS enforcement.

Local Chromium checks with mocked Supabase and external requests passed: granted staff can render ledger totals, ungranted staff are denied, and revocation blocks printing. No Supabase endpoint was contacted.
