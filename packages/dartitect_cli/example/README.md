# CLI example

Install `dartitect_cli`, run read-only discovery first, and review every preview:

```console
dart pub global activate dartitect_cli 1.0.0-rc.6
dartitect inspect --json
dartitect scan --no-baseline
dartitect doctor
dartitect doctor --deep
dartitect init --dry-run
dartitect baseline create --dry-run
dartitect codex sync --dry-run
dartitect model check --json
dartitect model migrate primary --json
dartitect model sync
dartitect dependencies audit --json
dartitect dependencies explain uuid
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
dartitect fleet policy apps/a --root . --bundle=tool/fleet_policy_bundle.json --sha256=<sha256> --json
dartitect create app shop --targets=android,ios,web
dartitect create feature orders --profile=offline-full --scope=session --targets=android,ios,web --storage-context=primary --transport=api --pagination=cursor --headless-targets=android,ios
dartitect wiring sync --dry-run --json
dartitect fleet upgrade apps/a --root . --to=1.0.0-rc.6 --json
dartitect fleet upgrade apps/a --root . --to=1.0.0-rc.6 --apply --json
```

Mutating counterparts are `init` without `--dry-run`, `baseline create` without
`--dry-run`, and `codex sync` without `--dry-run`. `create` generators also
support `--dry-run`; MCP exposes only the bounded feature preview. `create app`
emits an empty shell and no productive provider defaults; examples require
explicit `--example=tasks`. Config migration is accepted only through the
versioned Dartitect-project fleet path.
Unlike create-only mutators, convergent `model sync` previews by default and
only `model sync --apply` writes or recovers; `--dry-run` and `--apply` cannot
be combined. Generated outputs and
`.dartitect/generation/modeling/manifest.json` are committed.
Primary-constructor migration also previews by default; only
`model migrate primary --apply` writes source under the shared project lock and
its namespaced source journal.
Fleet report/check/policy commands never write. Upgrade previews by default;
`--apply` acquires the fleet lock and ordered project locks, journals all bytes,
runs only allowlisted validation, and commits the cohort atomically or restores
and verifies every digest. Policy uses only a local, doubly pinned bundle.
Codex sync distributes eleven manifest-owned `dartitect-*` skills, preserves
consumer-owned skills such as `repository-contribution`, and requires
`--overwrite-managed` before replacing local changes to a managed skill.

Exit codes are `0` success, `1` findings/conflicts, `2` usage/config, and `3`
unexpected I/O/internal failure. JSON output uses `CommandEnvelope` schema v1.
