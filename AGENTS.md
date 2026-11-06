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
15. Keep deferred, future, or currently out-of-scope implementation ideas in `docs/future-implementation/`, with an entry in its `README.md` and a clear deferred/proposal status. Consult that index when the user asks to revisit future work. Saving an idea is not implementation authorization: do not automatically include it in a current task or reopen completed work. When an item is explicitly approved and completed, update its status and reference rather than carrying it forward as pending. All other approval and manual SQL rules remain in force.
