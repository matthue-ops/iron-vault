# Unclear authentication warnings during pilot testing

- Recorded: 2026-11-07 (Asia/Manila).
- Status: Review only; do not implement without approval.
- Evidence: User-reported manual testing in TEST GYM; no credentials recorded.

## Signed-out admin navigation

After explicit gym-admin sign-out, browser Back did not restore usable authenticated access. A browser alert displayed: “Reporting access: Please sign in again”. Refresh then remained at the TEST GYM login portal.

The reporting-specific wording is confusing in this navigation context. Review whether a general session-expired/sign-in-required message can be used while retaining the existing authorization checks. No authentication bypass was reported in this path.

## Suspended staff login

Owner confirmed suspension, then the staff login attempt displayed “Invalid request”. The same credentials worked after owner reactivation. This supports suspension enforcement in the tested path, but the message does not explain the access restriction. Review safe, clear wording without disclosing account status to unauthenticated users unnecessarily.

## Member sign-out navigation follow-up

After member sign-out, the user clarified that Back showed the login portal and then exited to the browser; the member profile never reappeared. The observed Back-navigation check passed. A separate refresh check was not explicitly confirmed; this observation does not establish every session-restoration path.

No application code, permissions, SQL or database changes are part of this record.
