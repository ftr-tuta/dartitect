# Selection matrix

Select only rows justified by a concrete boundary. The matrix lists all 25
stable packages so an omitted package is an explicit decision.

| Package | Select for | Route or boundary |
| --- | --- | --- |
| `dartitect` | Result, ownership, commands, credentials, and composition | `$dartitect-runtime` |
| `dartitect_flutter` | Basic Flutter ViewModels, hosts, forms, queries, or opt-in reactive entrypoints | `$dartitect-runtime`, `$dartitect-reactive` |
| `dartitect_flutter_testing` | Dev-only semantics, accessibility, contrast, tap-target, and paired UI matrices | `$dartitect-ui`, `$dartitect-testing` |
| `dartitect_sync` | Durable mutation/outbox, dataset DAGs, checkpoints, leases, and headless sync | `$dartitect-offline-first` |
| `dartitect_resilience` | Bounded retry, single-flight, breaker, bulkhead, or rate limiting | `$dartitect-runtime`, `$dartitect-testing` |
| `dartitect_jobs` | Versioned job envelopes, bounded dispatch, deadlines, receipts, and fencing ports | `$dartitect-offline-first`, `$dartitect-testing` |
| `dartitect_transfer` | Resumable chunks or attachment staging with durable checkpoints | `$dartitect-adapters`, `$dartitect-testing` |
| `dartitect_devtools` | Development-only, read-only, payload-free service extensions | `$dartitect-observability`, `$dartitect-testing` |
| `dartitect_isolates` | Versioned worker ACK/readiness/heartbeat/deadline lifecycle | `$dartitect-runtime`, `$dartitect-testing` |
| `dartitect_observability` | Provider-neutral logs, errors, tracing, and diagnostics | `$dartitect-observability` |
| `dartitect_dio` | Explicit Dio ownership, typed transport failures, and safe instrumentation | `$dartitect-adapters` |
| `dartitect_drift` | Lifecycle and operational adapters around a consumer-generated Drift database | `$dartitect-adapters`, `$dartitect-offline-first` |
| `dartitect_objectbox` | Native Store/query/watch/projection lifecycle around a consumer-generated model | `$dartitect-adapters`, `$dartitect-offline-first` |
| `dartitect_sentry` | Borrowed-Hub telemetry after the consumer selects and initializes Sentry | `$dartitect-adapters`, `$dartitect-observability` |
| `dartitect_testing` | Deterministic failure, lifecycle, provider, and residual-resource harnesses | `$dartitect-testing` |
| `dartitect_cli` | Config v3, inspect/scan/doctor, generators, fleet, contracts, and Codex sync | `$dartitect-tooling` |
| `dartitect_lints` | Analyzer-host Native Strict and modeling diagnostics | `$dartitect-tooling` |
| `dartitect_locale_br` | Structural Brazilian postal-code value handling only | `$dartitect-design` |
| `dartitect_geometry` | Finite planar polygon/polylabel values only | `$dartitect-design` |
| `dartitect_privacy` | Explicit iOS ATT status/request boundary | `$dartitect-adapters` |
| `dartitect_media` | Explicit Android/iOS image-save permission and action boundary | `$dartitect-adapters` |
| `dartitect_mcp` | Local bounded interactive context, previews, and reviewed writes | `$dartitect-mcp` |
| `dartitect_workmanager` | Workmanager callbacks adapted to a fresh job graph per execution | `$dartitect-adapters`, `$dartitect-offline-first` |
| `dartitect_modeling` | Opt-in immutable values, JSON, projections, lenses, and pure mappers | `$dartitect-modeling` |
| `dartitect_modeling_analyzer` | Tooling-only semantic compilation and model diagnostics | `$dartitect-modeling`, `$dartitect-tooling` |

Generated `FeatureHost` and `CommandStateBuilder` remain Material-neutral;
product UI stays consumer-owned. Scheduling, recurrence, schemas, transactions,
conflict/retry/authentication policy, provider configuration, and semantic
mappings stay consumer-owned. ObjectBox has no web support. CLI and MCP run on
the Dart VM. Provider adapters never belong in domain, application, ViewModel,
or presentation layers.

Native Strict does not provide an overlap or coexistence mode for competing
application architecture runtimes.
