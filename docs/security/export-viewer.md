# Read-only export viewer

Open `gym/export-viewer.html`, or choose **View saved export** beside a tenant/Master ZIP export in either Master dashboard. Select a saved ZIP or JSON. No tenant needs to exist and no account/password is required to browse a file you already possess.

Supported ZIP entries are `tenant_owner_export.json`, `tenant_members_export.json`, `ironvault_owners_export.json` and `ironvault_members_export.json`; single owner/member JSON arrays are also supported. Gym details/pricing, member snapshots, included staff and included activity entries have separate views with gym filtering, search and pages of 100 rows. Inactive/deleted tenant snapshots remain viewable. Clear removes the loaded data from the page; nothing is saved to browser storage.

The viewer makes no database, import, upload, or recovery call. Its ZIP-reader library uses the same pinned JSZip CDN version as the existing application. Export contents are rendered through textContent; logos, portal tokens, credentials, and arbitrary HTML/URLs are not executed or displayed. Compressed files are limited to 20 MB, expanded entries to 10 MB each / 20 MB total, with file/row limits. Unknown ZIP files are ignored, ambiguous recognized files rejected.

This does not expand the export format or turn profile import into disaster recovery. Current ZIP exports contain gym/member snapshots and any embedded staff/activity entries, not the full financial/attendance ledger or recoverable account passwords. Displayed credits/pricing are historical file values, not current balances, validated financial totals or proof of payment. The original file remains on the user's device. Viewer deployment requires only the application files; no SQL, Edge deployment or secrets change.
