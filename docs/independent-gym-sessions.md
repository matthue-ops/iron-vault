# Independent, persistent gym and provider sessions

## Behavior

Each gym has its own saved Supabase session; Super Admin has a separate provider session. Signing into Gym B does not replace Gym A or Super Admin. Signing out clears/revokes the current SDK session only and broadcasts to other tabs for that same gym, not other gyms/provider. The existing same-gym session remains one account per browser/storage profile; parallel owner/member accounts for the same gym still require separate browser profiles/incognito.

The SDK persists refresh credentials and automatically renews access tokens. Closing an app or restarting the browser/device does not intentionally clear them. A closed/background app need not keep making refresh requests: the SDK can renew on reopening. Days/weeks of continuity depend on the Auth server's session policies and available browser storage; no exact duration is promised and no server lifetime/security setting is relaxed. Sign-out, revoked/expired refresh credentials, account restrictions, site-data clearing, private browsing, browser eviction or changing site origins may require signing in again.

## Implementation boundaries

`assets/session-scopes.js` is a client factory. The primary clients on login, member, admin/staff, reports and Super Admin pages use:

- Gym: `iv-auth:v1:<Supabase host>:gym:<gym ID>`.
- Provider: `iv-auth:v1:<Supabase host>:provider`.
- Unknown legacy entry: a nonpersistent anonymous bootstrap client, never the old shared credential key.

The SDK derives its refresh locks/broadcast channels from the storage key, so identity events/refreshes are isolated as well as stored credentials. Persistent clients explicitly enable `persistSession` and `autoRefreshToken`. Password-verification clients remain nonpersistent. Anonymous legal-document clients remain anonymous. All sign-out paths use local-session scope, not global user-session revocation.

No database schema, SQL routine, RLS grant, account-linking rule, password, financial request or payment/attendance policy is changed. Resume uses existing authenticated role checks and the public member-portal availability result. Browser aliases/session fields are routing/UI hints, never authority. Server role/tenant permissions still apply to every operation. No new SQL, Edge Function, domain, subdomain or Supabase setting is required.

## Legacy links and UI state

Normal installed apps already start at `/g/<gym ID>/login?key=...`; their saved-login namespace is known before SDK initialization. Provider routes and the existing `/gym/index.html` page use the provider namespace. Provider Reports also uses it, including legacy `from=index`/`from=superadmin` links.

A legacy gym slug/key login uses the existing public branding lookup, then replaces its history entry with the canonical scoped login before signing in or consuming a callback. Non-secret token → gym ID aliases remembered from that verified lookup let existing key-based admin/report links locate the same session. Editing aliases or URL paths cannot grant another gym's role.

Generic legacy private-page bookmarks with neither a gym path nor a usable gym key cannot safely choose among multiple accounts. Open that gym's QR/link or installed app instead; there is no fallback to a first/cached gym. Recovery and verification fragments survive the handoff and are scrubbed before verification on the canonical page. Older implicit recovery tokens are processed explicitly there; SDK-wide automatic URL-session adoption is disabled.

When ordinary login opens, a stored session is checked against the authenticated user's current role and selected gym. Only then are the existing UI/session hints rebuilt and the user sent to member/admin pages. A changed identity, wrong gym or revoked role fails closed. Member-portal availability still blocks member auto-resume when unavailable; dashboard-only owner/staff access remains possible. Resume does not create an account, log a synthetic staff sign-in, buy a pass, credit a wallet or record entry.

An incoming verification/recovery callback never auto-resumes past its form. Recovery authorization is granted only after its gym/account proof is checked, is cancelled on sign-out/account change, and is rechecked before updating the password. Reset completion signs out only that gym. Provider Reports with no valid session returns to the provider login rather than a gym login or Command.

Existing tab-local UI hints and financial/provisioning retry IDs keep their formats. Pending/uncertain financial request records are not removed or moved. The persistent login is the SDK session, not those UI flags or any cached role. Plain old browser data caches remain excluded as before.

## Deployment / existing sessions

1. Review/deploy this frontend with the existing scoped routing from the previous release. No additional SQL or backend deployment is needed.
2. Close/reload all open app/browser windows so older clients using the shared storage key are not left active.
3. Sign into each desired gym and Super Admin once. Existing shared sessions are deliberately **not copied into another realm**. This avoids importing the wrong account or duplicating rotating refresh credentials. Old default-key entries are ignored and not modified by this release.
4. No reinstall is needed just for this session change. Existing installed app IDs, icons and scopes are unchanged.
5. Test reopening/restarting before broader rollout. Same-origin browser profiles still share website storage: clearing all site data can remove every saved realm. Other browsers or some platform-installed storage areas may require their own initial sign-in.

A failed network sign-out retains the existing error/retry behavior; do not treat an unconfirmed server sign-out as a confirmed revocation. The new local scope does not bypass backend session controls.

## Validation

`npm test` covers namespace selection, project/gym/provider separation, legacy handoff, callback preservation, role checks, portal gating and existing controller regressions.

`tests/browser/independent-sessions.cjs` uses the actual frontend Supabase UMD SDK with an isolated local Auth/PostgREST mock and disposable persistent Chrome profile. It never contacts Supabase. It tests:

- Two gyms + provider signed in simultaneously, including a branch-gateway `setSession` login.
- Full browser shutdown/relaunch with saved credentials, plus a deliberately expired access-token record refreshed using its stored refresh token.
- Same-gym cross-tab sign-out and other-gym/provider preservation; even identical Auth user IDs in separate realms do not receive global logout.
- A valid old default-key session is neither adopted nor changed.
- Revoked roles and a wrong-gym session are denied.
- Actual login HTML: legacy callback handoff before one-time proof consumption; recovery completion and account binding; implicit recovery compatibility; normal automatic resume; unavailable-member-portal versus dashboard-only owner behavior; provider Reports denial returning to provider login.

To run that browser test, download the frontend's public Supabase UMD SDK to a temporary file and set `SUPABASE_BROWSER_SDK` to its path (default `/tmp/iv-supabase-browser.js`). The reviewed run used Supabase JS 2.119.0, as resolved by the frontend's existing `@2` CDN URL. This does not add a dependency/vendor bundle to production. Existing installation, scoped-navigation, registration, sign-out, offline and photo browser checks also apply.

These are actual SDK/storage/browser lifecycle tests with mocked service responses, not a live Supabase integration or a weeks-long uptime test. Server policies and physical phone/PWA storage behavior still need acceptance.

## Preview / pilot acceptance

1. In one normal browser profile, sign into two different dummy gyms and Super Admin. Revisit each and verify the intended account, gym, role and permissions.
2. Close all windows and reopen each installed icon. Restart the phone/browser and repeat. Existing scopes should resume the intended account.
3. Sign out of Gym A. Gym A's other windows should leave protected views, while Gym B and provider stay signed in. Check provider sign-out separately.
4. Confirm refresh after the normal access-token lifetime. Do not change JWT expiry to a long value just to make the UI appear persistent.
5. Suspend/revoke a dummy role and verify private access is denied on return/refresh; another gym must stay usable.
6. Test a legacy QR/link, member and staff recovery email, verification callback, wrong-gym recovery proof and normal password update. Account security messages/forms must not be skipped by resume.
7. Check member-portal-disabled/dashboard-only scenarios and normal wallet top-up, refunds and manual/QR entry. This change must not create duplicate business events or weaken financial permissions.
8. Check offline/reconnect and browser-data clearing. Credentials must not be copied into another gym as a fallback.

## Rollback

The previous scoped-routing frontend can be redeployed without SQL rollback, but it restores shared-session behavior and may require fresh sign-in. New per-realm entries can remain inert; do not merge/copy JWTs back into the default key. Keep the app-path aliases for installed icons. Existing photo-storage rollback considerations remain separate.
