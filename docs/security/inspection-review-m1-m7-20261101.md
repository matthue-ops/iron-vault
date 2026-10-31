# M1–M7 authorization inspection review

The supplied CSVs are inspection evidence, not instructions to execute SQL. No SQL was executed, Supabase accessed, records reset, deployment performed or PR merged. These are snapshot findings; no migration is assumed applied.

| Evidence | Verified finding | Consequence |
| --- | --- | --- |
| M1 | Seven Auth accounts, all with email, confirmed email and password credentials. | Preserve all accounts; no reset is justified by these counts. |
| M2 | Zero duplicate contact-email groups within a tenant. | No deduplication is needed at this snapshot. |
| M3 | Four member links, two scoped owner links and one unscoped Super Admin link; no staff bindings. | Existing role vocabulary matches the browser guard. Real staff integration still needs a user-controlled fixture. |
| M4A/C | Five role/history tables have broad API table and column grants, including TRUNCATE. RLS is enabled, not forced; postgres owns them. | Revoke redundant direct writes and TRUNCATE without removing authenticated SELECT or definer RPC execution. Grants alone do not establish effective INSERT/UPDATE/DELETE: M4B has SELECT-only policies. TRUNCATE is not protected by RLS. |
| M4B | Financial and attendance policies compare r.member_id=r.member_id and r.tenant_id=r.tenant_id inside an uncorrelated role subquery. | **Critical:** an authenticated member with a populated link can read other members' records across tenants. Correlate both columns to the requested outer row and require role=member. The financial helper also grants ordinary staff blanket reporting; replace it with explicit administrator-granted tenant permission. |
| M5A | anon/authenticated lack CREATE on public. | Preserve this restriction; creator membership evidence is still missing. |
| M6 | Enabled ensure_rls event trigger calls public.rls_auto_enable for table creation. | Preserve this platform/application dependency. Explicitly enable RLS on the new private table because the reviewed event function targets public only. |
| M7 | postgres and supabase_admin each have public-schema default ACLs for tables/functions granting anon/authenticated broad privileges. | Separate creator-scoped default migrations; preserve service_role and owner rights and all existing RPC grants. |

## Prepared remediation and limits

Migration 005 protects role bindings and four history/session tables against direct API writes, including explicit column grants, while retaining authenticated SELECT and existing postgres SECURITY DEFINER writers. Migration 006 adds a private permission table, narrowly granted helpers, administrator-only grant/revoke/list RPCs, current staff-role checks, self-grant rejection and mandatory audit. It changes no existing balances, accounts, history or role bindings. Tenant foreign-key attachment awaits inspected owner constraints/types; permission reads independently require the current tenant and staff link. New Auth foreign keys use standard Supabase UUID IDs. Migration 007 alters the two existing SELECT policies with normalized-definition drift guards. Members retain their own linked financial/attendance records; gym owners and global Super Admin retain intended access. Ordinary staff retain tenant attendance access, while whole-gym financial access requires an explicit current grant.

The report browser now asks the backend for permission before queries/render/print/credit display and after identity changes, scopes queries by tenant, clears denied cached views and includes ledger totals even where a member profile is absent. Administrator controls use the scoped permission RPCs. Missing migration APIs fail closed; coordinate manual database confirmation before releasing these report changes. This is not evidence that hosted RLS works yet.

Migrations 003/004 remove only public-schema API defaults for their respective creators. **Per-schema revocation cannot cancel global/built-in PUBLIC EXECUTE on functions.** Each new function must revoke PUBLIC/anon and deliberately grant intended execution in the same transaction, as 006 does. These files do not globally modify Supabase-managed schemas, alter platform role memberships, affect existing objects or remove legitimate authenticated RPC access. 004 is optional pending executor authority and platform compatibility; do not escalate privileges or block urgent 005–007 on it. A native permission failure is a stop condition, not a reason to assume managed-role authority.

## Remaining evidence and release gates

- T1–T5: trigger attachments and additional trigger bodies, constraints/FKs, column types/defaults and standalone indexes from 20261101_trigger_dependencies.sql. These block safe financial RPC replacement, full owners/members RLS, identity lifecycle and retained-history deletion work.
- Targeted creator/executor membership and namespace compatibility results from 20261101_default_acl_compatibility.sql; M1–M7 need not be repeated.
- Deployed provision-gym-tenant, iv-create-member and iv-admin-correct-member-email source, imported helpers, JWT verification and binding names; retrieval steps are in supabase-prerequisites.md.
- Non-secret Auth confirmation, recovery, redirect, session, provider, SMTP status and hooks configuration from that checklist. Also report Data API exposed schemas and max-row setting; do not expose ironvault_private through the Data API.

Existing owners/members public ALL policies, client-influenced financial RPC amounts/idempotency, legacy credential fields, generic activity text/member financial summaries, signed-pass enforcement, secure import/restore and identity provisioning are not fixed by this package. Report isolation does not mean every financial value elsewhere is hidden. No reset is necessary or prepared.

## Required verification after separately approved manual application

Return each migration's metadata verification and exact committed file names. Use dedicated test identities, never a service-key/SQL Editor session, to verify API authorization: anonymous denied; member A sees only A in its tenant; member B and another tenant denied; owner sees only its tenant; global Super Admin sees intended tenants; ungranted staff denied reports but retains check-in; owner grants staff in the same tenant, staff gains reports; wrong-tenant grants and self-grants denied; revocation/role removal blocks subsequent refresh/print. Test direct role/ledger mutation and TRUNCATE denial without actually truncating data. Exercise legitimate authenticated top-up, purchase, check-in, event/session logging and signup only in an explicitly approved test workflow; preserve balances/history or record intentional test transactions. Verify duplicate financial requests and manipulated amounts during the later RPC stage. Test logout, identity changes, expired sessions, browser Back, missing permission API, account recovery and registration. No hosted tests have been run.

Local validation: 75 Node tests passed; all 10 SQL files and contained SQL/PLpgSQL bodies parsed with pglast 8.7. Static/mocked checks cannot prove database privileges, planner resolution, trigger effects or transactional behavior.

Local Chromium checks with mocked Supabase and external requests passed: granted staff can render ledger totals, ungranted staff are denied, and revocation blocks printing. No Supabase endpoint was contacted.
