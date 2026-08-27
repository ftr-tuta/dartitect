# dartitect_lints

[Português (Brasil)](README.pt-BR.md)

## Purpose

Native-first boundary diagnostics implemented with Dart's official
`analysis_server_plugin` API.

## When to use it

Use it for editor/analyzer feedback in Dart and Flutter packages. Use
`dartitect scan` as the deterministic CI or plugin-host fallback.

## When not to use it

Do not use it as a runtime dependency or assume every editor can host analyzer
plugins. It reports architecture boundaries; it does not prove business logic,
ownership cleanup, or provider behavior.

## Recommended combinations

Combine with `dartitect_cli` scan/doctor in CI and focused tests for runtime and
provider contracts. Keep justified local suppressions narrow. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_lints: 1.0.0-rc.3` under `dev_dependencies` and use the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to pin it to the protected tag.

```yaml
# analysis_options.yaml
plugins:
  dartitect_lints:
```

Repository contributors use the local path:

```yaml
plugins:
  dartitect_lints:
    path: packages/dartitect_lints
```

## Minimal example

After enabling the plugin, `dart analyze` and supported editors report the
diagnostics. See `example/README.md` for a complete configuration.

## Public API tour

`plugin` is the analyzer-discovered entrypoint. `DartitectPlugin` registers the
architecture warning rule. Application code should not import either.

## Ownership

The analyzer owns plugin lifecycle. The plugin reads source analysis only and
does not edit the project.

When resolution is available, type, annotation, locator, and telemetry rules
use element/library identity. A local class named `Store` or `Widget` is not a
provider/Flutter type. Sensitive map keys are reported only at a recognized
telemetry sink. Invalid `dartitect.json` emits
`dartitect_invalid_configuration` instead of silently behaving as strict
defaults.

## Limitations

Diagnostics are warnings: `DT1001` domain imports Flutter; `DT1002` domain
imports data/infrastructure; `DT1003` data imports presentation; `DT1004`
`BuildContext` crosses ViewModel/domain/data/service/repository boundaries;
`DT1005` presentation imports infrastructure; `DT1006` forbidden architecture
framework; `DT1007` private cross-package `src` import.

Generated sources outside an explicit `generatedInfrastructure` glob are
recognized only when a standard generated-code header and a reviewed suffix
both match. Defaults cover `.g.dart`, `.freezed.dart`, `.gr.dart`, and
`.router.dart`; `generatedSuffixes` can replace that list in stable config v1.

Suppress a single finding only with a justification:

```dart
// dartitect-ignore: DT1004 -- required by a reviewed legacy callback
```

## Extending

Keep diagnostics semantically aligned with `dartitect scan`, document a stable
code/remediation, and add analyzer-host plus scanner fixtures.

## Testing

Run `dart test` and `dart run tool/check_boundary_parity.dart`. The versioned
corpus enforces scanner/plugin parity and analyzer performance. Compatibility
pins and their rationale live in the root dependency ledger.

## Links

See [dependency rationale](https://github.com/ftr-tuta/dartitect/blob/main/DEPENDENCIES.adoc),
[CLI fallback](https://github.com/ftr-tuta/dartitect/tree/main/packages/dartitect_cli), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
