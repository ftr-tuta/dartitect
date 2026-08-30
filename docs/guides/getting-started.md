# Getting started

## Choose the boundary

Start only in a new Dart or Flutter project. Dartitect does not provide an
incremental adoption path, legacy zone, competing-runtime bridge, or general
application conversion. The supported continuity path is an SDK-owned upgrade
for a project that was created with Dartitect.

Start with `dartitect` for `Result` and ownership. Add
`dartitect_sync` only for dataset orchestration, `dartitect_flutter` only at
Flutter UI composition, observability only where telemetry is needed, and
provider adapters only in infrastructure. Testing, CLI, lints, and MCP are
development-time choices.

Use the [ecosystem selection matrix](ecosystem-selection.md) to check packages,
entrypoints, platforms, skills, and contraindications before adding anything.

## Install

The candidate is not published on pub.dev. Keep the selected package versions
visible and generate Git overrides for their complete internal closure:

```console
dart run tool/git_dependency_overrides.dart \
  dartitect,dartitect_sync,dartitect_flutter,dartitect_observability
```

Paste the result under `dependency_overrides`, run `flutter pub get`, and
follow the [Git candidate consumption guide](git-candidate-consumption.md) to
verify the URL, tag, package paths, and resolved commit.

## Compose

Create dependencies in an app/session/isolate composition root with constructor
injection. Record owned versus borrowed values. Dispose bindings/commands,
watchers/queries, clients/Stores, then observability resources. Provider objects
owned by the consumer close afterward.

## Validate

```console
dart run dartitect_cli:dartitect inspect --json
dart run dartitect_cli:dartitect scan
dart run dartitect_cli:dartitect doctor
dart test
```

Resolve every violation. Greenfield projects cannot suppress architecture debt
through a baseline.

## Agent guidance

`dartitect codex sync --dry-run` previews eleven managed, implicitly invocable
skills. New work starts with `$dartitect-design`; `$dartitect-audit` validates
that a Dartitect-created project still conforms after development or an SDK
upgrade. It does not produce an adoption or conversion plan. Focused
implementation routes to runtime, reactive, offline-first,
observability, adapters, testing, tooling, or MCP. The sync never
manages the repository-local `repository-contribution` skill.

## Next

Use the [implementation recipes](implementation-recipes.md), then read the
composition, commands, reactive, observability, adapters, custom integrations,
or MCP guide for the boundary you are changing.
