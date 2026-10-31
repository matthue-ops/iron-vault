# Phase 1 migration and verification entry point

Use the single [Phase 1 progress and acceptance checklist](phase1-status.md) for the evidence ledger, mandatory/optional prerequisites, implementation sequence, testing requirements and endpoint.

Use [the migration README](../../supabase/migrations/README.md) for exact prepared filenames, manual execution order, assertions and recovery. Files 001–007 are prepared, not assumed applied; 004 is optional pending managed-creator authority. Future files are dependencies in the progress checklist, not scripts already created.

No destructive test-data reset or project rebuild is required or included. Preserve existing Auth identities, balances, transaction history and working features. No normal deletion or account operation is authorized for execution. If a future destructive action is proposed it requires a separate exact scope and approval; it cannot be hidden inside these security migrations.
