# Local-first pagination

`PagedLiveResource<C, K, T, F>` requests a `PageBatch`, deduplicates by the
consumer key callback, and gives a `PageWrite` to the repository-owned local
transaction. The transaction returns a `PageWriteReceipt`; advance the cursor
only after the borrowed `LiveResource<PagedLocalSnapshot<K, T>, F>` publishes
that exact revision. Update the exposed `LiveCollection` only from the local
snapshot.

Refresh uses a joining lane, load-more drops reentrant calls, and search uses
restart-latest. Check cancellation before local write so a stale search cannot
patch the database. Expected request, write, or observation-timeout failure
preserves last local data and the valid cursor. Keep the synchronous timeline
bounded to phase facts rather than domain payloads.
