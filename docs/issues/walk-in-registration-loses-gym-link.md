# Walk-in registration reloads and loses the gym link

- Recorded: 2026-11-07.
- Status: Confirmed in an isolated browser reproduction; **fix implemented locally; awaiting PR review/deployment**.
- Authorization: Initially saved only; the user subsequently authorized fixing the saved issues and preparing a PR.
- Scope: Separate from the three financial retry/draft/polling fixes in commit b3c222a.
- Reviewed source: b3c222a, building on 618dfdd.

## User-observed problem

During TEST gym walk-in registration, the page navigated away, displayed “Open a valid gym link.”, and then showed an INVALID LINK access portal. The subsequent Super Admin screenshot showed an active pilot and zero members. Screenshots do not establish whether any partial Auth/provisioning records exist; check before retrying registration.

## Confirmed cause in the reviewed code

The subscription wrapper in `assets/subscriptions.js` wraps `handleAdminAddMember` and waits for `iv_subscription_access` before calling the original handler. It does not synchronously prevent the form's default submit action.

The original handler in `assets/application-workflows.js` calls `event.preventDefault()`, but the wrapper reaches it only after the asynchronous check. The Express Walk-In form in `gym/admin.html` calls `adminApp.handleAdminAddMember(event)` from its `onsubmit` attribute.

Consequently, the browser can submit the form normally before registration runs. Its default GET navigation replaces the query string, losing the gym key. Admin startup then cannot resolve the gym and redirects to the access portal.

Relevant locations at the reviewed commit:

- `assets/subscriptions.js`: operations wrapper, approximately lines 639–657.
- `assets/application-workflows.js`: `handleAdminAddMember`, approximately lines 109–113.
- `gym/admin.html`: Express Walk-In form, approximately line 495; `detectTenantFromUrl` and `checkExistingSession`.

## Local reproduction

Use an isolated browser with mocked services, not the production database:

1. Open a test admin URL such as `/gym/admin.html?key=mock-gym-token`.
2. Use an actual form whose onsubmit calls the wrapped `handleAdminAddMember`.
3. Load the real `assets/subscriptions.js` wrapper.
4. Delay the mocked subscription response by 1.5 seconds.
5. Click the form's actual Register button.
6. Observe navigation and whether the underlying registration handler was reached.

Observed result:

```json
{
  "finalUrl": "https://walkin.test/gym/admin.html?",
  "gymKeyLost": true,
  "registrationHandlerReached": false
}
```

The temporary diagnostic script was `/tmp/iv-walkin-submit-diagnostic.cjs`; temporary files may not persist across environments. The steps above are the durable reproduction. No SQL, account creation or live member registration was executed by the diagnostic.

## Implemented minimal remedy

The subscription operations wrapper now calls the submit event’s preventDefault() synchronously before its first awaited check. Existing subscription and role checks and the original registration handler remain unchanged. The same wrapper correction protects staff/profile/pricing form handlers without adding permissions or database operations.

No SQL migration or database structure change is expected for this frontend remedy.

## Required regression coverage

- Click the actual Register submit button with a delayed mocked subscription check; direct calls to the JavaScript handler alone are insufficient.
- The URL and gym key remain unchanged while waiting.
- Authorized submission invokes registration exactly once and refreshes the correct gym roster.
- A denied/failed subscription check creates no member, keeps the valid gym context, and displays the error.
- Pressing Enter submits safely too.
- Verify staff signup and any other affected form wrappers without changing their permissions or business policies.
- Check phone and desktop layouts. Use disposable test members only after checking for an earlier completed or partial registration.

## Current disposition

Implemented under the user’s subsequent authorization. Native browser tests pass at 320/375/1280 for delayed registration, Enter submission, denied access with no writes, preserved gym URL and staff signup. Node tests also assert prevention occurs before authorization resolves. No SQL, real registration, merge or manual deployment was performed. Await PR approval and deployment, then retry with a disposable member after checking for prior partial records.
