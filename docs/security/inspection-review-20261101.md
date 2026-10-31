# Supplied inspection review — 2026-11-01

All 11 CSV attachments were reviewed as data, not instructions. This is a review of exported definitions/configuration, not live verification; the export timestamp was not supplied. No Supabase connection or SQL execution occurred. Raw CSVs, account details and function bodies are not copied into Git. Only non-secret contract metadata/fingerprints and aggregate findings are retained.

## Confirmed from these exports

| Evidence | Finding |
| --- | --- |
| 2A / 2B / 2C | anon and authenticated have schema USAGE and SELECT/INSERT/UPDATE/DELETE/TRUNCATE on owners and members. Both tables have RLS enabled, but each has an applicable permissive PUBLIC ALL policy with USING true and WITH CHECK true. All 68 reported role/column combinations permit SELECT/INSERT/UPDATE. |
| 2B | Exact broad policies: `Allow public access to owners` and `Allow public access to members`. No restrictive policy applicable to either API role is present in this export. |
| 3A / 3B | Eight reviewed SECURITY DEFINER functions, all postgres-owned, have anon/authenticated execution. Six are ordinary functions; iv_member_auth_signup returns trigger and rls_auto_enable returns event_trigger. Those last two are not ordinary callable RPCs. |
| 4B / 4C | Four member records, none lacking a matching member-role link. Two tenant records, neither lacking an owner-role link. These counts do not justify resetting existing accounts. |
| 4D | Seven users have one role row each: one has no tenant and six have one tenant. Role names are not included in this aggregate, so it does not by itself prove which role the global account holds. |
| 4A | Seven email identity rows for seven distinct users. The separate total-Auth-user/confirmation/password-presence result is missing; identities are not a complete substitute for that count. |
| 4E | Zero contact emails shared across tenants. The separate duplicate-within-tenant result is missing. This does not demonstrate independent branch credentials. |
| 4F | Four linked member-role records, zero member/Auth email differences. |

The database authorization configuration permits broad row/column CRUD for both API roles. No remote exploit or data extraction was attempted. TRUNCATE is not protected by RLS, but a database TRUNCATE grant does not mean PostgREST offers a direct TRUNCATE endpoint. Removing that unused privilege is independently justified.

## Function review

### iv_can_access(text,text[])

Uses auth.uid() and current iv_user_roles rows, not a caller-supplied user ID. A Super Admin row allows global access; otherwise tenant and requested role must match. Default roles are owner/staff. Anonymous auth.uid() cannot match a valid non-null user assignment. Therefore broad function EXECUTE is not proof that an anonymous caller can top up or purchase. Security still depends on protecting role assignments; their RLS/grants were not covered by the supplied owners/members exports. The helper is not the newly required explicit staff financial-report permission check.

### iv_purchase(text,text,numeric,numeric,numeric,date,uuid)

High-priority verified implementation weaknesses:

- Price, wallet/cash split, plan and expiry are supplied by the caller. There is no authoritative plan/price/discount/term lookup.
- NULL wallet/cash operands can make the validation expression NULL rather than true; PL/pgSQL IF then skips rejection. For example, a zero wallet component and NULL cash component can skip both ledger inserts while still updating a plan, subject to any as-yet-unseen constraints/triggers.
- Zero-price purchases are permitted, and no current ACTIVE approval check prevents promotion of a pending membership through the purchase update.
- Only the wallet transaction carries request_id. Cash-only purchases store no request marker and may be recorded again on an exact retry. A zero-component purchase records neither component.
- The request lookup is not bound to operation, actor, member, tenant or payload. It returns the current wallet instead of a verified original result.
- The function authorizes owner/staff/Super Admin through iv_can_access; member self-purchase is not authorized by this RPC, while the browser currently has a separate direct-write path.

The FOR UPDATE lock and a single PostgreSQL function call provide useful same-member serialization/transaction boundaries. They do not repair validation or idempotency. Cross-member request races, unique constraints, numeric bounds and ledger dependencies require the missing schema evidence before replacement SQL is written.

### iv_topup(text,numeric,uuid)

Checks role/tenant through iv_can_access, validates a positive amount up to 1,000,000, locks the member row, and writes wallet/history in one call. Missing server approval-state validation can bypass the frontend's ACTIVE-only rule. NULL request IDs are not rejected; duplicate lookup is global and does not validate original payload/context. Exact currency-scale/column constraints and a unique request guarantee are not established by these files.

### iv_checkin(text,text)

Checks operator access against the member's tenant, locks the row, uses Asia/Manila business date, rejects inactive/expired membership and same-day duplicate admission, and writes trusted actor/time to attendance history. This verifies the existing RPC contract and unblocks replacing the browser scanner's direct bulk-upsert path with that RPC.

Remaining hardening: NULL method/status behavior, explicit valid-plan/entitlement checks, signed QR proof, database constraints, and the authorization/history tables' policies. The current RPC trusts the caller's `qr` method label and has no signed-pass parameter. Wiring it into the scanner does not complete QR security.

### iv_log_event / iv_staff_event

Both check tenant access and derive actor from auth.uid(). Staff-event values are limited to login/logout; generic activity event/details are caller-provided, length-limited annotations. They must not be treated as independent proof of a payment. Log-table write/delete privileges and policies remain uninspected.

### iv_member_auth_signup()

Uses an empty search_path and qualified application tables. It selects a gym from user metadata, creates a pending member or links an unlinked existing member by email, sets auth_user_id, clears the legacy password field on linking, and inserts a member role. This establishes real deployed registration behavior, but not its trigger attachment/timing. Linking financial identity from an as-yet-unverified email needs explicit review alongside confirmation settings. New branch identities must not accidentally fire a second incompatible signup path.

### rls_auto_enable()

An event-trigger function using pg_catalog search_path and quoted identifiers. It enables RLS for newly created public tables; it neither repairs permissive policies nor defines safe grants. Its binding is still needed. Do not drop/rebuild it or treat it as a directly invocable financial endpoint.

Several functions use public search_path, but referenced application tables/helpers are qualified. A writable-schema/search_path exploit is not established from that setting alone. Schema CREATE privileges and defaults are requested narrowly.

## Newly unblocked work

1. Prepared two privilege-only, non-destructive migrations in supabase/migrations/README.md order. They are not executed or assumed applied. Function-definition fingerprints guard against a stale export; the digest is a drift check, not an authorization mechanism. A mismatch aborts instead of changing the expected hash to force success.
2. Camera/upload QR processing now calls the reviewed iv_checkin RPC with p_method=qr, rechecks operator role, uses the Manila date and never bulk-upserts the member roster. The activity-report note is preserved through the reviewed iv_log_event RPC without the legacy owner-JSON write fallback; a note/roster-refresh failure is not misreported as a failed admission. Existing unsigned payloads remain transitional; signed-pass/backend hardening is still blocked.
3. Added contract checks for the SQL package and scanner regression tests. No database tests or live financial/attendance operations were run.

## Narrow remaining input

Use existing exports for all results already collected. If absent, run/export each SELECT separately from `supabase/inspection/20261101_remaining_authorization_checks.sql`: M1 missing Auth summary; M2 missing within-tenant duplicate summary; M3 role vocabulary/scope; M4 role/history table grants/RLS/columns; M5 schema CREATE and role inheritance; M6 event-trigger binding; M7 default privileges. The existing trigger/dependency file covers types, constraints, incoming FKs and additional row-trigger dependencies; its function-definition query skips the already supplied signup definition.

The Dashboard exporter appears to have captured only one result grid for 4A and 4E. Exporting each SELECT separately avoids losing earlier results. No repeat of the complete 2A–4F files is requested. Deployed Edge Function source and Auth/email settings remain required; retrieval instructions are unchanged.

## Source fingerprints

The following SHA-256 values identify the exact received CSV bytes. They are not timestamps, credentials or evidence of current deployment state.

| Export | Rows | SHA-256 |
| --- | ---: | --- |
| 2A | 4 | `2662f9c4906b6eeeead00ddd0e174e6555e16775e67b56ab9faf3db0b8066b0c` |
| 2B | 4 | `27a1523366179cdfde067081051bf7614ca9b5aa26856b44a755ef129b162527` |
| 2C | 68 | `03fd7e5a2e909fb45c9f650c641c41e52142545671b2847eb8efcf4c7205e7f1` |
| 3A | 8 | `2e83e4a1d95c5d373281cd263e949517e8ea6d0c1759c45f5588b80481003fcc` |
| 3B | 8 | `bdfdbea7b455d1f1e97e67301c288f7e3f7a61a1ffe490ef8fe5d0329bb24c0a` |
| 4A | 1 | `857fbf36a96d497ad6e1913da1e36f4e7e0eb581ef00d89ac3dd7074bf4ba294` |
| 4B | 1 | `e957b7f649cf63e2e8167877ea4166b126487288d732d7d5656ff29e92d34ee5` |
| 4C | 1 | `51975c94d7ef8076e9cb6f3ed34d4af6d80b289129a04aa9b133ef1dc0022155` |
| 4D | 2 | `71adcf7facd2790b76e6a78c0d6400b9833e04b71bc7597dc5260807bfbc0c92` |
| 4E | 1 | `c248465908eb95ee1e326d7c821d0bb37737fe067322330100764a0a674af724` |
| 4F | 1 | `7ea0b57e0eec0ab3bdc6e996b46967e9c341cae83407d9015dc0ec02ef51da91` |
