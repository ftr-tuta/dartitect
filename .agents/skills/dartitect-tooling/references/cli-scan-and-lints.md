# CLI, scan, and lints

Keep `inspect`, `scan`, and ordinary `doctor` read-only. Deep doctor is explicit
and bounded. Accept exactly stable config v1 with `native_strict`; reject
experimental versions, preserve unknown v1 extension keys without interpreting
them, never store credentials, and provide no compatibility migrator.

Scan only declared roots using real path segments; ignore nested caches and
generated code. A baseline fingerprints code, path, and evidence without line
number. New findings fail, obsolete entries warn, and local suppressions require
a reason. Keep CLI and official analyzer-plugin diagnostics semantically aligned
through the versioned true/false-positive corpus while respecting their
different hosts and entrypoints. Prefer element/library identity when resolved.
Sensitive metadata needs a recognized telemetry sink. Generated fallback needs
both a reviewed header and configured suffix. Invalid analyzer config is an
explicit diagnostic, never a silent strict-default outcome. Enforce scanner and
analyzer performance budgets with stable machine-readable schemas.
