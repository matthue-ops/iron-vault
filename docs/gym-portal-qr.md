# Gym Portal QR

Owners and all signed-in staff can open **Gym Portal QR** from the gym dashboard menu. No extra staff grant is required. The QR uses the same `IronVaultGymPortals.url` helper as the provider link: the named gym URL when available, otherwise the existing public `login.html?key=...` link. It is not a member entry ticket and does not bypass login, membership or subscription requirements.

The new module generates a high-resolution black/white PNG locally with an integer-pixel matrix and four-module quiet zone. Copy link briefly highlights its button without changing the label. Download saves the PNG; Print opens a separate printable sheet with the gym name and public URL. If pop-ups are blocked, the user can download and print the image instead. Closing or signing out clears the in-memory QR. Actions check the current account/gym context before using an open QR.

No new API, database query, permission, migration or installation behavior is introduced. Existing entry QR generation/redemption and provider QR functions are untouched. Deploy the branch normally; no SQL or new external dependency installation is required.

Validation: 483 existing tests, production build, and isolated Chromium `tests/browser/gym-portal-qr.cjs` for owner/staff at 320/390/1280px (canonical URL and fallback, copy, real PNG download, printable sheet, no service calls, sign-out and stale-context handling). Existing `tests/browser/phone-interface.cjs` verifies dashboard, appearance, reports, backups and member QR behavior with mocked services.
