> Superseded by [SERVICE_PAGES_ROLLOUT.md](SERVICE_PAGES_ROLLOUT.md). The PDF workflow is retired by 038; do not use these historical publication steps for the current UI.

# Private PDF service documents

This replaces the normal policy-writing wizard with six editable subscription settings and three PDF uploads: Terms of Use, Privacy Notice and Data Processing Agreement. Earlier text versions, owner acceptance receipts and approved subscription periods remain intact. Installation publishes nothing and activates no subscription.

## Manual deployment order

1. Confirm migrations through **036** are already applied. Do not rerun 035. Back up through your normal project process.
2. In Supabase SQL Editor run **supabase/manual/pdf_service_documents.sql** once. It is identical to **supabase/migrations/202611050037_pdf_service_documents.sql**; run only one copy. The installer rejects an existing installation or a conflicting bucket. The agent has not executed SQL, including locally.
3. Create the new Edge Function **iv-service-pdf**, paste the complete **supabase/dashboard/iv-service-pdf.ts**, and deploy. Keep **Verify JWT ON**. Use the same real APP_URL, CORS_ORIGINS, SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY configuration as the existing trusted functions. Never put the service-role key in the frontend. Existing functions need no replacement for this change.
4. Merge the frontend branch and let Cloudflare build only after the SQL and new function are ready. Refresh open sessions.
5. Open **Service Agreement Settings**. Set the six subscription values; upload the three reviewed PDFs; set a unique version label and effective date; save the draft. Use **Copy subscription settings** to compare PDFs with CURRENT, SAVED DRAFT and SCHEDULED values. Unsaved inputs are deliberately excluded. Export/retention values are also included in the reference for document review.
6. Review all three documents, check the confirmation and explicitly publish. A first publication may take effect today; later versions require at least 30 days or a longer applicable promised notice, and must follow queued versions. Registered owners receive old/new settings and effective-date notices, plus an effective-day notice. Saving and uploading never notify owners.

## Document and access rules

The new iv-service-documents bucket is private. Only the global provider account uploads through the verified Edge endpoint. Enabled registered gym owners can read published versions, including scheduled versions; staff and anonymous users cannot. Draft files are provider-only. Owners see PDFs, Open PDF and Download PDF links, and an unchecked agreement checkbox. Existing acceptance RPCs record the exact version; viewing alone is not acceptance. Each version retains its own files and settings. Changes do not rewrite approved periods or historical receipts.

Uploads must be actual, unencrypted PDFs, at most 5 MiB and 100 pages. The server parses them and rejects recognized scripts, attachments and active actions. SHA-256, size and page count are registered. Storage objects cannot be replaced through the client. Lost upload/publication responses can be retried with the same request identifiers. Signed viewing URLs expire after five minutes; downloaded copies and links held during that interval can be shared. This is access control, not DRM.

The copy button performs no external AI submission. There is no automatic legal review or PDF text-to-price consistency check. A human must ensure the PDFs agree with the saved app settings, actual provider identity, infrastructure and practices. Do not publish earlier draft PDFs containing unresolved notes. Documents are provider-level: exclude gym-specific private information. The accepting gym is identified in its acceptance receipt.

The app continues using the version effective on the current Philippine date. Structured settings govern quotes and access; changing PDF wording alone cannot change prices. Price changes protect approved periods. Owner confirmation and the existing activation, renewal, proration, grace and suspension rules remain. The legacy editor remains available for text draft/preview/history; after the first PDF publication, further legacy text publication is blocked to keep one publishing workflow.

Failed or unattached draft uploads are not automatically deleted. Review these privately before any future cleanup; never remove files referenced by published versions. No production documents have been uploaded by the agent.

## Staging checks after manual deployment

- Test provider upload and owner viewing on phone and desktop, including Open/Download fallback. Reject malformed, oversized, encrypted and active-content PDFs.
- Verify anonymous/staff access, owner access to unpublished files, revoked accounts and overwrite/delete attempts are denied using actual Supabase Storage policies.
- Save in two provider sessions: stale revisions must fail. Change legacy numeric settings after a PDF draft save: publication must require resaving/reviewing.
- Retry the same upload and publication after a lost response; ensure no duplicate version/notice. Concurrent requests and different bytes under an existing upload ID must fail safely.
- Publish a future version: current quotes remain unchanged before its effective date, owner-only notices state old/new settings, and the new settings apply on the Philippine effective day. Check longer previously accepted notice promises and queued versions.
- Confirm historical acceptance receipts and period amounts/dates remain unchanged; accept a PDF version and verify the recorded version and corresponding PDFs.

Local checks cover parser behavior, SQL contracts, UI behavior and builds. Live database policies, migrations, scheduling and deployed Edge integration require staging verification after the user applies SQL; SQL was not executed by the agent.
