# Dashboard single-file installation

These generated files contain the same implementation as ../functions, including all shared helpers. Use one whole file as the corresponding function's index.ts; do not combine several files. Existing ../functions source remains the CLI/multi-file option.

| Function name | Paste this file | Verify JWT |
| --- | --- | --- |
| iv-create-member | iv-create-member.ts | ON |
| provision-gym-tenant | provision-gym-tenant.ts | ON |
| iv-admin-correct-member-email | iv-admin-correct-member-email.ts | ON |
| iv-purge-tenant | iv-purge-tenant.ts | ON; global Super Admin plus fresh password required |
| iv-branch-auth | iv-branch-auth.ts | OFF; authenticated actions validate getUser/current roles internally |

Owner manually deploys after the matching SQL and private mail bindings are ready. No deployment has been performed by the agent. Dashboard: Functions → function → Code → select index.ts → replace all contents with the matching complete file → Deploy updates. For the two new functions, create them with the exact names above. Then check Settings and the JWT flag. Never paste a secret into source; the code reads Edge secrets by name.

Generate with `node scripts/build-dashboard-functions.cjs`. Check freshness with `--check`. Do not hand-edit generated entries. Keep PR #2 in Draft until actual acceptance passes.
