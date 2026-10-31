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
11. Avoid modifying unrelated files or features.
12. Never commit passwords, secret keys, or other credentials.
