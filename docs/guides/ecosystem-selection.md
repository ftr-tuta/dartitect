# Selecting the Dartitect ecosystem

[Português (Brasil)](ecosystem-selection.pt-BR.md)

## Start with the boundary

Select packages from the behavior the application actually needs. `dartitect`
is the core for typed failures, concurrency, ownership, and offline mutation
contracts. Every other package is optional. Provider SDKs, entities, generated
models, credentials, and vendor configuration remain consumer-owned.

For a new application or feature, use `$dartitect-design`. An existing codebase
may use `$dartitect-audit` for read-only conformance evidence. It is not a path
to migrate or coexist with another DI/application-state runtime.

## Capability matrix

| Capability | Package(s) | Public entrypoint(s) | Platforms | Focused skill | Do not choose it when |
| --- | --- | --- | --- | --- | --- |
| Results, ownership, command lanes, mutation contracts | `dartitect` | `package:dartitect/dartitect.dart` | Dart, Flutter, web | `$dartitect-runtime`; `$dartitect-offline-first` for mutations | A service locator, state manager, logger, ORM, or HTTP client is expected |
| Dataset DAG sync, checkpoints, leases, progress, headless protocol | `dartitect_sync` | `package:dartitect_sync/dartitect_sync.dart` | Dart, Flutter, web | `$dartitect-offline-first`; `$dartitect-testing` | A scheduler, retry policy, durable queue, provider client, or conflict engine is expected |
| Basic Flutter ViewModels and commands | `dartitect_flutter` | `package:dartitect_flutter/dartitect_flutter.dart` | Flutter | `$dartitect-runtime` | Advanced hot/warm/cold resources or local-first pages are required |
| Reactive graph, resources, families, collections, headless builders | `dartitect_flutter` | `package:dartitect_flutter/dartitect_flutter_reactive.dart` | Flutter | `$dartitect-reactive` | Basic `ChangeNotifier`/command composition is sufficient |
| Logs, reporting, tracing, redaction | `dartitect_observability` | `package:dartitect_observability/dartitect_observability.dart` | Dart, Flutter, web | `$dartitect-observability` | A remote destination has not been explicitly selected; local developer logging already suffices |
| Dio integration | `dartitect_dio` | `package:dartitect_dio/dartitect_dio.dart` | Dio platforms | `$dartitect-adapters` | The application did not choose Dio or the import would cross into domain/presentation |
| ObjectBox integration | `dartitect_objectbox` | `package:dartitect_objectbox/dartitect_objectbox.dart` | Android, iOS, Linux, macOS, Windows | `$dartitect-adapters`; combine with `$dartitect-offline-first` | Web support or an ORM abstraction is required |
| Sentry integration | `dartitect_sentry` | `package:dartitect_sentry/dartitect_sentry.dart` | Dart, Flutter | `$dartitect-adapters` + `$dartitect-observability` | The consumer has not initialized/selected Sentry or another hook already captures the same telemetry |
| Tracking authorization | `dartitect_privacy` | `package:dartitect_privacy/dartitect_privacy.dart` | iOS; typed not-supported elsewhere | `$dartitect-adapters` | Authorization would be requested automatically or ATT is not required |
| Gallery image save | `dartitect_media` | `package:dartitect_media/dartitect_media.dart` | Android, iOS | `$dartitect-adapters` | A picker/editor, video pipeline, or broad media abstraction is expected |
| Brazilian postal code values | `dartitect_locale_br` | `package:dartitect_locale_br/dartitect_locale_br.dart` | Dart, Flutter, web | `$dartitect-runtime` | General Brazilian form widgets or unrelated document formats are expected |
| Polygon pole of inaccessibility | `dartitect_geometry` | `package:dartitect_geometry/dartitect_geometry.dart` | Dart, Flutter, web | `$dartitect-runtime` | A GIS engine or mutable geometry model is expected |
| Deterministic boundary helpers | `dartitect_testing` | `package:dartitect_testing/dartitect_testing.dart` | Dart, Flutter, web | `$dartitect-testing` | The real provider/code-generation boundary is what the test must prove |
| Inspect, scan, doctor, config, baselines, generators, Codex sync | `dartitect_cli` | `package:dartitect_cli/dartitect_cli.dart`; `dartitect` executable | Dart VM | `$dartitect-tooling` | Application runtime behavior or a remote service is expected |
| Analyzer diagnostics | `dartitect_lints` | plugin `package:dartitect_lints/main.dart` | Dart analyzer | `$dartitect-tooling` | The host cannot run analyzer plugins; use `dartitect scan` instead |
| Local MCP tools/resources | `dartitect_mcp` | `package:dartitect_mcp/dartitect_mcp.dart`; local STDIO executable | Dart VM, STDIO | `$dartitect-mcp` | Shell/CI automation, arbitrary files, HTTP/OAuth, or running-app access is required |

The native ObjectBox fixture installer, `tool/setup_objectbox_vm.dart`, belongs
to `$dartitect-tooling`; it is not an application entrypoint.

## Routing scenarios

| Scenario | Start with | Combine when needed |
| --- | --- | --- |
| New application or feature | `$dartitect-design` | Route the selected boundary to one or more focused skills |
| Existing codebase conformance audit | `$dartitect-audit` | Read-only evidence; no conversion plan is emitted |
| Immutable generated values | `$dartitect-modeling` | `$dartitect-tooling` for CI/release integration |
| Simple Flutter runtime | `$dartitect-runtime` | `$dartitect-testing` |
| Reactive lifecycle and UI | `$dartitect-reactive` | `$dartitect-runtime`, `$dartitect-testing` |
| Local-first pagination or durable outbox | `$dartitect-offline-first` | `$dartitect-reactive`, provider `$dartitect-adapters`, `$dartitect-testing` |
| Foreground or headless dataset sync | `$dartitect-offline-first` | `$dartitect-adapters`, `$dartitect-observability`, `$dartitect-testing` |
| Dio, ObjectBox, Sentry, or custom provider | `$dartitect-adapters` | `$dartitect-observability` or `$dartitect-offline-first` according to policy |
| Telemetry policy and capture | `$dartitect-observability` | `$dartitect-adapters` only after selecting a provider |
| Failure/lifecycle/provider verification | `$dartitect-testing` | The focused implementation skill |
| CLI, scanner, lints, generators, native setup, release gates | `$dartitect-tooling` | Keep MCP work separate |
| Local agent inspection and reviewed previews | `$dartitect-mcp` | Use the CLI directly for scripts and CI |

Cross-cutting flows intentionally invoke more than one skill. Overlap does not
transfer ownership: each skill remains responsible only for its named boundary.

## Recommended stacks

- Pure Dart service: `dartitect`; add `dartitect_observability` only for a
  concrete telemetry contract and `dartitect_testing` as a dev dependency.
- Basic Flutter feature: `dartitect` + `dartitect_flutter` through the thin
  entrypoint; no reactive entrypoint is necessary.
- Reactive Flutter feature: add only the reactive entrypoint and keep Material
  or Cupertino rendering in consumer presentation.
- Offline-first feature: core mutation contracts + reactive local-authority
  presentation + `dartitect_sync` when dataset orchestration is needed + the
  selected storage/transport adapters. The repository owns transaction, schema,
  conflict, retry, scheduling, and compensation policy.
- Architecture enforcement: `dartitect_cli` in scripts/CI and
  `dartitect_lints` in supported editor/analyzer hosts.
- Agent-assisted local work: add `dartitect_mcp` as a dev dependency. Keep it
  read-only unless a reviewed local write is intended.

## Ownership and platform checks

Create one graph per app, session, route, or background isolate. Dispose
bindings/commands, reactive observations and provider watchers/queries, clients
and Stores, then owned observability. Consumer-owned SDKs close after every
Dartitect borrower.

Before committing to a stack, verify web versus native requirements, Flutter
versus pure Dart entrypoints, Material dependency, ObjectBox host support, CLI/
MCP Dart VM availability, provider licensing, and the real code-generation or
SDK fixture needed by tests.

## Next

Use the [implementation recipes](implementation-recipes.md) for a concrete
composition. The [getting-started guide](getting-started.md) covers installation,
and the focused composition, reactive, observability, adapter, and MCP guides
cover their deeper contracts.
