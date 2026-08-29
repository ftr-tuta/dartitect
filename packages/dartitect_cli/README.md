# dartitect_cli

## Purpose

Local Dart VM inspection, architecture scanning, diagnostics, stable config,
reviewed baselines, modeling generation/migration, dependency/fleet policy,
managed Codex skill synchronization, and transactional filesystem changes.

## When to use

Use the CLI in local development and CI. Start with read-only inspection and
preview every supported change. Tooling integrations may use the exported typed
services directly instead of parsing console output.

## When not to use

Do not embed it in an application runtime, expose it as a remote service, or use
it as a build system or arbitrary shell bridge. Scripts and CI should call this
CLI directly; local agents needing typed MCP tools use `dartitect_mcp`.

## Platforms and entrypoints

- The executable is `dartitect` (or `dart run dartitect_cli:dartitect`).
- The tooling library is `package:dartitect_cli/dartitect_cli.dart`.

Both run on the Dart VM. Commands that create Flutter projects additionally
invoke the consumer's local Flutter SDK.

## Mental model and data flow

Read-only operations resolve a confined project root, parse stable config,
compile semantic source facts, and return `CommandEnvelope`/typed reports.
Mutating operations first produce a deterministic `DartitectChangePlan` with a
semantic-input manifest. Apply revalidates the plan under an OS-level project
lock, writes through a recoverable journal, and commits or rolls back.

Generated-once files become consumer-owned. Only fully generated,
manifest-owned namespaces are converged. Managed skill sync follows the same
rule and preserves consumer-owned skills and an existing `AGENTS.md`.

## Minimal workflow

```console
dartitect inspect --json
dartitect scan --no-baseline
dartitect doctor
dartitect model check --json
dartitect model sync
dartitect codex sync --dry-run
```

`model sync` previews by default and writes only with `--apply`. Other mutators
document their own `--dry-run`/apply form in `example/README.md`.

## Public API tour

- `DartitectProjectService` is the shared typed inspect/scan/doctor/change layer.
- `ProjectScanner`, `DartitectFinding`, `DartitectRuleCodes`, source
  classification, and SARIF/report types expose architecture results.
- `DartitectConfig`, `ConfigMigrator`, and `nativeStrictProfile` define stable
  config v2 and architecture defaults.
- `DartitectBaseline` fingerprints code/path/evidence without line numbers.
- `DartitectChangePlan`, semantic inputs/manifests, receipts, and
  `GenerationEngine` implement preview/revalidation/recovery.
- `DartitectModelGenerator` and `PrimaryConstructorMigration` consume shared
  semantic modeling IR.
- `EcosystemDependencyAuditor` and policy types provide pinned offline
  dependency decisions.
- `DartitectFleetService` confines explicit application roots and returns
  versions, profile/provider/matrix reports, checks, policy, and upgrade
  previews without process execution or project writes.
- `DartitectFleetCanaryService` is a separate opt-in boundary that archives an
  exact candidate commit, runs a closed command allowlist only in a temporary
  consumer copy, sanitizes receipts, and verifies both originals are unchanged.
- `CodexSkillSynchronizer` synchronizes eleven canonical managed templates while
  preserving consumer-owned skill directories.
- `DartitectVerificationService` and `DartitectCliRunner` map services to stable
  JSON and exit codes.
- `FeatureProfile` and scaffold/generation types expose the `online`, `cache`,
  `replica`, and `offline-full` paths plus reviewed file-ownership contracts
  for tooling authors. Pre-1.0 blueprint aliases are not accepted.

## Ownership and lifecycle

The caller owns process I/O, project roots, source files, and provider tooling.
The CLI owns only an active lock/journal/temporary transaction. Generated-once
outputs become consumer-owned; fully generated model outputs and managed skills
remain tool-owned only while their strong manifest digest matches.

Keep `.dartitect/project-change.lock` ignored but at its stable path so
concurrent processes coordinate on one OS lock inode. Do not edit canonical
managed-skill output under `.agents/skills` independently; update the catalog
and synchronize it.

## Failure, cancellation, and concurrency

Exit codes are `0` success, `1` findings/conflicts, `2` usage/configuration, and
`3` unexpected I/O/internal failure. Plans fail closed on changed semantic input,
path escape, symlink/traversal, manifest mismatch, lock conflict, or partial I/O.
Recoverable journals preserve integral rollback.

Mutations serialize through locks and revalidate immediately before commit.
Read-only operations do not grant write authority. Deep doctor may run
`dart analyze` only when explicitly requested. Fleet upgrade applies only as
an all-project transaction with byte journals and digest-verified rollback.

## Prohibited uses and limitations

- No application runtime dependency, remote service, arbitrary shell, or
  arbitrary file access.
- No parsing human output when typed service/JSON output is available.
- No apply without reviewing the corresponding preview.
- No overwrite of consumer-owned or locally modified managed files without the
  explicit documented override.
- No claim that scan proves business correctness, provider behavior, or
  lifecycle cleanup.
- No tag, release, package publication, or dependency download performed by
  ordinary verification.

## Testing

Run `dart test`. Cover paths with spaces/Unicode, root confinement, symlinks,
traversal, semantic-plan invalidation, conflicts, concurrent processes, partial
I/O, recovery/rollback, deterministic JSON, generated consumers, analyzer
parity, and managed-skill idempotency. Run formatting and analysis for modified
Dart tooling.

## Related packages and guides

Use `dartitect_lints` for editor feedback,
`dartitect_modeling_analyzer` for shared semantic IR, and `dartitect_mcp` for a
bounded local agent interface. Read
[getting started](../../docs/guides/getting-started.md),
[model generation](../../docs/guides/model-generation.md),
[fleet tooling](../../docs/guides/fleet-tooling.md), and
[MCP](../../docs/guides/mcp.md).

## Availability

The workspace contains the `1.0.0-rc.6` source candidate. Global activation or
Git use is supported only from coordinates in a matching tagged GitHub Release.
If no compatible Release exists, there is no supported consumption path. See
the [Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
