# Correctness fixes — first batch

Scope approved: inquiry items 5–10 and 12. Monthly email/retention automation, the wider mobile/report/staff redesign and a dedicated outstanding-credit print view are later batches.

- Password creation help and the remaining legacy creation guards consistently use eight characters. Existing sign-in credentials are unchanged.
- Short codes from migration 018 remain the user-facing member ID. Member profile, rosters, admission confirmations, alerts and outstanding-credit notes use the code; internal IDs remain in RPC parameters and record relationships. No replacement IDs are generated in the browser.
- Manual desk search includes ACTIVE members only, for both initial display and typed search. Pending and removed/INACTIVE members are excluded. Server admission checks remain authoritative.
- Remove member verifies current gym-owner authority and requires a finite zero wallet balance before confirmation. The existing iv_deactivate_member RPC repeats authority/balance checks under its row lock. A stale zero preview cannot bypass a newer balance. Successful removal revokes access and removes operational listings; it preserves financial/attendance history. It is not physical purge.
- Membership sales is the primary sales metric and includes plan_cash + plan_wallet only. Top-ups are separately labeled prepaid cash received. A 100-peso top-up followed by a 100-peso wallet purchase is 100-peso membership sales, never 200. Recorded cash refunds remain separately disclosed; sales are gross, not net profit.
- Attendance table/CSV show current pass expiry and days remaining, or No pass / Expiry unavailable / Expired / Expires today. Dates use the Manila business day. Headers correctly identify entry method instead of scans used. The column explicitly describes the current pass, not an unsupported historical entitlement snapshot.
- Administrative Activity renders actual activity records; the duplicate payment audit button and financial fallback are removed. Staff sessions remain a distinct selectable view. Money movements stay in the Money tab. Activity counts follow the selected/search-filtered view.

## Deployment

This batch changes application files only: no new SQL, Edge deployment, secret change or data deletion is required beyond the preceding usability release. If that preceding release has not been installed, its one-time usability_update.sql (018–020) and existing iv-branch-auth / provision-gym-tenant updates are still required for persisted short codes and report metadata. Do not rerun a successfully installed SQL delta.

Review the new preview and promote the matching commit in Vercel → iron-vault for ironvaultph.vercel.app. Continue using the production domain rather than generated protected deployment URLs. No production deployment or live database action was performed by the agent.

Validation: 159 local tests pass, including active-only manual search, member code display, zero-balance/owner and stale-balance removal guards, exact money totals, expiry states and separate activity/session data. Local browser mocks exercise sales, report search/CSV, expiry, separate activity, scoped login and access revocation; real acceptance remains owner-run.
