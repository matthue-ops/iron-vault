# Phase 1 — single progress document

Branch: security/phase1-auth-authorization. PR #2 stays for review; no merge/deployment/SQL execution was performed. Existing records and accounts have not been changed. **The implementation package is now connected across app, SQL and Edge source; database/provider acceptance remains pending.** Use [phase1-cutover.md](phase1-cutover.md) as the single finite execution/validation sequence after review.

## Closed evidence — do not request again

- Initial 2A–4F: all eleven exports reviewed, including all eight function definitions and known broad policies/grants.
- M1–M7: complete. Seven confirmed password accounts; four members, two scoped owners, one global Super Admin, no staff. No duplicate member contact within tenant. Financial/attendance tautology policies and public-schema creator defaults accounted for.
- T1–T5: complete; T1 one enabled Auth signup trigger, T2 successful zero rows/no CSV, T3 all 43 constraints, T4 all 65 columns, T5 all 21 indexes reviewed. Text dates, nullable numeric/request fields, NO ACTION history references, tenant cascade and unique role/Auth/request indexes are preserved/accounted for.
- Both existing Edge sources received/reviewed. Original signup metadata flag does not run for their current requests; new lifecycle preserves the trigger but rejects the obsolete flagged public path. iv-admin-correct-member-email was absent and now has implementation source; no nonexistent deployed source is requested.
- Screenshots: signup/email provider enabled, confirmation/manual-linking/anonymous-signin disabled; secure email change enabled; secure password/current-password requirement disabled; minimum password 6; Brevo SMTP configuration present, delivery unverified; no Auth Hooks; Site URL ironvaultph.vercel.app and memberlogin redirect. Both original functions show legacy JWT verification enabled. No secret values were retained.

No further broad inspection bundle is requested. Missing deployment-version metadata is not a coding blocker. Original SMTP credentials must be entered privately as deployment bindings, not sent in chat. Optional managed-creator authority can be checked by existing transaction guards/results; inability to run 004 does not block ordinary per-object security.

## Progress

COMPLETED means implemented/prepared in this branch, not applied on Supabase.

| Work | State | Evidence |
| --- | --- | --- |
| Four-role verified Auth/session foundation and cleanup | COMPLETED | auth-session/super-admin-session helpers, six HTML entry points. No embedded-password/admin-default authority. |
| Direct owner/member write closure and safe reads | COMPLETED | 012 replaces public ALL policies, revokes table/column access, safe branding/member projections with enabled-role checks. Anonymous branding uses one deliberate projection function, no anonymous role-helper grant. |
| Profile/branding/approval/staff paths | COMPLETED | Scoped patch RPCs, shared data/workflow adapters, no financial/credential/role updates in profile saves; staff creation/name/recovery/revocation use trusted paths. |
| Financial authority/idempotency | COMPLETED code | 010/011 plus 013: server price/term/discount, current permission/status, locks, bound original-outcome receipts, cash-only/mixed handling, exact retry and changed-payload rejection. Browser sale/top-up/member wallet paths connected. |
| Staff report permission and M4 policies | COMPLETED code | 005–007 and 015: explicit audited grant/revoke, correlated member+tenant reads, enabled staff checks, gated audit; report snapshot avoids row truncation. |
| Independent gym accounts and email lifecycle | COMPLETED code | 014 and four Edge Functions plus shared helpers: separate Auth identities, service-only contact mappings/jobs, real-address verification, branch-aware login/recovery and dual-address changes. Existing IDs/passwords retained; private Auth identifier rotation uses supported administration and retry metadata. |
| Attendance and QR | COMPLETED code | 013: actual text-date validation, active entitlement, Manila day, member lock, duplicate check, server-issued opaque daily tickets. Manual/camera/upload paths connected. No offline signature claim. |
| Retained history and liabilities | COMPLETED code | Deactivation/suspension and enabled-role revocation; no row deletion or cascade purge; nonzero wallet blocks removal. Existing history foreign keys remain intact. |
| Data backup/profile restore | COMPLETED code | Authorized exports use credential-free projections; 015 atomic existing-profile/branding restore, explicit UI notice that financial/account/role state is preserved. Unknown identities/tenant moves reject. |
| Local automated regression | COMPLETED, latest counts below | Native tests use real controller/helper source with mocked clients; Edge bodies execute against mocked services. |
| All migration files/order/recovery and deployment configuration | COMPLETED | 001–015, 004 optional; generated single-transaction manual SQL alternative; config.toml; cutover runbook; metadata acceptance file and opt-in staging HTTP harness. |
| Real PostgreSQL migration/RLS/financial concurrency checks | BLOCKED execution boundary | SQL must be run manually only after owner review/approval; no SQL executed even locally. Syntax parsing does not prove execution. |
| Deno dependency/runtime and actual email delivery | BLOCKED deployment/validation boundary | Local Node parses TypeScript and runs mocked bodies; Deno import/TLS/provider/SMTP behavior not exercised. Owner supplies bindings privately and approves staging/deployment. |
| Live app regression and acceptance | BLOCKED until matching SQL/backend/app cutover | Four-role allow/deny, independent passwords/recovery, real transactions/concurrency, pass reuse, report totals and backup checks must pass. |
| PR #2 Draft verification | BLOCKED tool capability | Git push does not change Draft status. No mark-ready/merge action was taken; available tools cannot verify/convert the PR. |

NOT STARTED optional follow-ups: permanent erasure/retention cleanup, shorter display IDs, a framework redesign, advanced reporting UI and additional external monitoring. None requires resetting test data or delays the current cutover code. Normal security validation above is mandatory, not optional.

## Exact remaining prerequisites

1. Review the complete package and approve a deliberate test/cutover target. No repeat SQL inspections are needed to continue implementation.
2. Configure the app's Edge mail bindings privately using existing Brevo SMTP credentials or an app-specific HTTP key. APP_URL/CORS origins must match the reviewed site/staging origin. Verify delivery; never send credentials here.
3. Owner manually applies the approved 001–015 sequence, skipping optional 004 only when platform authority is unavailable, returns per-file confirmation/errors and preservation checks. Existing creator-membership SELECTs remain available if needed for that optional decision; no managed-role escalation.
4. Only with separate authorization deploy the matching four functions/config and app, then execute the finite acceptance matrix. Integration/financial tests need approved dedicated fixtures/target; do not mutate existing records implicitly.

## Compatibility and material limitations

- Legacy users retain Auth IDs/passwords and real contact addresses in branch mappings. Once their private Auth email identifier rotates, older external clients using native real-email login/reset are incompatible; use the new branch gateway. Do not roll back only the HTML after rotation.
- New accounts verify email before role activation; self-registered members need approval. Old metadata signup, browser JSON administrator flags, direct financial profile writes, manual expiry edits, plaintext password viewing and unsigned QR entry are intentionally replaced for security.
- Profile restore updates existing identities/branding only, never financial disaster recovery. Deactivation retains personal/account/history rows; permanent erasure is separate.
- Public-schema default revokes do not cancel global PUBLIC EXECUTE; each new function sets object ACLs. The deliberately anonymous safe branding RPC is an explicit exception; all account service RPCs deny anon/authenticated.
- API cash amounts are authorized desk declarations, not external payment proof. Request IDs cannot deduplicate two independently entered physical payments with different IDs across tabs; reconciliation/desk controls still matter.
- SMTP/Deno/provider behavior and SQL semantic execution are not proven by mocks/parsing. All accounts/financial records remain unchanged because nothing was applied or deployed.

## Latest validation record

- 118 native Node tests passed, 0 failed/skipped. These include controller, client retry/profile, Edge authentication/CORS/rate/provisioning/email-proof mocks and SQL contract checks.
- All 21 SQL files and contained SQL/PLpgSQL bodies parsed with pglast 8.7 without execution; final parsing is repeated before commit.
- Deno 2.5.6 successfully checked all four Edge entry points against pinned Supabase 2.49.8 npm package types through a temporary import map, including SMTP dependencies. No function was run/deployed and no Supabase connection was made. The production esm.sh transport and actual SMTP network behavior still need validation.
- Local Chromium with mocked Supabase/external requests passed branch login to the member profile, Super Admin directory/inspection with recovery controls, retained ledger snapshot display, ungranted staff denial and revoked print access. These are browser/controller checks, not hosted acceptance.
- Inline/local JS and Edge TypeScript syntax checks passed. The opt-in staging HTTP mutation harness was not run. No staging/live SQL or integration harness has been run. See the cutover runbook for acceptance, not another evidence-gathering cycle.

## Dashboard installation continuation

The owner supplied a SQL Editor screenshot showing the final role verification result and reported adding Edge secrets. This is owner-reported installation evidence, not agent SQL execution or proof of end-to-end acceptance; do not blindly rerun the SQL. The current Code screenshot shows the original iv-create-member index.ts. Four generated standalone Dashboard files now avoid manual shared-helper setup and preserve the modular implementation exactly. 119 local tests pass; all four standalone entries passed Deno type checking. No function was deployed by the agent. Mail delivery and actual backend/app acceptance remain unverified.
