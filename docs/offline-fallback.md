# Offline navigation fallback

## Scope

`offline.html` is a self-contained public warning page with inline styling and script, system fonts and no external resources. It explains uncertainty around previously submitted payments/check-ins, recommends a secure manual log, and provides Retry and a launcher link. It never verifies membership, processes payments, records attendance, queues writes or collects member information.

`assets/offline-fallback.js` registers `/service-worker.js` after the document loads on HTTPS (or localhost during development). Registration is optional and failure does not block the app. Existing pages receive this registration script; redirect-only aliases hand off to the real pages as before.

The service worker saves **only** the static warning page. All app pages remain network-only. It does not cache dashboards, credentials, member data, API responses, exports or financial submissions. It intercepts same-origin GET navigations only; other requests continue normally. A failed navigation, a ten-second navigation timeout, or an HTTP 5xx response uses the warning page. Normal redirects, authentication responses and 404s are preserved. The original navigation URL remains available, so Retry retries that URL rather than guessing a gym/account.

The worker reconstructs the cached warning response to avoid replaying Cloudflare's canonical `.html` redirect. Installation checks the page marker before saving it. Activation deletes only older caches in this feature's own namespace. There is no forced page reload when the worker updates.

## Limits

- A device/browser must visit this origin online and finish installation first. It cannot show the app's own fallback on a first-ever offline visit.
- Clearing site data, private browsing limitations, storage eviction, disabled service workers or unsupported browsers may remove/prevent the fallback. The browser's normal error page may appear instead.
- Each origin is separate: visiting a preview deployment does not install the fallback for production.
- A backend/API outage inside an already-open page is not a navigation failure. This feature does not implement a new general in-app outage modal, offline app operation or any of the held diagnostic fixes. Existing app connection handling remains unchanged.
- Browser `onLine` is a connectivity hint, not proof of service health. The page does not identify which hosting/database provider failed, and does not declare recovery merely because the browser reports an internet connection.

## Build and rollout

The Pages build copies `offline.html` and `service-worker.js` to the publish root. Generated routing excludes the static fallback and worker URLs from the slug function. Generated `_headers` asks browsers to revalidate the worker and fallback. No SQL, grants, Edge Function updates, account changes or service-side data writes are required.

After frontend deployment, visit the site online on each gym device before relying on offline fallback. In staging, load a real gym URL, allow worker installation, turn off connectivity and reload; the warning should appear at the same URL. Restore connectivity and select Retry. Check that existing login and recovery links still work.

If withdrawing this feature, removing registration alone does not uninstall workers already controlling a browser. Publish a replacement worker that stops interception/unregisters and cleans only this cache namespace, or remove the worker through browser site controls as part of an explicit rollback.

## Validation

- `npm test`: worker install/activation, public-only caching, offline/HTTP failure fallback, successful and 404 response preservation, exclusion of POST/API/script/cross-origin requests, and rejection of an unexpected install response.
- `npm run build:pages`, Dashboard generation checks, service policy checks and whitespace checks.
- `node tests/browser/offline-fallback.cjs`: actual Chromium service workers against a local test server at 320, 375 and 1280px. Covers cached offline navigation, preserved URL, cache contents, reconnect/retry, 503, 404 and first-ever offline access. No live service or database is contacted.
