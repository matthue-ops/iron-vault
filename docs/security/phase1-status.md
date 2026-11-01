# Phase 1 — single progress and completion checklist

This is the **only current prerequisite queue and progress tracker**. Earlier inspection reviews are historical evidence, not additional requests. Work remains on `security/phase1-auth-authorization`, PR #2; do not merge, deploy or mark ready. Existing accounts, balances, history and unrelated features must be preserved. No SQL has been executed or assumed applied. COMPLETED below means prepared/reviewed in the branch, not active in Supabase.

## Evidence ledger — closed inspections are not requested again

| Evidence | Status | Treatment |
| --- | --- | --- |
| Initial 2A–4F | COMPLETED | All eleven exports available/reviewed; exact broad owners/members policies and eight function bodies recorded. Missing first-result summaries were subsequently resolved by M1/M2. |
| M1–M7 | COMPLETED | All supplied exports reviewed. Seven confirmed password accounts; no within-tenant duplicate emails; four members, two owners, one global Super Admin and no staff. M4 policy errors, M6 event trigger and M7 creator defaults recorded. |
| T1 | COMPLETED inspection; detailed export unavailable here | Owner confirms AFTER INSERT auth.users trigger calling iv_member_auth_signup. Preserve it. This is separate from the M6 DDL event trigger. |
| T2 | COMPLETED | Zero rows, successful; no CSV required. Known signup function was intentionally excluded. |
| T3/T4/T5 | COMPLETED inspections; detailed exports unavailable here | Owner reports 43 constraints, 65 columns, 21 indexes. Text tenant IDs, UUID identities, numeric money, nullable request IDs, legacy passwords, JSONB pricing, non-assumed date types and existing unique indexes are recorded. Exact FK actions, index predicates/types and column definitions cannot be invented from counts. |

No initial/M/T inspection will be requested again. If access to the original T1/T3/T4/T5 files is restored, mark the evidence-access item below closed; never generate a duplicate catalog query to replace those completed inspections. No need to supply T2.

## One consolidated prerequisite checklist

Each item closes once; record the returned artifact/result and review outcome here rather than opening another checklist. An absent setting should be reported as absent, not changed to satisfy the checklist. No secrets or raw account exports belong in git.

| ID | Priority | Missing item, why it matters, and exact source | Exit evidence |
| --- | --- | --- | --- |
| P1 | Mandatory evidence-access blocker for schema-dependent changes | Existing T1/T3/T4/T5 exports are not in the available attachments/workspace. Reuse the already generated files from the conversation/download location holding them. Needed for cascade-safe history retention, exact money/date types, role checks, request uniqueness and index migration compatibility. This is file retrieval, not another inspection. | Exact definitions reviewed and dependencies mapped to planned migrations; counts reconciled to 43/65/21 or differences explained. |
| P2 | Mandatory compatibility gate for affected files; managed-creator change optional | Previously outstanding executor/creator membership and namespace results. Single SELECT-only file: supabase/inspection/phase1_remaining_prerequisites.sql. Needed for 003/004 authority, inherited privilege assertions and 006 namespace collision. Reuse existing answers if already collected. | R1–R4 returned once, including zero-row success/error; decide applicable creator migrations. Lack of supabase_admin authority explicitly defers 004, never causes escalation or blocks 005–007. |
| P3 | Source review COMPLETED for two supplied functions; deployment metadata pending | provision-gym-tenant and iv-create-member source received and reviewed against 3B. Both show only a remote supabase-js import; no local imports shown. Dashboard screenshot lists only these two functions: iv-admin-correct-member-email is absent, so no source retrieval is requested for it. Its referenced application workflow requires implementation. Remaining metadata: displayed deployed version/time and actual Verify JWT state for the two existing functions. Comments do not prove settings. | Source findings below; confirm source/version correspondence and verification settings once. Design replacements using known contracts rather than requesting the same source again. |
| P4 | Mandatory identity/recovery blocker | Non-secret Auth, mail and redirect configuration below. Needed for tenant-independent credentials, real-address delivery, confirmation, recovery and existing-account compatibility. | One completed configuration worksheet, absent/unused settings explicitly recorded, chosen branch-aware delivery design verified. |
| P5 | Mandatory environment/verification gate, not a catalog inspection | A user-controlled non-production validation target and test identities for all four roles, including two tenants and a staff binding (none currently exists). Tests involving transactions require explicit target/fixture authorization; current no-delete/no-reset boundary stays in force. | Approved target/actions; credentials stay outside git/chat; reconciliation baseline and signed-off test results. Existing accounts remain intact. |
| P6 | Mandatory implementation/release gate | Owner confirmation of the exact migration files manually applied, with verification outputs/errors; then coordinated application/API release authorization. Neither local tests nor git push proves SQL was applied. | File-by-file confirmation, live identity-based deny/allow results and reconciliation; merge/deploy remain separately authorized. |

Optional improvements, not blockers: managed supabase_admin default migration 004 if platform authority is unavailable (per-object ACLs remain mandatory); permanent erasure policy/legacy column removal; broader UI/framework cleanup, additional telemetry, and a full database rebuild/reset. None justifies delaying urgent M4 fixes. Short display IDs are outside this security cutover. Normal deletion safety, report completeness and signed-pass protection remain required security work, not optional cleanup.

## One-time Edge Function retrieval checklist (P3)

In the intended Dashboard project: **Edge Functions → each named function → Code/source**. Download/read only; do not edit, invoke or Deploy.

- [x] provision-gym-tenant source supplied as a pasted upload; reviewed. Required binding names: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY. No values supplied or needed.
- [x] iv-create-member source supplied in chat; reviewed. Same binding names; no secret values needed.
- [x] iv-admin-correct-member-email absent from the displayed complete two-function Dashboard list. Do not request a nonexistent deployed source. The admin email-correction call must be implemented securely as remaining work.
- [ ] For the two existing functions only: displayed deployment version/time and actual Verify JWT setting. The source comment requesting JWT verification is not evidence of its configured state. No source needs to be supplied again unless it differs from the pasted version.

No deployed function was invoked or downloaded by the agent. Source is user-supplied evidence, not a live deployment attestation. The pasted instructions to deploy are source comments and are not followed. Both sources import supabase-js@2 from esm.sh; that major-version URL is not an exact dependency pin. Pin a reviewed exact version in replacement implementations.

### Supplied Edge source review

**Verified from provision-gym-tenant:** getUser validates the caller and the service client requires a super_admin role row; OPTIONS/CORS is handled; tenant passwords are inserted as null. Gaps: the role query does not require tenant_id IS NULL and maybeSingle rejects legitimate multiple assignments; unknown mode values silently become create; real Auth email is globally unique and cannot meet independent branch identity requirements; createUser auto-confirms addresses without a real-address verification workflow; tenant/Auth/role/staff JSON writes are separate operations with no idempotency receipt. Failure cleanup calls deleteUser and deletes a newly created tenant, with unchecked cleanup errors; interruption can leave partial records. Staff JSON read/append/write can lose concurrent updates. Existing staff mode is Super Admin-only, so authorized gym-owner staff management needs a compatible secure backend path. No suspension check is present for existing-tenant staff provisioning. Errors expose backend details. These are source findings, not remotely demonstrated exploits. CORS wildcard is not itself an authorization bypass.

**Verified from iv-create-member:** authenticated owner/staff must match the target tenant, but single() assumes one role row. Real Auth email prevents independent same-contact-email registration. Tenant duplicate precheck uses ilike (wildcards in email) and separate read/insert without an atomic tenant-email uniqueness guarantee. Caller-selected plan/expiry/classification/discount are accepted and membership activated without a financial purchase in this function. Whether the intended desk workflow grants initial complimentary entitlement must be made explicit; a provisioner cannot silently serve as an unrestricted purchase bypass. Expiry uses UTC; failure cleanup deletes Auth/member records in separate calls. No browser CORS preflight handling is present. These behaviors require coordinated replacement, not deployment of the pasted source.

**Signup trigger correction:** the supplied 3B iv_member_auth_signup immediately returns unless raw_user_meta_data.iv_member_signup equals the string true. provision-gym-tenant sends only name metadata, and iv-create-member sends no signup metadata. Therefore these exact paths invoke the Auth trigger but do not enter its member/role provisioning branch; double insertion through that branch is not established. Future branch-aware provisioning must preserve this discriminator contract or replace it in a coordinated migration, and must not trust caller-editable metadata for privileged roles. Public flagged signup remains a distinct flow.

**Replacement boundaries:** preserve existing IDs/accounts/balances/history; use explicit scoped current roles, recognized modes, durable request/outcome state and recoverable provisioning rather than destructive rollback. Separate tenant/owner/staff/member responsibilities, financial entitlement issuance and real-address confirmation. Existing Auth users cannot be recreated just to introduce aliases. Final identity delivery depends on P4 and exact constraints/date/index contracts on P1. No new SQL or deployed function replacement is claimed complete.

## One-time non-secret settings worksheet (P4)

Dashboard labels vary; report values without saving changes. Return one worksheet with all rows, using “absent/unused” where appropriate.

| Dashboard location | Values/source needed |
| --- | --- |
| Authentication → Sign In / Providers → Email | Email/password and signup enabled; confirm email; secure email change; password policy; password-change reauthentication. |
| Authentication → URL Configuration | Site URL, allowed redirect patterns, intended local/staging/production origins/subpaths. No token-bearing links. |
| Authentication → Email/SMTP | Built-in/custom sender, configured/working delivery status, provider and sender/domain verification; never credentials. |
| Authentication → Email Templates | Redacted confirmation/recovery/invite/email-change templates and placeholders/custom redirects. |
| Authentication → Auth Hooks | Enabled hook names/types, redacted source and mail-routing behavior. This determines whether private Auth aliases can deliver to real contact addresses. |
| Authentication → Sessions | Lifetime, inactivity/single-session controls and intended multi-tab behavior. |
| Authentication → Rate Limits / Attack Protection | Signup/login/recovery throttles, CAPTCHA enabled/provider, no CAPTCHA key. |
| Authentication → other Providers | Enabled providers and identity-linking behavior; no client secrets. |
| Project Settings → JWT/Signing Keys | Signing mode and JWT lifetime only; no signing material. |
| Project Settings → Data API | Exposed schemas and max-row limit; private permission/identity schema must remain unexposed. |

Confirmed requirements are closed decisions: same contact email can have independent same/different passwords at different gyms; no duplicate within the same gym; explicit administrator-granted staff reports; normal membership deletion retains financial history. Do not ask these again. Until wallet settlement is explicitly defined, deletion with nonzero liability must be rejected safely rather than guessing a refund/write-off. Permanent erasure is deferred.

## Implementation progress and dependency order

| Work | Status | Branch evidence / remaining action |
| --- | --- | --- |
| Supabase verified identity and scoped role/session foundation | COMPLETED | assets/auth-session.js, assets/super-admin-session.js and six HTML entry points. Removed embedded credential bypass and admin defaults; cleanup on logout/identity change. |
| Scanner uses reviewed check-in RPC | COMPLETED | gym/admin.html no bulk profile mutation for QR admission; Manila date check. Server strengthening/signed passes still pending. |
| Explicit report permission backend and M4 policy correction | COMPLETED, prepared only | 005 role/history grant protection, 006 private permission table/audited APIs, 007 correlated financial/attendance policies; report gating and administrator widget. No live enforcement claimed. |
| Existing/future ACL hardening | COMPLETED, prepared only | 001/002 preserve authenticated ordinary RPCs; 003 postgres public defaults and optional 004 supabase_admin defaults. Per-schema revokes cannot cancel global PUBLIC EXECUTE; each new function explicitly clears ACLs. |
| Permission widget stale identity/tenant response protection | COMPLETED | Reject late responses and detached controls after account/tenant changes; covered by regression tests. |
| Schema dependency reconciliation | BLOCKED P1 | Review exact completed exports once available; preserve auth signup/event triggers and map cascade/unique constraints. |
| Server-authoritative finance and idempotency | BLOCKED P1 | Separate additive receipt foundations, then exact RPC replacements. Price/term/discount from trusted gym data; validate finite exact amounts/splits/status, lock member, atomic wallet/entitlement/ledger/receipt, exact retry returns saved outcome, changed payload rejects. Preserve history and nullable legacy request IDs; cash-only retries covered. Existing pricing UI semantics are available in code; review any exceptional configured pricing values through the existing test target rather than starting a broad new inspection. |
| Independent branch identities, signup/confirmation/recovery/email change | BLOCKED P1/P4; P3 metadata pending | Separate Auth identities behind server-owned tenant/contact mapping; preserve existing IDs/passwords and signup-trigger compatibility. Finalize delivery/callback design before code; no aliases with broken mail and no shared-password identity. |
| owners/members RLS, public branding and protected mutations | BLOCKED P1; known Edge contracts reviewed | Replace public ALL policies with compatible branding/profile/admin APIs and field-level financial/privacy controls; preserve four-role workflows, no open-access fallback. |
| Member/tenant lifecycle preserving ledger/audit | BLOCKED P1 | Map cascades; prefer deactivation/anonymization and stable historical links. Deny unresolved nonzero-wallet deletion; no account/row deletion operation authorized now. |
| Attendance server entitlement/date validation and signed passes | BLOCKED P1 | Respect actual date storage, tenant/status/plan, Manila day and concurrent duplicates; manual/camera/upload share backend authority. |
| Protected staff/approval/pricing/import/export/restore operations | BLOCKED P1; known Edge contracts reviewed | Remove JSON/browser credential authority and raw financial writes through validated scoped operations; retain legitimate features without exporting credentials. |
| Report pagination/server aggregation | NOT STARTED, follows secure data API | Remove silent max-row truncation with consistent scoped aggregation/pagination; retained ledger totals must reconcile for large data. Not a reason to remove existing report access. |
| Isolated SQL/RLS and concurrency regression harness | NOT STARTED, depends on complete schema/RPC replacements | Build fixtures without live credentials; test actual database behavior in an approved local/staging target. Mocks are insufficient. |
| Owner-run migration acceptance / hosted regression | BLOCKED P5/P6 | No SQL/testing mutations or release performed by this agent. |
| PR #2 Draft verification | BLOCKED tooling | Git push cannot verify/change PR state. Available tools have no PR management; previous GitHub API access was forbidden. Owner checks PR #2; if necessary “Convert to draft.” Never mark ready or merge. |

Do not label blocked items completed because a plan exists. Safe prepared work is retained; no speculative financial/identity/policy replacement is generated without its dependency contract.

## Migration and application delivery sequence

1. Review existing 001/002; narrow ACL changes, preserve ordinary authenticated RPCs and service rights.
2. Review 003 and optionally 004 only with creator capability; these are independent of urgent M4 remediation.
3. Apply approved 005 → 006 → 007 manually, separately; return checks/confirmation before activating dependent report controls. No migration is assumed applied. See supabase/migrations/README.md for exact names/guards/recovery.
4. Once P1/P3/P4 close, prepare separately numbered additive identity/request foundations and necessary validated uniqueness/FK changes. No destructive reset or automatic account conversion. Inspect legacy data compatibility from existing snapshots; abort/fix forward on drift rather than dropping guards.
5. Prepare exact finance/attendance/lifecycle/administration RPC replacements, then scoped table/column RLS and explicit function ACLs in compatible staged order. Update registration/login/profile/admin/import/report calls against those APIs. Validate before coordinated cutover; do not close working paths without replacements and do not retain insecure public policies as fallback.
6. Run schema-level integration and four-role feature regression; reconcile accounts/wallets/ledger before/after. Owner manually applies reviewed migrations and returns verification. Security release readiness is distinct from permission to merge/deploy.

Every actual file documents additive/behavior-changing/destructive classification, prerequisites, data effects, assertions, manual verification and recovery. Destructive operations are excluded. Optional 004 may remain explicitly deferred with per-object ACL controls; everything else in the required acceptance gates must be resolved.

## Phase 1 endpoint and acceptance gates

Phase 1 **implementation complete** means all required code/migrations/tests are reviewed and these gates pass in an approved isolated environment. **Database accepted** additionally requires owner-confirmed manual execution and identity-based tests on the intended target. Neither status authorizes merge or deployment.

- [ ] Every required migration exists separately with exact dependencies/guards/verification; no assumed schema application or account resets; no credentials committed. Existing accounts/links, balances and financial history reconcile.
- [ ] Supabase Auth is the sole credential system for all four roles. No browser default role, embedded password authority, plaintext credential comparison/export or user-metadata role escalation remains.
- [ ] Same contact email supports independent passwords/profiles in two gyms; same-gym duplicate rejected atomically. Legacy accounts can still authenticate; confirmation, recovery and email change affect only the selected branch. Auth trigger provisions once without duplicate links.
- [ ] Direct anonymous/private requests denied; members see/edit only permitted personal fields; owner/staff stay in tenant; Super Admin authority explicit. Direct role/wallet/ledger edits denied; no PUBLIC ALL exposure. Financial values elsewhere in member/activity fields cannot bypass report privacy.
- [ ] Staff can perform allowed desk transactions without blanket reports. Same-tenant administrator grants/revokes work; self-grant/cross-tenant grant denied; revocation and role removal deny subsequent requests, refresh and print.
- [ ] Financial RPCs reject manipulated prices/amounts/expiry/discount/split/tenant, NULL/nonfinite/negative/overflow values, insufficient balance and unauthorized actors. Same/changed-payload retries, concurrent requests, cash-only and mixed payments, ledger failure rollback and original-result retrieval are exercised; no duplicate processing or negative wallet.
- [ ] Check-in enforces tenant/status/entitlement/actual date storage, signed-pass validation, Manila boundaries and duplicate/concurrent admission; manual/camera/upload parity, trusted actor/time and protected audit.
- [ ] Member deactivation/deletion design preserves historical amount/date/type/tenant, audit and report totals; cascades cannot erase finance; unsettled-wallet deletion safely denied. No destructive test of existing records required.
- [ ] Reports reconcile with ledger including absent/inactive profiles and datasets exceeding API row limits. Backup/import/export/restore preserve tenant/ledger invariants and contain no passwords.
- [ ] Regression passes for tenant registration/branding/pricing, owner/staff administration, approvals, member signup/login/recovery/profile, top-up/purchase, check-in, reports and authorized data operations. Logout/expired session/revoked role/wrong tenant/URL/body tampering/browser Back/cross-tab identity changes all covered.
- [ ] Actual database RLS/RPC tests use authenticated/anonymous identities (not service-key or SQL Editor bypass), concurrency tests run, and financial reconciliation has recorded results. Any untested material security invariant blocks completion.
- [ ] Owner-run migrations confirmed, errors resolved, target acceptance recorded, PR remains Draft until explicit readiness/merge/release authorization.

## Current validation and next bounded step

77 Node tests passed in this continuation (0 failed/skipped), including two new delayed identity/tenant permission regressions. Earlier mocked Chromium report checks and pglast parsing passed; new consolidated SELECT file is syntax-parsed separately. None establishes hosted RLS, migration execution, concurrency, mail delivery or complete Phase 1. No Supabase SQL, deployment, merge, reset or deletion was performed.

The next review consumes a **single prerequisite bundle P1–P4**, reusing existing files/results wherever possible. P5/P6 are later validation/acceptance gates, not additional catalog discovery. Any genuinely new dependency must cite its exact code/schema reference and amend this tracker with a reason; no broad repeated inspection cycle. Work can resume per dependency as bundle parts arrive, without waiting on optional 004.

Source-review continuation: both existing Edge Function sources are now received; no source retrieval for the absent third function remains. This continuation changes documentation only. No runtime test was rerun for a documentation-only change; prior 77-test result remains historical evidence, not validation of these functions.
