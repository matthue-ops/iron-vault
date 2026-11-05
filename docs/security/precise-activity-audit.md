# Precise Activity audit rollout

This change styles admin desk confirmations and feedback, moves the existing header actions into a menu, and adds authoritative Activity records for wallet top-ups, membership purchases, manual/QR admissions, changed member fields, staff names, and contact-email requests/completions. Existing role permissions remain in effect.

## Manual deployment order

1. After migration 032, run `supabase/manual/precise_activity_audit.sql` once in the gym project's Supabase SQL Editor. This is the exact copy of migration 033. It adds nullable audit metadata columns and private helpers/triggers, and updates profile/contact audit functions. No historical business or audit rows are rewritten. Existing staff-contact correction still invalidates its old verification tokens, as before.
2. Update these generated single-file Edge functions through the dashboard: `supabase/dashboard/iv-branch-auth.ts` (Verify JWT OFF) and `supabase/dashboard/iv-admin-correct-member-email.ts` (Verify JWT ON). Keep their existing environment secrets. The new email-change gateway requires migration 033 first.
3. Merge the frontend branch and let Cloudflare Pages deploy. Refresh open browser sessions.

The agent does not execute SQL or deploy Edge functions. Other generated dashboard bundles are refreshed to match shared source but do not need deployment for this feature.

## Recorded evidence and access

Money events originate from successful saved transaction receipts. Request replays do not insert another receipt or successful audit entry. Wallet before/after and purchase wallet/cash amounts come from that receipt's exact operation; top-ups do not invent a payment channel. Admissions originate from attendance inserts with the operator identity and method. Audit writes share the business transaction, so a failed audit insert rolls it back.

Changed profile fields include their old/new values. Unchanged profiles produce no entries; photo changes record presence flags without image content. New records snapshot the operator's name and role at the event, preserving attribution through later renames. Email requests identify the operator separately from subsequent recipient email proof; older requests without recorded initiators say so. Passwords, verification tokens and private authentication aliases are excluded.

Activity remains under the existing financial Reports permission. A restrictive SELECT policy also applies that same permission to direct reads of the activity table because the new details include amounts and contact information. CSV, print and spreadsheet exports use the same recorded values as the table.

Older generic entries remain unchanged: missing historic actions and initiators cannot be reconstructed reliably. Unrelated existing audit/session event types retain their current behavior.

## Validation and limits

Automated checks cover dialog cancellation, identity changes, money/retry flows, menu permissions, audit SQL contracts, report snapshots and exports. SQL is parsed without execution. Live database execution, concurrent transactions and Edge delivery must be checked after the manual rollout: test one top-up and retry, a purchase, manual and QR entries, a changed and unchanged profile, and both partial/completed email proofs. Verify staff with Reports access can view details and staff without it cannot.
