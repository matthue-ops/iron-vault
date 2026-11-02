# Super Admin tenant purge

Purge is separate from subscription expiry and suspension. It permanently removes the selected tenant's database records and dedicated Supabase Auth identities. Outstanding wallet credit is shown in the review, but purge does not refund money. The UI requires `PURGE <exact tenant ID>` and the current global Super Admin's password. Owner/staff/member sessions cannot invoke it. The service-only SQL API accepts an actor verified by the Edge function; it is not granted to browser roles.

## Manual rollout

1. With migrations 001–016 already installed, manually run only `supabase/migrations/202611010017_super_admin_tenant_purge.sql`. This installs the API and empty job table; it does not call purge or remove any existing record. Do not rerun the full installation bundle.
2. Create the Edge function named exactly `iv-purge-tenant`. Paste all of `supabase/dashboard/iv-purge-tenant.ts` into its `index.ts`, deploy, and keep Verify JWT **ON**. Existing Edge secrets and origin allowlist apply; no new secret is required.
3. Review the new application deployment, then promote it in the `iron-vault` Vercel project for `ironvaultph.vercel.app`. Leave the PR Draft until acceptance is complete. No agent deployment or live deletion has occurred.
4. First exercise this action only on an intentionally disposable test tenant. Verify other tenants and the global Super Admin still work. Review table/role access separately before using this irreversible action on real records.

## Behavior and boundaries

- Preview shows gym name/ID, members, accounts, ledger, attendance, activity and session counts, and outstanding credit. The start transaction checks that this review still matches the current data. A stale review is rejected.
- One database transaction deletes the tenant's receipt records, daily QR tickets, staff report permissions, email-action tokens, provisioning jobs, ledger, attendance, sessions, activity, branch mappings, roles, members, and gym. Foreign-key conflicts abort the transaction instead of broadening its scope or deleting another tenant's records.
- Auth accounts are removed afterward through Supabase's supported Admin API, never through SQL Auth DML. At most 20 accounts are processed per invocation. Global Super Admin and accounts linked to another tenant are excluded. Before deletion, remaining application foreign-key references are checked; shared/historically referenced identities are preserved.
- If Auth cleanup fails, the durable private job retains target IDs, review summary and remaining account IDs. **Resume pending purges** remains available even after the gym row disappears. Any currently enabled global Super Admin may resume, again with password proof. Completion removes the temporary job. A failure cannot restore already purged data; no false rollback claim is made.
- External exports, Brevo mail logs, infrastructure backups and hashed anti-abuse counters are outside this application-data purge. It does not erase data from other systems or promise removal from provider retention/backups.
- No automatic purge runs on subscription expiry or nonpayment. Suspension remains the reversible option.

Local validation covers unauthorized roles, exact confirmation, bad password, successful Auth cleanup, partial cleanup/resume, shared identities, and UI confirmation/password clearing. SQL and PL/pgSQL were parsed only; database execution and disposable-tenant acceptance remain owner-run work.
