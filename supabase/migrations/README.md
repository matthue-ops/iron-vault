# Phase 1 manual migrations

**Prepared only; none executed or assumed applied.** Review [the complete coordinated cutover](../../docs/security/phase1-cutover.md) and [single progress tracker](../../docs/security/phase1-status.md). They supersede historical partial-stage holds and repeated prerequisite lists.

**One-file option:** [phase1_security_install.sql](../manual/phase1_security_install.sql) is an atomic combined installation for an untouched inspected schema, excluding optional 004, with preservation assertions. Use EITHER this bundle OR the individual path, never both. It was generated only; no SQL executed.

Run each approved file separately in numeric order, 001 through 015. The only optional file is **004**, which changes supabase_admin defaults and must be skipped if platform authority is unavailable. Never escalate managed-role membership. Existing 001/002/007/011/012 definition/policy guards must not be bypassed; if a file was already manually committed, verify that fact rather than rerunning it blindly.

| Number | Scope | Existing data effects |
| --- | --- | --- |
| 001 | API TRUNCATE removal | No record changes. |
| 002 | Existing function execution restrictions | Authenticated ordinary RPC/service execution retained. |
| 003/004 | Creator/public-schema future defaults | Existing objects unchanged; 004 optional. |
| 005 | Role/history direct-write protection | Authenticated RLS SELECT retained; no record changes. |
| 006/007 | Explicit report permissions and M4 isolation fix | New permission objects, corrected policy correlation; no historical rewrite. |
| 008/009 | Permission tenant FK and tenant/contact uniqueness | No merges/deletions; duplicates abort safely. |
| 010/011 | Receipt foundation and server financial APIs | Original ledger/request IDs retained; old RPC signatures validated through secure core. |
| 012 | Base write closure, safe views, scoped profile/settings/deactivation APIs | Adds enabled/default-true and disabled_at role fields; no account/history deletion. |
| 013 | Member wallet purchases and opaque daily pass tickets | No initial balance/history change; old unsigned QR codes cease authorizing entry. |
| 014 | Branch mappings, account jobs, real-address verification/recovery | Backfills six scoped identities from the snapshot; no Auth table writes or account recreation in SQL. Trigger attachment preserved. |
| 015 | Server report snapshots and atomic profile restore | No financial/credential restore or historical rewrite. |

001–015 require coordinated matching Edge/app cutover; do not publish old HTML against the closed base tables. The earlier 010/011 warning is resolved by including 012–015, not by applying 011 alone. See the runbook for exact secrets/configuration and the four functions to deploy only after separate authorization. SMTP settings already configured for Supabase Auth are not automatically available as Edge secrets.

Every file has a transaction and metadata verification; failures require ROLLBACK and review. A later failure does not undo earlier commits. Fix forward while preserving records; never restore public ALL policies, unsafe financial bodies or blanket grants. Files 009 and integrity changes can acquire write-blocking locks; use the scheduled maintenance window. Public-schema default cleanup alone cannot revoke global PUBLIC EXECUTE, so per-object ACLs are set explicitly. Only iv_visible_gyms() intentionally allows anonymous safe branding reads.

Read-only acceptance is in ../verification/phase1_acceptance.sql. Capture its V1/V2 preservation baseline before application and compare after; do not invoke mutating RPCs from SQL Editor as an authorization test. Test real RLS with actual authenticated/anonymous clients and dedicated approved fixtures. No SQL, Supabase call, reset, deployment or merge was performed by the agent.
