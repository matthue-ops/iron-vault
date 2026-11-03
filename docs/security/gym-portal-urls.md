# Readable gym login addresses

Adds root-level gym links such as `https://ironvaultph.vercel.app/fitness-gym` and `/wild-card-gym`. Both open the existing Member / Admin-Staff / Join page, displaying the selected gym's name and logo. Login layout and authentication rules remain unchanged.

## URL assignment and data impact

Manual migration 026 creates the private `iv_gym_portal_links` mapping table. Existing gyms receive generated, unique lower-case URL names in tenant-ID order. Duplicate names receive `-2`, `-3`, etc. Non-ASCII characters and punctuation become hyphens; empty or reserved names use `gym-branch`. Existing names are never reassigned during repeat installation or an ordinary gym-name change. Newly inserted gyms receive a URL in the same transaction through an insert trigger; no provisioning Edge update is necessary.

The mapping table has no direct API grants and RLS is enabled. The existing safe `iv_gyms` view retains `iv_visible_gyms()` and its display-code column, appending only `portal_slug`. The existing status/role-based projection still controls branding visibility and contact/staff fields. The login requests only the exact selected slug's existing safe branding fields. A URL name identifies a gym; it is not a credential or proof of membership. Cross-gym authentication remains checked through the existing gateway and role checks.

No existing tenant ID, token, member, password, balance, plan, financial record or history is rewritten or deleted. The new mapping follows an existing explicitly confirmed whole-gym purge through its tenant foreign key. This change does not enable any purge or retention job.

## Links and navigation

Both Super Admin entry pages display the assigned URL and use it for Copy Link and branch entrance QR generation/download. They fall back to the original key-based link if the mapping is unavailable. Gym names are never guessed into working URLs in the browser.

Vercel checks existing files before rewriting a single lower-case URL segment to the login page. Existing application paths and assets remain available. Root-relative login assets and `/gym/` sign-in destinations also work with a trailing slash. A friendly path takes precedence over a conflicting query-string key. Missing or unknown gyms do not select another gym or load a cached directory.

Original `memberlogin.html?key=...` and `?gym=...` links remain supported, so printed entrance QRs keep working. Recovery emails and sign-out return links may continue to use the original gym-specific key address; they still select the same gym. Member daily QR tickets are unchanged.

## Manual rollout

1. On the existing installation through 025, review and manually run **only** [gym_portal_urls.sql](../../supabase/manual/gym_portal_urls.sql) in Supabase SQL Editor. It is identical to `202611030026_gym_portal_urls.sql`; do not run both copies. Copy the complete file through the final `COMMIT;`. This exact file can be reapplied; assigned names stay unchanged. DDL can briefly lock affected objects, so use a quiet period.
2. Optionally run the read-only [verification script](../../supabase/verification/gym_portal_urls.sql) yourself to inspect assigned names and check completeness/duplicates.
3. Open the matching branch preview. In Super Admin, confirm the displayed links, Copy Link and downloaded QR point to the preview origin plus the assigned name. Use a real assigned name rather than assuming a particular gym received the unsuffixed name. If needed, allow the exact preview origin in the existing authentication CORS configuration.
4. Check the acceptance cases below, then merge the frontend/Vercel configuration PR through the normal workflow. No Edge Function deployment, Auth credential change or email template change is required.

Do not assume SQL installation succeeded until it is confirmed. Before 026, old links remain the fallback; new readable URLs cannot resolve until the database exposes the mapping.

## Acceptance and limitations

Verify two gyms, all three login tabs, phone/desktop views, direct URL loading, browser refresh and trailing slashes. Test sign-in for members/owners/staff, sign-up and recovery using approved fixtures. A different gym's member must not enter through another gym's login. Unknown names must leave controls disabled. Confirm original links and printed QR destinations still work, and decode a newly downloaded branch QR independently.

Check duplicate gym names, names containing punctuation/non-ASCII text, reserved names and new gym creation. Changing a gym display name must retain its URL. Confirm inactive gyms remain subject to existing branding/sign-in restrictions. There is no URL-renaming screen in this stage.

Validation: all 250 local Node tests passed. SQL, both PL/pgSQL functions and the backfill block were syntax-parsed without executing SQL. Mocked Chromium tests used the checked-in route pattern at 320, 375 and 1280 pixels and verified routing/refresh, two brands, unknown names, canonical login destinations, scoped signup/recovery requests, old links and both Super Admin copy/QR controls. These checks do not establish live SQL behavior, concurrent allocation or hosted Vercel acceptance. The agent did not execute SQL, send emails, change live data, merge a PR or deploy production.
