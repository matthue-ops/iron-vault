# Super Admin gym accent colors

Apply `supabase/manual/gym_accent_colors.sql` manually in Supabase SQL Editor **after migration 027 (live dashboard updates)** and before deploying the matching frontend. This is the same SQL as migration 028; run one copy only. The agent has not executed it.

The migration adds `owners.accent_color` with a six-digit hex constraint and emerald default, appends that safe branding field to the existing filtered `iv_gyms` view, and adds `iv_set_gym_accent`. Existing tenant IDs, wallet balances, plans, pricing, and history remain unchanged. Existing base-table write restrictions remain in place. Only an authenticated, enabled global Super Admin whose access has not been revoked can call the setter successfully. Owners, staff, members, and anonymous users cannot write the color. Existing generic settings saves do not accept the color field.

On either Super Admin page, open a gym's Edit Tenant Details panel. Pick a color or reset to emerald, inspect the local preview, then click **Save accent color**. This saves independently from the other tenant settings. Canceling or closing without saving leaves the stored color unchanged. A new gym starts with emerald and can be edited afterward. Only the admin/staff dashboard consumes this setting; member and login page themes are unchanged.

The owners trigger from 027 emits the existing gym signal. Connected admin/staff dashboards read the new color through their authorized gym view and update without reloading; the existing periodic checkpoint catches missed events. Hidden/offline pages catch up on return. Foreground text on the main accent button automatically switches between black and white for contrast. Warning, approval, and success status colors do not follow the accent. The old admin logo sampler is disabled so it cannot overwrite the saved color.

Before SQL is applied, existing pages default to emerald and the new save button reports the server error rather than claiming success. No Edge Function deployment or new Realtime publication is required.

Validation: automated tests cover color validation, contrast, local previews, reset/save separation, tenant scoping, failed saves, draft preservation, admin application, and SQL authorization contracts. SQL must still be verified against your actual Supabase project: sign in as Super Admin and change one gym, confirm another gym stays unchanged, verify owner/staff RPC attempts are denied, and check another open dashboard receives the change. No database calls were executed during development testing.
