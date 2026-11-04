# Cloudflare Pages migration

## Build configuration

Merge the Cloudflare preparation branch into `main` before creating the deployment:

- Production branch: `main`
- Framework preset: None
- Build command: `npm run build:pages`
- Build output directory: `dist`
- Root directory: repository root (leave the optional field blank)
- Environment variable: `NODE_VERSION` = `24`

The build copies root `index.html`, browser assets and the gym pages into `dist`. It excludes database migrations, Edge Function source, tests, docs, package files and Git metadata. `functions/[[path]].js` is the Cloudflare Pages routing handler; it is compiled separately by Pages from the repository's root functions directory. Do not upload `dist` alone as a manual static deployment: that omits the routing function.

The handler preserves existing-file priority and internally serves `/gym/login` for missing, lowercase single-segment gym slugs. It preserves query strings and the browser-visible gym path. Pages' native extensionless URLs handle `.html` canonicalization. Legacy memberlogin/memberprofile aliases remain present. The generated 404 page prevents Pages' implicit SPA fallback from returning the master page for missing files. `_routes.json` bypasses the function for root, gym and asset paths; only unmatched paths need the routing function. Vercel configuration remains intact for rollback.

## Supabase settings (user performs these; no SQL)

Confirm the final production Pages address first. The setup screenshot currently proposes `https://iron-vault-433.pages.dev`; use the address Cloudflare actually assigns.

1. In Supabase Edge Functions secrets, preserve the existing `CORS_ORIGINS` entries and append the exact production Cloudflare origin, comma-separated, with no path or trailing slash. Include the Vercel origin during testing, for example `https://ironvaultph.vercel.app,https://iron-vault-433.pages.dev`. Do not use `*` or broad preview-domain wildcards. All Edge Functions using the shared runtime read these project secrets.
2. For initial testing, keep `APP_URL` at the existing live address. Email verification, recovery and contact-confirmation links will continue pointing there. When ready to test the complete Cloudflare email flow, set `APP_URL` to the exact production Cloudflare origin. The Edge Functions generate their own email links using this value.
3. In Authentication → URL Configuration, add the exact Cloudflare callback URLs needed by the app: `/gym/login.html`, `/gym/login`, `/gym/memberlogin.html`, and `/gym/memberlogin`, all under the production Pages origin. Keep existing live redirect entries during testing. Change the Auth Site URL to the new origin at final cutover. Do not replace unrelated existing callback settings.

No database migration or data transfer is required. Existing Supabase data and accounts stay in place. No secrets belong in Cloudflare build settings for this static app. Do not paste service-role keys into the browser build.

## Review before cutover

Keep Vercel available. Test root master sign-in, gym Super Admin, canonical and legacy gym page links, readable gym slugs with/without trailing slash, query/hash preservation, member and owner/staff sign-in, manual registration/check-in, QR scan/redemption, pass purchase, report loading/exports, and live updates. Test email recovery/verification/contact changes after updating APP_URL. Existing printed QR links using Vercel do not change automatically; keep the old host available or issue new links during migration.

Unit tests simulate the Pages asset binding and check routing and publication boundaries; they do not replace the first real Cloudflare deployment test. The agent has not deployed to Cloudflare or changed any Supabase setting. A paid/commercial-plan assessment is separate; this document does not claim to verify hosting terms.
