# Dartitect DevTools extension source

This non-published Flutter Web project builds the read-only UI bundled by
`dartitect_devtools`.

```sh
flutter analyze
flutter test --platform chrome
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=../../packages/dartitect_devtools/extension/devtools
dart run devtools_extensions validate \
  --package=../../packages/dartitect_devtools
```
