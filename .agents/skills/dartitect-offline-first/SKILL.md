---
name: dartitect-offline-first
description: Implement Dartitect local-authority pagination, mutations, durable outbox delivery, idempotency, retries, conflicts, compensation, and crash recovery. Use for offline-first correctness; do not use for generic reactive UI or provider setup alone.
---

# Build offline-first Dartitect flows

## When to use

Use this skill when the local store is authoritative for presentation and remote
pages, mutations, or dataset sync must cross an explicit durable boundary.

## When not to use

Use `$dartitect-reactive` for live UI without persistence/delivery semantics.
Use `$dartitect-adapters` to wire a chosen database or transport provider after
the repository contracts are defined.

## Invariants

Remote data never patches presentation state directly. The repository-owned
local transaction is authoritative. A mutation changes domain data and enqueues
its outbox operation atomically. Reuse one non-empty consumer-scoped idempotency
key for every at-least-once attempt. Persist acknowledgement before reporting
synced. Never auto-rollback queued or uncertain changes.

## Workflow

Define local snapshot and revision contracts, implement page writes or
`applyLocalAndEnqueue`, map expected delivery failures, choose retry/conflict/
compensation policy, and specify new-session recovery. Add provider integration
only at the infrastructure composition root.

Read [references/local-first-pagination.md](references/local-first-pagination.md)
for pages, [references/mutations-and-outbox.md](references/mutations-and-outbox.md)
for writes and recovery, or [references/sync-execution.md](references/sync-execution.md)
for foreground/headless dataset orchestration.

## Validate

Test duplicate remote items, cancellation before local commit, exact-revision
observation, stale search, same-key serialization, different-key concurrency,
idempotent retries, rejection/conflict/uncertain outcomes, compensation,
acknowledgement persistence failure, crash recovery, and zero residual work.
