# Physical membership IDs — Stage 2

## Base and scope

Implemented on `feat/physical-ids-stage2`, based on main `ba26c97` (PR #65 merging Stage 1 commit `83a368e`). Stage 1 is present in this checkout. **Its installation in your Supabase database has not been confirmed.** No SQL has been executed against Supabase, and nothing has been merged or deployed by this work.

This stage adds physical cards, scoped request queues, production exports and atomic lost-card replacement. It does not charge fees, deduct credits, create payments, approve membership, alter subscription entitlements, or record attendance. Existing verification/admission SQL is unchanged. The existing Stage 1 “Member QR” control delegates to this workspace when loaded; scanner behavior stays separate and unchanged.

## Production readiness and card design

The same current permanent `IVC1|…` credential powers the preview and production artwork. Front: profile photo, name, display number, permanent QR, gym logo/name/address. Back: return instructions, public gym address/contact, named-member/valid-pass/verification/lost-card instructions. No expiry, balance, birth date, or member home address is printed. Renewal retains the same card. The card is labelled “Membership Card”; it is not a government ID.

Before production, supply a real member photo (at least 236×236 pixels for the 20 mm photo at 300 DPI), gym logo, member name/display number, gym name, published public address and at least one public contact. Upload images through the existing profile controls. Existing optimized 256 px member photos qualify. Missing/unavailable/low-resolution photos have explicit prompts; no photo is fabricated. Draft requests and previews remain available when details are incomplete; export is blocked until the renderer can load and fit the required details. Very long names/addresses/contact details must fit at the minimum readable font size; they are never silently truncated. A legacy arbitrary external image URL must be reuploaded through the existing image controls before production.

Gym address, public email and phone come from the gym's **published** legal/profile details, not unpublished edits. Branding uses the existing gym name, logo and accent. Body text stays dark on white for contrast, even with a light accent.

### Download bundle

- CR80 trim: **85.60 × 53.98 mm**, landscape, both sides with the same top edge.
- Front/back PNGs: **2022 × 1275 px**, nominal 600 DPI. Import at the stated physical dimensions; PNG DPI metadata is not relied upon.
- `card-local-actual-size.pdf`: two exact-trim-size pages, front then back.
- `card-production-3mm-bleed.pdf`: two **91.60 × 59.98 mm** pages with 3 mm white bleed and exact CR80 TrimBox.
- At least 2.5 mm content safety margin. Artwork/photo/text rasterized at 600 DPI; the PDF QR is additionally drawn as vector modules.
- QR area: 26 mm square, white, four-module quiet zone, high error correction. Decoration does not overlap it. No mirroring or fit-to-page.

Download authorization rechecks current credential, request revision, route, permissions and a hash of the current member/gym details. The browser builds files in memory, requests authorization/audit immediately before emitting the download, and discards stale/sign-out responses. No public bucket, public file listing, signed production URL or persisted production blob is introduced. The audit records the actor UUID, time, card ID/version relationship, request and format; it never records a QR token.

A successful audit means **download authorized**, not proof that the browser saved or a printer produced it. Downloading never changes issuance. Already authorized/in-flight or saved files cannot be recalled. Revocation makes their old QR invalid. Screenshots and copying a visible QR cannot be prevented. Entry still requires the existing staff verification and eligibility checks.

Print at actual size (100%), disable automatic scaling, keep front/back orientation consistent, and test duplex registration on the intended printer. The automated tests decode the 600/300 DPI PNG and a PDF rendered at 300 DPI; a **physical proof scan and alignment check** is still required before producing a batch.

## Access

| Actor | Preview | Requests/review | Production download | Lost-card replacement |
|---|---|---|---|---|
| Member | Own card, including pending membership | Own initial/replacement request and status | No controls | Own card, explicit confirmation |
| Owner/admin | Own gym only | Initiate/review/local/provider route | Approved local production | Own gym |
| Staff | Existing Stage 1 gym authorization | Explicit `physical_ids_manage` | Separate `physical_ids_download` | Both `physical_ids_manage` and `physical_ids_replace` |
| Provider | Select gym; scoped member search/inspection | Initiate on behalf; manage forwarded production | Forwarded provider route | Selected gym; confirmation |

The three staff flags start ungranted. Download permission alone can download an already approved local request; it does not grant review or replacement. Replacement cannot be enabled without management. The old staff permission wrapper remains underneath the extension, including refund, report and Revenue Today behavior. Existing staff state/role/subscription checks remain enforced. A suspended/removed staff member has no access.

Normal card access/production respects current operations and portal access; global provider status does not bypass production entitlements. The explicitly approved exception is owner/provider **security-only** lost-card revocation while restricted: it shows identity/card-version metadata without exposing a preview QR and creates an awaiting-review replacement request. It cannot produce a card while restricted. This does not expand subscription plans.

Member menu: **Physical ID**. Gym/provider menu: **Physical IDs**. Gym member profile and provider member inspection include **View Physical ID**. QR lookup remains separate from check-in. Pending member previews/requests never approve membership or confer entry.

## Requests and notifications

All submissions require acknowledgement:

> A physical card or replacement may incur a fee. Your gym will confirm any charges before production.

There is one active request per member/gym. A stable operation UUID, member/card identity and request revision protect retries. The browser retains only opaque identifiers/status/confirmation fields in session storage for an uncertain retry, never card tokens or artwork. Reopen and retry to resolve an interrupted submission. Different data cannot reuse the same operation UUID. Definitively failed submissions can be corrected and resubmitted.

| Current state | Gym owner / permitted management staff | Provider |
|---|---|---|
| Awaiting gym review | Print locally; send to provider; reject; cancel | Wait for gym review |
| Printing locally | Ready for collection; cancel | No action |
| Sent to provider | Cancel | Start production; reject; cancel |
| In production | Cancel | Production complete; cancel |
| Production complete | Confirm receipt → ready for collection; cancel | Complete |
| Ready for collection | Explicitly mark issued; cancel | No issuance authority |
| Issued / rejected / cancelled / obsolete | Closed; start a new eligible request or report loss | Closed |

Local requests need no provider intervention. The provider queue shows forwarded jobs; the selected member's inspection also shows local/awaiting-review history, without granting provider actions on those routes. Requests forwarded to the provider are separated from local jobs; an approved local request cannot be exported by the provider queue and a forwarded request cannot be exported as a local job. Fee collection, if any, uses the existing independent payment process; this workflow never creates a charge.

Existing compact notification feeds receive distinct physical-card notices: gym on submission, provider on forwarding, gym on production completion, member on relevant progress. State changes resolve obsolete notices; operation replay generates no repeated notifications. Existing announcements, status, financial and subscription notices remain in their original feeds and read flows. Opening a notice can open the corresponding Physical ID workspace.

## Replacement and preservation

“Report Lost Card” requires:

> Your current card will stop working. A new card QR will be created. Continue?

The same transaction locks the member first (matching admission), then the current card and affected request. It revokes the old credential, inserts exactly one replacement active credential/version, links the replacement, marks active old requests obsolete, resolves their notices, records safe actor/version history, and creates a replacement request. A failure rolls back all these changes. The old QR never becomes valid again, even if found. Retrying the committed operation returns its original result without another rotation.

Member identity, plan/expiry, wallet, financial/history rows and daily entry usage remain untouched. Generated daily QR and Manual Check-In retain their original shared allowance. A lost-card replacement cannot reset today's used entry. A stale print/transition/export cannot act on the revoked version.

## Exact database changes

`055` is a transaction that:

1. Adds opaque `card_id`, per-member `version`, `replaces_card_id`, revocation actor/reason and supporting constraints to the existing private Stage 1 card table. Backfills metadata only; **existing tokens are not rotated**.
2. Creates four private RLS-protected tables: `physical_id_requests`, `physical_id_events`, `physical_id_operations`, `physical_id_notices`, with gym/member deletion cascades matching existing purge behavior. No client direct table grants.
3. Adds authenticated scoped APIs `iv_physical_ids` (queries) and `iv_physical_id_action` (mutations), with private authority/snapshot/production/notification helpers.
4. Preserves and wraps the existing `iv_staff_access`, `iv_account_announcements`, `iv_member_announcements` and `iv_provider_console` functions to extend explicit staff keys and notification results. Original definitions move to private `*_055_base` names, with client execution revoked. Financial, legal, subscription, daily QR, manual check-in and Stage 1 verification/approval functions are not replaced.

No Supabase Edge Function, new storage bucket, public production files, cron job or subscription tier is added.

## Manual SQL and release order

1. Confirm the existing prerequisites through `053` are installed, then confirm Stage 1 `054` is installed. If `054` has **not** been installed, manually execute **only** `supabase/manual/permanent_qr_verification.sql` (identical numbered file `202611140054_permanent_qr_verification.sql`) after its prerequisites. Do not reapply an installed migration.
2. Manually execute **only** `supabase/manual/physical_membership_ids.sql` once, after confirmed `054`. It is byte-identical to `supabase/migrations/202611160055_physical_membership_ids.sql`. These are two copies of the same update: **do not execute both**. The migration guards against missing Stage 1 and reapplication.
3. Confirm completion before deploying the matching Stage 2 frontend. SQL can be applied before frontend release. No merge or deployment is performed automatically.
4. On a disposable/test gym, verify published details/photos, grant only needed staff flags, test member/local/provider workflows, then scan a physical proof. Verify old-card rejection and same-day allowance preservation with synthetic accounts. Do not use real financial operations as tests.

Optional read-only installation checks (not run against Supabase by the agent):

```sql
SELECT to_regprocedure('public.iv_approve_entry_qr(text,text)') AS stage1,
       to_regprocedure('public.iv_physical_ids(text,text,jsonb)') AS stage2_query,
       to_regprocedure('public.iv_physical_id_action(text,text,jsonb)') AS stage2_action;
```

### Rollback limits

A failed installation rolls back as one SQL transaction. After successful installation, reverting the frontend can restore Stage 1's basic view while leaving additive SQL installed. **Do not restore old QR tokens, drop the card registry, or delete request/audit history to undo a replacement.** Revoked credentials must remain revoked. Once requests/replacements have been used, a database rollback requires a reviewed forward migration preserving versions, history and revocations; no destructive down migration is supplied. Previously saved files remain outside recall. Never apply `055` twice.

## Reproducible local validation

All database/browser tests use disposable embedded PostgreSQL and synthetic accounts/storage/RPC responses. No Supabase URL, secret, real member record or live financial operation is needed.

```sh
npm test
npm run build:pages
# Install test tools into a disposable directory, outside the application package.
npm install --prefix /tmp/iv-physical-tests --no-save --package-lock=false @electric-sql/pglite@0.3.14 playwright@1.56.1 pdf-lib@1.17.1 jsqr@1.4.0 pngjs@7.0.0 jszip@3.10.1
NODE_PATH=/tmp/iv-physical-tests/node_modules node tests/database/physical-membership-ids.cjs
NODE_PATH=/tmp/iv-physical-tests/node_modules node tests/database/permanent-qr-verification.cjs
NODE_PATH=/tmp/iv-physical-tests/node_modules node tests/browser/physical-membership-ids.cjs
NODE_PATH=/tmp/iv-physical-tests/node_modules node tests/browser/entry-verification.cjs
```

Browser tests expect `/usr/bin/chromium` and `pdftoppm` (Poppler) on the local machine. Renderer dependencies are pinned and vendored for production, with licenses, so production exports require no CDN. PGlite exercises transactional rollback and serialized conflicting actions with real SQL; a multi-session production PostgreSQL scan/replacement concurrency smoke check remains appropriate before rollout.
