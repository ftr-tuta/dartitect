# dartitect_lints

## Purpose

Official Dartitect architecture diagnostics implemented with Dart's
`analysis_server_plugin` API and the shared semantic modeling compiler.

## When to use

Use it as a development dependency for editor and `dart analyze` feedback in
Dart/Flutter packages. Use `dartitect scan` as the deterministic CI or
unsupported analyzer-host fallback.

## When not to use

Do not add it as a runtime dependency or assume every editor hosts analyzer
plugins. It reports static boundary evidence; it does not prove business logic,
runtime ownership cleanup, provider behavior, or transaction durability.

## Platforms and entrypoints

Enable the analyzer plugin from package `dartitect_lints`. Its analyzer-facing
library is `package:dartitect_lints/main.dart`, exporting `plugin` and
`DartitectPlugin`; application code should not import either. The host must
support Dart analyzer plugins.

## Mental model and data flow

The analyzer owns plugin lifecycle. The plugin reads resolved source and
`dartitect.json`, classifies semantic boundaries with element/library identity,
and reports warnings at source locations. It never edits source. When an editor
cannot host it, the CLI scanner consumes the same policy and parity corpus.

## Minimal workflow

```yaml
# analysis_options.yaml
plugins:
  dartitect_lints:
```

Run `dart analyze`. A repository checkout may use the documented local `path`
plugin configuration from `example/README.md`.

## Public API tour

`plugin` is the analyzer-discovered entrypoint and `DartitectPlugin` registers
the official rule. Public application APIs are intentionally absent.

Diagnostics:

- `DT1001` domain imports Flutter.
- `DT1002` domain imports data/infrastructure.
- `DT1003` data imports presentation.
- `DT1004` `BuildContext` crosses ViewModel/domain/data/service/repository.
- `DT1005` presentation imports infrastructure.
- `DT1006` a forbidden architecture framework appears in a strict boundary.
- `DT1007` code imports another package's private `src`.
- `DT1050` a sensitive expression is interpolated into a logger call.
- `DT1051` Dio `LogInterceptor` bypasses classified capture.
- `DT1052` production source contains high-risk remote risk acceptance.
- `DT1053` a custom telemetry capture value lacks explicit classification.
- `DT1054` a legacy Sentry adapter is registered in a prepared runtime.

The analyzer and `dartitect scan` use the same policy and parity corpus for
these privacy bypasses. They do not require or create config v4.

## Ownership and lifecycle

The analyzer owns plugin construction, contexts, scheduling, and shutdown. The
plugin borrows source/config and retains no project resource after analyzer
teardown. Suppressions are consumer-owned reviewed source comments.

## Failure, cancellation, and concurrency

Invalid `dartitect.json` emits `dartitect_invalid_configuration` instead of
silently using strict defaults. Analyzer cancellation/staleness is owned by the
host. Rules are read-only and safe under analyzer concurrency; scanner/plugin
parity is checked independently.

A single suppression must include a reason:

```dart
// dartitect-ignore: DT1004 -- required by a reviewed legacy callback
```

## Prohibited uses and limitations

Do not treat warnings as runtime proof, suppress a whole rule without evidence,
or duplicate divergent policy in another plugin. Generated source is exempt
only when it matches the documented generated header/suffix or an explicit
`generatedInfrastructure` glob. A local type named `Store` or `Widget` is not a
provider/Flutter match because resolved identity is used when available.

## Testing

Run `dart test` and `dart run tool/check_boundary_parity.dart`. Cover
analyzer-host loading, resolved identity, invalid configuration, suppressions,
generated-source recognition, every diagnostic, scanner parity, and performance
over the versioned corpus.

## Related packages and guides

Use `dartitect_cli` for CI scan/doctor and
`dartitect_modeling_analyzer` for shared semantic interpretation. Read
[getting started](../../docs/guides/getting-started.md),
[ecosystem policy](../../docs/guides/ecosystem-policy.md), and the
[dependency ledger](../../DEPENDENCIES.adoc).

## Availability

Dartitect `1.0.0` is distributed only by the annotated `v1.0.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
