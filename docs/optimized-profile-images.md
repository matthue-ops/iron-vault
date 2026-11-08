# Optimized pictures and gym-logo app icons

## What changed

New/replacement member photos are square-cropped to 256 × 256 and compressed to WebP when supported (JPEG fallback) (target up to 40 KB, maximum 64 KiB). Gym images fit inside 512 × 512 without stretching/cropping the logo, preserve transparency and use WebP (transparent PNG or opaque JPEG fallback) (target up to 100 KB, maximum 128 KiB). Inputs may be PNG/JPEG/WebP/GIF, up to 8 MiB and 24 megapixels (maximum dimension 8192). Animated inputs become still pictures. Invalid/oversized images fail before uploading. Browsers without a native WebP encoder use JPEG for member photos and PNG for transparent gym logos; opaque square gym images can use JPEG. Storage filenames are format-neutral (`photo` / `logo`); MIME metadata carries the actual format. The same output size caps apply, so unusually detailed PNGs may require a simpler image.

Each gym upload also generates transparent 192px/512px PNG app icons and a separate 512px maskable icon with a padded logo on a solid background. App launchers may add a background/mask. Opaque white pixels in an original logo remain opaque; this does not remove backgrounds. The manifest uses versioned, public gym-image URLs and keeps the existing gym-specific app identity. Existing Base64 logos need one re-upload to generate these files. Already installed icons may update later or require reinstallation, depending on the device.

## Storage, privacy and compatibility

047 creates public `iv-gym-images` and private `iv-member-images` buckets plus `ironvault_private.profile_images`. It reuses `owners.logo` / `members.avatar` for stable references rather than adding columns/changing the compatibility views. Member references are `iv-photo:<upload UUID>`; gym references are the configured Supabase public bucket URL. Existing Base64 images remain supported. There is no bulk conversion and no historical member/payment/attendance change.

Private member files require the existing authenticated member/operator/provider boundaries. Only the active member or provider can upload a member photo; owner/staff retain read access within their gym. Pending members remain read-only. Gym-logo upload remains a provider function. Disabled accounts and other gyms cannot access private photos through Storage. The public gym bucket is intentional: logos/icons already appear on the public gym login page.

The browser resolves private photo references into signed URLs only in the DOM, not in persisted records, browser local/session storage, or exports. URLs expire after 120 seconds, are refreshed while visible and cleared from the DOM on sign-out/account changes. Previously issued URLs remain bearer links until expiry; an authorized viewer can always save a displayed image. Private uploads use zero cache lifetime; no private-image offline cache is added. Existing service-worker logic remains unchanged.

The public image base is currently the same Supabase project URL already used by the app. A project move requires updating the SQL reference helper, frontend path matcher and Pages manifest handler together. Buying an app domain alone does not require changing the Supabase image base.

## Replacement and failures

1. Process locally before making an image request.
2. Reserve a unique upload ID, checking the current picture and role. Upload immutable files under that ID; overwrites are forbidden.
3. Commit only after all required objects exist with accepted MIME metadata/size, and after rechecking permissions, subscription and the original photo version.
4. Attach through the existing profile/settings RPC, preserving its audit and business rules. The former image becomes retired only after attachment succeeds in the same database transaction.
5. Remove retired files through the Storage API, then acknowledge registry cleanup. Never delete `storage.objects` rows with SQL. Failed cleanup remains durable and is retried on subsequent uploads or after authenticated page initialization/data loads, including restore/purge refreshes. Provider cleanup includes images retired by member/gym deletion; no scheduled cleanup service is introduced.

If the save response is lost, the client checks the same upload ID. A confirmed active image is returned without another upload. If the outcome cannot be checked, the UI asks the user to refresh rather than claim failure. A failed/uncommitted request can be retired safely; stale concurrent replacements fail without changing the current picture. Removed-request tombstones are retained for at least 24 hours, preserving replay protection and the upload rate limit even after file cleanup. They are pruned during later authorized cleanup. Pending requests expire after one hour and enter cleanup on a later authenticated visit/load. Old clients attempting to overwrite a managed image from a stale profile receive a refresh message.

A gym is provisioned before its logo can be stored. If account creation succeeds but the logo fails, the gym remains created and the UI directs the provider to Edit gym for a logo retry; it does not create a duplicate gym. Other setting changes can succeed independently of an image failure, with an explicit partial-result message.

## Backup and restore

Provider ZIP exports download current managed image bytes and embed them as data URLs in the existing profile JSON format. A failed image download cancels the export instead of creating a backup with missing pictures. The existing 10 MB restore limits remain in place. Use gym-specific exports for smaller sets; a very large individual gym still needs a separately designed larger backup strategy.

Explicit profile restoration still uses the original restore engine and permission checks. A wrapper allows embedded backup pictures to replace managed references; the old files enter cleanup. Restoring Base64 pictures does not automatically generate stored gym icons; re-upload the gym logo afterward. No financial/authentication data is restored by this change.

## Manual deployment order

1. Keep the existing production deployment and source backup. Review/test in staging first if available.
2. In Supabase SQL Editor, open `supabase/manual/optimized_profile_images.sql`. Select/run the **entire file**, beginning with BEGIN and ending with COMMIT. It requires confirmed 046. Do not run the numbered copy as well. The installation guard deliberately rejects a second application.
3. Confirm success (optional read-only checks: `supabase/verification/optimized_profile_images.sql`), then deploy/merge the matching frontend/Pages Function. No new Edge Functions, API keys or email settings are required. Until SQL is installed, a new photo upload gives an installation-required message; existing pictures remain readable.
4. Refresh provider/member/admin pages. Re-upload one dummy gym logo with transparency and a dummy member photo. Complete the acceptance checks below before wider use.

## Acceptance checklist

- Existing gym logos/member photos still show before replacement, including provider inspection and live refresh.
- Upload an ordinary large member photo: it displays correctly, remains after refresh, and is cropped to a square without distortion. Pending/disabled members cannot bypass access restrictions.
- Upload a transparent gym PNG: branding stays transparent and the manifest has logo-specific PNG icons plus a separate maskable icon. Inspect Android installation and iPhone Add to Home Screen on actual devices. Confirm each installed icon starts the correct gym.
- Owner/staff can see only authorized member photos. A different gym/anonymous browser cannot download a private member image; gym-logo/icon public access is expected.
- Invalid input, failed upload, missing icon file or stale concurrent upload leaves the prior image current. A lost successful response resolves to one committed request. Clear UI feedback distinguishes successful save with deferred cleanup from failure.
- Old managed files are removed after confirmed replacement; active files cannot be overwritten/deleted through ordinary Storage access. Interrupted cleanup is still listed for the next authenticated retry/provider cleanup.
- Export a dummy gym ZIP, then replace its pictures and explicitly restore the backup. Both images survive restoration from embedded bytes even if their old storage files were cleaned up. Verify financial/history data is unchanged.
- Sign out during a delayed photo load; the late signed URL must not appear. Test a second account and live refresh.
- Check normal member registration, admin/staff sign-in, top-up, refund, manual/QR check-in and offline retry in the preview. No changes to those business policies are included.

## Validation and rollback limits

`npm test` includes image request/failure tests. `node tests/browser/profile-images.cjs` uses actual browser raster encoding and mocked storage. `tests/database/profile-images.cjs` executes 047 against an isolated embedded PostgreSQL fixture, including actual RLS boundaries with deliberately broad legacy policies. It does not connect to Supabase. To run, install `@electric-sql/pglite@0.3.14` in a temporary directory and set `PGLITE_MODULE` to its module path. Existing installation/offline/login browser regressions also apply.

The local database fixture stubs existing profile/subscription functions; production integration is not verified until you manually apply SQL and run the preview checks. Actual device installation/icon updates and hosted Storage behavior remain manual acceptance items.

047 is additive but **do not blindly roll back to a frontend predating managed-image support after new pictures have been saved**: old code cannot render private `iv-photo:` references. Keep a compatible frontend, or explicitly restore verified embedded-picture backups before reverting that support. Do not drop buckets/functions/tables or delete objects as an ad hoc rollback. Original legacy pictures remain in any backups that contain them; replacement cannot remotely erase backups or previously downloaded copies.
