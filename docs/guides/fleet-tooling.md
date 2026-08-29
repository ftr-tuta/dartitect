# Fleet tooling

Fleet reads explicit roots confined below `--root`; roots are canonicalized
once, sorted, and never followed through escaping symlinks.

```console
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
dartitect fleet upgrade apps/a apps/b \
  --root . --to=1.0.0-rc.8 --apply --json
```

Upgrade preview is deterministic across the complete cohort. Apply acquires a
fleet lock and project locks in order, journals every affected byte, upgrades
dependencies, runs the exact Dartitect RC6/v1-to-RC8/v2 upgrade, synchronizes primary
constructors, models, wiring, and operational schemas, then executes only the
allowlisted pub-get, analyze, test, and contract-matrix commands.

No project commits until every project passes. Failure restores every codebase
and validates all digests. Receipts are sanitized per project, and a later run
recovers or rolls back an interrupted journal before planning new work.

Structured path/Git/SDK dependencies and unknown constraints fail closed.
Fleet never accepts arbitrary shell commands, URLs, credentials, or roots
outside the declared boundary. Preview JSON contains relative paths and state
tokens only.

Use `dartitect verify --sarif` for the complete read-only gate or
`dartitect scan --sarif` for architecture only. JSON and SARIF are mutually
exclusive.
