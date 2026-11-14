# Stage 1 — permanent member QR and unified entry verification

## What changes

Both permanent `IVC1|<random UUID>` cards and existing server-issued `IV1|<random UUID>` daily passes use a read-only verification request, then an explicit Approve Entry request. A scan alone no longer records entry. The verification screen shows the permitted gym member's photo (or a missing-photo ID prompt), name, display code, pass/expiry and entry status. Staff may request other ID. Approval is disabled if ineligible; there is no extra checkbox.

Approval re-resolves the credential in the selected gym, locks the member before the credential, rechecks status/pass/agreement/duplicate admission, and calls the existing locked `record_admission`. Existing audit, membership snapshot and subscription triggers still run. No wallet, payment, pricing, membership expiry or manual-check-in function is replaced. Entry still uses method `qr`, preserving current reporting and member entry feedback.

All entry methods share the existing member/date and attendance checks. A card admission also consumes any outstanding daily pass for that day. A daily ticket remains usable when a permanent card is revoked, if the member otherwise remains eligible and has not entered. Daily pass creation stays unchanged.

Existing and newly registered members receive an unguessable permanent credential in a private, RLS-enabled table; public member rows and profile serialization do not contain the token. The new-member trigger only inserts a credential. Existing data is not deleted. Credentials cascade only with the existing explicit member/gym deletion procedure, so they do not block approved purge operations. Revocation fields and one-active-card constraint prepare for Stage 2; card replacement UI is not part of this stage.

## App surfaces

- Member menu: **Member QR** opens a basic permanent-code view. This is not the Stage 2 front/back Physical ID or printing workflow.
- Admin member profile: **Member QR** opens that gym member's basic code view.
- Member roster: **Scan Member Card** performs read-only lookup and opens the existing profile. It never approves or records admission.
- Main scanner: paused during verification, optional sound cues, success only after server confirmation, and approximately 1.5-second cooldown after returning from verification. Wrong-gym codes return no member details; revoked codes return no profile. Permission and subscription errors fail closed.
- Auth/session changes and late responses cannot reopen a dismissed verification window. Approval cancellation is disabled while its result is outstanding; an uncertain outcome requires scanning again to check attendance before retrying.

## Manual SQL and deployment order

**The agent has not connected to or executed SQL against Supabase.**

1. Confirm migration **053** and all its prerequisites have already been applied. Do not reapply earlier SQL just because it appears in this sequence.
2. Arrange a short coordinated reception pause. Existing open tabs must refresh after deployment.
3. In Supabase SQL Editor, manually execute the entire **`supabase/manual/permanent_qr_verification.sql`** once, as one transaction. It is byte-identical to `supabase/migrations/202611140054_permanent_qr_verification.sql`. **Run one copy, not both.** The guard rejects reapplication.
4. Confirm success before deploying the matching app changes. Do not deploy the frontend ahead of the SQL; the new scanner fails closed if the APIs are absent.
5. Deploy the approved app branch through the normal review process, refresh reception/member tabs, and validate with synthetic test accounts in a test gym before general use.
6. Test a valid daily QR and permanent QR, deny/close without an entry, duplicate entry, expired pass, wrong-gym card, missing photo, authorized member lookup, and Manual Check-In followed by QR. Confirm reports, attendance and member entry feedback.

Important compatibility impact: `iv_redeem_member_pass(uuid,text)` now refuses direct redemption with a refresh message so an old tab does not bypass the new approval screen. Old reception tabs cannot automatically admit through that API after SQL 054. A frontend-only rollback does not restore the old scanner; coordinate any database rollback through a reviewed SQL change. Manual Check-In remains subject to its existing permissions and checks.

No existing QR subscription entitlement is expanded. Permanent and generated QR scanning/lookup require the existing operations and member-portal entitlements; dashboard-only gyms retain existing manual entry. Owner/staff role restrictions and disabled-account checks are enforced by the server. Profile navigation retains existing staff access rules; no new renewal privilege is granted.

## Verification

- `npm test`
- `PGLITE_MODULE=/path/to/@electric-sql/pglite node tests/database/permanent-qr-verification.cjs` — disposable embedded PostgreSQL with synthetic data, not Supabase. Tests actual migration and existing admission function; entitlement/agreement/subscription fixtures model the existing boundaries.
- `node tests/browser/entry-verification.cjs` — synthetic RPCs with actual scanner lifecycle and verification module; phone and desktop layouts, approval-only writes, denial, lookup, cooldown and stale-session cleanup.
- `node tests/browser/scanner-screen.cjs` — existing camera regression coverage.
- `npm run build:pages`

Database replay/competing approvals are exercised sequentially in embedded PostgreSQL. Independent concurrent Supabase sessions and physical camera/audio behavior still need a controlled deployment smoke test. The database member row lock, not camera debounce, provides entry serialization. No fixed check-in speed or resource savings are claimed.
