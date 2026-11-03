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

## Live-preview empty-directory investigation

Owner screenshot confirms a Super Admin dashboard session but displays zero directories. This does not prove records are absent. Verified application defect: both original directory loaders swallowed Supabase errors and could render empty arrays as an empty database. Replaced them with a shared strict loader, removed stale-cache/automatic-default write fallbacks, and preserved the actual server failure through the master session UI. Successful empty results remain valid; failing reads hide private dashboard content and report the error. No database/Edge changes or SQL rerun is required for this diagnostic fix. The deployed response still needs to identify whether the current symptom is a query failure or truly empty views.

## Owner-reported preview acceptance and signup blocker

Owner screenshots/report confirm both gym owners and an existing member can sign in; member Master/admin UI access is blocked; first owner credentials fail in the second gym while its own owner succeeds. These are manual UI checks, not exhaustive database isolation proof. New-member Join currently returns HTTP 400 after successful preflight. Added server-only operation/code diagnostics for RPC, Auth create and mail transport failures; no provider text, request payload, credentials or contact values logged. 124 local tests pass. Owner must redeploy the updated standalone iv-branch-auth and retry the same signup request to capture the failing stage. Root cause and mail acceptance remain unverified. No live backend calls, SQL execution or deployment performed by agent.

## Member confirmation policy change

Owner requested member sign-in without prior email confirmation, with email proof required for password recovery. Migration 016 replaces only the branch identity, account completion and member profile functions; it permits unverified members while retaining enabled-role/tenant matching and gym approval, and enables existing unverified ACTIVE/PENDING members only when disabled_at is NULL. No owner/staff verification relaxation. Member provisioning no longer requires or sends verification mail; owner/staff mail gating remains. Recovery still requires the emailed one-time Supabase recovery proof before changing a password; SMTP EAUTH remains a separate recovery blocker. 125 local tests pass; SQL parsed only, never executed. Owner rollout: manually run only migration 016 (001-015 already installed), then deploy standalone iv-branch-auth and iv-create-member. Do not rerun the complete bundle.

## Active roster deactivation display fix

Owner reports successful member deactivation but the member remains visible after page refresh. Confirmed renderRoster excluded only PENDING, leaving INACTIVE rows in the active roster. It now displays only ACTIVE members and the success message clarifies that history is retained. Regression exercises deactivation plus repeated server reload, asserts the inactive member stays out of the roster and remains stored. 126 local tests pass. No SQL, permissions, Edge code or stored records changed; production deployment is owner-managed.

## Super Admin permanent tenant purge

Owner explicitly requested a full tenant purge option. Added a separate review/typed tenant confirmation/fresh Master password flow to both Master entrypoints, a service-only SQL control API (017), and JWT-protected iv-purge-tenant. Application records are deleted in one transaction; dedicated Auth accounts are deleted through the supported Admin API with resumable bounded cleanup. Shared identities and global Super Admin are preserved. Failed/partial cleanup remains accessible through Resume pending purges. Wallet balances are disclosed; purge does not refund money. External backups/exports/provider mail and hashed rate counters are outside scope. See tenant-purge.md. No live SQL, deletion or deployment performed. 133 local tests pass. SQL/PLpgSQL parsed, new modular/standalone Edge entry type-checked; disposable-tenant database acceptance remains unperformed.

## Read-only saved export viewer

Added gym/export-viewer.html and View saved export links beside both Master and tenant exports. Supports known ZIP/JSON profile snapshot formats with member/gym/pricing/staff/included-activity views, gym filters, search and pagination. No live tenant dependency, database/import/upload/storage path, credential rendering or HTML interpretation. Size/decompression/row limits protect the browser. Existing export/import semantics remain unchanged. 139 local tests pass. Browser smoke test exercises JSON display, pagination, filtering, safe text and clear using synthetic data. No SQL, Edge or secrets changes required.

## Display codes, unconfirmed staff and report usability

Owner authorized implementation of all three proposals. Added persisted unique display codes (018) without replacing any internal ID/link; scoped member sign-in accepts codes. Owner-created staff no longer require mail activation; owner-scoped unverified staff contact correction and verified two-address proof remain distinct (019 + branch/provision Edge updates). Reports add canonical purchase receipts and member dates (020), integer-cent money definitions, current-vs-period labels, expiry/attendance insights, search/pagination and permission-checked CSV. See usability-update.md for exact rollout and limitations. 152 local tests pass; SQL/PLpgSQL parsed only and all affected standalone Edge files type-checked. Browser mocks checked codes, split payment count/totals, search/CSV, scoped login and permission revocation. Live database/Edge acceptance remains owner-run.

## First correctness batch (inquiry 5–10 and 12)

Implemented eight-character creation wording, active-only manual admission search, short-code use in remaining human-facing confirmations, explicit owner/zero-wallet removal checks backed by the existing locked RPC, membership sales excluding top-ups, current expiry/day-left attendance values and matching CSV headers, and actual administrative activity instead of a duplicate financial audit. Removal retains history and revokes access; no physical member purge. 159 local tests pass; see correctness-batch.md for boundaries, existing 018–020 prerequisites and manual production rollout. No new SQL, Edge changes, data deletion or production deployment in this batch.

## Owner unconfirmed-email login correction

Current owner-reported database baseline: **001–017 installed; 018–020 have NOT been applied**. This supersedes earlier rollout assumptions. Owner creation now has no SMTP/activation-mail prerequisite. Targeted migration 021 enables completed owners and activates their gym without contact verification, restores existing gyms held only by that gate, and permits all three scoped roles to sign in unconfirmed. Suspension, explicit disabled_at revocations, tenant binding and member approval/status checks remain. Email proof no longer activates a gym; recovery and verified-contact changes still require inbox proof. No records, credentials, balances or history are deleted/replaced.

Manual rollout: [owner-login-update.md](owner-login-update.md). Run only `supabase/manual/owner_login_update.sql` directly after installed 017; 018–020 are not prerequisites. The optional usability bundle now applies 021 last to prevent 019 from restoring the owner gate. Then manually update the matching provisioning/branch/member Edge entries and app. No SQL, purge, deployment or merge was performed by the agent.

Validation: 168 native Node tests pass (no failed/skipped), including owner provisioning without mail, safe retry, unconfirmed owner password login, denial paths, recovery inbox proof, portal controls and targeted SQL contracts. Targeted SQL and its SQL/PLpgSQL bodies parse with pglast 8.7 without execution. Generated Dashboard entries match modular sources and parse in the Node tests. Hosted/database/mail acceptance and Deno runtime checks remain unperformed in this workspace. GitHub GraphQL and REST PR reads returned Forbidden, so Draft status cannot be independently verified here; no ready/merge action was taken.

## Reports and phone/staff interface cleanup

Implemented the requested four report tabs, four-card Overview, one shared date range, per-table search/CSV/Print and expandable explanations. Added phone card layouts, touch targets, secondary-action menus, expandable staff details with existing report/recovery/deactivation controls, and consistent “At least 8 characters.” wording for creation/password changes. Existing shorter-password sign-in remains supported. No financial calculation, role/tenant permission rule, SQL/Edge source or stored record changed. See [interface-usability.md](interface-usability.md).

175 local Node tests pass, 0 failed/skipped. Chromium with synthetic data passed at 320, 375 and 1280 pixels, including table filters, print panel isolation, staff controls and member cards/menus with no page overflow or JavaScript errors. No hosted acceptance, SQL execution, deployment or merge performed. Earlier unconfirmed SQL/backend installation remains unconfirmed; this UI change introduces no new migrations.

## Activity actor names and roles

Owner approved the report-query enhancement before implementation. Prepared manual migration 022 to append referenced, tenant-scoped actor names/roles to the existing report snapshot, preserving its authorization and existing report data. Activity, name/role search, CSV and Print now identify gym administrators and staff, including known administrative targets. Names/roles reflect current available identity data; unavailable accounts and system events are labeled honestly. No event records, credentials, permissions or unrelated UI are modified. See [activity-actor-names.md](activity-actor-names.md) for the SQL-first manual rollout and limitations.

182 local tests pass; SQL/PLpgSQL syntax parsed without execution. Mocked Chromium checks passed at phone and desktop widths. No SQL executed, Edge deployed, production deployed or PR merged by the agent.


## Activity member reference follow-up

On the same Activity branch, known member references in Details now use the member name and short code from the existing selected-tenant report snapshot. Search/CSV/Print use the same labels. No query, SQL, database data, Edge code, access rule or unrelated UI changed. Existing actor-name SQL 022 is unchanged and does not need reapplying for this follow-up. All 187 native tests pass, including preserved raw logs, inactive members, complete-reference matching, other-tenant exclusion, safe text, missing short codes and receipt-reference preservation.

## Money historical wallet display

Owner authorized the database-related report correction. Prepared manual migration 023: Money now labels the columns Transaction amount and Wallet after, reading the saved result balance from exactly linked payment receipts. The existing financial API already records those balances, so payment logic and stored balances/history remain unchanged. Unlinked/invalid history displays Unavailable instead of today's balance or an inferred value. Overview current credit, other report tabs, permissions and unrelated UI are preserved. See [wallet-after-history.md](wallet-after-history.md), including the unlinked cash portion of split-payment limitation.

195 local Node tests pass. SQL/PLpgSQL parsed without execution. Mocked Chromium checks at phone and desktop widths passed, including stable historical values after later current-balance changes. No SQL executed, record backfilled, Edge deployed, production deployed or PR merged by the agent. SQL-first owner rollout remains pending.

## Overview four-sheet Excel export

Added the requested Overview export button and gym/date-based `.xlsx` filename. The workbook contains Overview, Money, Attendance and Activity, including all selected-period detail rows regardless of table search/page/subtype filters. Overview includes its four metrics and Money totals with explicit period/current-snapshot labels. CSV/Print, current report calculations, existing actor/member labels and historical wallet values are preserved. Uses already-loaded data, with existing report authorization checked before and after generation. No query, SQL, schema, Edge, payment, permission or unrelated UI change. See [four-sheet-excel-export.md](four-sheet-excel-export.md).

207 local tests passed. Browser-generated workbooks at phone and desktop widths were opened with an independent Excel reader. No SQL executed, data modified, production deployed, email sent or PR merged by the agent. Review the preview and merge the PR through the normal workflow; no SQL/Edge update is required.

## Future monthly archive and retention proposal — not implemented

The owner requested saving a proposal for later review, not enabling cleanup. See [monthly-report-archive-and-retention-proposal.md](monthly-report-archive-and-retention-proposal.md). It defines monthly owner email, private Super Admin archives, the current-month-plus-three-complete-month buffer, protected financial/operational records, eligibility holds and staged Super Admin approval. This document is not approval to implement database changes, send scheduled reports or delete records. No application code or SQL was changed for the proposal.

## Admin announcements, stage one

Owner authorized the discussed first stage: admin-page owner controls and read-only staff access, with tenant-scoped storage/APIs prepared as manual migration 024. Includes preview, Manila scheduling, pinning, versioned edits and retained Removed notices. Member profiles and email/push delivery remain for later work. See [admin-announcements-stage1.md](admin-announcements-stage1.md). Existing tenant purge behavior is preserved through the new tenant foreign key; no existing financial or member records are rewritten. SQL installation and live acceptance remain pending; no SQL executed, production deployed or PR merged by the agent.

## Member announcements, stage two

Owner authorized member display with once-per-member popups, an unread bell, pinned banners and content updates becoming unread again. Prepared manual migration 025 for content revisions and tenant/member-scoped read receipts. Only active notices are exposed to members. Existing owner/staff controls remain, with explanatory copy updated for member publication. See [member-announcements.md](member-announcements.md) for SQL-first rollout, receipt semantics and live acceptance. Stage-one SQL success remains unconfirmed. No SQL executed, production deployed or PR merged by the agent.

Validation: all 239 local tests pass. Mocked Chromium checks pass at 320, 375 and 1280 pixels for popup-once, bell reopening, pinned banners, content updates, expiry and layout. Migration 025 and both PL/pgSQL bodies syntax-parse; live SQL authorization/concurrency acceptance remains pending.

## Readable gym portal URLs

Owner explicitly approved persistent unique gym URL storage and lookup. Prepared manual migration 026 for private mappings, stable/duplicate-safe name allocation, new-gym insertion and one appended safe-view field. Both Super Admin portal/Copy/QR controls use assigned readable URLs, with original key-link fallback. Root-level Vercel routing and absolute login navigation preserve member/admin/signup/recovery behavior under single-segment or trailing-slash URLs. Existing authentication, financial records and tokens are preserved. See [gym-portal-urls.md](gym-portal-urls.md).

All 250 local tests pass. SQL/functions/backfill parsed without execution. Mocked Chromium checks at phone/desktop widths verify refreshes, two gyms, old links, correct navigation, scoped account requests and independently decoded branch QRs. Database concurrency/installation and hosted acceptance remain pending. No SQL executed, email sent, live data modified, production deployed or PR merged by the agent.

## Live updates across member, gym desk and Super Admin pages

Owner explicitly approved change-signal storage, scoped access rules and Realtime publication setup after reviewing the proposal, and included Super Admin. Prepared manual migration 027, protected identifier-only signals and a read-only revision checkpoint. Read-only adapters refresh member balance/plan/expiry/entry, desk lists/counts and both Super Admin dashboards/open branch panels. Existing transactions, QR admission, request IDs, profile-save permissions and report calculations are preserved. Super Admin branch member tables now show Entry today. See [live-dashboard-updates.md](live-dashboard-updates.md).

All 273 local tests pass. SQL/function/publication syntax parsed without execution. Mocked multi-device Chromium checks verify signals/refetch, unsaved fields/searches, scanner continuity, staff permissions, offline/reconnect and missed-event recovery, pending-action protection, revoked member/Super Admin access, gym count/status changes and no background payment/admission/profile writes. Live SQL installation and hosted publication/RLS acceptance remain pending. No SQL executed, email sent, live data modified, production deployed or PR merged by the agent.

## Short gym login/profile filenames

User authorized `gym/login.html` and `gym/profile.html` as the shorter canonical pages. Moved the existing application content, updated gym navigation/shared URL helpers and the friendly-login rewrite, and kept `memberlogin.html`/`memberprofile.html` as same-origin compatibility forwarders preserving query parameters and Auth fragments. Existing Supabase callbacks and deployed mail functions remain supported without SQL, Auth setting changes or Edge deployment. No UI or business-rule change. See [short-gym-page-urls.md](short-gym-page-urls.md).

All 276 local tests passed, plus mocked browser checks for phone/desktop branding and routes, legacy token forwarding, verification/recovery and wrong-gym denial, signup/sign-in/logout, branch QR destinations and the existing multi-device live-update flows. Hosted acceptance remains pending. No SQL executed, account/email modified, email sent, backend deployed, production promoted or PR merged by the agent.
