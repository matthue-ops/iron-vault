# Short gym login and profile filenames

Canonical gym pages are now `/gym/login.html` and `/gym/profile.html`. Their existing forms, roles, branding, membership/payment behavior, QR tools, announcements and live-update controllers remain in the real pages. Visible Member Portal/Profile labels are unchanged.

| Original address | Compatibility destination |
| --- | --- |
| `/gym/memberlogin.html` | `/gym/login.html` |
| `/gym/memberprofile.html` | `/gym/profile.html` |

The original files remain as small same-origin JavaScript forwarding pages. They use `location.replace` so they do not add a back-button redirect loop. They preserve the complete query string and fragment, including gym keys, recovery/verification tokens and standard Auth session fragments. They perform no authentication, API requests or storage changes themselves. The real destination page still verifies access normally. JavaScript remains required, as it already is for the application.

Readable entrance links such as `/fitness-gym` remain the same; the existing Vercel rewrite now serves `gym/login.html`. The filesystem-first rule and other application paths are unchanged. Portal fallback links, ordinary sign-in/sign-out/error navigation and displayed/copied entrance addresses use the new filenames. The shared route helper also accepts its previous member-profile argument and returns the new profile path.

## Supabase compatibility

This is a frontend-only change. No SQL, database migration, Auth setting change or Edge Function deployment is required. Existing deployed mail functions and fallback Auth callbacks deliberately retain `/gym/memberlogin.html`, which forwards their query/fragment to `/gym/login.html`. Keep the existing Supabase allowed callback addresses and both compatibility files. Do not remove them while old printed QRs, bookmarks, emails or deployed callback generators still depend on them.

Changing future email generators to use the new URL directly can be a separate coordinated change with the relevant allowlist/deployment review. It is not necessary for this rename.

## Review and rollout

Review the branch preview, then merge the frontend PR through the existing Vercel workflow. Test both canonical pages and the old addresses. Use an existing approved test member to sign in, open the profile, generate the daily QR and sign out. Verify a gym owner/staff sign-in and Reports navigation. Keep a member and desk open for the existing live-update smoke test. Test a real recovery/verification email using an authorized test inbox when performing hosted acceptance; the agent has not sent emails or changed any account.

Validation: all 276 local Node tests passed. They cover the real controllers at the new paths, alias forwarding with complete query/fragment preservation, same-origin redirects and existing callback support. Mocked Chromium checks passed at 320, 375 and 1280 pixels for two gym brands, all login tabs, friendly URL refresh/trailing slash, sign-in/signup/recovery requests, Copy/QR destinations and no missing assets. Dedicated mocked callback checks exercised legacy verification, recovery, wrong-gym denial, profile forwarding and logout. The existing multi-device live-update checks also passed with the new filenames. Hosted Auth acceptance remains a user check; no SQL, backend deployment, email, production promotion or merge was performed by the agent.
