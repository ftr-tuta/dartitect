# Dartitect model generator fixture

This pure-Dart workspace package is the executable RC4 modeling example. Its
single model opts independently into value equality, JSON, projection, and a
boundary mapper; the tests execute equality/copyWith, unknown-key rejection,
round-trip, typed selector/lens, and lossless mapping.

The generated output and namespaced ownership manifest are committed. From the
repository root, run:

```console
dart run dartitect_cli:dartitect model check \
  --root examples/model_generator_fixture
dart run dartitect_cli:dartitect verify --json \
  --root examples/model_generator_fixture
dart analyze examples/model_generator_fixture
dart test examples/model_generator_fixture
dart test examples/model_generator_fixture --platform chrome
```

All read-only commands must pass from a clean checkout without invoking sync.
To reproduce generation intentionally, review the preview first and then run
`dart run dartitect_cli:dartitect model sync --apply --root
examples/model_generator_fixture`; commit both the generated part and manifest.
