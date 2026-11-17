# Held bundle Stage 1 — Member-list improvements

Based on inspected main `6163393`. This stage preserves the working member roster, existing Logged Entry / Not Entered toggles, profile actions, scanner permissions, entry verification/approval, balances and membership records. Other held bundles are untouched. **No SQL, database query, API contract, permission or entitlement changes are included. No SQL is required.**

## Expiring Soon

An amber calendar-clock button sits beside the existing entry filters. The dropdown defaults to **Within 3 days** and offers Today, Within 7 days, Within 14 days and Custom days. Custom accepts whole numbers from 0 to 365; invalid input leaves the last valid range in effect and shows an inline message. Selecting a preset or entering valid custom days activates Expiring Soon. Clicking the active filter again returns to the existing all-members view. Existing text search continues to narrow results.

The filter uses the existing loaded roster only: the selected gym, ACTIVE status, a recognized existing day/week/month plan and a real expiry date with **0–3 days remaining inclusive** by default. Today uses the Asia/Manila business date, independently of the device timezone. Expired, inactive/deleted, pending, invalid-date, no-plan and foreign-gym records are excluded. Entry already used today does not exclude a member from renewal follow-up and is never reset. This is a renewal filter, not an admission eligibility decision.

The badge counts all matching expiring members in the selected gym/window before the text search; the existing Active Members count reflects the displayed search/filter result. Both desktop and phone results show expiry date and days remaining while Expiring Soon is active. Existing entry filters stay mutually exclusive and retain their original behavior. No preferences are written to the database or shared across gyms/accounts. The initial default is three days; sign-out clears the added controls.

## QR lookup in search

The existing standalone Scan Member Card control is replaced by a QR icon inside the member search field. It has a visible hover title and an accessible label, **Scan member card to find member**, and a 44 px touch target. It calls the existing `openMemberCardLookup` flow unchanged: the existing `iv_verify_entry_qr` API receives `p_lookup: true`, then opens the member profile. It does not call approval, record attendance, spend wallet credit or consume a daily allowance. The separate door-entry scanner and its pause/cooldown/audio/stale-response/sign-out behavior remain intact. No direct-table fallback is introduced. Existing QR backend prerequisites remain the same; this change does not assume any new SQL has been installed.

## Responsive behavior

The same search/filter controls follow the roster into the existing phone Members view. Controls wrap within the card at narrow widths. Landscape widths use the existing desktop roster presentation with contained table scrolling. Returning to portrait restores an open member list, search, range, filter and list state; a profile that was already open stays selected with the underlying member dialog inert. Explicit close and sign-out still close the phone view. No financial or check-in controls are redesigned.

## Validation and release

- `npm test`: includes pure tests for inclusive boundaries, invalid/pending/inactive/no-plan exclusions, gym isolation, Manila midnight and leap dates, and preservation of used daily passes.
- `npm run build:pages`.
- `tests/browser/member-list-stage1.cjs`: actual roster/scanner methods and markup with synthetic records at 320×740, 390×844, 844×390 and 1280×850, including portrait–landscape–portrait changes. Tests search, range validation, page reset, pre-existing entry filters, scope, profile state, sign-out cleanup and lookup-only QR calls with unchanged member data.
- `tests/browser/entry-verification.cjs`: existing scanner regression, updated only for the search icon's accessible label.
- `tests/database/permanent-qr-verification.cjs`: existing disposable PostgreSQL scanner/admission regression; no live Supabase access.

Browser tests require Playwright and `/usr/bin/chromium`. The Stage 1 layout fixture also uses a locally compiled Tailwind stylesheet at `/tmp/iv-admin-tailwind.css`, matching the admin markup (no CDN requests). Compile using a pinned disposable `tailwindcss@3.4.17` tool, with `gym/admin.html` and `assets/*.js` in its content list. Test dependencies stay outside the application package.

Review the scoped branch before merging/deploying the matching static frontend. No migration or Edge Function deployment is required. A frontend rollback restores the old list controls without changing any member record or QR credential.
