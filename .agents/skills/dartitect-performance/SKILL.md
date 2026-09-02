---
name: dartitect-performance
description: Diagnose, improve, and benchmark Dartitect runtime efficiency with bounded structures and structural complexity gates. Use for hot queues, listener dispatch, DAG scheduling, retention, scan throughput, or benchmark evidence; do not use for speculative micro-optimization.
---

# Bound runtime efficiency

## When to use

Use this skill when a repeated path may grow with emissions, listeners,
dependencies, destinations, files, queued work, or retained history, or when a
change needs reproducible latency, memory, or throughput evidence.

## When not to use

Do not optimize an unmeasured cold path or trade away public ordering,
ownership, cancellation, privacy, or failure semantics. Use
`$dartitect-incremental` to design the incremental contract and
`$dartitect-dart` to resolve language-runtime correctness first.

## Invariants

Every in-memory queue and history has a visible capacity or eviction policy.
FIFO front removal is constant-time, retained weight is maintained in O(1),
listener dispatch is reentrancy-safe O(N), and topological scheduling uses
dependents plus indegrees rather than repeated full scans. Preserve stable
public order and isolate callback failures.

Structural complexity and bounds are release gates. Wall time, RSS, first item,
p50, and p95 are informative unless compared on the same controlled runner.
Never weaken cleanup, backpressure, or privacy to improve a benchmark.

## Workflow

State the input scale and required bound, inspect the execution model, identify
the retained state and asymptotic path, make the smallest semantics-preserving
change, then measure a curated set of representative cases.

Read [references/hot-paths.md](references/hot-paths.md) for implementation
patterns and [references/measurement.md](references/measurement.md) for the
benchmark and evidence contract.

## Validate

Prove capacity rejection/eviction, stable order, reentrant removal, isolated
callback crashes, linear DAG/listener behavior, bounded slow-consumer state,
cancellation cleanup, and identical public results. Run positive and negative
execution-model fixtures and record benchmark environment with every metric.

## Dartitect inclusion gate

Before adding a capability, answer:

> Is it business-neutral, difficult to implement correctly, and a source of
> repetitive infrastructure in consumer applications?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
