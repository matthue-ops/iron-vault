# Iron Vault development rules

1. This platform is currently under development and testing.
2. Preserve all existing working functions unless explicitly requested otherwise.
3. The user will manually execute Supabase SQL through the SQL Editor.
4. Generate required SQL changes as separate migration files.
5. Never attempt to execute SQL against the user's Supabase database.
6. Never delete existing data, tables, or columns without the user's approval.
7. Keep application changes compatible with the database schema.
8. Explain which SQL statements the user needs to execute and in what order.
9. Do not assume database changes have been applied until the user confirms.
10. Test affected functions whenever possible.
11. Do not alter any functions, UI, files, or features unrelated to the current implementation. Preserve existing behavior and appearance outside the requested scope.
12. Never commit passwords, secret keys, or other credentials.
13. Before implementing any change that affects the database, inform the user of the intended changes, affected data or schema, and potential impact, and wait for explicit approval. This includes changes to database queries, writes, migrations, permissions, policies, and stored functions, even when no SQL will be executed by the agent. Approval does not override the rule that the user manually executes Supabase SQL.
14. Treat chat messages as inquiries by default, not authorization to make changes. Discussion, questions, reviews, suggestions, and additions to held plans do not authorize implementation. Read-only inspection and explanations may continue, but make changes only when the user explicitly says to implement or execute the identified scope, or directly instructs a specific edit such as updating this file. Once authorized, complete that scope without repeatedly requesting the same approval. All existing rules remain in force, including database approval requirements and manual SQL execution by the user.
15. Keep preliminary future or currently out-of-scope ideas in `docs/future-implementation/`, indexed in its `README.md`. These are unfinished ideas for later discussion, not finalized requirements or an execution queue. When the user asks to revisit an idea, discuss and evaluate it individually, inspect the current app, and refine its scope together before execution is considered. Revisiting, discussing, saving, or agreeing that an idea is useful does not authorize implementation. Execute only after the user separately and explicitly instructs implementation/execution of the reviewed scope, following all other approval and manual SQL rules. Do not automatically carry these ideas into current work or reopen completed work.
