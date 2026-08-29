# CLI, scan, and lints

Keep `inspect`, `scan`, and ordinary `doctor` read-only. Deep doctor is explicit
and bounded. Accept exactly stable config v2 with `native_strict`; reject
experimental versions, unknown keys, credentials, and opaque plugin data.
The target-aware `features` section declares `local`, `online`, `cache`,
`replica`, or `offline-full` and refers to named provider blocks. `verify` checks declarative
compatibility; behavioral guarantees remain contract-matrix evidence.

Scan only declared roots using real path segments; ignore nested caches and
generated code. Every finding fails strict scan. Local suppressions require an
owner, reason, and expiry, and release doctor rejects all suppressions. Keep CLI
and official analyzer-plugin diagnostics semantically aligned
through the versioned true/false-positive corpus while respecting their
different hosts and entrypoints. Prefer element/library identity when resolved.
Sensitive metadata needs a recognized telemetry sink. Generated fallback needs
both a reviewed header and configured suffix. Invalid analyzer config is an
explicit diagnostic, never a silent strict-default outcome. Enforce scanner and
analyzer performance budgets with stable machine-readable schemas.

`fleet report` stays read-only and aggregates versions, profiles, providers,
and bounded matrix-source detection. Keep process execution in the separate
`DartitectFleetCanaryService`: require an exact commit, use only an archive and
temporary consumer copy, run a closed command allowlist, sanitize receipts,
compare original SHA/worktree/tree state, and remove the copy after failure.
