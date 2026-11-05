# Tenant service pages, notifications and test-data cleanup

## Scope and safety

This replaces PDF uploads with the guided Provider form and shared, tenant-specific Terms of Use / Privacy Notice / Data Processing Agreement pages. Templates are based on the three user-supplied simplified drafts. Actual database regions, email delivery, overseas processing, backups and payment instructions remain fields the Provider must verify. Existing filled contact/policy fields are retained; nothing is automatically published. The draft address/name are the user's supplied details, not a claim of business registration or legal certification.

SQL 038 labels every currently enrolled gym Test. Future enrolments default Live. Test is a reporting/selection label, never an entitlement or authorization bypass. Provider list filters and Live metrics use the private subscription tag; member balances and gym operational reports are unchanged. No tenant is purged by either installer.

PDF deletion is explicitly authorized test-data cleanup, not a general retention policy. Storage objects must be removed through Storage API, never by deleting storage.objects rows. SQL 039 removes test PDF versions, files registry, PDF draft, matching acceptance records and document notices. Existing approved periods retain amounts, dates, numeric policies and references. Their foreign keys move to retired, non-PDF numeric-policy rows; these are not document archives and are never offered for acceptance. Pending requests tied to removed PDF versions are cancelled and must be requoted. Historical text documents and unrelated records are preserved.

## Manual rollout order

1. Confirm **037** and its prerequisites are installed. Use your normal backup process if you need copies. Keep all existing gyms Test until step 6; do not onboard Live gyms during this one-time cleanup.
2. Run **supabase/manual/tenant_service_pages.sql** once in Supabase SQL Editor. This is the exact copy of migration **202611050038_tenant_service_pages.sql**. Run only one copy. Never rerun 035 or 037. The agent has not executed SQL, including locally.
3. Retire the deployed **iv-service-pdf** function: replace it with the complete denying entry **supabase/dashboard/iv-service-pdf.ts**, keeping Verify JWT **ON**, or delete that obsolete function in Supabase. The new frontend never calls it. SQL 038 also revokes the old registry/publication RPCs and denies PDF reads.
4. Deploy the new **iv-cleanup-test-pdfs** function using the entire **supabase/dashboard/iv-cleanup-test-pdfs.ts**, Verify JWT **ON**. Keep your actual APP_URL/CORS_ORIGINS and standard Supabase environment bindings. No secret values belong in browser files. Other Edge Functions do not need redeployment for these changes; their generated bundles remain unchanged.
5. Merge the frontend branch and let Cloudflare build. Refresh sessions. In the Provider menu choose **Remove test service PDFs**, type **DELETE TEST SERVICE PDFS**, then submit. The function deletes only the dedicated iv-service-documents bucket's UUID-named document objects, in batches of at most 100. Repeat if it reports more remain. Unexpected files stop cleanup for manual Storage review. Once empty it removes the bucket. No backup is created.
6. Run **supabase/manual/remove_test_service_pdfs.sql** once. It is the exact copy of **202611050039_remove_test_service_pdfs.sql**; run only one copy. It refuses to run if Storage objects remain, or if an existing gym is not explicitly Test. It removes PDF database records in dependency order and preserves approved subscription periods. Refresh the Provider page; the cleanup menu item disappears once no PDF versions or bucket remain. You may then remove the temporary iv-cleanup-test-pdfs deployment.
7. Open **Service Agreement Settings**. Review Provider contacts, subscription settings and prefilled policies. Complete verified infrastructure, backup/deletion and payment details. Choose a new document version. Save, copy settings/documents if needed, preview all three pages, explicitly review and publish with the permitted effective date. Historical text publications, accepted promises and queued versions still control minimum notice; they are not erased by PDF cleanup.
8. Each registered owner reviews **My Plan & Subscription → Agreements**. Missing gym legal details must be completed first. The owner explicitly accepts the precise version. New acceptances preserve full rendered text, the tenant/owner identity, version and timestamp. A review hash prevents accepting a document after the gym details change behind the preview.

Do not run 039 before Storage cleanup. Do not run both a migration and its manual copy. The frontend requires 038 and the cleanup action requires its new deployed function. No live SQL, Storage deletion, publication, deployment or tenant purge was performed by the agent.

## Everyday workflow

### Provider

The header bell opens a Provider-only notification feed. Subscription requests, references and accepted-document onboarding work link to the selected tenant. Notices are read per Provider account and resolve when the work is completed. Authorized dashboard reloads refresh the console; visible dashboards poll lightweight unread counts once per minute; they do not download document bodies or announcement delivery histories for badge refresh. Signout/account changes clear the UI.

The header menu contains Platform Legal Details, Service Agreement Settings, Tenant announcements and Sign Out. The standalone Gym subscriptions button is gone. **Manage Subscription** is beside each tenant's View Branch and inside branch inspection. Approval/password and first-pilot requirements remain. A Provider can return a stale request for review with a recorded reason; this does not refund money and preserves submitted reference/history. Resolve any received payment before the owner submits a fresh quote.

**All / Live / Test** filters control the tenant list; headline Live gym/member metrics exclude Test gyms. The private console also returns Live approved-subscription totals. Mark Live / Mark Test records a tag-change event. Test badges appear on the Provider's list/inspection and authenticated gym dashboard. No records or restrictions change when retagging.

Announcements support **All Live gyms** or an explicit list of one or more gyms, including Test gyms. They are delivered only to the registered owner bound at publication. Recipients are frozen at publication, not dynamically expanded when new gyms join. Optional schedule dates use Philippine time. Provider delivery history shows each recipient's read status; owners never receive recipient lists. A general announcement cannot change prices, contracts or acceptance. Use formal publication for those changes.

### Registered owner

The bell opens **Notifications**, not subscription tabs. Opening a notice reveals its message and records it as read; it no longer appears in the active feed on the next opening. The unread badge/wiggle updates immediately. Periodic owner refreshes fetch only access/setup flags and an unread count; full documents load when opening the subscription screen. Related actions open the appropriate subscription/agreements screen. Read/resolved billing notices appear in subscription History; read announcements have a separate collapsed archive in Notifications.

**My Plan & Subscription** has My Plan, Agreements and History. Plan cards explain inclusions and total prices. The flow is review server quote → explicitly confirm request → payment instructions/Contact Provider → submit reference → await verified approval. Pending requests block accidental duplicates. Owners may cancel only a still-unpaid request; submitted references require Provider review. A reference alone never approves payment.

The existing server billing rules stay intact: Philippine-time next-day counting, pilot-to-paid queuing, early renewal preservation, grace renewal from the original due date, fresh post-suspension periods, prorated upgrades and next-period downgrades. Test PDF cleanup changes only agreement references in quotes. Existing approved periods keep recorded prices and dates. Future approved periods display Scheduled.

On verified renewal, covered old-period reminder/expiry/grace/suspension notices resolve, including unread notices and future ones. The new period retains its own 7/3/1-day reminders and approval/start notices. Unrelated announcements and document notices do not resolve with payment. Notices are in-app, not automatic email or SMS.

### Purge

Purge remains available for Test and Live gyms with the existing fresh Provider password, exact typed tenant confirmation and reviewed summary. The summary now includes the tag, subscription periods, requests, acceptances and notification counts. The warning asks for needed exports/backups and retention review but does not require a backup before proceeding. Tenant-owned database subscription/acceptance/notification rows cascade with that tenant. Dedicated Auth deletion uses the existing bounded/resumable Admin API process; shared accounts remain. Global document templates and Provider-wide announcement metadata are not tenant-owned records and remain; target delivery links are removed. External exports, mail logs, infrastructure backups and separately stored files need their own review. No automatic refund or backup occurs.

## Verification and limitations

Local tests cover retirement/cleanup authorization, bounded Storage API batches, unexpected objects, exact installer copies, snapshot/hash contracts, tag defaults, audience isolation/replay checks, notice resolution and preserved date/pricing code. SQL is parsed, not executed, per repository rules. Browser checks use actual UI code and mocked RPCs at 320/375/639/640/1280 widths. Cloudflare builds and generated entries are checked.

After the user applies SQL, verify in a staging/test project: actual function permissions and RLS; cross-tenant/staff denial; concurrent acceptance/profile edits; replayed publication/announcement requests; stale quotes and returns; current versus queued policy dates; approval during pilot/grace/suspension; announcement schedule/read receipts; unread reminder resolution; all cleanup guards; retained numeric-period values; and existing resumable purge with new cascades. In-app documents are not automatically certified legally compliant, and publication remains an explicit Provider action.
