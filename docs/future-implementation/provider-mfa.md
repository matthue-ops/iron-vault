# FUT-001: Provider MFA

Status: **PRELIMINARY IDEA — REVISIT AND DISCUSS BEFORE DEFINING A FINAL SCOPE**

This note is a starting point for discussion, not finalized requirements. Revisit this idea individually with the user; execution requires a separate explicit instruction after reviewing the scope.

Consider authenticator-app multi-factor authentication for the Iron Vault Provider account: password plus a temporary code. The user chose to defer this discussion.

Before revisiting:

- Confirm Supabase's current support, plan limits and pricing; do not assume a past pricing statement is still current.
- Review secure enrollment, recovery/lost-device handling and server-side enforcement for the Provider's protected actions.
- Keep SMS authentication and its potential charges outside this proposal unless separately requested.

No MFA enrollment, policies or billing changes were made for this idea.
