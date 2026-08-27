import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_objectbox/dartitect_objectbox.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/fixture_entity.dart';
import '../lib/drift_fixture_database.dart';
import '../lib/objectbox.g.dart';

void main() {
  final originalWorkingDirectory = Directory.current;
  setUpAll(() {
    final fixture = Directory('tool/objectbox_native_fixture');
    if (fixture.existsSync()) Directory.current = fixture.absolute;
  });
  tearDownAll(() => Directory.current = originalWorkingDirectory);

  test('real generated Store owns query and watcher before cleanup', () async {
    final tracer = _RecordingTracer();
    String? directoryPath;
    var watcherEvents = 0;
    final owner = await ObjectBoxStoreOwner.temporary(
      openStore: (path) {
        directoryPath = path;
        return openStore(directory: path);
      },
      instrumentation: ObjectBoxInstrumentation(tracer: tracer),
      configure: (store, observations) async {
        final box = store.box<FixtureEntity>();
        box.put(FixtureEntity(value: 'alpha'));
        final query = observations.ownQuery(
          box.query(FixtureEntity_.value.equals('alpha')).build(),
        );
        expect(query.find().single.value, 'alpha');

        final firstWatch = Completer<void>();
        final watcher = _WatcherHandle();
        watcher.subscription = box
            .query()
            .watch(triggerImmediately: true)
            .listen((query) {
              watcher.query ??= query;
              watcherEvents += 1;
              if (!firstWatch.isCompleted) firstWatch.complete();
            });
        observations.own<_WatcherHandle>(
          watcher,
          (value) => value.dispose(),
          label: 'ObjectBox watcher and query',
        );
        await firstWatch.future;
      },
    );

    expect(watcherEvents, greaterThanOrEqualTo(1));
    expect(owner.store.box<FixtureEntity>().count(), 1);
    expect(directoryPath, isNotNull);

    await expectLater(
      openStore(directory: directoryPath),
      throwsA(anything),
      reason: 'opening the same path twice in one isolate must be rejected',
    );

    await owner.disposeAsync();
    await owner.disposeAsync();

    expect(() => owner.store, throwsStateError);
    expect(await Directory(directoryPath!).exists(), isFalse);
    expect(tracer.spans.map((span) => span.status), <SpanStatus>[
      SpanStatus.ok,
      SpanStatus.ok,
    ]);
    expect(tracer.spans.every((span) => span.endCalls == 1), isTrue);
  });

  test(
    'generated ObjectBox workload uses the provider-neutral sync engine',
    () async {
      final owner = await ObjectBoxStoreOwner.temporary(
        openStore: (path) => openStore(directory: path),
      );
      final box = owner.store.box<FixtureEntity>();
      final checkpoints = ObjectBoxSyncCheckpointStore<String, int>(
        store: owner.store,
        readCheckpoint: (store, key) {
          for (final entity in store.box<FixtureEntity>().getAll()) {
            if (entity.value.startsWith('checkpoint:$key:')) {
              return int.parse(entity.value.split(':')[2]);
            }
          }
          return null;
        },
        writeCheckpoint: (store, key, checkpoint, fencingToken) {
          final checkpointBox = store.box<FixtureEntity>();
          for (final entity in checkpointBox.getAll()) {
            if (entity.value.startsWith('checkpoint:$key:')) {
              checkpointBox.remove(entity.id);
            }
          }
          checkpointBox.put(
            FixtureEntity(value: 'checkpoint:$key:$checkpoint'),
          );
        },
        removeCheckpoint: (store, key) {
          final checkpointBox = store.box<FixtureEntity>();
          for (final entity in checkpointBox.getAll()) {
            if (entity.value.startsWith('checkpoint:$key:')) {
              checkpointBox.remove(entity.id);
            }
          }
        },
      );
      final engine = SyncEngine<String, int, _FixtureSyncFailure>(
        datasets: <SyncDataset<String, int, _FixtureSyncFailure>>[
          SyncDataset<String, int, _FixtureSyncFailure>(
            key: 'notes',
            synchronize: (context) async {
              owner.store.runInTransaction<void>(
                TxMode.write,
                () => box.put(FixtureEntity(value: 'local-authority-note')),
              );
              return const Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.checkpoint(1),
              );
            },
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: checkpoints,
      );

      final report = await engine.start().done;

      expect(report.succeeded, isTrue);
      expect(
        box.getAll().map((entity) => entity.value),
        containsAll(<String>['local-authority-note', 'checkpoint:notes:1']),
      );
      await engine.disposeAsync();
      expect(engine.activeRunCount, 0);
      await owner.disposeAsync();
    },
  );

  test('reference bytes attach a distinct wrapper inside an isolate', () async {
    final owner = await ObjectBoxStoreOwner.temporary(
      openStore: (path) => openStore(directory: path),
    );
    owner.store.box<FixtureEntity>().put(FixtureEntity(value: 'background'));
    final reference = objectBoxStoreReference(owner.store);
    final resultPort = ReceivePort();

    await Isolate.spawn<(SendPort, ByteData)>(_readFromReference, (
      resultPort.sendPort,
      reference,
    ));
    final count = await resultPort.first.timeout(const Duration(seconds: 5));
    resultPort.close();

    expect(count, 1);
    expect(owner.store.isClosed(), isFalse);
    await owner.disposeAsync();
  });

  test('query source owns one watcher query per hot activation', () async {
    final owner = await ObjectBoxStoreOwner.temporary(
      openStore: (path) => openStore(directory: path),
    );
    final box = owner.store.box<FixtureEntity>();
    final alphaId = box.put(FixtureEntity(value: 'alpha'));
    final events = <ObjectBoxQueryLifecycleEvent>[];
    final collection = LiveCollection<int, String>();
    final projection =
        ObjectBoxVersionedProjection<FixtureEntity, int, String, String>(
          keyOf: (entity) => entity.id,
          versionOf: (entity) => entity.value,
          project: (entity) => entity.value,
        );
    final resource = LiveResource<List<FixtureEntity>, String>(
      source: ObjectBoxQuerySource<FixtureEntity, String>(
        builderFactory: box.query,
        mapFailure: (error, _) => error.toString(),
        lifecycleObserver: events.add,
      ),
      policy: const ActivationPolicy.alwaysHot(),
    );
    void projectPublishedValue() {
      final entities = resource.state.lastData;
      if (resource.state is ResourceReady<List<FixtureEntity>, String> &&
          entities != null) {
        projection.apply(collection, entities);
      }
    }

    resource.addListener(projectPublishedValue);

    await resource.start();
    await _waitFor(
      () => resource.state.lastData?.map((item) => item.value).toList(),
      <String>['alpha'],
    );
    expect(resource.readCount, 1, reason: 'activation must not double-query');
    expect(collection.item(alphaId).value, 'alpha');
    expect(collection.lastProjectionCount, 1);

    box.put(FixtureEntity(value: 'beta'));
    await _waitFor(
      () => resource.state.lastData?.map((item) => item.value).toList(),
      <String>['alpha', 'beta'],
    );
    expect(resource.readCount, 2);
    expect(collection.length.value, 2);
    expect(collection.lastProjectionCount, 1);

    final alpha = box.get(alphaId)!..value = 'alpha-updated';
    box.put(alpha);
    await _waitFor(
      () => <String>[collection.item(alphaId).value ?? ''],
      <String>['alpha-updated'],
    );
    expect(collection.lastProjectionCount, 1);

    resource.removeListener(projectPublishedValue);
    await collection.dispose();
    await resource.dispose();
    expect(resource.activeOperationCount, 0);
    expect(events, <ObjectBoxQueryLifecycleEvent>[
      ObjectBoxQueryLifecycleEvent.watcherStarted,
      ObjectBoxQueryLifecycleEvent.watcherCancelled,
      ObjectBoxQueryLifecycleEvent.queriesClosed,
    ]);
    expect(owner.store.isClosed(), isFalse, reason: 'Store is borrowed');
    await owner.disposeAsync();
  });

  test(
    'background projection uses isolate-local Store and drains before close',
    () async {
      final owner = await ObjectBoxStoreOwner.temporary(
        openStore: (path) => openStore(directory: path),
      );
      final box = owner.store.box<FixtureEntity>()
        ..putMany(<FixtureEntity>[
          FixtureEntity(value: 'alpha'),
          FixtureEntity(value: 'beta'),
        ]);
      final query = box.query().build();
      try {
        final found = await query.findAsync();
        expect(found.map((entity) => entity.value).toSet(), <String>{
          'alpha',
          'beta',
        });
      } finally {
        query.close();
      }

      final executor = ObjectBoxProjectionExecutor<String, List<String>>(
        store: owner.store,
        project: _projectFixtureValues,
      );
      final cancellation = CancellationSource();
      final result = await executor.execute(
        const TransferableProjectionRequest<String>(
          generation: 11,
          payload: 'projected:',
        ),
        cancellation.signal,
      );

      expect(result.generation, 11);
      expect(result.value.toSet(), <String>{
        'projected:alpha',
        'projected:beta',
      });
      expect(executor.activeTaskCount, 0);
      expect(owner.store.isClosed(), isFalse);

      final slowCancellation = CancellationSource();
      final slow = executor.execute(
        const TransferableProjectionRequest<String>(
          generation: 12,
          payload: 'slow:',
        ),
        slowCancellation.signal,
      );
      slowCancellation.cancel('fixture stale result');
      await expectLater(slow, throwsA(isA<CancellationException>()));
      await executor.disposeAsync();

      expect(executor.activeTaskCount, 0);
      expect(executor.isDisposed, isTrue);
      expect(owner.store.isClosed(), isFalse, reason: 'Store is borrowed');
      expect(box.count(), 2);
      cancellation.dispose();
      slowCancellation.dispose();
      await owner.disposeAsync();
    },
  );

  test(
    'mutation helper commits or rolls back local and outbox writes together',
    () async {
      final owner = await ObjectBoxStoreOwner.temporary(
        openStore: (path) => openStore(directory: path),
      );
      final box = owner.store.box<FixtureEntity>();
      final transaction = ObjectBoxMutationTransaction(owner.store);

      final committed = transaction.run<void, String>((store) {
        final transactionBox = store.box<FixtureEntity>();
        transactionBox
          ..put(FixtureEntity(value: 'local:entity-1'))
          ..put(FixtureEntity(value: 'outbox:idempotency-1'));
        return const Ok<void>(null);
      });
      expect(committed, isA<Ok<void>>());
      expect(box.getAll().map((entity) => entity.value), <String>[
        'local:entity-1',
        'outbox:idempotency-1',
      ]);

      final rejected = transaction.run<void, String>((store) {
        final transactionBox = store.box<FixtureEntity>();
        transactionBox
          ..put(FixtureEntity(value: 'local:must-rollback'))
          ..put(FixtureEntity(value: 'outbox:must-rollback'));
        return Err<String>('validation', StackTrace.current);
      });
      expect(rejected, isA<Err<String>>());
      expect(box.count(), 2);

      expect(
        () => transaction.run<void, String>((store) {
          store.box<FixtureEntity>().put(
            FixtureEntity(value: 'crash:rollback'),
          );
          throw StateError('broken atomic callback');
        }),
        throwsStateError,
      );
      expect(box.count(), 2);
      expect(owner.store.isClosed(), isFalse, reason: 'Store remains borrowed');
      await owner.disposeAsync();
    },
  );

  test(
    'ObjectBox and Drift coexist in separate bounded contexts and teardown',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'dartitect-coexistence-',
      );
      final teardown = <String>[];
      final objectBoxOwner = await ObjectBoxStoreOwner.temporary(
        openStore: (path) => openStore(directory: path),
      );
      final driftOwner =
          await DriftDatabaseOwner.create<CoexistenceDriftDatabase>(
            openDatabase: () => CoexistenceDriftDatabase(
              NativeDatabase.createInBackground(
                File('${temporary.path}/orders.sqlite'),
              ),
            ),
          );
      final notes = _ObjectBoxNotesRepository(objectBoxOwner.store, teardown);
      final orders = _DriftOrdersRepository(driftOwner.database, teardown);
      final observations = _FixtureObservationOwner(teardown);
      final sync = _FixtureSyncOwner(teardown);
      try {
        notes.save('note-one');
        await orders.save('order-one');

        expect(notes.values(), <String>['note-one']);
        expect(await orders.values(), <String>['order-one']);
        expect(objectBoxOwner.store.isClosed(), isFalse);
        expect(
          await driftOwner.database.customSelect('SELECT 1').getSingle(),
          isNotNull,
        );
      } finally {
        await observations.disposeAsync();
        await sync.disposeAsync();
        await notes.disposeAsync();
        await orders.disposeAsync();
        teardown.add('objectbox-database');
        await objectBoxOwner.disposeAsync();
        teardown.add('drift-database');
        await driftOwner.disposeAsync();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      }

      expect(teardown, <String>[
        'observations',
        'sync',
        'objectbox-repository',
        'drift-repository',
        'objectbox-database',
        'drift-database',
      ]);
    },
  );
}

final class _FixtureSyncFailure implements Exception {
  const _FixtureSyncFailure();
}

final class _ObjectBoxNotesRepository implements AsyncDisposable {
  _ObjectBoxNotesRepository(this._store, this._teardown);

  final Store _store;
  final List<String> _teardown;

  void save(String value) {
    _store.box<FixtureEntity>().put(FixtureEntity(value: value));
  }

  List<String> values() => _store
      .box<FixtureEntity>()
      .getAll()
      .map((entity) => entity.value)
      .toList(growable: false);

  @override
  Future<void> disposeAsync() async => _teardown.add('objectbox-repository');
}

final class _DriftOrdersRepository implements AsyncDisposable {
  _DriftOrdersRepository(this._database, this._teardown);

  final CoexistenceDriftDatabase _database;
  final List<String> _teardown;

  Future<void> save(String id) =>
      DriftMutationTransaction<CoexistenceDriftDatabase>(_database)
          .run<void, _FixtureSyncFailure>((database) async {
            await database
                .into(database.driftFixtureOrders)
                .insert(
                  DriftFixtureOrdersCompanion.insert(
                    id: id,
                    description: 'drift-only',
                  ),
                );
            await database
                .into(database.driftFixtureOutbox)
                .insert(
                  DriftFixtureOutboxCompanion.insert(payload: 'order:$id'),
                );
            return const Ok<void>(null);
          })
          .then((_) {});

  Future<List<String>> values() async =>
      (await _database.select(_database.driftFixtureOrders).get())
          .map((row) => row.id)
          .toList(growable: false);

  @override
  Future<void> disposeAsync() async => _teardown.add('drift-repository');
}

final class _FixtureObservationOwner implements AsyncDisposable {
  _FixtureObservationOwner(this._teardown);

  final List<String> _teardown;

  @override
  Future<void> disposeAsync() async => _teardown.add('observations');
}

final class _FixtureSyncOwner implements AsyncDisposable {
  _FixtureSyncOwner(this._teardown);

  final List<String> _teardown;

  @override
  Future<void> disposeAsync() async => _teardown.add('sync');
}

Future<void> _waitFor(
  List<String>? Function() read,
  List<String> expected,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (read().toString() == expected.toString()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('ObjectBox query did not publish $expected; last value: ${read()}');
}

Future<void> _readFromReference((SendPort, ByteData) message) async {
  final store = Store.fromReference(getObjectBoxModel(), message.$2);
  try {
    message.$1.send(store.box<FixtureEntity>().count());
  } finally {
    store.close();
  }
}

Future<List<String>> _projectFixtureValues(Store store, String prefix) async {
  if (prefix == 'slow:') {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  final query = store.box<FixtureEntity>().query().build();
  try {
    return query
        .find()
        .map((entity) => '$prefix${entity.value}')
        .toList(growable: false);
  } finally {
    query.close();
  }
}

final class _WatcherHandle {
  late final StreamSubscription<Query<FixtureEntity>> subscription;
  Query<FixtureEntity>? query;

  Future<void> dispose() async {
    await subscription.cancel();
    query?.close();
  }
}

final class _RecordingTracer extends Tracer {
  final spans = <_RecordingSpan>[];

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    final span = _RecordingSpan(
      TraceContext(
        traceId: '0123456789abcdef0123456789abcdef',
        spanId: spans.isEmpty ? '0123456789abcdef' : 'fedcba9876543210',
      ),
    );
    spans.add(span);
    return span;
  }
}

final class _RecordingSpan extends Span {
  _RecordingSpan(this.context);

  @override
  final TraceContext context;

  int endCalls = 0;
  SpanStatus? status;

  @override
  bool get isEnded => endCalls > 0;

  @override
  void addEvent(String name, {Map<String, Object?> attributes = const {}}) {}

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (isEnded) return;
    endCalls += 1;
    this.status = status;
  }
}
