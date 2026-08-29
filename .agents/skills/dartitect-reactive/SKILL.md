---
name: dartitect-reactive
description: Implement Dartitect ReactiveOwner, hot/warm/cold lifecycle, LiveResource, causal refresh, families, collections, selectors, and headless builders. Use for the opt-in advanced Flutter reactive runtime; do not use for basic commands/ViewModels or durable offline mutations.
---

# Build a reactive Dartitect runtime

## When to use

Use this skill when a feature needs explicit dependency tracking, temperature,
authoritative live sources, causal refresh, bounded keyed resources, incremental
collections, explicit-dependency derived async resources, selectors, debounce,
or reactive Flutter builders.

## When not to use

Use `$dartitect-runtime` for basic commands and ViewModels. Use
`$dartitect-offline-first` when paging or mutation correctness depends on local
database authority, an outbox, retries, conflicts, or crash recovery.

## Invariants

One `ReactiveOwner` owns a graph; disposed owners are terminal. Resource data
state is separate from hot/warm/cold temperature. Sources create activation-local
sessions and borrow injected providers. Refresh completion must name its causal
boundary. Collections publish complete validated updates atomically. Widgets
borrow resources and never dispose them from `build`.

## Workflow

Choose owner and activation policy, model the authoritative source, select the
required refresh completion type, then add bounded families/collections and the
smallest builder entrypoint. State backpressure, retry, retention, and disposal
semantics explicitly.
For a derived resource, also name every dependency, stale-data policy, equality
rule, cancellation behavior, and generation guard. Reuse the existing family
boundary rather than creating a parallel key cache.

Read [references/lifecycle-and-resources.md](references/lifecycle-and-resources.md),
[references/families-and-collections.md](references/families-and-collections.md),
or [references/selectors-and-builders.md](references/selectors-and-builders.md)
for the feature being implemented.

## Validate

Test hot/warm/cold transitions, stale-publication rejection, expected failure,
crash-and-explicit-retry, backpressure, exact causal refresh, bounded eviction,
atomic collection failure, selected rebuilds, TickerMode pause, and complete
graph cleanup.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
