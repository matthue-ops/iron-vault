# Gym and Super Admin app installation

## Purpose and scope

Android Chrome reported a second gym as already installed while both gyms used the same `/gym/` scope and login path. Each gym now has its own manifest URL, path-based app ID, launch URL and scope. Super Admin has a separate installation as well. This is installation/routing support, not a change to authentication methods, database permissions, transactions, QR validation or offline capabilities. No additional SQL is required. The held Authenticator/recovery proposal is not implemented.

## Separate app paths

| Installation | Manifest | Scope / ID | Start |
| --- | --- | --- | --- |
| Gym A | `/g/GYM-A/manifest.webmanifest?...` | `/g/GYM-A/` | `/g/GYM-A/login?key=...` |
| Gym B | `/g/GYM-B/manifest.webmanifest?...` | `/g/GYM-B/` | `/g/GYM-B/login?key=...` |
| Super Admin | `/_provider/manifest.webmanifest` | `/_provider/` | `/_provider/index` |

The original `/gym-app.webmanifest` endpoint remains compatible, but now returns the new gym-specific scope/ID/start. `/provider-app.webmanifest` is also accepted. Gym identity remains stable across display-name/key changes. Public branding parameters are not credentials; normal live-gym resolution and server-side authorization still apply. A scoped manifest rejects a conflicting gym ID in its query.

Cloudflare Pages serves the existing gym pages internally under these aliases. HTML gets a same-gym/provider base URL, and asset references are rooted at `/assets/`. Member/admin sign-in, relative Reports links, Back and logout therefore remain in the installation's own path. Only the explicit gym page allowlist is mapped; a gym scope cannot map the Super Admin index. Invalid pages return 404. Super Admin uses the existing master page and email/password gates. The provider prefix starts with an underscore so it cannot collide with an existing friendly gym slug.

Existing friendly URLs, printed QRs, legacy key links, email verification/recovery links and member-login redirects remain valid. The independent-session update resolves legacy login links through their existing public lookup and hands them off to the canonical scoped login before authentication or callback consumption; existing links themselves remain valid. If installation is requested before the browser supplies a native prompt, the Install action can open that same portal's scoped start URL with `install=1`. The one-time `install=1` flag is removed from browser history after it is consumed, so refresh does not repeatedly reopen the chooser. This explicit request opens installation help; a ready native event updates it to ask for another user click. Native prompts are never opened automatically.

Scoped public login rejects a different gym's key. Member/report contexts are checked against the path using already-resolved account/gym information before rendering private content. These UI routing checks supplement, not replace, the existing server permissions.

## Install menu and choices

The login page has a top-right three-dot **Portal options** menu with **Install app**, outside the login form. Super Admin has the same menu on its existing login/dashboard page. Its logout control stays available alongside the menu. Summary controls support normal keyboard navigation, Escape and click-outside closing. No tutorial is added yet.

A gym's first-visit **Install app / Continue in browser** choice remains optional. Remembered choices are per gym and browser, not device-wide. A successful new installation is remembered as `installed-scoped`; old `installed` flags do not hide the upgrade option. The chooser/menu is suppressed in standalone mode only when the actual page path is inside the current app's scope, so opening another gym inside an old app does not falsely mark it installed. Browser storage changes synchronize choices across tabs.

The dialog shows waiting status while Chrome responds. A stalled native request times out after ten seconds and gives explicit help rather than remaining indefinitely disabled. If no native event is available, help explains Chrome's **Install and create shortcut** menu and distinguishes a shortcut from an installed app. iPhone/iPad instructions use Safari → Share → Add to Home Screen. Browser-specific behavior and installation detection remain best effort.

Recovery/verification callbacks do not show an automatic installation chooser, including callbacks whose fragment was removed by existing code. Clearing site data, incognito or another browser can show the first choice again. Scanning a QR may open Chrome rather than the installed app; installation cannot force the operating system to launch a particular app.

## Icons and storage

Gym name and public portal key come from existing gym resolution. With migration 047 and the matching photo frontend, newly uploaded gym logos generate transparent 192/512px PNG icons and a padded maskable icon. Legacy/missing logos use the shared fitness icon until re-uploaded. iOS touch icons use the gym image when available. Super Admin uses its own gold-crown icons. Installed icon updates depend on the browser and may require reinstallation.

The [independent-session update](independent-gym-sessions.md) gives each gym and Super Admin its own persistent SDK session key. Different gyms/provider can stay signed in concurrently; the same gym still has one active account per browser/storage profile. This is not a separate security origin: all server role/tenant checks remain required. Existing shared-key sessions require one fresh sign-in after deployment; no Authenticator/recovery proposal is activated.

The unchanged root service worker caches only the public offline warning. Offline retry keeps the scoped URL. No private records or transactions are cached, and offline payment/check-in writes are not introduced. Purged/invalid gyms retain the existing unavailable behavior; installed icons cannot be remotely removed.

## Deployment and migration

Deploy this frontend and Pages Function together. No new SQL or Edge Function deployment is required for these installation repairs. Existing photo storage requirements are unchanged.

The prior shared-scope installation has a different identity from the repaired scoped app. It is not silently migrated or removed. Test the new icon first, then remove an old duplicate icon/app if replacing it. An old first gym app can remain installed while testing a second gym's new installation. A browser-controlled update or uninstall cannot be guaranteed by page JavaScript.

## Validation

- `npm test`: manifests, allowlisted rewrites, path isolation and existing app/controller regressions.
- `node tests/browser/app-scopes.cjs`: actual Pages handler rewrites in local fixtures, distinct gym/provider manifests, mobile header menus, scoped sign-in/Reports/Back/logout routes and offline retry at 320/390/1280px.
- `node tests/browser/gym-install.cjs`: chooser persistence, prompt acceptance/cancellation, callback exclusion, installed mode, iOS instructions, blocked storage and Chrome manifest/icon retrieval.
- Existing `tests/browser/saved-issues.cjs`, `tests/browser/offline-fallback.cjs` and image browser checks cover working flows.

Native prompt outcomes and standalone mode are simulated in the automated tests. Local Chrome's native OS installation API is disabled, so the tests do not prove two completed Android installations. These physical-device checks are still required after preview/deployment:

1. Keep the original first-gym app installed. In Android Chrome, open the second gym, use the top-right menu and install. Confirm Chrome offers a fresh installation rather than only opening the first app.
2. Open both icons and verify each gym name, destination, standalone window and normal sign-in. Check account switching and local sign-out isolation explicitly; see the independent-session acceptance checklist.
3. Install Super Admin separately from its own menu. Confirm the master email/password login is still required and ordinary gym accounts cannot enter. Test Super Admin Reports and logout.
4. Reopen QR links after choosing Continue in browser; confirm no repeated automatic choice and that the menu remains available. Check iPhone Safari Add to Home Screen separately.
5. Test member/admin/staff login and logout, Reports/Back, password recovery/verification callbacks, camera QR scanning and normal wallet/refund flows.
6. Test offline retry/reconnect and unavailable gym links. No route should redirect a gym to the provider login.

## Rollback

Keep the prior production deployment. Reverting this routing change makes newly installed scoped URLs unavailable; it cannot remove their icons. Prefer retaining the small alias handler while reverting UI changes if a rollback is needed, or tell users to use their existing gym links/reinstall after recovery. No database rollback is needed for this installation update. Image-storage rollback limitations in `optimized-profile-images.md` remain separate and unchanged.
