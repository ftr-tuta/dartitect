# Greenfield vertical platform

RC6 established the initial paved-road source cohort; it did not complete the
vertical platform. RC8 completes the remaining generated closure, operational
storage, race safety, semantic API, and observed-evidence requirements before
1.0. This work does not create a tag, release, or stable `1.0.0`; promotion is
release-only.

## Canonical creation

```console
dartitect create app shop \
  --preset=offline-hybrid --transport=dio \
  --observability=developer --scheduler=workmanager

dartitect create feature orders \
  --profile=offline-full --scope=session \
  --persistence-native=drift --persistence-web=drift \
  --transport=dio --pagination=cursor --headless-sync \
  --diagnostics=full \
  --capabilities=credentials,attachments,forms,queries

dartitect wiring sync --dry-run --json
dartitect wiring sync --apply
```

The only feature profiles are `online`, `cache`, `replica`, and
`offline-full`. Tooling updates and removes only manifest-owned
`*.dartitect.g.dart` outputs. Domain schema, repositories, remote mappings,
conflict policy, queries, and UI remain consumer-owned and are never
overwritten.

`create app` generates a six-platform graph, session runtime, observability,
credentials/scheduler seams, shutdown, and a `main.dart` of at most 15
non-empty lines using `runDartitectApplication`. `create feature` records the
strict declaration, creates consumer seams once, and materializes executable
repository/provider/resource/command/pagination/outbox/sync/job/diagnostic/
ViewModel and contract-fixture wiring.

## Stable opt-in workflows

- `package:dartitect/dartitect_credentials.dart`: expiry, refresh
  single-flight, invalidation, forced logout, session rebuild, Dio/headless
  integration, and a consumer-owned store.
- `package:dartitect_transfer/dartitect_attachments.dart`: atomic temporary
  file plus metadata/outbox staging, resumable upload, background scheduling,
  retry, and consumer picker/share/gallery ports.
- `package:dartitect_flutter/dartitect_flutter_forms.dart`: original/current,
  dirty/touched, sync and restart-latest async validation, submit, versioned
  drafts, history, restoration, and unsaved changes.
- `package:dartitect_flutter/dartitect_flutter_queries.dart`: filters,
  debounce, cursor paging, refresh, selection, bulk actions, local authority,
  closed presentation states, and restoration.
- `package:dartitect_workmanager/dartitect_workmanager.dart`: fresh graph per
  callback, versioned envelopes, deadlines, receipts, and cancellation.

Workmanager capability maturity is stable on Android/iOS/macOS, preview on
web/Linux because of upstream lifecycle limits, and typed unsupported on
Windows.

## Evidence

Typed contract fixtures must execute every row for the selected profile and
finish `disposeAsync` with a zero resource census. Provider fixtures prove
atomic domain/outbox writes, restart, checkpoint, fencing, uncertainty,
conflict, migrations, UID persistence, and cleanup. `paved_road_canary` and
`thin_consumer_canary` ensure the generated road does not leak coordinators,
provider owners, sync engines, mutation commands, job dispatchers, or manual
diagnostics into consumer-owned Dart files.

Before extending the platform, ask:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be yes; otherwise reusable infrastructure belongs in a
typed project-local extension and business behavior remains in the application.
