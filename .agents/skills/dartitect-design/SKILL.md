---
name: dartitect-design
description: Select the smallest Dartitect package and skill stack for a new Dart/Flutter application or feature. Use for architecture choices; do not use for conformance auditing or detailed implementation.
---

# Design with Dartitect

## When to use

Use this skill before implementing a new application, feature, composition root,
or provider boundary when the required Dartitect packages are not yet clear.

## When not to use

Use `$dartitect-audit` to inspect an existing codebase without changing it.
Route detailed runtime, reactive, offline-first, telemetry, adapter, testing,
CLI, or MCP work to the matching focused skill after suitability and the stack
are decided.

## Invariants

Choose the smallest stack that satisfies the feature. Riverpod, BLoC, Provider,
GetIt, MobX, Signals, and equivalent architecture runtimes are incompatible with
the Native Strict application graph. Keep domain/application contracts
provider-neutral, use constructor injection, and make every resource owned or
borrowed. Do not add a container, global runtime, provider package, or remote
telemetry without a stated requirement.

## Workflow

1. Decide whether Dartitect's constructor-injection, single-owner, typed-failure,
   local-authority, and sanitized-telemetry principles fit the target. If they
   do not, recommend not adopting Dartitect.
2. Classify the target as pure Dart, basic Flutter, reactive UI, durable
   mutation/outbox, dataset sync, headless sync, provider integration, or
   development tooling.
3. Identify platforms, authoritative data source, failure model, lifecycle
   owner, isolate boundaries, and telemetry policy.
4. Select only the packages and focused skills needed for those boundaries.
5. Reject provider leakage, service location, duplicate ownership, and
   competing application runtimes.
6. Record explicit exclusions so optional packages do not become defaults.

Read [references/selection-matrix.md](references/selection-matrix.md) when
choosing packages or routing the implementation.

## Validate

Confirm every selected package owns a concrete responsibility, every provider
stays at infrastructure composition, and removing any unneeded package would not
break a stated requirement.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise the capability belongs in
`softgran_*`, `agrox_*`, or the application, not in a Dartitect package.
