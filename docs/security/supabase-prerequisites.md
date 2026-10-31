# Missing Supabase evidence and how to retrieve it

No Supabase project was accessed. No SQL or Supabase CLI command was executed. Main and the advertised documentation branch contain no Edge Function source. The checkout is not shallow; no tracked backend source was found in the available repository history. Earlier unverified local drafts are preserved in stash, not reused as deployed definitions.

## Supplied exports: reviewed, no repeat requested

All 11 supplied 2A–4F exports and all supplied M1–M7 result files are reviewed. The previously missing Auth summary and within-tenant duplicate counts are now supplied. See inspection-review-m1-m7-20261101.md. Do not repeat these exports or the completed remaining_authorization_checks script.

The owner reports T1–T5 complete, but T1/T3/T4/T5 attachments are not available in this turn/workspace; supply the existing exports, do not rerun them. T2 succeeded with zero rows and needs no CSV. See trigger-schema-dependency-status.md. Only the targeted SELECT-only default_acl_compatibility.sql (executor/creator memberships and private namespace) remains an outstanding inspection result. Return labeled results and errors unchanged. Redact credentials, tokens and recovery links from any sources/configuration shared.

## Existing Edge Function source

In the intended Supabase project open **Edge Functions**, select each function, and open its **Code/source editor** if available:

1. provision-gym-tenant
2. iv-create-member
3. iv-admin-correct-member-email

Provide the deployed entry point and every imported local helper/configuration file. Record the function name and displayed deployment version/time, if available. Include whether JWT verification is enabled and names/presence of required environment bindings, never their values. Do not press Deploy, change verification, or edit secrets.

If the Dashboard does not expose downloadable source, the owner can use their own authenticated Supabase CLI to read/download each deployed bundle:

```sh
supabase functions download provision-gym-tenant --project-ref <project-ref>
supabase functions download iv-create-member --project-ref <project-ref>
supabase functions download iv-admin-correct-member-email --project-ref <project-ref>
```

These commands read the deployed function and write local files on the owner's machine; they do not deploy or execute SQL. Do not run functions, publish a bundle, send credentials in chat, or include secrets in the returned source. If deployment was from an external CI/repository, provide that exact deployed revision and shared dependencies instead. If the deployed bundle cannot be retrieved, identify that specific gap rather than assuming the local drafts are equivalent.

## Non-secret Auth configuration checklist

Dashboard section labels can vary by version. Report the settings without saving changes:

| Location | Non-secret details needed |
| --- | --- |
| Authentication → Sign In / Providers (or Providers) → Email | Email/password enabled, signup enabled/disabled, confirmation required, secure email-change setting, password requirements, password-change reauthentication setting if present. |
| Authentication → URL Configuration | Site URL and allowed redirect URL patterns; intended local/staging/production application origins and hosting subpaths. Do not include a URL with a live token. |
| Authentication → Email / SMTP Settings | Built-in versus custom delivery, configured/working status, verified sender domain/address as appropriate; provider name only. Never supply SMTP/API credentials. |
| Authentication → Email Templates | Confirmation, recovery, invite and email-change template structure/placeholders and any custom redirect logic. Replace tokens/keys with placeholders. |
| Authentication → Sessions | Configured session lifetime/inactivity/single-session controls and desired multi-tab behavior. |
| Authentication → Auth Hooks | Which hooks are enabled, their purpose, and redacted source for custom hooks; whether email delivery is intercepted. |
| Authentication → Rate Limits / Attack Protection | Current signup/recovery/login throttling and CAPTCHA enabled/disabled/provider; no CAPTCHA secret. |
| Project Settings → Data API | Exposed schemas and max-row limit only; keep ironvault_private unexposed. |
| Project Settings → JWT/Signing Keys, if relevant | Legacy versus asymmetric signing mode and JWT expiry configuration only; never signing secrets/private keys. |
| Authentication → other enabled Providers | Provider names and any identity-linking behavior used by current test accounts; no provider secrets. |

The branch-independent requirement is already confirmed: the same contact email may have different passwords at different gyms. No repeat decision is needed. Staff financial reporting is explicitly tenant-scoped and administrator-granted. Normal member deletion retains financial history. No reset has been approved or performed in this stage.

## Remaining trigger/schema dependencies

T1–T5 are reported complete. Return only the existing T1/T3/T4/T5 files; no T2 CSV or repeated SQL is needed. Exact constraint/index/column definitions have not yet been reviewed. The reported Auth signup trigger must be preserved and accounted for in provisioning.

Return each labeled result set and any errors unchanged. Inspect definitions for secrets before sharing them. PostgreSQL catalogs may not record dependencies inside every PL/pgSQL/dynamic-SQL body; referenced helper bodies and Edge Function source still need review.
