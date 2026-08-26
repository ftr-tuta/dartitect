# Sync execution

Use `dartitect_sync` only when a feature needs an explicit dataset DAG,
checkpoints, leases/fencing, progress, deadlines, or headless acknowledgements.
The repository operation commits remote results into the authoritative local
transaction before returning a confirmed checkpoint. A failed dependency blocks
only downstream datasets; independent branches continue.

Treat checkpoint and lease ports as borrowed. Persist the lease fencing token
atomically with checkpoint writes and reject stale writers. Validate headless
payloads before graph creation, create a fresh `OwnedGraph` per accepted request,
deduplicate request IDs, and transfer data rather than provider objects. Retry,
scheduling, authentication, conflicts, schemas, and durable cross-process
deduplication remain consumer policy. Expected failure returns `Err`; an
unexpected exception preserves its stack and is never retried automatically.
