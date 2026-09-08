# Mutations and outbox

`MutationCommand<A, K, T, F>` serializes operations per entity key. The
`MutationOutboxStore.applyLocalAndEnqueue` implementation performs the domain
write and persists `OutboxOperation` in one transaction. Dartitect does not
define entities, outbox schema, endpoints, or conflict rules.

Map expected delivery failures through `MutationFailurePolicy` to pending,
rejected, conflicted, or uncertain. Only definitive rejection may run an
explicit compensation transaction. Transient retries are opt-in, bounded, and
reuse the operation/idempotency key. An unexpected delivery crash is reported
once and rethrown; if delivery may have committed, persist uncertainty and stop
only that key lane until repository audit, a deliberate pending decision, and
`resume(key)`. On a new session, `recoverPending()` deduplicates idempotency keys
and drains pending records only; uncertain records require human/domain policy.

Borrow a consumer-owned `RetryBudget` through `MutationCommand.retryBudget`
when delivery shares a bootstrap/reconnect admission window. Budget rejection
preserves pending data and identity. Pass typed HTTP feedback through
`MutationFailurePolicy.queued(retryAfter: ...)`; invalid/excessive feedback
defers delivery, and valid server minimums survive jitter. Dispose borrowers
before the budget's borrowed `Bulkhead`; budgets do not own providers.
