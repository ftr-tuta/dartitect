# Fleet tooling

## Distribution

Run the CLI from an exact dev-dependency version or activate it separately:

```console
dart run dartitect_cli:dartitect --version
dart pub global activate dartitect_cli 1.0.0-rc.4
```

Do not add `dartitect_cli` to application runtime dependencies. Analyze and
build never activate the CLI or download fleet policy.

## Read-only fleet commands

`--root` defines the fleet boundary. Every following root is explicit,
relative to that boundary, sorted in output, and resolved without symlink
escape.

```console
dartitect fleet versions apps/a apps/b --root . --json
dartitect fleet report apps/a apps/b --root . --json
dartitect fleet check apps/a apps/b --root . --json
```

`versions` reads pubspec/lock metadata without invoking pub. `report` adds
declared feature profiles, persistence/transport providers, and bounded
source-level detection of the matching `FeatureContractMatrix` constructors.
`check` runs the
same read-only architecture, modeling, ecosystem, and provider verification as
`dartitect verify`, without a baseline. Both outputs include `modelStatus` and
`providerStatus`; paths remain fleet-relative. None of these services executes
a process or writes a project.

## Isolated candidate canaries

`DartitectFleetCanaryService` is a separate opt-in process boundary. It requires
an exact lowercase 40-character commit SHA, creates a Git archive, copies the
consumer into a temporary directory, and injects `pubspec_overrides.yaml` plus
a candidate receipt only into that copy. Commands are selected from a closed
Dart/Flutter pub-get, analyze, and test allowlist. Logs are sanitized and
bounded in receipts.

After execution it compares candidate HEAD/worktree state and a consumer tree
digest with their original values, then proves the temporary copy was removed.
It does not provide a general remote execution protocol, arbitrary shell
command, or mutation path for `DartitectFleetService`.

## Pinned offline policy

Policy requires both a local bundle and its lowercase SHA-256 digest. The
bundle pins the policy file by a second digest. No URL or implicit download is
accepted.

```console
sha256sum tool/fleet_policy_bundle.json
dartitect fleet policy apps/a apps/b \
  --root . \
  --bundle=tool/fleet_policy_bundle.json \
  --sha256=1bc7b8921f16a95a2712081289392f0c93f9883635869f4cf266e9567052f90c \
  --json
```

Recompute the outer digest after a reviewed bundle change; never reuse the
example digest for different bytes.

## Upgrade preview

Fleet upgrade is deliberately preview-only:

```console
dartitect fleet upgrade apps/a apps/b \
  --root . --dry-run --to=1.0.0-rc.4 --json
```

Each result includes sanitized operations, the target cohort, a semantic input
manifest, and its state token. The reusable project service can apply one
reviewed plan under an OS lock and a recoverable pubspec journal, but the fleet
CLI has no `--apply` path. Structured path/git/sdk dependencies and unknown
constraints require manual review.

## SARIF

Use `dartitect verify --sarif` for the complete read-only gate, or
`dartitect scan --sarif` for architecture only. SARIF and stable JSON are separate
outputs; `--json` and `--sarif` are mutually exclusive. SARIF uses relative
artifact URIs and sanitized messages and omits source evidence and remediation.
