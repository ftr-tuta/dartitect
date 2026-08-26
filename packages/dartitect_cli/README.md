# dartitect_cli

[Português (Brasil)](README.pt-BR.md)

## Purpose

Local Dart VM inspection, architecture scanning, diagnostics, config migration,
reviewed baselines, managed Codex skills, and transactional generators. The CLI
has no runtime dependency outside the Dart SDK.

## When to use it

Use it in local development and CI. Read-only commands are safe for discovery;
preview every generator or migration before writing. It does not run arbitrary
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
dart pub global activate dartitect_cli 1.0.0-rc.2
```

## Minimal example

```console
dartitect inspect --json
dartitect scan --no-baseline
dartitect doctor
dartitect model check
dartitect dependencies audit
```

See `example/README.md` for all commands and exit codes.

## Public API tour

- `DartitectProjectService` is the typed shared inspect/scan/doctor/change layer.
- `ProjectScanner`, `DartitectFinding`, and `CommandEnvelope` provide results.
- `DartitectConfig`/`ConfigMigrator` preserve unknown keys and originals.
- `DartitectBaseline` fingerprints code/path/evidence without line numbers.
- `GenerationEngine` preserves generated-once files and converges manifest-owned
  model outputs through recoverable create/update/delete transactions.
- `DartitectModelGenerator` and `EcosystemDependencyAuditor` provide native
  value generation and offline direct/transitive policy checks.
- `CodexSkillSynchronizer` synchronizes eleven templates and replaces only
  manifest-owned skills; consumer-owned skills remain untouched.
- `DartitectCliRunner` maps the public service to stable exit codes.

## Ownership

Generated-once files become consumer-owned. Fully generated model outputs and
skill directories remain tool-owned only while their strong manifest digest
matches. Existing `AGENTS.md` is preserved. `model sync` previews by default;
only `--apply` writes or recovers.

## Limitations

Deep doctor runs `dart analyze` only when requested. `create app` invokes the
local Flutter SDK. Scan is conservative and does not prove business correctness.

## Extending

Add typed service operations first, then CLI rendering. Never implement CLI/MCP
features by subprocessing Dartitect or parsing its human output.

## Testing

Run `dart test`. Cover paths with spaces/Unicode, symlinks, traversal, conflicts,
partial I/O, recovery, rollback, deterministic JSON, and generated consumers.

## Links

See [getting started](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/getting-started.md),
[MCP](https://github.com/ftr-tuta/dartitect/tree/main/packages/dartitect_mcp), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
