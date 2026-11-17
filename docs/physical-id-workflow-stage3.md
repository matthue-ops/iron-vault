# Held bundle Stage 3 — Physical ID workflow

Based on main `ebd2df5` after Reports performance Stage 2. The user approved the inspected database scope before implementation. **Preserving working member, financial, attendance, subscription, permission and gym-isolation behavior is the priority. No SQL has been executed against Supabase. No merge or deployment is automatic.**

## Card windows

| Actor | Primary actions |
|---|---|
| Member | Request Physical ID; Report Lost Card |
| Owner/admin | Download ID; Request Printed Card; Report Lost Card |
| Staff | Only the corresponding explicitly granted actions |
| Provider | Download ID |

Physical IDs sits immediately after My Account in the gym menu and after the existing account/security item in the member menu, with an ID-card icon. Existing profile inspection shortcuts remain. The existing member account/security label and handler are preserved.

The window shows a compact request status instead of a stack of old request cards. A pending submission replaces the member request button, preventing duplicate active submissions. Requests/production management is in a separate Requests view, preserving local readiness/issuance and provider production status controls for authorized users. Direct Download ID does not require a request or route approval and never marks a card issued. Request Printed Card sends an awaiting-review request to the provider, or creates a new provider production request if none is active; it neither rotates a QR nor charges the wallet. Already active local/provider production requests must be managed or cancelled rather than silently rerouted.

Downloads use the existing print-ready bundle and current credential. Incomplete production details leave the button disabled with a visible explanation. Current operations/portal entitlement checks, explicit download permission and required photo/branding/public contact details remain enforced by the backend. A stale or revoked version cannot receive a new download authorization. Production files are generated in browser memory, not stored publicly. The audit records authorization, actor, card version and time; it does not prove the browser saved a file. Already authorized/in-flight/saved files cannot be recalled; revocation makes their old QR invalid.

One **Activity history** section is collapsed by default. Opening or refreshing it replaces its entries; it never appends duplicate history sections. Sensitive content clears on sign-out/account/gym changes and late responses are rejected. Existing artwork, QR quiet zone, print sizes and both-side output are unchanged. Templates/background editing and single-card flip previews remain in Stage 4. Portrait, landscape and desktop controls remain scrollable and touch accessible.

## Lost cards

### Member reports first

1. Confirm that the current QR will stop working and acknowledge the possible replacement fee.
2. In one transaction, lock the member then card; revoke the old credential, obsolete its pending production requests, resolve obsolete notices and create one replacement request attached to the old card in `awaiting_replacement`.
3. The preview shows **Lost card reported / awaiting replacement**, with **no usable permanent QR**. No new credential is issued by the member action.
4. An owner or staff member with both management and replacement permissions sees **Create Replacement QR**.
5. That transaction locks member → old card → request, validates its revision, creates exactly one new active version linked through `replaces_card_id`, and updates the same request to `awaiting_gym_review`. The preview then shows the new QR; direct download/provider production become available subject to their own permissions.

The member cannot create the replacement. Repeated submissions and retries cannot revoke a newer card or create another credential accidentally. Operation identities are tied to actor, gym, member, action and expected card version. The client persists only opaque identifiers and confirmations for uncertain retries, never a QR/image. A retry of the same operation returns its original result. A new stale operation fails without changing the current card.

### Gym reports first

The existing confirmed owner/permitted-staff combined revoke-and-replace action remains atomic. If a member has already reported loss, the gym must use Create Replacement QR for that request rather than report the same loss again. Provider card actions exclude loss, replacement and initiating member/gym requests; existing provider production transitions remain available in Requests.

The existing restricted-owner security exception is retained: owners can revoke/replace while production access is unavailable, using metadata-only security views. This never unlocks downloads, portal operations or subscriptions. Members and staff keep their existing access requirements.

Old QR codes stay revoked even if found. No identity, membership/expiry, wallet, payment history, attendance or today's used daily allowance is reset. Eligible generated daily QR remains usable during the pending replacement, with the original agreement and shared-admission checks. This workflow never creates a payment, debits a balance, approves membership or records attendance.

## Exact database scope

Migration `202611180056_physical_id_workflow.sql`:

- Extends the existing request status constraint and active-request unique index with `awaiting_replacement`. No records are deleted or credentials rotated on installation.
- Preserves the existing Physical ID query/action implementations as private `physical_ids_056_base` / `physical_id_action_056_base` functions, then wraps the same public signatures. No client execution is granted on the private bases.
- Adds capability version 3, pending metadata without a QR, `report_loss`, `create_replacement`, `request_provider` and `download_direct`. Legacy member `replace` is safely interpreted as reporting loss; owner/staff combined replacement and existing request transitions/bound downloads retain their established guarded implementation.
- Reuses the existing card, request, event, retry-operation and notice tables and notification helpers. No new table, public production bucket or Edge Function is added.
- Reuses `physical_ids_manage`, `physical_ids_download` and `physical_ids_replace`. No grants are automatically added. Download permission alone does not grant management/replacement; replacement requires management plus replacement permission.

Admission/verification, generated QR, Manual Check-In, financial writers, staff permission-management and existing notification feed definitions are unchanged. Tests fingerprint those functions before/after 056. All new mutation paths keep member-first locking and auditable retry identities. Failed loss/replacement transactions roll back in full.

## Manual SQL and frontend order

1. **Confirm** migrations through `055` are already installed. Do not rerun 054 or 055 blindly. No live installation status is assumed from the repository.
2. Manually execute **only** `supabase/manual/physical_id_workflow.sql` once. It is byte-identical to the numbered migration `supabase/migrations/202611180056_physical_id_workflow.sql`. **Do not execute both copies.** Missing prerequisites or reapplication are rejected before changes.
3. After successful SQL completion, release the matching Stage 3 frontend and refresh open sessions before using the revised workflow. No Edge deployment is required. The frontend checks capability version 3 before exposing actions and gives setup guidance if 056 is unavailable; it never falls back to direct writes or the old member replacement behavior.
4. On disposable accounts, verify member reporting → revoked old QR/no pending QR → authorized replacement → download/production; test the daily allowance and scan a printed proof. Preserve the separate local/provider request status actions.

Optional read-only version check for the operator:

```sql
SELECT to_regprocedure('ironvault_private.physical_ids_056_base(text,text,jsonb)') AS workflow_056,
       to_regprocedure('public.iv_physical_id_action(text,text,jsonb)') AS action_api;
```

A failed migration rolls back atomically. After pending losses exist, the old 055 frontend cannot manage the new waiting state correctly. Prefer a reviewed forward fix with the compatible frontend. **Do not restore revoked tokens, undo replacements or delete audit/request history as a rollback.** No destructive down migration is supplied. Previously downloaded files remain outside recall.

## Local verification

Use disposable tools, for example the existing `/tmp/iv-stage2-tools/node_modules`, via `NODE_PATH`. No real member records, live Supabase calls or financial operations are used.

```sh
npm test
npm run build:pages
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/database/physical-id-workflow.cjs
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/database/physical-membership-ids.cjs
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/database/permanent-qr-verification.cjs
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/browser/physical-id-workflow.cjs
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/browser/physical-membership-ids.cjs
NODE_PATH=/tmp/iv-stage2-tools/node_modules node tests/browser/entry-verification.cjs
```

Test tools: PGlite 0.3.14, Playwright 1.56.1, pdf-lib 1.17.1, JSZip 3.10.1, jsQR 1.4.0, pngjs 7.0.0, `/usr/bin/chromium` and `pdftoppm`. Database tests execute actual 054/055/056 definitions against synthetic data, including injected transaction failures, serialized conflicting operations, old QR/download rejection, permissions and unchanged wallet/membership/attendance/allowance. Browser tests cover 320/390/844/1280 px, rotation, menus, a single history section, cancellations, unknown committed responses, missing migration, separate production management, stale export denial and cleanup. The retained renderer checks decode PNG/PDF QR output at intended print resolutions. A multi-session PostgreSQL concurrency smoke test is an appropriate preproduction acceptance check; embedded tests do not simulate independent PostgreSQL server sessions.
