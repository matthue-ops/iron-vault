# One-file SQL Editor package

Open **phase1_security_install.sql** and review [the cutover guide](../../docs/security/phase1-cutover.md).

- The file combines migrations 001–015 except optional 004 into **one atomic transaction**.
- Use it only when no earlier Phase 1 migrations have already been applied. Otherwise use only the remaining individual migrations after confirming their status. **Never run both installation paths.**
- Stop app writes during the maintenance window. The package fingerprints existing accounts, role links, balances, entitlements and histories before/after; unexpected differences abort installation. Fingerprints are internal temporary data and no password hashes are selected.
- Optional supabase_admin default hardening remains a separately reviewable file; no managed-role escalation is attempted.
- After review/approval, the owner manually pastes/runs the file in Supabase SQL Editor. If it errors, issue ROLLBACK and return the error; do not modify guards or reset records. A successful run ends with COMMIT and read-only metadata checks.
- SQL creates database objects only. The matching four Edge Functions, private mail bindings and browser assets must also be deployed through the separately authorized cutover. None was deployed by the agent.

Generated deterministically from individual source files with `node scripts/build-manual-sql.cjs`; `--check` verifies freshness without executing SQL. Do not edit the generated file by hand. All source files remain independently reviewable.

For an installation already through 017, `usability_update.sql` is the reviewed 018–020 delta for short codes, staff sign-in/contact and report metadata. Do not run the initial installation again. Generate/check this delta with `node scripts/build-usability-sql.cjs [--check]`.
