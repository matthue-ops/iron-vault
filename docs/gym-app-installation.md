# Optional gym app installation

This change adds installation metadata and an optional install choice to the existing gym portal. It does not change authentication, gym permissions, database queries or writes, transactions, QR validation, service-worker caching, or Super Admin/Command pages. No SQL is required.

## How it works

After the login page has resolved a valid gym using its existing lookup, it attaches a gym-specific manifest and offers **Install app** or **Continue in browser**. The existing friendly URLs, printed QR codes, legacy key links, and member-login redirects still work. No QR replacement is required. Existing links cannot distinguish a QR visit from an ordinary link visit, so the same first-visit choice appears for either.

The choice is saved under the gym ID in browser local storage. Continuing, attempting installation, or dismissing the choice with Escape suppresses the automatic choice on later visits in that browser. The login page retains an installation button. A successful installation event hides the button; a new browser installation event can reveal it again after uninstalling. Installed display mode always hides the choice and button. Browser storage events synchronize the choice between tabs. If storage is blocked, the app remains usable but the choice may reappear on another visit.

Installation detection is best effort, not device-wide. Clearing site data, incognito, another browser profile, or another gym may offer the choice again. iOS does not provide the same installation events as Chromium; an installation made elsewhere may not be detectable in the ordinary browser. Scanning a QR may continue opening the browser rather than automatically launching an installed app.

Chrome/Edge can show a captured native install prompt after a user clicks Install. If no native prompt is available, the dialog explains how to use the browser menu. iPhone/iPad instructions direct the user to Safari, Share, Add to Home Screen, with Open as Web App enabled when shown. The chooser never automatically opens a native prompt. Verification/reset callbacks are excluded even when the original callback hash is subsequently removed by existing code.

## Manifest and deployment

The existing Cloudflare Pages Function serves `/gym-app.webmanifest`. Public query parameters contain the resolved gym ID, its public portal key, and gym display name; these are branding/navigation hints, not credentials or access grants. The endpoint makes no database calls. Do not add user credentials, access tokens, member records, or private data to this URL.

Each manifest has a stable app ID derived from the gym ID, a `/gym/` scope, and a start URL of `/gym/login?key=<public gym key>`. Rename or portal-key rotation does not change the app ID. A key already stored in an installed manifest can become obsolete after key rotation, so provide the current gym link for reinstallation if needed. Start-up uses the existing login portal and existing sign-in behavior; no new automatic sign-in or role selection is introduced.

The gym name is personalized, with shared 192px and 512px fitness icons (including maskable support). Per-gym uploaded logo icons are not introduced. The root Pages Function already receives this manifest path; the existing `/gym/*` and `/assets/*` static exclusions and build asset rules remain unchanged. This dynamic endpoint is for the current Cloudflare Pages deployment; a different hosting platform would need an equivalent handler.

Installation is a web-app window, not an App Store or Play Store package. Separate app IDs do not isolate authentication/storage by gym: the existing account, server permissions and shared origin still control access. All launches resolve the live gym normally. A purged/invalid link follows the existing unavailable/invalid-gym behavior, rather than granting access from stored metadata. An installed icon may retain public branding and cannot be remotely uninstalled. No private gym/member data is cached by this feature.

The unchanged service worker caches only the public offline warning, never account records or transactions. Installing does not enable offline check-ins or payments. No endpoint or capability for offline writes has been added.

## Verification

- `npm test`: unit/regression checks, including manifest identity, validation and HTTP methods.
- `npm run build:pages`: static asset packaging.
- `node tests/browser/gym-install.cjs`: first choice, remembered choice, per-gym separation, native prompt acceptance/cancellation handling, standalone mode, callback exclusion, blocked storage, iOS instructions, real Chrome manifest retrieval and icon requests, and offline retry/public-only caches at 320/390/1280px. Native prompt interactions are simulated; actual phone installation still needs manual verification.
- Existing `tests/browser/offline-fallback.cjs` and `tests/browser/saved-issues.cjs`: offline navigation and login/registration/navigation regressions.

## Preview acceptance before production

1. Open a real gym link in Android Chrome. Choose Continue; reopen the QR/link and confirm no automatic chooser. Confirm installation remains available from login.
2. Tap Install and complete the actual browser prompt. Launch the gym icon and verify the gym destination, name, standalone window and absence of the choice. Sign in with a dummy member; test one normal entry. Separately test admin/staff permissions and logout.
3. Install a second dummy gym and check that its icon and destination remain distinct. Do not assume these icons support simultaneous different accounts in shared-origin storage.
4. On iPhone Safari, complete Add to Home Screen and verify standalone launch. Check QR scanner embedded-browser guidance when applicable.
5. Check verification/password-reset links, existing reports, wallet/payment confirmation and camera QR scanning in the installed window. Confirm no login or transaction policy changed.
6. Go offline, retry, reconnect and retry. Confirm the gym destination is retained and no private data or pending write is cached.
7. Use only a disposable gym to verify unavailable/purged-gym behavior through normal authorized tools. This implementation does not alter purge policy or delete anything.

## Rollback

Deploy the previous successful Cloudflare Pages version or revert this PR and redeploy. There is no database migration to undo. Already-installed icons remain on devices and may need removal; rollback of web assets cannot remotely uninstall them. Keep the prior production deployment available.
