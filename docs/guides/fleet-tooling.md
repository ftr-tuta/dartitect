# Fleet tooling

Fleet reads explicit roots confined below `--root`; roots are canonicalized
once, sorted, and never followed through escaping symlinks.

```console
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
dartitect fleet inventory apps/a apps/b --root . --json
dartitect fleet impact --from=before.json --to=after.json --root . --json
dartitect fleet upgrade apps/a apps/b \
  --root . --to=1.1.0 --apply --json
```

Upgrade preview is deterministic across the complete cohort. Apply acquires a
fleet lock and project locks in order, journals every affected byte, upgrades
dependencies, runs the versioned v1→v2→v3 config chain and registered renderer
migrations, synchronizes contracts, primary constructors, models, wiring, and
operational schemas, then executes only the allowlisted pub-get, analyze, test,
and contract-matrix commands. Every config or renderer migration records a
stable ID even when its action is `no-op`.

`inventory` snapshots versions, used public entrypoints and symbols, profiles,
capabilities, scoped contexts, targets, schemas, manifests, blueprints,
extensions, and deprecations. `impact` compares two snapshots and separates
outputs that can be regenerated from changes that need a domain decision.

Local versioned blueprints are confined to the target project:

```console
dartitect blueprint check ./blueprints/mobile
dartitect create app shop --blueprint=./blueprints/mobile
dartitect create feature orders --blueprint=./blueprints/mobile
```

Blueprint manifests are closed, templates contain no executable code, and
preview/apply uses a digest lock. Stable blueprints cover architecture and
tests, not product UI/UX.

No project commits until every project passes. Failure restores every codebase
and validates all digests. Receipts are sanitized per project, and a later run
recovers or rolls back an interrupted journal before planning new work.

Noncanonical path/Git/SDK dependencies and unknown constraints fail closed.
Fleet never accepts arbitrary shell commands, URLs, credentials, or roots
outside the declared boundary. Preview JSON contains relative paths and state
tokens only.

Use `dartitect verify --sarif` for the complete read-only gate or
`dartitect scan --sarif` for architecture only. JSON and SARIF are mutually
exclusive.
