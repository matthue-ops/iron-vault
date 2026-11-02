# Activity names and roles

Scope: Reports → Activity only, including its search, CSV and print output. No unrelated page, financial calculation, authentication rule or access permission is changed.

## Manual rollout

1. With the previously installed report/account updates (020/021), run the **entire** `supabase/manual/activity_actor_names.sql` in the Supabase SQL Editor. This is migration 022 only, is transactional and may be repeated. Do not rerun the older installation/usability bundles.
2. Test the branch preview with the same gym report link. Then create/review the branch PR and merge into `main` when satisfied. Vercel deploys `main` automatically; no manual promotion is needed. No Edge Function update is required.
3. Verify an owner login shows `Name — Gym Admin`, a staff login shows `Name — Staff`, and administrative events identify both the actor and known target accounts. Search by name/role and compare CSV/Print with the displayed records. Confirm ordinary staff without report permission still cannot open the report.

The SQL replaces only `public.iv_report_snapshot`. It keeps its existing tenant/date/permission check, financial/attendance/member/purchase data and existing function privileges. It appends an `actors` list containing only IDs, names and roles referenced in the selected tenant's administrative/session records. No emails, passwords or other Auth metadata are returned. Tenant role, member, staff and provisioning lookups are constrained to that tenant; a global Super Admin is included only when referenced in that report. Revoked/disabled accounts may be identified for historical attribution, without being reenabled.

Existing records and IDs are not rewritten. Names and roles reflect **current available account information**, not a new claim about the person's name/role at the original event time. Staff names come from the saved staff profile with the protected provisioning name as a fallback. Missing identities display `Account unavailable`; missing names on a known role display `Name unavailable`. System events remain `System`. Known account IDs in Details are labeled; unrelated UUID references, such as receipt IDs, stay unchanged.

The SQL is backward compatible with the older frontend, so apply it first. Without the SQL, the new frontend still loads reports but cannot resolve missing identity data. If an older migration later replaces `iv_report_snapshot`, reapply 022 last.

Validation: 182 native Node tests passed, covering owner/staff labels, corrected login/logout roles, administrative targets, name/role search, CSV/Print consistency, revoked report access, identity clearing, unavailable identities, text-only rendering and preservation of non-account references. SQL and PL/pgSQL parsed with pglast without execution. Chromium with mocked backend data passed at 320, 375 and 1280 pixels, showing owner/staff names with no JavaScript errors or horizontal page overflow. Actual database execution and hosted acceptance remain owner-run. No SQL, deployment or merge was performed by the agent.
