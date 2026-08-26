# Analyzer plugin example

Add the plugin as a development dependency:

```console
dart pub add --dev dartitect_lints:^1.0.0-rc.2
```

Enable it at the top level of `analysis_options.yaml`:

```yaml
plugins:
  dartitect_lints:
```

For a checkout of the Dartitect repository, use the local contributor form:

```yaml
plugins:
  dartitect_lints:
    path: packages/dartitect_lints
```

Run `dart analyze`. The plugin emits `DT1001`–`DT1007` warnings. A local
suppression must be narrow and justified:

```dart
// dartitect-ignore: DT1004 -- required by a reviewed legacy callback
```

Use `dartitect scan` for CI and analyzer hosts that cannot load plugins.
