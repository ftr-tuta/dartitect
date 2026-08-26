---
name: dartitect-design
description: Select the smallest Dartitect package and skill stack for a new Dart or Flutter application or feature. Use for greenfield architecture choices; do not use for brownfield migration or detailed implementation.
---

# Design with Dartitect

## When to use

Use this skill before implementing a new application, feature, composition root,
or provider boundary when the required Dartitect packages are not yet clear.

## When not to use

Use `$dartitect-adopt` for an existing codebase migration. Route detailed runtime,
reactive, offline-first, telemetry, adapter, testing, CLI, or MCP work to the
matching focused skill after the stack is selected.

## Invariants

Choose the smallest stack that satisfies the feature. Keep domain/application
contracts provider-neutral, use constructor injection, and make every resource
owned or borrowed. Do not add a container, global runtime, provider package, or
remote telemetry without a stated requirement.

## Workflow

1. Classify the target as pure Dart, basic Flutter, reactive UI, offline-first,
   provider integration, or development tooling.
2. Identify platforms, authoritative data source, failure model, lifecycle
   owner, isolate boundaries, and telemetry policy.
3. Select only the packages and focused skills needed for those boundaries.
4. Record explicit exclusions so optional packages do not become defaults.

Read [references/selection-matrix.md](references/selection-matrix.md) when
choosing packages or routing the implementation.

## Validate

Confirm every selected package owns a concrete responsibility, every provider
stays at infrastructure composition, and removing any unneeded package would not
break a stated requirement.
