# Sync execution

Dataset DAG synchronization and headless synchronization are separate flows.
Use `SyncEngine` for a validated dataset DAG, checkpoints, journals, leases/
fencing, progress, and deadlines. Use `HeadlessSyncEndpoint` for a versioned
sync definition adapted through `dartitect_jobs`, bounded duplicate retention,
separate acceptance and terminal acknowledgements, and a fresh graph per
admitted request.

Opt into `package:dartitect_sync/dartitect_sync_titect.dart` only for explicitly
selected Titect wire contracts. Keep opaque cursors and exact numeric tokens;
require checked narrowing, bounded reads and parser allocation, explicit
capabilities, and the same retry/read budgets at leaf attempts. The consumer
owns transport, authentication, schemas, integrity policy, durable application
proof and atomic authority checks. Confirm the checkpoint before the next page.
Run the pinned Python/Dart VM/Chrome corpus and real persistent recovery;
preliminary or divergent evidence cannot establish release compatibility.

For a dataset run, the repository operation commits remote results into the authoritative local
transaction before returning a confirmed checkpoint. A failed dependency blocks
only downstream datasets; independent branches continue.

Treat checkpoint, lease, and optional cleanup ports as borrowed. With a lease,
call `context.authority.ensureAuthority()` immediately before the dataset commit
and atomically compare/commit its fencing token in a capable consumer Store.
Persist the same token with checkpoint writes. If storage cannot enforce the
token, explicitly declare dataset fencing unsupported. Inspect application,
checkpoint, journal, lease-release, and cleanup receipts before retrying a
`SyncRunTerminalException`.

For headless work, validate payloads before graph creation, create a fresh `OwnedGraph`
per accepted request, deduplicate request IDs, and transfer data rather than
provider objects. Retry, scheduling, authentication, conflicts, schemas, and
durable cross-process deduplication remain consumer policy. Expected failure
returns `Err`; an unexpected exception preserves its cause/stack and is never
retried automatically.

Use `RetryExecutor` only with explicit expected-failure classification, budget,
deadline, and injected timing/randomness in tests. An uncertain result always
stops retry. Share one `RetryBudget` across the leaf operations used by refresh,
reconnect, outbox, and headless sync in the same isolate. Queue and retry waits
consume the scope window. Keep retries at one layer and pass the same budget
to participating executors; no cross-isolate authority is inferred.
Use `JobDispatcher` for generic bounded headless definitions and
one graph per job; scheduling, recurrence, credentials, schemas, and durable
cross-process policy remain outside the SDK. Use `TransferEngine` for chunks,
pause/resume/cancel, checksums, and post-commit checkpoints; remote protocol,
ETag, Range, auth, and idempotency remain consumer policy.
