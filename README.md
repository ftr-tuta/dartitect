# Dartitect

[Português (Brasil)](README.pt-BR.md)

Dartitect is a native-first architecture and owned-state platform for Dart and
Flutter. It gives applications explicit dependency injection, state ownership,
typed failures, small observability contracts, architecture checks, safe
tooling, and optional infrastructure adapters without a global container.

All sixteen public packages share the `1.0.0-rc.3` candidate line. This cohort
targets the protected Git tag; pub.dev publication is not authorized. Android
API 24 is covered by build compatibility and Android 14/API 34 runtime runs on
a clean GitHub-hosted emulator. iOS uses deployment-floor builds and the
simulator installed on the GitHub-hosted macOS runner. No phone, tablet, iPhone,
or privately managed runner is required. Local commands provide optional
feedback; only `CI / Required` and its main-branch `actions-readiness-v1`
artifact are formal release evidence.

## Why it exists

Large Flutter codebases often accumulate invisible global state, ambiguous
resource ownership, infrastructure imports in UI/domain code, provider-specific
telemetry, and filesystem changes that cannot be previewed safely. Dartitect makes those
boundaries explicit while retaining Dart and Flutter primitives.

Use it when you want constructor injection, deterministic disposal, feature-first
boundaries, typed expected failures, native listenables, owned reactive state,
privacy-first telemetry, or machine-checkable conformance. The supported 1.0
architecture is Native Strict and greenfield-only: one explicit composition,
ownership, and application-state runtime, without migration or coexistence
with competing DI/state runtimes.
It is not an ORM, HTTP client, router, backend, model generator, or promise of
support for every vendor.

## Principles

- **Native-first:** prefer Dart types, Flutter listenables, constructors, and
  explicit composition over a runtime container.
- **Ownership:** every resource is owned or borrowed; dependents are disposed
  before their dependencies.
- **Composition roots:** each app, session, and background isolate builds a fresh
  graph. Transfer configuration and validated trace context, not live resources.
- **Strict MVVM:** composition roots construct ViewModels; Views receive them and
  never look up repositories, clients, Stores, or services from widget context.
- **Owned state:** commands, values, computeds, resources, families, collections,
  pages, and one-shot effects have explicit owners, bounds, and teardown.
- **Expected versus unexpected failure:** `Result<T, F>` carries expected failure;
  unexpected exceptions remain crashes and can be reported once.
- **Consumer-owned providers:** clients, Stores, entities, schemas, credentials,
  DSNs, and vendor configuration stay in the application.

## Packages

| Package | Purpose | Platforms | Stability |
| --- | --- | --- | --- |
| [`dartitect`](packages/dartitect/) | Result, lifecycle, resource ownership, architecture events | Dart, Flutter, web | `1.0.0-rc.3` |
| [`dartitect_sync`](packages/dartitect_sync/) | Provider-neutral sync DAG, checkpoints, leases, progress, headless protocol | Dart, Flutter, web | `1.0.0-rc.3` |
| [`dartitect_isolates`](packages/dartitect_isolates/) | Versioned typed isolate workers, ACKs, heartbeats, deadlines, safe-stop | Dart VM, Flutter native | `1.0.0-rc.3` |
| [`dartitect_flutter`](packages/dartitect_flutter/) | ViewModel ownership, async commands, selectors, scope, Flutter error binding | Flutter | `1.0.0-rc.3` |
| [`dartitect_observability`](packages/dartitect_observability/) | Logs, redaction, reporting, W3C tracing, bounded runtime | Dart, Flutter, web | `1.0.0-rc.3` |
| [`dartitect_dio`](packages/dartitect_dio/) | Dio ownership, typed failures, cancellation, minimal telemetry | Dio platforms | `1.0.0-rc.3` |
| [`dartitect_objectbox`](packages/dartitect_objectbox/) | Store/query/watcher ownership around generated consumer models | Android, iOS, Linux, macOS, Windows | `1.0.0-rc.3` |
| [`dartitect_sentry`](packages/dartitect_sentry/) | Adapters for a borrowed, consumer-initialized Sentry Hub | Dart, Flutter | `1.0.0-rc.3` |
| [`dartitect_privacy`](packages/dartitect_privacy/) | Explicit ATT status/request without automatic prompts | iOS; typed not-supported elsewhere | `1.0.0-rc.3` |
| [`dartitect_media`](packages/dartitect_media/) | Typed gallery permission and image-save boundary | Android, iOS | `1.0.0-rc.3` |
| [`dartitect_locale_br`](packages/dartitect_locale_br/) | Immutable Brazilian postal-code values | Dart, Flutter, web | `1.0.0-rc.3` |
| [`dartitect_geometry`](packages/dartitect_geometry/) | Deterministic polygon pole-of-inaccessibility geometry | Dart, Flutter, web | `1.0.0-rc.3` |
| [`dartitect_testing`](packages/dartitect_testing/) | Deterministic clocks, probes, recording telemetry, contract harnesses | Dart, Flutter, web | `1.0.0-rc.3` |
| [`dartitect_cli`](packages/dartitect_cli/) | Inspect, scan, doctor, config, baseline, generators, Codex sync | Dart VM | `1.0.0-rc.3` |
| [`dartitect_lints`](packages/dartitect_lints/) | Official analyzer-plugin architecture diagnostics | Dart analyzer | `1.0.0-rc.3` |
| [`dartitect_mcp`](packages/dartitect_mcp/) | Local MCP tools/resources for reviewed architecture work | Dart VM, STDIO | `1.0.0-rc.3` |

## Ecosystem selection

Choose the smallest package and entrypoint set for the feature. The
[ecosystem selection guide](docs/guides/ecosystem-selection.md) maps
capabilities, platforms, skills, combinations, and contraindications. The
[implementation recipes](docs/guides/implementation-recipes.md) cover a simple
feature, reactive runtime, local-first pagination, mutation/outbox,
observability, and adapter composition using existing tested APIs.
See also [model generation](docs/guides/model-generation.md) and the
[offline ecosystem policy](docs/guides/ecosystem-policy.md).
The [Native Strict matrix](docs/guides/native-strict-matrix.md) maps common
Flutter responsibilities to their Dartitect boundaries and records what stays
consumer-owned.

## Quickstart

Until the cohort is authorized for pub.dev, declare the selected package at its
candidate version and override its complete Dartitect closure to the protected
Git tag. For `dartitect_flutter`:

```yaml
dependencies:
  dartitect_flutter: 1.0.0-rc.3

dependency_overrides:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.3
      path: packages/dartitect
  dartitect_flutter:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.3
      path: packages/dartitect_flutter
```

Generate the exact override closure for any combination of the sixteen
packages with `dart run tool/git_dependency_overrides.dart <package>[,<package>...]`.
The [Git candidate consumption guide](docs/guides/git-candidate-consumption.md)
documents validation and the distinction from the future signed formal
channel.

```dart
import 'package:dartitect/dartitect.dart';

Future<Result<String, String>> loadName() async => const Ok('Dartitect');

Future<void> main() async {
  final resources = ResourceOwner(label: 'application');
  final result = await loadName();
  switch (result) {
    case Ok(:final value):
      print(value);
    case Err(:final failure):
      print('Expected: $failure');
  }
  await resources.disposeAsync();
}
```

Start with [`docs/guides/getting-started.md`](docs/guides/getting-started.md),
select the ecosystem, then read the focused guide for the boundary you are
changing.

## Sync and headless work

Add `dartitect_sync` when multiple local-authority datasets need explicit
ordering, checkpoints, leases, progress, deadlines, or background delivery.
The package supplies mechanism only: repositories still own local transactions,
remote mapping, idempotency, retry, conflict resolution, authentication, and
scheduling. Every headless request builds a fresh owned graph and transfers
validated data rather than live provider resources.

## Observability and adapters

`dartitect_observability` is local-first: developer logging is the default;
remote reporting and tracing are opt-in. Sanitize before every destination.
Never record request/response bodies, headers, queries, credentials, DSNs,
identity, or identifying paths.

Official adapters are deliberately small. Dio records method/protocol/status,
ObjectBox uses the consumer's generated model, and Sentry borrows an injected
Hub. For another database, HTTP client, or telemetry vendor, implement the small
public contracts described in the
[custom integrations guide](docs/guides/custom-integrations.md).

## CLI and analyzer plugin

```console
dart run dartitect_cli:dartitect inspect --json
dart run dartitect_cli:dartitect scan --no-baseline
dart run dartitect_cli:dartitect doctor
dart run dartitect_cli:dartitect init --dry-run
dart run dartitect_cli:dartitect baseline create --dry-run
dart run dartitect_cli:dartitect codex sync --dry-run
dart run dartitect_cli:dartitect fleet versions apps/a apps/b --root . --json
dart run dartitect_cli:dartitect fleet check apps/a apps/b --root . --json
```

Fleet roots are explicit and confined. Pinned offline policy and preview-only
cohort upgrades are documented in the [fleet tooling guide](docs/guides/fleet-tooling.md).

Install the analyzer plugin in the consuming package:

```yaml
dev_dependencies:
  dartitect_lints: 1.0.0-rc.3
```

```yaml
# analysis_options.yaml
plugins:
  dartitect_lints:
```

Repository contributors can use the local package instead:

```yaml
plugins:
  dartitect_lints:
    path: packages/dartitect_lints
```

The plugin reports `DT1001`–`DT1007` as warnings. Suppress one occurrence only
with a reason, for example `// dartitect-ignore: DT1004 -- legacy callback API`.
Use `dartitect scan` in CI or when an editor cannot host analyzer plugins.

## Codex skills

`dartitect codex sync --dry-run` previews eleven focused, managed skills; running
without `--dry-run` updates only manifest-owned `dartitect-*` directories and
preserves an existing `AGENTS.md`. The suite covers design, conformance audit, core
runtime, reactive runtime, offline-first, observability, adapters, testing,
tooling, and local MCP. Every skill permits implicit invocation and supplies a
focused `$dartitect-*` prompt. Consumer-owned skills—including this repository's
`repository-contribution`—are never managed by sync. Skills encode invariants;
they do not grant write authority.

## Local MCP server

`dartitect_mcp` is experimental, local, STDIO-only, and read-only by default.
It exposes bounded inspect/scan/doctor/explain/conformance/preview tools plus
generated package, diagnostic, guide, and config resources. It exposes no
`create`, shell, arbitrary file read, HTTP server, OAuth, or remote application
access.

```yaml
dev_dependencies:
  dartitect_mcp: 1.0.0-rc.3
```

```console
dart run dartitect_mcp:dartitect_mcp --root .
codex mcp add dartitect -- dart run dartitect_mcp:dartitect_mcp --root .
```

Project-scoped Codex configuration:

```toml
[mcp_servers.dartitect]
command = "dart"
args = ["run", "dartitect_mcp:dartitect_mcp", "--root", "."]
default_tools_approval_mode = "writes"
startup_timeout_sec = 20
tool_timeout_sec = 120
```

To permit reviewed changes, add `--allow-writes`. A write still requires a
prior preview, an opaque unexpired single-use `planId`, `confirmed = true`, the
client's MCP approval, full state revalidation, in-process serialization, and a
filesystem lock. See the [MCP guide](docs/guides/mcp.md) for generic clients and
the complete threat model.

## Compatibility and versioning

The workspace requires Dart `^3.13.0`; Flutter packages require Flutter
`>=3.47.1`. ObjectBox has no web support. The CLI/MCP are local VM tools.
Candidate packages may receive reviewed API corrections before a new release;
semantic versioning applies after stable release. The complete
sixteen-package cohort moves in lockstep.

Only stable config v1 is accepted; experimental versions have no migration
path. Baselines fingerprint code, path, and evidence without line numbers.
Public API changes are checked against a reviewed snapshot.

## Limitations and security

Dartitect does not validate business logic, make provider SDKs safe, hide
isolate constraints, or guarantee rollback against hostile concurrent programs.
Existing projects may run the read-only conformance audit, but 1.0 supplies no
official runtime migration, compatibility shim, or coexistence workflow.
Generated-once application files become consumer-owned. Only fully generated,
manifest-marked artifacts may be replaced by tooling.

Do not put credentials in `dartitect.json`, MCP config, examples, issues, or
logs. Report vulnerabilities privately through GitHub Security Advisories; see
[`SECURITY.md`](SECURITY.md).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). New adapters need an isolated package,
real boundary tests, public docs, dependency rationale, license review, and a
skills update. All normal changes use the short-lived branch, complete PR,
required-check, and squash workflow in the
[repository contribution guide](docs/guides/repository-contribution.md). No
package is published by repository verification commands.

## License and next steps

The current candidate line and future versions are available under the
[BSD 3-Clause License](LICENSE). GitHub Actions performs every technical gate;
a human selects only the manual publication channel after the exact main SHA
and CI run are verified.
