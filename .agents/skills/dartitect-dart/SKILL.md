---
name: dartitect-dart
description: Apply Dart language and runtime semantics to Dartitect producers, streams, cancellation, cleanup, and isolate data transfer. Use when correctness depends on generator, subscription, stack, or isolate behavior; do not use as a general Dart tutorial or architecture selector.
---

# Apply Dart runtime semantics

## When to use

Use this skill when Dartitect or consumer infrastructure depends on exact
`sync*`/`async*`, single-subscription stream, cancellation, cleanup, stack
preservation, sendability, or transferable-data behavior.

## When not to use

Use `$dartitect-incremental` for the higher-level incremental operation,
Flutter command, sync, or worker-pool contracts. Use `$dartitect-performance`
when the question is primarily capacity, algorithmic complexity, or benchmark
evidence. Do not invoke this skill for ordinary syntax or business logic.

## Invariants

Create cold sources per execution and reject broadcast streams where one owner
must control consumption. Await consumer work before requesting the next item.
Cancellation stops admission, awaits subscription cancellation and producer
`finally`, and fences late publication. A plain `Iterator` has no cancel/close
protocol; resource-owning synchronous sources need an explicit cleanup seam.
Preserve original errors and stacks. Never infer retries or make a VM-only
boundary run silently on the web or main isolate.

## Workflow

Identify the source kind, its owner, the cancellation path, and the terminal
cleanup order before coding. Then check sendability and platform support for
every isolate boundary.

Read [references/streams-and-cancellation.md](references/streams-and-cancellation.md)
for producer and subscription behavior, and
[references/isolate-data.md](references/isolate-data.md) for worker messages and
transferable bytes.

## Validate

Test list, `sync*`, `async*`, consumer failure, producer failure with original
stack, cancellation during work, exact-once cleanup, nested stream behavior,
unsupported web use, and zero late values or residual workers.

## Dartitect inclusion gate

Before adding a capability, answer:

> Is it business-neutral, difficult to implement correctly, and a source of
> repetitive infrastructure in consumer applications?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
