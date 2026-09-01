# Dartitect

> **Scope:** Dartitect is an opinionated SDK for new Dart and Flutter projects.
> It does not convert, incrementally adopt, or coexist with an existing
> application architecture. Projects originally created with Dartitect can be
> upgraded between supported Dartitect versions.

Dartitect is a greenfield-only set of focused Dart and Flutter packages for constructor-based
composition, explicit resource ownership, typed expected failures, native
reactive state, offline-first coordination, and architecture tooling. It is not
an application framework: the consuming application continues to own its
domain, data model, provider configuration, schemas, migrations, navigation,
and product policy.

## Project suitability

Dartitect is a good fit when a team wants these rules to be visible in code:

- dependencies enter through constructors at an app, session, route, feature,
  or isolate composition root;
- every stateful value or resource has one owner and a documented disposal
  order;
- expected failures are values while unexpected failures remain exceptions;
- local persistence is presentation authority in offline-first features;
- provider SDKs remain at infrastructure boundaries; and
- telemetry is bounded, sanitized, and unable to change application behavior.

It is a poor fit when the application relies on ambient service lookup, wants
provider objects available throughout the widget tree, treats multiple state
runtimes as simultaneous owners of the same feature, or expects a library to
choose schemas, conflict policy, retries, authentication, navigation, or
telemetry contents on its behalf.

`native_strict` is the only architecture profile. A Dartitect application does
not install Riverpod, BLoC, Provider, GetIt, MobX, Signals, another container,
or another state/lifecycle runtime. Feature profiles (`local`, `online`,
`cache`, `replica`, and `offline-full`) select behavior, not architecture.

Before adding a capability to this repository, ask:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

It enters Dartitect only when all three answers are yes. Non-neutral reusable
plumbing belongs in a typed extension local to the project; business rules,
domain behavior, schema, semantic mapping, conflict policy, and UI remain in
the application.

## Package selection map

Select the smallest set that owns the required boundary. Every package is
independently documented and exports only public entrypoints under `lib/`.

| Workflow | Start with | Add when needed |
| --- | --- | --- |
| Pure Dart results, cancellation, ownership, or bounded work | [`dartitect`](packages/dartitect/) | [`dartitect_isolates`](packages/dartitect_isolates/) for a typed native worker |
| Flutter MVVM with native listenables | [`dartitect_flutter`](packages/dartitect_flutter/) | Import `dartitect_flutter_reactive.dart` only for the owned reactive runtime |
| Adaptive, accessible Flutter presentation | `package:dartitect_flutter/dartitect_flutter_ui.dart` | Consumer-owned Material/Cupertino controls, themes, localization, navigation, focus, and restoration |
| Credentials and authenticated-session rebuild | [`dartitect`](packages/dartitect/) | Import `dartitect_credentials.dart`; storage and credential values stay consumer-owned |
| Restorable forms and local-authority queries | [`dartitect_flutter`](packages/dartitect_flutter/) | Import `dartitect_flutter_forms.dart` or `dartitect_flutter_queries.dart` explicitly |
| Immutable values, bounded JSON, projections, or boundary mapping | [`dartitect_modeling`](packages/dartitect_modeling/) | [`dartitect_modeling_analyzer`](packages/dartitect_modeling_analyzer/) is for tooling authors, not applications |
| Reactive resources, families, collections, and local-authority paging | `dartitect_flutter_reactive.dart` | A persistence adapter only after repository and ownership boundaries exist |
| Durable local mutation and outbox delivery | [`dartitect_sync`](packages/dartitect_sync/) | [`dartitect_drift`](packages/dartitect_drift/) or [`dartitect_objectbox`](packages/dartitect_objectbox/) for consumer-owned transactions |
| Ordered multi-dataset synchronization | [`dartitect_sync`](packages/dartitect_sync/) | Checkpoint, journal, and lease implementations selected by the application |
| Bounded retry, single-flight, breakers, bulkheads, or rate limiting | [`dartitect_resilience`](packages/dartitect_resilience/) | Consumer failure classification, budget, deadline, clock, scheduler, and randomness |
| Generic headless/background work | [`dartitect_jobs`](packages/dartitect_jobs/) | [`dartitect_isolates`](packages/dartitect_isolates/) when the host uses an isolate worker |
| Workmanager scheduling | [`dartitect_workmanager`](packages/dartitect_workmanager/) | Stable contract; web/Linux capability maturity is preview and Windows is typed unsupported |
| Resumable chunk transfer | [`dartitect_transfer`](packages/dartitect_transfer/) | [`dartitect_dio`](packages/dartitect_dio/) for an optional transport adapter |
| Attachments | `package:dartitect_transfer/dartitect_attachments.dart` | Consumer picker/share/gallery/file ports and an optional background scheduler |
| HTTP infrastructure | [`dartitect_dio`](packages/dartitect_dio/) | [`dartitect_observability`](packages/dartitect_observability/) for neutral telemetry policy |
| Persistence with Drift | [`dartitect_drift`](packages/dartitect_drift/) | Consumer-generated database, schema, migrations, codecs, and executor |
| Persistence with ObjectBox | [`dartitect_objectbox`](packages/dartitect_objectbox/) | Consumer entities, generated model, native fixture, and Store opener |
| Logs, errors, tracing, and redaction | [`dartitect_observability`](packages/dartitect_observability/) | [`dartitect_sentry`](packages/dartitect_sentry/) for a borrowed consumer-initialized Hub |
| Platform or domain leaves | [`dartitect_privacy`](packages/dartitect_privacy/), [`dartitect_media`](packages/dartitect_media/), [`dartitect_locale_br`](packages/dartitect_locale_br/), [`dartitect_geometry`](packages/dartitect_geometry/) | Add only the capability the application actually uses |
| Deterministic contract tests | [`dartitect_testing`](packages/dartitect_testing/) | Real provider fixtures when generated/native behavior is under test |
| Paired Flutter UI tests | [`dartitect_flutter_testing`](packages/dartitect_flutter_testing/) as a dev dependency | Consumer root, themes, locales, keyboard, focus, navigation, and action assertions |
| Read-only local diagnostics inspection | [`dartitect_devtools`](packages/dartitect_devtools/) | Explicit development-entrypoint registration only; never product activation |
| Inspection, generation, editor diagnostics, or agent context | [`dartitect_cli`](packages/dartitect_cli/), [`dartitect_lints`](packages/dartitect_lints/), [`dartitect_mcp`](packages/dartitect_mcp/) | Managed Codex skills synchronized by the CLI |
| OpenAPI 3.1 JSON contracts | `dartitect contracts check|sync` | Local specs/refs only; generated DTOs and endpoint descriptors never infer domain mappings or execute security schemes |
| Non-neutral reusable infrastructure | `DartitectLocalExtension<B>` in the consumer workspace | Typed project-local binding generated from confined semantic source analysis; no plugin execution, registry, marketplace, or SDK preset |

The [ecosystem selection guide](docs/guides/ecosystem-selection.md) gives the
detailed decision matrix. The [implementation recipes](docs/guides/implementation-recipes.md)
show complete boundary-oriented flows. The [greenfield platform guide](docs/guides/paved-road-platform.md)
connects feature profiles, hosts, resilience, jobs, transfer, diagnostics, and
contract matrices without turning them into a framework. The
[business-neutral UI quality guide](docs/guides/ui-quality.md) covers responsive
layout, exhaustive presentation, localization, accessibility, and the paired UI
matrix.

## Core workflow

Use `Result<T, F>` only for an expected failure the caller can handle. Own
resources at composition and release dependents before dependencies.

```dart
import 'dart:async';

import 'package:dartitect/dartitect.dart';

Future<Result<int, StateError>> loadCount() async => const Ok<int>(42);

Future<void> main() async {
  final owner = ResourceOwner(label: 'application');
  owner.own(StreamController<void>(), (value) => value.close());
  try {
    switch (await loadCount()) {
      case Ok(:final value):
        print(value);
      case Err(:final failure):
        print('Expected failure: $failure');
    }
  } finally {
    await owner.disposeAsync();
  }
}
```

In Flutter, a `ViewModelHost.create` owns its ViewModel and
`ViewModelHost.value` borrows one. Views receive ViewModels; ViewModels receive
application-facing ports. `BuildContext`, database objects, network clients,
and provider containers do not cross those boundaries. See
[getting started](docs/guides/getting-started.md) and
[composition, lifecycle, and isolates](docs/guides/composition-lifecycle-isolates.md).

## Reactive workflow

The optional Flutter reactive entrypoint models a graph owned by one
`ReactiveOwner`. Data state (`waiting`, `ready`, expected `failed`, or unexpected
`crashed`) is independent of source temperature (`hot`, `warm`, or `cold`). A
`ReactiveSource.open()` creates an activation-local session that owns its
watcher, subscription, query, or cursor and borrows its provider.

Resources activate through an explicit policy, apply bounded backpressure, and
reject late publication after cancellation or disposal. Families bound idle
retention; collections separate structure from item notifications; paging
publishes only after a consumer-owned local transaction is observed. Read the
[reactive runtime guide](docs/guides/reactive-runtime.md) before composing these
types.

## Offline-first and synchronization workflows

Three mechanisms solve different problems:

1. `MutationCommand` performs a local change and durable outbox enqueue through
   one consumer-owned atomic transaction, then attempts at-least-once delivery
   in bounded per-key lanes. The application owns idempotency scope, retry and
   conflict classification, compensation, and outbox persistence.
2. `SyncEngine` runs a validated dataset dependency graph. Checkpoints confirm
   local coverage; journals record payload-free run facts; leases provide a
   fencing token only when the local commit compares that token atomically.
3. `HeadlessSyncEndpoint` adapts a versioned sync definition through
   `dartitect_jobs`, returns acceptance separately from a terminal receipt,
   builds a fresh owned graph for admitted work, deduplicates a bounded request
   set, and drains on disposal without hidden retries.

These mechanisms can be composed, but none replaces a repository transaction.
Never advance a checkpoint before the corresponding local state is durable.
Never infer exactly-once delivery from an outbox or lease. Inspect terminal
receipts before retrying an uncertain run. See the
[commands/results/effects guide](docs/guides/commands-results-effects.md) and
the sync package README.

## Persistence workflows

`dartitect_drift` and `dartitect_objectbox` are lifecycle and integration
adapters, not database abstractions. The application owns its schema, generated
types, migrations, executor/Store configuration, encryption, serialization,
and repository policy.

- Drift supports consumer-selected native and web executors. Use
  `DriftDatabaseOwner.create` when the wrapper owns closing the generated
  database and `.value` when it borrows one. Drift streams feed a
  `StreamReactiveSource` without a Dartitect query DSL.
- ObjectBox is native-only. Queries, watchers, projections, and isolate-local
  Store wrappers must close before the original Store. A Store object never
  crosses an isolate; transferable Store reference bytes may be used to attach
  another wrapper with the consumer-generated model.

Do not span one transaction across Drift and ObjectBox. A feature chooses one
write authority; coexistence is allowed only across separately owned feature
boundaries with no dual-write invariant.

## Observability workflow

Create `ObservabilityRuntime` at composition and inject its provider-neutral
logger, reporter, and tracer. Local developer logging is the default. Remote
destinations are opt-in, and provider objects remain consumer-owned or are
registered with explicit ownership.

Sanitize before every destination. Authorization, cookies, tokens, passwords,
request or response bodies, headers, query strings, DSNs, identity, entity
keys, and identifying paths are prohibited telemetry. Expected `Err<F>` values
remain application state; unexpected crashes may be reported once and rethrown.
See [observability](docs/guides/observability.md) and
[adapters](docs/guides/adapters.md).

## Tooling workflow

The CLI is the deterministic interface for local development and CI:

```console
dart run dartitect_cli:dartitect inspect --json
dart run dartitect_cli:dartitect scan
dart run dartitect_cli:dartitect doctor
dart run dartitect_cli:dartitect inspect --consumer-tax --json
dart run dartitect_cli:dartitect contracts check api/openapi.yaml --json
dart run dartitect_cli:dartitect model check --json
dart run dartitect_cli:dartitect wiring sync --dry-run --json
dart run dartitect_cli:dartitect codex sync --dry-run
```

Preview mutating operations before applying them. Generated-once files become
consumer-owned; only manifest-owned outputs can be converged by the tool. The
analyzer plugin supplies editor feedback, while `dartitect scan` is the CI and
unsupported-host fallback. MCP is local STDIO, read-only by default, and maps
to the typed project service rather than a shell. See [model generation](docs/guides/model-generation.md),
[config v3](docs/guides/config-v3.md),
[typed project-local extensions](docs/guides/project-local-extensions.md),
[bounded OpenAPI contracts](docs/guides/openapi-contracts.md),
[credential generations](docs/guides/credential-generations.md),
[consumer tax](docs/guides/consumer-tax.md),
[MCP](docs/guides/mcp.md), and [fleet tooling](docs/guides/fleet-tooling.md).

## Ownership and lifecycle rules

- Create owned graphs at visible app, session, route, feature, or isolate roots.
- Mark every injected resource as owned or borrowed. Borrowed resources are
  never closed by the borrower.
- Stop admission, request cooperative cancellation, drain active work, detach
  observers/watchers, and then dispose dependencies in reverse order.
- Publish a replacement graph atomically. If old cleanup fails after
  publication, the new generation remains authoritative; inspect the cleanup
  receipt instead of replaying construction blindly.
- Build a new graph inside every isolate. Transfer versioned data and validated
  trace context, never live clients, databases, Stores, owners, subscriptions,
  ViewModels, or widget state.
- Keep resource bounds explicit: queues, concurrent keys, retained family
  entries, progress history, diagnostic buffers, and remembered request IDs.

## Allowed and prohibited patterns

| Allowed | Prohibited |
| --- | --- |
| Constructor injection from a visible composition root | Service location or ambient global lookup inside Dartitect-owned code |
| A provider container adapting into one constructor boundary | Provider/container types leaking into domain, application, or ViewModel APIs |
| One owner for a feature state graph | Duplicate ownership or two runtimes publishing the same authoritative state |
| One local write authority and an atomic domain-plus-outbox transaction | Dual-write across stores or a transaction claimed across persistence engines |
| Versioned transferable DTOs and isolate-local resource construction | Live database, Store, client, subscription, owner, or ViewModel objects crossing isolates |
| Sanitized fixed telemetry facts | Credentials, payloads, identity, entity keys, or identifying paths in telemetry |
| Drift and ObjectBox in separate bounded contexts with one writer per dataset | Any second architecture/state/container runtime in a Dartitect application |

The prohibited cases are incompatibilities, not style preferences: Dartitect
cannot provide deterministic ownership, atomicity, or privacy when those
boundaries are violated.

## Platforms and versions

The workspace requires Dart `^3.13.0`; Flutter packages require Flutter
`>=3.47.1`. Pure-Dart packages support the platforms declared in their package
READMEs. Drift accepts consumer-owned native and web executors. ObjectBox has no
web support. The CLI, modeling analyzer, and MCP server run on the Dart VM.

All 25 packages permanently share one lockstep version and are distributed only
through the immutable GitHub Release for `v1.0.0`. Declare only direct packages;
transitive Dartitect packages resolve from the same tag without overrides:

```yaml
dependencies:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      path: packages/dartitect
      tag_pattern: 'v{{version}}'
    version: 1.0.0
```

External dependencies continue to use their normal registries. See the
[Git release consumption guide](docs/guides/git-release-consumption.md) and the
[release page](https://github.com/ftr-tuta/dartitect/releases/tag/v1.0.0).

## Security, contribution, and license

Do not place credentials in `dartitect.json`, MCP configuration, examples,
issues, or logs. Report vulnerabilities through GitHub Security Advisories as
described in [SECURITY.md](SECURITY.md).

Repository work follows [CONTRIBUTING.md](CONTRIBUTING.md), the
[repository contribution workflow](docs/guides/repository-contribution.md), and
the [Code of Conduct](CODE_OF_CONDUCT.md). Verification does not publish
packages, create tags, or create releases.

Dartitect is available under the [BSD 3-Clause License](LICENSE).
