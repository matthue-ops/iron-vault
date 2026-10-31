# Phase 1 security architecture

Status: target design documented before branch-aware authentication implementation. This branch contains only the evidence-independent browser/session stage. It does not establish a secure database or complete Phase 1. The deployed CSV exports, schema dependencies, Edge Functions, and Auth settings have not been supplied in this workspace.

## Evidence and source of truth

The baseline is main `de6de04e3b0e94c780f7393137d763c0e3f651ec`. The owner reports public ALL policies on owners/members, eight broadly executable SECURITY DEFINER functions, seven valid role assignments, and existing iv_purchase/iv_can_access functions. These are reported findings, not independently reviewed definitions. Earlier local SQL and Edge Function drafts were preserved in Git stash and are not deployed evidence or release artifacts. No database migration has been applied or assumed applied.

## Identity and branch-independent accounts

Supabase Auth remains the sole credential/password/session provider. The application never compares a password to an application record, stores a password in a profile, or grants access from browser flags or user-editable metadata.

A branch account maps `(tenant, normalized contact email)` to a branch-specific Auth identity. Public contact email is distinct from the private Auth login identifier. The same email may register in two gyms with equal or different passwords, without connecting their profiles, wallets, recovery or account changes. Duplicate member registration within a gym is rejected by a database constraint and a server check. A branch account may hold explicit tenant-scoped roles if the approved schema supports that; conflicting membership links fail closed.

Proposed implementation: an unguessable private Auth email alias per branch identity, with a trusted gateway resolving the selected public gym link and contact email. The gateway delegates password validation/session issuance to Supabase Auth. A separate global Auth identity handles Super Admin login. No alias algorithm is an authorization secret. Identity linkage is server-owned and RLS is based on auth.uid(), never email comparison.

Confirmation, recovery and contact-email verification must be delivered to the real contact address through a trusted server mail adapter. Links must be signed, expire, use approved return origins, and apply to one branch identity only. Changing contact email requires proof of ownership of the new address before the mapping changes. Signup/login/resend/recovery require generic errors, throttling and appropriate abuse protection. Existing provider, Auth settings and trigger behavior must be inspected before implementing this gateway. Do not introduce a guessed mail-provider dependency or reuse the old draft gateway.

## Authorization and permissions

Authoritative database role rows grant access. Current application role names are super_admin, owner (gym administrator), staff and member. A global Super Admin grant is explicit and unscoped; tenant-bound grants require a real tenant. Multiple role rows are evaluated against the requested portal and tenant rather than `.single()` or the first result. Existing SDK session storage behavior is retained in this first stage; callback and multi-tab policy changes require the Auth configuration and integration tests.

Super Admin manages tenants, administrator provisioning, platform oversight and approved cross-tenant operations. Gym administrators manage their own gym's pricing, staff, memberships and reports. Staff perform authorized desk operations. Members access their own profile and entitlements. The final action matrix must define destructive/adjustment privileges; no broad role is inferred from the legacy staff.isAdmin JSON field.

Financial reports require Super Admin, the relevant gym administrator, or a staff role with an explicit `financial_reports_read` permission for that tenant. Only an authorized gym administrator or Super Admin can grant/revoke it. Staff cannot self-grant. Database checks consult current assignments for every protected operation; the permission is not an enduring JWT claim or browser cache. Revocation blocks subsequent protected requests. Previously downloaded data cannot be retroactively made unread.

A row policy cannot protect individual financial columns. Direct table/column grants and RPC ownership must protect balances, role assignments, discounts, approval, subscription state and history. Members receive only explicitly permitted personal-field edits. All request inputs and tenant/member relationships are validated server-side. Public gym discovery exposes only safe branding fields. The remaining public ALL policies must be replaced at coordinated cutover, not retained as a fallback.

SECURITY DEFINER is retained only when justified. Owners, search_path, fully qualified references, dynamic SQL, overloads and effective PUBLIC/anon/authenticated grants must be reviewed. Private helpers must not create policy recursion or become publicly exposed escalation endpoints. Narrow authenticated execution is not automatically a vulnerability; function bodies determine the authorization boundary.

## Financial and attendance invariants

- Use exact monetary units consistently, such as integer centavos or constrained fixed-precision numeric values. Validate valid bounds, currency, plan terms and permitted discounts on the server.
- Wallet mutations, plan entitlements and immutable transaction records commit together. Lock the relevant wallet/member state or use equivalent concurrency-safe conditional updates.
- Derive prices, member/tenant associations, actors and timestamps from trusted records. A member cannot declare cash received or override prices/discounts. Staff cash collection is an authorized record of desk collection, not proof of external payment settlement.
- Idempotency binds operation, tenant, actor, stable request key and normalized request payload. An exact retry returns its original result; a changed payload under the same key fails. The client reuses the key while retrying. Different concurrent requests must still respect wallet/entitlement constraints.
- All camera, upload and manual check-in paths use the same server authorization and entitlement checks. A signed/expiring tenant/member pass replaces the unsigned date/ID authority; manual admission remains an explicitly authorized staff action.
- Use Asia/Manila as the business-day authority. Enforce the approved one-admission-per-business-day rule atomically; any override must be explicit and audited.
- Historical financial entries cannot be edited/deleted by ordinary users. Corrections use authorized compensating entries. Reports use ledger values and transaction-time snapshots, with pagination/aggregation rather than silently truncated client totals.

## Deactivation, deletion and erasure

Deactivation preserves the membership/account but denies the affected operations. Normal member deletion revokes that membership's access and removes/anonymizes unnecessary personal information while retaining tenant-linked amounts, dates, types and financial audit integrity. A non-personal membership tombstone or nullable historical reference must preserve referential integrity. Report queries must retain historical transactions even when no active member profile exists.

Account deletion is separate from membership deletion and from permanent erasure. Auth removal must not affect another gym's independent account. A nonzero wallet liability requires an explicit settlement/refund policy before deletion; it must not disappear silently. The retention period and permanent-erasure authority require a product decision before implementing erasure. No account or row is deleted in this stage.

Disposable development resets are separate, clearly destructive operations. No automatic cascade purge of financial history belongs in the normal deletion path.

## Preserved workflows and security-required changes

Tenant provisioning, branding/pricing, staff administration, registration/confirmation/recovery, profiles/approvals, wallet sales/top-ups, admission, reports and authorized backups remain intended features. Both master entry points share one Auth controller without a framework or visual rewrite.

Password viewing, browser administrator defaults, unverified private-cache fallback, raw financial upserts and unsigned pass authority cannot remain security mechanisms. Imports/restores require a validated privileged workflow; they cannot bypass tenant/role/ledger invariants. Replacing those paths remains blocked on backend evidence. Never release this browser stage as if it already enforces those database guarantees.
