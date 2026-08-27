# Sync execution

Use `dartitect_sync` only when a feature needs an explicit dataset DAG,
checkpoints, leases/fencing, progress, deadlines, or headless acknowledgements.
The repository operation commits remote results into the authoritative local
transaction before returning a confirmed checkpoint. A failed dependency blocks
only downstream datasets; independent branches continue.

Treat checkpoint, lease, and optional cleanup ports as borrowed. With a lease,
call `context.authority.ensureAuthority()` immediately before the dataset commit
and atomically compare/commit its fencing token in a capable consumer Store.
Persist the same token with checkpoint writes. If storage cannot enforce the
token, explicitly declare dataset fencing unsupported. Inspect application,
checkpoint, journal, lease-release, and cleanup receipts before retrying a
`SyncRunTerminalException`.

Validate headless payloads before graph creation, create a fresh `OwnedGraph`
per accepted request, deduplicate request IDs, and transfer data rather than
provider objects. Retry, scheduling, authentication, conflicts, schemas, and
durable cross-process deduplication remain consumer policy. Expected failure
returns `Err`; an unexpected exception preserves its cause/stack and is never
retried automatically.
