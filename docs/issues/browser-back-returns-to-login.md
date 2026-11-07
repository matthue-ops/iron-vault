# Browser Back returns to login and appears to sign out

- Recorded: 2026-11-07.
- Status: **History-entry remedy implemented and mock-tested; actual session termination remains unconfirmed. Awaiting PR review/deployment.**
- Authorization: Initially saved only; the user subsequently authorized fixing the saved issues and preparing a PR.

## Observation

While testing the TEST gym on a phone, the user reported returning to the login page after closing Subscription and pressing browser/phone Back from the dashboard. A subsequent report also described returning to login; it is not yet clear whether that navigation was Dashboard → Back or Reports → Back. No accompanying session error or exact URL sequence was provided.

The separate refund-draft trial passed: Alice and Marian each retained their own draft.

## What source inspection establishes

The reviewed code does not attach a deliberate sign-out operation to browser Back. Admin login in `assets/branch-auth.js`, `handleAdminLoginSubmit`, navigates using `location.href`, which keeps the login page in history. The login page does not automatically route an already authenticated owner back to the dashboard. Consequently, Back can display the login form without necessarily ending Supabase authentication.

Reports navigation uses `location.href` from `gym/admin.html`, `openReportsPage`. A successful Reports → Back transition should normally restore the prior dashboard. Admin/reports startup and restored-page checks may redirect to login if authorization or gym resolution fails; this is distinct from an intentional sign-out. That failure has not been demonstrated for this report.

## Unconfirmed points

- Whether the session was actually terminated, or an earlier login page was simply shown.
- Whether the failing route was Dashboard → Back → Login or Reports → Back → Login.
- Whether the gym key survived and whether any authorization error occurred.
- Exact deployed revision and browser-history state during the report.

Do not classify this as a confirmed automatic-logout or subscription-polling defect yet.

## Follow-up checks

Use a disposable test gym, without financial mutations:

1. Record the starting URL and signed-in role. Do not record passwords, session tokens or cookies.
2. Test Dashboard → Reports → browser Back; record the final URL and visible state.
3. Separately test Dashboard → browser Back; identify whether it returns to the earlier login entry.
4. From that login entry, use browser Forward or reopen the valid admin link in the same browser profile. If authorized dashboard access succeeds without entering credentials, authentication remained active.
5. If credentials are required or the dashboard redirects again, inspect authorization errors, gym-key resolution and Auth SIGNED_OUT events before proposing a fix.
6. If the finding is only confusing history navigation, review a minimal navigation/valid-session landing improvement separately, preserving explicit logout, recovery, tenant binding and browser restoration checks.

## Current disposition

The authorized minimal change uses location.replace only after successful owner/staff sign-in and the existing tenant/role verification. The submitted login entry no longer remains immediately behind the dashboard. It does not intercept Back, introduce an automatic session redirect, bypass authorization, or change explicit logout/member registration/recovery. Existing browser-history entries are not retroactively rewritten.

Mocked native-browser tests at 320/375/1280 verify Login → Dashboard → Reports → Back → Dashboard, then Back → the page preceding login; authentication remains active. Explicit logout clears the mocked session; wrong-gym owner sign-in is still denied. Actual production session termination was not reproduced and should not be described as fixed on this evidence alone. No SQL, real login, merge or manual deployment was performed. Await PR approval/deployment and repeat the live navigation check.
