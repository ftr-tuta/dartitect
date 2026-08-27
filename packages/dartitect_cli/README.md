# dartitect_cli

[Português (Brasil)](README.pt-BR.md)

## Purpose

Local Dart VM inspection, architecture scanning, diagnostics, config validation,
reviewed baselines, managed Codex skills, and transactional generators. The CLI
has no runtime dependency outside the Dart SDK.

## When to use it

Use it in local development and CI. Read-only commands are safe for discovery;
preview every supported filesystem change before writing. It does not run arbitrary
shell supplied by a model and is not a build system.

## When not to use it

Do not embed it as application runtime behavior or use it as a remote service.
Use the MCP package only when a local agent needs bounded typed tools/resources;
scripts and CI should call this CLI directly.

## Recommended combinations

Combine with `dartitect_lints` for editor feedback and with the eleven managed
Codex skills for focused guidance. Use `dartitect_mcp` separately for local
agent context. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

```console
dart pub global activate dartitect_cli 1.0.0-rc.3
```

## Minimal example

```console
dartitect inspect --json
dartitect scan --no-baseline
dartitect doctor
dartitect model check
dartitect model migrate primary
dartitect dependencies audit
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
```

See `example/README.md` for all commands and exit codes.

## Public API tour

- `DartitectProjectService` is the typed shared inspect/scan/doctor/change layer.
- `DartitectFleetService` confines explicit project roots and provides offline
  versions/check/pinned-policy reports plus upgrade previews.
- `DartitectChangePlan` exposes a sorted semantic-input manifest. Its SHA-256
  digest is revalidated while an OS-level project lock is held through commit
  or rollback; unrelated assets do not invalidate a plan.
- `ProjectScanner`, `DartitectFinding`, and `CommandEnvelope` provide results.
- `DartitectConfig`/`ConfigMigrator` preserve unknown keys and originals.
- `DartitectBaseline` fingerprints code/path/evidence without line numbers.
- `GenerationEngine` preserves generated-once files and converges manifest-owned
  model outputs through recoverable create/update/delete transactions.
- `DartitectModelGenerator` and `EcosystemDependencyAuditor` provide native
  value generation and offline direct/transitive policy checks.
- `PrimaryConstructorMigration` provides semantic preview/apply with a shared
  project lock, dedicated source journal, and integral rollback.
- `CodexSkillSynchronizer` synchronizes eleven templates and replaces only
  manifest-owned skills; consumer-owned skills remain untouched.
- `DartitectCliRunner` maps the public service to stable exit codes.

## Ownership

Generated-once files become consumer-owned. Fully generated model outputs and
skill directories remain tool-owned only while their strong manifest digest
matches. Existing `AGENTS.md` is preserved. `model sync` previews by default;
only `--apply` writes or recovers.
Fleet CLI commands are read-only; `fleet upgrade` requires `--dry-run`. Policy
bundles are local and pinned by caller-supplied bundle and policy SHA-256
digests. See the [fleet tooling guide](../../docs/guides/fleet-tooling.md).
Ignore `.dartitect/project-change.lock`; its stable pathname is required so
concurrent processes always coordinate on the same OS lock inode.

## Limitations

Deep doctor runs `dart analyze` only when requested. `create app` invokes the
local Flutter SDK. Scan is conservative and does not prove business correctness.

## Extending

Add typed service operations first, then CLI rendering. Never implement CLI/MCP
features by subprocessing Dartitect or parsing its human output.

## Testing

Run `dart test`. Cover paths with spaces/Unicode, symlinks, traversal, conflicts,
partial I/O, recovery, rollback, deterministic JSON, and generated consumers.
The cross-process race and interrupted-lock tests run on Linux, Windows, and
macOS through the repository verification matrix.

## Links

See [getting started](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/getting-started.md),
[MCP](https://github.com/ftr-tuta/dartitect/tree/main/packages/dartitect_mcp), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
