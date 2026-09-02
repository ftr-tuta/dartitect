---
name: dartitect-incremental
description: Build bounded incremental Dartitect operations across core, Flutter, sync datasets, and isolate worker pools. Use when work must stream items with backpressure, partial aggregates, cancellation, or bounded admission; do not use for ordinary one-shot commands.
---

# Build incremental operations

## When to use

Use this skill when a workload should expose the first result before the whole
input completes, reduce an explicit aggregate item by item, checkpoint each
confirmed sync step, or dispatch a bounded sequence across isolates.

## When not to use

Keep a finite one-shot command or dataset one-shot when partial progress has no
consumer value. Use `$dartitect-dart` when only language-level stream/isolate
semantics need review and `$dartitect-performance` for profiling or hot-path
changes unrelated to the incremental API.

## Invariants

Import opt-in incremental entrypoints. Bound both item count and cumulative
weight, reject the item that would cross either limit, and retain nothing unless
the caller explicitly folds, collects within a bound, or supplies a ring
buffer. Stop at the first typed `Err`; preserve crashes and stacks. Cancellation
or deadline awaits cleanup before the terminal and prevents late publication.

Flutter coalescing changes notifications only: every admitted item still passes
through the reducer. Sync confirms a checkpoint before pulling the next item.
Worker pools bound workers, in-flight requests, queued requests, and completed
results waiting for order.

## Workflow

Choose the source ownership model, limits and weight, aggregate, expected
failure type, concurrency policy, publication policy, and terminal receipt.
Make the producer factory cold and explicit, then connect only the integrations
the workload requires.

Read [references/operations.md](references/operations.md) for core execution and
[references/flutter-sync-and-pools.md](references/flutter-sync-and-pools.md) for
the Flutter, dataset, and isolate projections.

## Validate

Test zero/one/many items, slow consumers, first `Err`, crashes with original
stack, count/weight boundaries, cancellation/deadline cleanup, partial
aggregate, bounded retention, restart/dispose fencing, checkpoint-before-pull,
pool capacity, ordered/unordered mapping, and zero late work.

## Dartitect inclusion gate

Before adding a capability, answer:

> Is it business-neutral, difficult to implement correctly, and a source of
> repetitive infrastructure in consumer applications?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
