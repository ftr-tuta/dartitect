# Analyzer plugin example

Add the plugin as a development dependency:

```yaml
dev_dependencies:
  dartitect_lints:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      path: packages/dartitect_lints
      tag_pattern: 'v{{version}}'
    version: 1.1.0
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
