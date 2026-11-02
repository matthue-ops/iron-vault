# Reports, phone layouts and staff management

This update changes only presentation and the related password validation messages. It adds no SQL or Edge Function changes, changes no stored passwords or records, and does not deploy anything.

Reports open on Overview with four cards: membership sales and visits for the shared selected period, plus current outstanding wallet credit and valid passes. Money, Attendance and Activity have separate panels. Activity combines the existing administrative and staff session logs with a type selector. Search is remembered per table; CSV exports all matching rows and Print shows the active filtered page. Export/Print retain the existing report authorization checks. Additional explanations and existing wallet-credit detail remain expandable.

At phone widths, existing table rows become labeled cards without replacing their controls or handlers. The primary row action remains visible; secondary actions are under a More actions menu. Forms stay within the screen and controls have larger touch targets. Registered staff show name, role and scoped access status with email, report controls, recovery and deactivation inside details. If a status cannot be read, the UI says so. Existing permission RPCs, authorization checks and deactivation confirmations remain.

Creation and new-password fields use “At least 8 characters.” Existing-password sign-in/current-password fields have no new minimum. No existing password is updated automatically.

Validation: 175 native Node tests pass, including report tab/date behavior, combined activity, scoped permission controls, staff details, eight-character creation messages and shorter existing-password sign-in. Local Chromium checks at 320, 375 and 1280 pixels passed four-card Overview, table search, activity filtering, print isolation, expandable staff controls and member cards/menus without horizontal page overflow or JavaScript errors. All browser backend/CDN requests used synthetic mocks; this is not hosted/database/mail acceptance.

Release is frontend-only: deploy the matching HTML and assets together through the existing review process. No new SQL or Edge deployment is required for this UI update. Previously delivered SQL/backend updates remain separate and must not be assumed installed; the last confirmed baseline was 001–017. PR #2 remains for review; do not mark ready, merge or deploy automatically.
