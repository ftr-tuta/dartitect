# CLI example

Install `dartitect_cli`, run read-only discovery first, and review every preview:

```console
dart pub global activate dartitect_cli 1.0.0-rc.3
dartitect inspect --json
dartitect scan --no-baseline
dartitect doctor
dartitect doctor --deep
dartitect init --dry-run
dartitect baseline create --dry-run
dartitect codex sync --dry-run
dartitect model check --json
dartitect model sync
dartitect dependencies audit --json
dartitect dependencies explain uuid
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
dartitect fleet policy apps/a --root . --bundle=tool/fleet_policy_bundle.json --sha256=<sha256> --json
dartitect fleet upgrade apps/a --root . --dry-run --to=1.0.0-rc.3 --json
```

Mutating counterparts are `init` without `--dry-run`, `baseline create` without
`--dry-run`, and `codex sync` without `--dry-run`. `create` generators also
support `--dry-run` and are deliberately absent from MCP. Experimental configs
have no migration; recreate and review stable v1 with `init`.
Unlike create-only mutators, convergent `model sync` previews by default and
only `model sync --apply` writes or recovers; `--dry-run` and `--apply` cannot
be combined. Generated outputs and `.dartitect/model-outputs.json` are committed.
Fleet commands never write. Upgrade has no apply mode; its preview exposes a
state token that callers of the typed project service can review and revalidate
under the project lock. Policy uses only a local, doubly pinned bundle.
Codex sync distributes eleven manifest-owned `dartitect-*` skills, preserves
consumer-owned skills such as `repository-contribution`, and requires
`--overwrite-managed` before replacing local changes to a managed skill.

Exit codes are `0` success, `1` findings/conflicts, `2` usage/config, and `3`
unexpected I/O/internal failure. JSON output uses `CommandEnvelope` schema v1.
