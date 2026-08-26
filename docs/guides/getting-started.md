# Getting started

[Português (Brasil)](getting-started.pt-BR.md)

## Choose the boundary

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
dart run dartitect_cli:dartitect scan --no-baseline
dart run dartitect_cli:dartitect doctor
dart test
```

Resolve new violations. Create a baseline only for reviewed existing debt, and
remove obsolete entries over time.

## Agent guidance

`dartitect codex sync --dry-run` previews ten managed, implicitly invocable
skills. Greenfield and brownfield work start with `$dartitect-design` and
`$dartitect-adopt`; focused implementation routes to runtime, reactive,
offline-first, observability, adapters, testing, tooling, or MCP. The sync never
manages the repository-local `repository-contribution` skill.

## Next

Use the [implementation recipes](implementation-recipes.md), then read the
composition, commands, reactive, observability, adapters, custom integrations,
or MCP guide for the boundary you are changing.
