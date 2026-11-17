# Physical ID appearance — Stage 4

Scope: card artwork only. Existing request/replacement workflow, staff flags, admission, wallet, payments, membership and subscriptions stay intact. No SQL was executed against the live database. A merged branch does not establish that any earlier migration was installed.

## Manual installation

1. Confirm migrations through **056** are installed, including private image storage 047 and Physical IDs 054/055. Do not rerun them blindly.
2. Execute **only** `supabase/manual/physical_id_appearance.sql` in Supabase SQL Editor, as one complete transaction. This is byte-for-byte identical to migration `202611180057_physical_id_appearance.sql`; do not execute both.
3. Deploy this branch's frontend through the normal reviewed process, then refresh existing tabs. No automatic deployment or merge is performed.
4. As gym owner, open Physical IDs → select member → Customize design. Choose template/colours, optionally upload backgrounds, preview both sides, then Save design.
5. Verify a downloaded front/back proof at actual size and scan the physical print before batch production.

Migration guards stop an incomplete prerequisite or repeat installation. With no saved design, existing cards keep the classic artwork. Without 057 the frontend retains normal Stage 3 previews/actions and does not offer customization. After 057, production authorization requires the refreshed Stage 4 frontend; older open tabs receive a refresh error rather than exporting artwork that ignores the saved design.

## Templates and production requirements

Classic is light and economical; Modern has a stronger brand band; Premium uses a dark background and subtle pattern. Primary/accent colours affect decoration, while fixed light/dark text and an at-least-85% readability overlay protect contrast. Premium remains dark. All templates retain the existing required content and exact protected white QR rectangle with four-module quiet zone. Backgrounds cannot cover the QR.

Upload PNG, JPEG or WebP, at most 8 MB/24 megapixels. The browser decodes and re-encodes a single raster image, strips metadata and caps the longest edge at 2022 pixels. The private bucket enforces a 4 MB limit and accepted MIME types; no arbitrary URL or SVG is accepted. File headers/MIME alone are not proof of image validity: rendering must successfully decode the stored image before export. Unavailable files block production. Horizontal/vertical position selects the cover crop; reset returns to the template background.

Prefer landscape backgrounds of **2022 × 1275 px** or larger source artwork. Effective resolution below 300 DPI after cropping is flagged and blocks production until replaced/reset. A real member photo, gym logo, name, member number, published gym address and contact remain required. No photo is fabricated.

Output remains CR80 **85.60 × 53.98 mm**, 600-DPI front/back PNGs, a two-page actual-size PDF and a two-page 3 mm white-bleed PDF with exact TrimBox. Keep 3.5 mm content safety margins, print at 100%, and test duplex alignment. Downloads always include both sides, irrespective of the currently visible preview side. This is a gym membership card, not government identification.

## Access and data changes

- Private `physical_id_designs`: one design per gym, revision, actor and update time. The owner saves explicitly; staff/provider/member cannot edit. Existing staff manage/download/replace flags are untouched.
- Private `physical_id_backgrounds`: opaque upload reservation IDs, gym, actor and time. Private `iv-card-backgrounds` bucket; current background reads are gym-role scoped, provider may read, uploads are owner-only and time-limited. No card QR, member photo or rendered production file is stored here.
- Authenticated `iv_physical_id_design` exposes owner get/reserve/save/cleanup/ack operations; direct table writes are denied. Duplicate identical save retries succeed; conflicting stale revisions fail.
- Shared card snapshot now includes design/revision. Both existing download paths use that same snapshot hash. Design saves and export authorizations share a transaction lock; stale files prepared before a design change cannot receive authorization. Existing request revisions, credential locks and entitlement checks remain enforced.
- Export actor/time auditing stays in the existing physical ID events. Saving a design does not regenerate credentials, issue a card, create a request, charge, activate membership or record entry.

Unreferenced upload reservations are durable cleanup records. On the owner's next editor visit, files older than one hour are removed and acknowledged; failed cleanup remains queued. This is opportunistic cleanup, not a scheduled background service. If a gym is permanently purged, its background reservation records intentionally remain for controlled provider/storage maintenance, because cascading metadata deletion would orphan private objects. Do not delete current background objects directly.

## Interaction and compatibility

One card side is visible at a time. Front/Back buttons work with keyboard/touch; horizontal swipes and desktop double-click flip it. Rotation/resizing preserves the selected side and proportions. Landscape uses the available wider layout. Members still have no production download controls; screenshots cannot be prevented. Sign-out, account/gym changes and late-response protection also cover editor artwork.

Previously downloaded cards/files cannot be recalled. Design edits do not invalidate their QR. Only the existing lost-card/revocation workflow invalidates credentials.

## Rollback

Do not drop private tables or the bucket as a routine rollback. Saved designs/files require retention or an explicitly approved cleanup plan. A frontend-only rollback to Stage 3 will cause production download refresh errors on migration 057, intentionally preventing wrong-design exports. Admission and existing card credentials do not depend on the editor. Prefer a forward fix; restoring old snapshot/download definitions requires coordinated SQL and frontend rollback, and loses design-revision validation. Never rerun 055/056 to undo this migration.

## Local checks

Run unit tests/build and the synthetic PGlite/browser suites: `physical-id-appearance`, existing `physical-id-workflow`, `physical-membership-ids`, `permanent-qr-verification` and `entry-verification`. Browser output tests decode QR rasters and rendered PDFs at print resolution. No real tenant/member or live financial operations are used.
