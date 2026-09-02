# Dartitect offline-first reference workload

This application is the consumer-owned integration workload for Dartitect's
stable `1.0.0` reactive runtime. Native targets use a generated ObjectBox 5.3.2
model; Web uses the same contract with a memory store because ObjectBox has no
Web runtime. Dio always crosses an HTTP adapter boundary, while UI state is
read exclusively from the local store.

## Run

From the repository root:

```text
flutter pub get
cd examples/reference_app
flutter run -d linux
```

The app seeds 10,000 deterministic tasks on first open. Search is
switch-latest, refresh joins, load-more drops reentrant calls, and each task has
a sequential durable mutation lane. Use **Airplane mode** to queue a local
change, then disable it to reconnect and recover pending outbox operations.
The diagnostics route demonstrates navigation/TickerMode without owning the
session.

## Scenario runbook

The automated workload covers:

- online commit, offline local authority, reconnect, and manual retry;
- duplicate delivery with the same idempotency key;
- definitive reject, conflict, uncertain delivery, and unexpected crash;
- explicit audit/resume after a crash—never automatic crash retry;
- 10k paging, incremental projection, search cancellation, and background
  isolate checksum;
- app background/foreground, navigation/TickerMode, dependents-first teardown,
  and zero residual watchers, queries, timers, or background work;
- native ObjectBox close/reopen of the same directory and durable outbox
  recovery.

Run the normal deterministic suite:

```text
flutter test examples/reference_app
```

Run the verified native ObjectBox gate on the current host:

```text
dart run tool/setup_objectbox_vm.dart
dart run tool/verify.dart --skip-get --native-objectbox
```

The native restart test is intentionally skipped by a plain `flutter test` and
executed by the second command with the checksum-verified ObjectBox library in
the platform loader path.

## Ownership and recovery

`AppRuntime` opens one `LocalFirstTaskRepository`. The generated feature graph
owns its teardown after the ViewModel. The repository owns the paged
resource, mutation lanes, local observation, bounded in-memory journal, Dio
client, background executor, and exactly one selected Memory, Drift, or
ObjectBox store. There is no dual-write or implicit migration between engines.
Disposal proceeds in that order. `TasksViewModel` owns commands, effects,
selection, and query state; widgets borrow it and retain only route callbacks,
controllers, navigation, and lifecycle observation.

Expected failures are typed and durable. Offline remains pending; reject and
conflict remain visible for consumer policy; uncertain delivery requires an
audit. An unexpected crash marks the operation uncertain and stops only its
entity lane. `auditAndResume` is the sole path that persists a pending decision,
resumes the lane, and reuses the original idempotency key.
