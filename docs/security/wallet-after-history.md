# Money: Transaction amount and Wallet after

Scope: Money's transaction table, its CSV and Print output, and the report query supplying its historical wallet value. Other tabs, calculations, permissions, payment processing and stored records are unchanged.

## Manual rollout

1. After installed 022, manually run the **entire** `supabase/manual/wallet_after_history.sql` in Supabase SQL Editor. This is migration 023 only; it is transactional and safe to repeat. Do not rerun previous installation or usability bundles. No Edge Function update is needed.
2. Test the branch's Vercel preview with the usual gym report URL. If the preview has a new origin, preserve the existing CORS allowlist and add only that exact origin when needed for sign-in.
3. Verify Ian's sequence: top-up ₱100 → Wallet after ₱100; wallet purchase ₱100 → Wallet after ₱0; top-up ₱50 → Wallet after ₱50. Later top-ups must not alter those historical values. Verify CSV and Print match, and Overview still shows current outstanding credit.
4. Review/create the branch PR and merge into `main` after acceptance. Vercel deploys `main` automatically. No manual promotion is needed.

## Source and limits

The existing financial API already stores the resulting wallet balance in `ironvault_private.financial_requests.result` when each top-up or purchase commits. The report now reads that saved value through the existing authorized report snapshot. The receipt must match the ledger row's exact request ID, tenant, member, actor and operation. Only the historical balance is added to each transaction row; raw private receipt payloads are not returned.

No balance, payment, receipt or ledger record is inserted/updated/deleted by this migration. No table/column/trigger is added and no grant is changed. The SQL replaces only `public.iv_report_snapshot`, preserving its tenant/date/report permission checks and all Activity identity metadata from 022. A later reinstallation of 020/022 would replace this report function, so reapply 023 last in that situation.

Rows without a trustworthy linked receipt display **Unavailable**. This can include older entries, recorded refunds without the supported receipt, and the unlinked cash component of split payments. The linked wallet component of a split purchase shows the saved final wallet balance; a cash-only purchase with its own linked receipt shows the saved unchanged wallet balance. No matching by timestamp/amount and no reverse calculation from today's balance is attempted. This avoids manufacturing historical values. Zero is a valid saved balance and is displayed as ₱0.00.

The transaction values do not depend on the selected date range, search or current profile balance. Names/classifications remain current profile data. The Overview outstanding-credit card and member wallet still show current balances.

Apply SQL first; the older frontend ignores the added field. Before SQL is applied, the new frontend will show Unavailable rather than mislabel current balances as historical.

## Validation

195 native Node tests pass, including the 100 → 0 → 50 example, later balance changes, missing/invalid history, cash/refund unavailability, date filtering, CSV/Print, authorization and unchanged non-Money report data. SQL/PLpgSQL syntax parsed with pglast without execution. Local Chromium checks with mocked backend data passed at 320, 375 and 1280 pixels and confirmed historical values stay fixed after changing the synthetic current wallet balance. These do not prove live database execution or hosted acceptance. No SQL, Edge deployment, production deployment or PR merge was performed by the agent.
