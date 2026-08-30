# Greenfield vertical platform

RC8 completes the generated closure, operational storage, race safety,
semantic API, consumer-tax, OpenAPI, and observed-evidence requirements before
1.0. This source delivery does not create a tag, release, or stable `1.0.0`;
promotion is release-only.

## Canonical creation

```console
dartitect create app shop \
  --targets=android,ios,web

# Declare named storage, transport, observability, and scheduler blocks in
# shop/dartitect.json before creating a feature that refers to them.
dartitect create feature orders \
  --profile=offline-full --scope=session \
  --targets=android,ios,web \
  --storage-context=primary --transport=api --pagination=cursor \
  --headless-targets=android,ios \
  --diagnostics=full \
  --capabilities=credentials,attachments,forms,queries

dartitect wiring sync --dry-run --json
dartitect wiring sync --apply
```

The only feature profiles are `local`, `online`, `cache`, `replica`, and
`offline-full`. Tooling updates and removes only manifest-owned
`*.dartitect.g.dart` outputs. Domain schema, repositories, remote mappings,
conflict policy, queries, and UI remain consumer-owned and are never
overwritten.

`create app` generates an empty shell for exactly the requested targets. It
does not select transport, storage, scheduler, or observability providers and
does not generate an example unless `--example=tasks` is requested.
`create feature` records the strict declaration, creates consumer seams once,
and materializes executable
repository/provider/resource/command/pagination/outbox/sync/job/diagnostic/
ViewModel wiring.

## Stable opt-in workflows

- `package:dartitect/dartitect_credentials.dart`: expiry, refresh
  single-flight with independent waiters, generation-fenced invalidation,
  forced logout, session rebuild, Dio/headless integration, and a
  consumer-owned store.
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
- `package:dartitect_sync/dartitect_sync.dart`: injected manual, lifecycle,
  connectivity, scheduler, push, and session trigger sources; generation
  fencing; one coalesced follow-up; and explicit offline/blocked/backoff state
  without hidden retries.

Workmanager capability maturity is stable on Android/iOS/macOS, preview on
web/Linux because of upstream lifecycle limits, and typed unsupported on
Windows.

## Evidence

Typed contract drivers must execute every row for the selected profile. The
matrix derives evidence from its own event journal, observed stores, revisions,
acknowledgements, fresh graph registrations, and `ResourceCensus`; drivers
cannot return facts or a residual map. Provider fixtures prove
atomic domain/outbox writes, restart, checkpoint, fencing, uncertainty,
conflict, migrations, UID persistence, and cleanup. `paved_road_canary` and
`thin_consumer_canary` ensure the generated road does not leak coordinators,
provider owners, sync engines, mutation commands, job dispatchers, or manual
diagnostics into consumer-owned Dart files.

Before extending the platform, ask:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be yes; otherwise reusable infrastructure belongs in a
typed project-local extension and business behavior remains in the application.
