# Getting started

The source workspace and public distribution are the stable `1.1.0` cohort.
Consume every direct Dartitect package from the annotated `v1.1.0` tag and its
immutable GitHub Release.

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

Declare only the Dartitect packages that the application uses directly. Their
transitive Dartitect dependencies resolve automatically from the same release
tag; no override section is needed.

```yaml
dependencies:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      path: packages/dartitect
      tag_pattern: 'v{{version}}'
    version: 1.1.0
```

Generate other official direct-dependency snippets with
`dart run tool/dependency_snippets.dart`, run `flutter pub get`, and follow the
[Git release consumption guide](git-release-consumption.md) to verify the URL,
paths, tag pattern, version, and common resolved commit.

Install the CLI from the same release tag:

```console
dart install https://github.com/ftr-tuta/dartitect.git \
  --git-path packages/dartitect_cli \
  --git-ref v1.1.0
```

## Compose

Create dependencies in an app/session/isolate composition root with constructor
injection. Record owned versus borrowed values. Dispose bindings/commands,
watchers/queries, clients/Stores, then observability resources. Provider objects
owned by the consumer close afterward.

The normal generated application entrypoint delegates ownership to the concrete
config-v3 graph:

```dart
void main() => runDartitectApplication<ApplicationGraph>(
  create: ApplicationModule.create,
  application: (graph) => OrdersApp(graph: graph),
);
```

At a route boundary, provide the generated `<Feature>FeatureHost` with its typed
factory and exhaustive loading, failure, and ready builders. The host starts and
closes the ViewModel, fences late work, and closes the feature graph after the
ViewModel. Generated hosts do not choose Material, text, layout, navigation,
color, or style. Use the [composition guide](composition-lifecycle-isolates.md)
for manual low-level ownership primitives.

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

`dartitect codex sync --dry-run` previews the managed, implicitly invocable
skills. New work starts with `$dartitect-design`; `$dartitect-audit` validates
that a Dartitect-created project still conforms after development or an SDK
upgrade. It does not produce an adoption or conversion plan. Focused
implementation routes to Dart semantics, incremental execution, performance,
runtime, reactive, offline-first, observability, adapters, testing, tooling, or
MCP. The sync never
manages the repository-local `repository-contribution` skill.

## Next

Use the [implementation recipes](implementation-recipes.md), then read the
composition, commands, reactive, observability, adapters, custom integrations,
or MCP guide for the boundary you are changing.
