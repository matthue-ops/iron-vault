# Full draft correction and simple detail rows

This corrects the shortened legal text and confusing combined editor from migration 030. The exact user-supplied draft is preserved in `docs/legal/member-portal-source-draft.md`. All 12 Terms sections and all 12 Privacy sections are retained in the templates. Only bracketed details are substituted; the author instruction “Before publication, complete the actual schedule” becomes the member-facing “The applicable retention schedule is.” Empty optional refund-policy lines are omitted; omitted age policy directs the reader to ask the gym, without inventing an age rule.

## Enable

1. After **030**, manually run **one copy** of `supabase/manual/full_legal_documents.sql` in the gym Supabase SQL Editor. It is identical to migration 031. No SQL has been executed by the agent.
2. Merge the frontend PR and let Cloudflare deploy. **No Edge Function update is needed** for this correction.
3. Super Admin: open Platform Legal Details. Fill the simple provider rows, including providers/locations and overseas-processing information. Preview and publish. Existing saved contact details are retained.
4. Gym owner (or Super Admin overseeing that gym): open Terms & Privacy. Fill one row for each missing gym detail: date, notice version, business/contact details, privacy contact, notification method, and five separate retention periods. Refund and age/guardian policies remain optional. Preview and publish.

The first view contains only relevant rows and Save Draft / Preview Documents. Preview opens the full documents below, with Terms/Privacy tabs and the review/publish controls. Version history, raw IDs and acceptance records stay in a collapsed advanced section. Provider fields are not mixed into the gym form. Login emails are still not copied to public fields.

## Version preservation

This migration replaces only the management/public rendering functions and adds private v2 token-rendering helpers. It adds no tables, changes no existing draft rows, and rewrites no published documents, acceptance records or accounts. Newly published gym versions carry the complete template text and a v2 marker alongside their detail values. Newly accepted documents are composed from that frozen template plus the exact immutable gym and platform version pair. A platform update can therefore supply its newer legal identity without rewriting the gym's original version; older pinned pairs remain reproducible. Do not change the v2 renderer in a later revision: introduce a new template/renderer version instead.

Previously accepted short documents keep their original two-section display. To make the full drafts current, publish the corrected provider details and a new gym version; old receipts retain their old IDs. Version-history preview shows each gym version's full body as saved at publication; public pinned links use the exact accepted pair. The public RPC's existing tenant/version isolation and private draft permissions are retained. Missing current provider information blocks publication rather than inventing details.

The full texts are rendered with safe DOM creation: headings, paragraphs, bullet lists and the retention table are formatted, without executing supplied HTML. Token substitution scans only the original template so bracket-like user text cannot substitute another field. No marketing opt-in, automatic cleanup, automatic member email or mandatory reacceptance for existing members is introduced.

## Checks

Automated checks compare the full templates against the uploaded draft after placeholder normalization, verify all 24 numbered sections, row separation, pinned-version behavior, old-version preservation, and existing signup safeguards. SQL/PLpgSQL parsing is not database execution. After the user installs 031, verify private previews, publication, old/new pinned pages and new signup acceptance against the real Supabase project. Legal wording, actual policies, contacts and retention statements still need the operator's review before publication.
