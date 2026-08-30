---
name: dartitect-runtime
description: Implement Dartitect Result, ownership, composition, commands, ViewModels, isolates, and basic Flutter bindings. Use for core or thin Flutter runtime work; route advanced reactive and offline-first behavior to their focused skills.
---

# Build a Dartitect runtime

## When to use

Use this skill for `Result<T, F>`, resource ownership, composition roots, typed
progress, bounded local history, `Command0`, ViewModels, application and session
hosts, generated `FeatureHost`, versioned UI restoration, isolate graphs, and the basic
`dartitect_flutter.dart` entrypoint.

## When not to use

Use `$dartitect-reactive` for `ReactiveOwner`, `LiveResource`, resource families,
live collections, or advanced builders. Use `$dartitect-offline-first` for local
authority, paging, durable mutations, or outbox recovery.

## Invariants

Use constructor injection. Record every resource as owned or borrowed and
dispose dependents before dependencies. Build a fresh graph per app, session,
route, or background isolate. Transfer configuration and validated trace
context—not clients, Stores, subscriptions, or other live resources.

Expected failures use `Result<T, F>`. Unexpected exceptions remain crashes, may
be reported once, and are rethrown with their stack. Keep `BuildContext` out of
ViewModels, domain, repositories, and services.
Application bootstrap extends `ResourceTransaction`; do not create parallel
ownership primitives. Replace session graphs only after explicit route-removal
confirmation, and let application resources outlive them.
Generated application/session graphs open each declared context once at its
configured scope. A feature host closes its ViewModel before its feature graph
and rejects publication after cancellation or disposal.

## Workflow

Define failure types and contracts, build the smallest composition root, wire
commands/ViewModels, then document ownership and reverse disposal. Select
`ViewModelHost.create` for owned values and `.value` for borrowed values.

Read [references/results-and-commands.md](references/results-and-commands.md),
[references/ownership-and-isolates.md](references/ownership-and-isolates.md), or
[references/basic-flutter.md](references/basic-flutter.md) only for the boundary
being implemented.

## Validate

Test `Ok`/`Err`, crash rethrow, cancellation or busy policy, disposal order,
owned/borrowed host behavior, stale completion, and zero notifications or
resources after disposal.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
