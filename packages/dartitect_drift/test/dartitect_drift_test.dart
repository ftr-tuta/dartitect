import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:drift/drift.dart' hide CancellationException, isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  group('DriftDatabaseOwner', () {
    test(
      'owned database closes exactly once under concurrent disposal',
      () async {
        final database = TestDatabase(NativeDatabase.memory());
        final owner = await DriftDatabaseOwner.create<TestDatabase>(
          openDatabase: () async => database,
          configure: (opened) async {
            await opened.customSelect('SELECT 1').getSingle();
          },
        );

        expect(owner.ownsDatabase, isTrue);
        expect(owner.database, same(database));
        await Future.wait(<Future<void>>[
          owner.disposeAsync(),
          owner.disposeAsync(),
          owner.disposeAsync(),
        ]);

        expect(database.closeCount, 1);
        expect(owner.isDisposed, isTrue);
        expect(() => owner.database, throwsStateError);
        await owner.disposeAsync();
        expect(database.closeCount, 1);
      },
    );

    test('borrowed database is guarded but remains open', () async {
      final database = TestDatabase(NativeDatabase.memory());
      final owner = DriftDatabaseOwner.value<TestDatabase>(database);

      expect(owner.ownsDatabase, isFalse);
      await owner.disposeAsync();

      expect(database.closeCount, 0);
      expect(() => owner.database, throwsStateError);
      expect(await database.customSelect('SELECT 1').getSingle(), isNotNull);
      await database.close();
    });

    test(
      'configure failure closes and preserves the primary failure',
      () async {
        final database = TestDatabase(
          NativeDatabase.memory(),
          closeFailure: const _CloseFailure(),
        );
        final primaryStack = StackTrace.current;

        await expectLater(
          () => DriftDatabaseOwner.create<TestDatabase>(
            openDatabase: () => database,
            configure: (_) => Error.throwWithStackTrace(
              const _ConfigureFailure(),
              primaryStack,
            ),
          ),
          throwsA(
            isA<_ConfigureFailure>().having(
              (_) => database.closeCount,
              'close count',
              1,
            ),
          ),
        );
      },
    );
  });

  group('DriftMutationTransaction', () {
    late TestDatabase database;
    late DriftMutationTransaction<TestDatabase> transaction;

    setUp(() {
      database = TestDatabase(NativeDatabase.memory());
      transaction = DriftMutationTransaction<TestDatabase>(database);
    });

    tearDown(() => database.close());

    test('commits domain and outbox atomically after awaited work', () async {
      final result = await transaction.run<String, _MutationFailure>((
        db,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await db
            .into(db.domainItems)
            .insert(DomainItemsCompanion.insert(id: 'one', value: 'domain'));
        await db
            .into(db.outboxEntries)
            .insert(OutboxEntriesCompanion.insert(payload: 'outbox'));
        return const Ok<String>('committed');
      });

      expect(result, const Ok<String>('committed'));
      expect(await database.select(database.domainItems).get(), hasLength(1));
      expect(await database.select(database.outboxEntries).get(), hasLength(1));
    });

    test('returns the same Err and rolls back every write', () async {
      final failure = _MutationFailure();
      final failureStack = StackTrace.current;
      final expected = Err<_MutationFailure>(failure, failureStack);

      final result = await transaction.run<void, _MutationFailure>((db) async {
        await db
            .into(db.domainItems)
            .insert(
              DomainItemsCompanion.insert(id: 'rollback', value: 'domain'),
            );
        await db
            .into(db.outboxEntries)
            .insert(OutboxEntriesCompanion.insert(payload: 'outbox'));
        return expected;
      });

      expect(identical(result, expected), isTrue);
      expect(await database.select(database.domainItems).get(), isEmpty);
      expect(await database.select(database.outboxEntries).get(), isEmpty);
    });

    test('unexpected exception rolls back with its original stack', () async {
      Object? caught;
      StackTrace? caughtStack;
      try {
        await transaction.run<void, _MutationFailure>((db) async {
          await db
              .into(db.domainItems)
              .insert(
                DomainItemsCompanion.insert(id: 'exception', value: 'domain'),
              );
          _throwMutation();
        });
      } catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, isA<_UnexpectedMutation>());
      expect(caughtStack.toString(), contains('_throwMutation'));
      expect(await database.select(database.domainItems).get(), isEmpty);
    });

    test('watch publishes after commit and never after rollback', () async {
      final emissions = <List<DomainItem>>[];
      final first = Completer<void>();
      final subscription = database
          .select(database.domainItems)
          .watch()
          .distinct(_sameDomainRows)
          .listen((rows) {
            emissions.add(rows);
            if (!first.isCompleted) first.complete();
          });
      await first.future;

      final releaseCommit = Completer<void>();
      final inserted = Completer<void>();
      final commit = transaction.run<void, _MutationFailure>((db) async {
        await db
            .into(db.domainItems)
            .insert(DomainItemsCompanion.insert(id: 'watch', value: 'domain'));
        inserted.complete();
        await releaseCommit.future;
        return const Ok<void>(null);
      });
      await inserted.future;
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
      releaseCommit.complete();
      await commit;
      await _waitFor(() => emissions.length == 2);
      expect(
        emissions.singleWhere((rows) => rows.isNotEmpty).single.id,
        'watch',
      );

      await transaction.run<void, _MutationFailure>((db) async {
        await db
            .into(db.domainItems)
            .insert(DomainItemsCompanion.insert(id: 'hidden', value: 'domain'));
        return Err<_MutationFailure>(_MutationFailure(), StackTrace.current);
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emissions, hasLength(2));
      await subscription.cancel();
    });
  });

  group('Drift sync adapters', () {
    late TestDatabase database;

    setUp(() => database = TestDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    DriftSyncCheckpointStore<String, String, TestDatabase> checkpoints() =>
        DriftSyncCheckpointStore<String, String, TestDatabase>(
          database: database,
          readCheckpoint: (db, key) async =>
              (await (db.select(
                    db.checkpointRows,
                  )..where((row) => row.key.equals(key))).getSingleOrNull())
                  ?.checkpoint,
          writeCheckpoint: (db, key, checkpoint, fencingToken) async {
            final current = await (db.select(
              db.checkpointRows,
            )..where((row) => row.key.equals(key))).getSingleOrNull();
            if (fencingToken != null &&
                current?.fencingToken != null &&
                fencingToken < current!.fencingToken!) {
              throw const _StaleFence();
            }
            await db
                .into(db.checkpointRows)
                .insertOnConflictUpdate(
                  CheckpointRowsCompanion.insert(
                    key: key,
                    checkpoint: checkpoint,
                    fencingToken: Value<int?>(fencingToken),
                  ),
                );
          },
          removeCheckpoint: (db, key) => (db.delete(
            db.checkpointRows,
          )..where((row) => row.key.equals(key))).go(),
        );

    test(
      'read, write, remove, cancellation, and stale fencing are atomic',
      () async {
        final store = checkpoints();
        final active = CancellationSource();
        await store.write('orders', 'v2', active.signal, fencingToken: 2);
        expect(await store.read('orders', active.signal), 'v2');

        await expectLater(
          store.write('orders', 'stale', active.signal, fencingToken: 1),
          throwsA(isA<_StaleFence>()),
        );
        expect(await store.read('orders', active.signal), 'v2');

        final cancelled = CancellationSource()..cancel('before');
        await expectLater(
          store.read('orders', cancelled.signal),
          throwsA(isA<CancellationException>()),
        );
        await expectLater(
          store.write('orders', 'cancelled', cancelled.signal),
          throwsA(isA<CancellationException>()),
        );
        await expectLater(
          store.remove('orders', cancelled.signal),
          throwsA(isA<CancellationException>()),
        );

        final cancelAfterRead = CancellationSource();
        final readStore =
            DriftSyncCheckpointStore<String, String, TestDatabase>(
              database: database,
              readCheckpoint: (db, key) async {
                final value = await (db.select(
                  db.checkpointRows,
                )..where((row) => row.key.equals(key))).getSingle();
                cancelAfterRead.cancel('after read');
                return value.checkpoint;
              },
              writeCheckpoint: checkpoints().writeCheckpoint,
              removeCheckpoint: checkpoints().removeCheckpoint,
            );
        await expectLater(
          readStore.read('orders', cancelAfterRead.signal),
          throwsA(isA<CancellationException>()),
        );

        final cancelAfterWrite = CancellationSource();
        final writeStore =
            DriftSyncCheckpointStore<String, String, TestDatabase>(
              database: database,
              readCheckpoint: checkpoints().readCheckpoint,
              writeCheckpoint: (db, key, checkpoint, fencingToken) async {
                await checkpoints().writeCheckpoint(
                  db,
                  key,
                  checkpoint,
                  fencingToken,
                );
                cancelAfterWrite.cancel('committed');
              },
              removeCheckpoint: checkpoints().removeCheckpoint,
            );
        await writeStore.write(
          'orders',
          'v3',
          cancelAfterWrite.signal,
          fencingToken: 3,
        );
        expect(await store.read('orders', CancellationSource().signal), 'v3');

        final cancelAfterRemove = CancellationSource();
        final removeStore =
            DriftSyncCheckpointStore<String, String, TestDatabase>(
              database: database,
              readCheckpoint: checkpoints().readCheckpoint,
              writeCheckpoint: checkpoints().writeCheckpoint,
              removeCheckpoint: (db, key) async {
                await checkpoints().removeCheckpoint(db, key);
                cancelAfterRemove.cancel('committed');
              },
            );
        await removeStore.remove('orders', cancelAfterRemove.signal);
        expect(await store.read('orders', active.signal), isNull);
      },
    );

    test('journal appends and returns immutable incomplete attempts', () async {
      final journal = DriftSyncRunJournal<String, TestDatabase>(
        database: database,
        appendEntry: (db, entry) => db
            .into(db.journalRows)
            .insert(
              JournalRowsCompanion.insert(
                attemptId: entry.attemptId,
                sequence: entry.sequence,
                timestamp: entry.timestamp,
                fact: entry.fact.index,
                datasetKey: Value<String?>(entry.datasetKey),
                hasDatasetKey: entry.hasDatasetKey,
              ),
            ),
        readIncompleteAttempts: (db) async {
          final rows = await db.select(db.journalRows).get();
          return <IncompleteSyncAttempt<String>>[
            IncompleteSyncAttempt<String>(
              attemptId: rows.single.attemptId,
              startedAt: rows.single.timestamp.toUtc(),
              completedDatasetKeys: const <String>[],
            ),
          ];
        },
      );
      final entry = SyncJournalEntry<String>(
        attemptId: 'attempt',
        sequence: 1,
        timestamp: DateTime.utc(2026),
        fact: SyncJournalFact.attemptStarted,
      );

      await journal.append(entry);
      final attempts = await journal.loadIncompleteAttempts();

      expect(attempts.single.attemptId, 'attempt');
      expect(() => attempts.add(attempts.single), throwsUnsupportedError);
      expect(
        () => attempts.single.completedDatasetKeys.add('orders'),
        throwsUnsupportedError,
      );
    });
  });

  test('instrumentation is fixed, sanitized, and failure-isolated', () async {
    final tracer = _RecordingTracer();
    final instrumentation = DriftInstrumentation(tracer: tracer);
    final database = TestDatabase(NativeDatabase.memory());
    final owner = await DriftDatabaseOwner.create<TestDatabase>(
      openDatabase: () => database,
      instrumentation: instrumentation,
    );
    final transaction = DriftMutationTransaction<TestDatabase>(
      owner.database,
      instrumentation: instrumentation,
    );
    await transaction.run<void, _MutationFailure>((_) async => const Ok(null));
    final checkpoints = DriftSyncCheckpointStore<String, int, TestDatabase>(
      database: owner.database,
      instrumentation: instrumentation,
      readCheckpoint: (_, _) => 1,
      writeCheckpoint: (_, _, _, _) {},
      removeCheckpoint: (_, _) {},
    );
    final signal = CancellationSource();
    await checkpoints.write('orders', 1, signal.signal);
    await checkpoints.read('orders', signal.signal);
    await checkpoints.remove('orders', signal.signal);
    signal.dispose();
    final journal = DriftSyncRunJournal<String, TestDatabase>(
      database: owner.database,
      instrumentation: instrumentation,
      appendEntry: (_, _) {},
      readIncompleteAttempts: (_) => const <IncompleteSyncAttempt<String>>[],
    );
    await journal.append(
      SyncJournalEntry<String>(
        attemptId: 'attempt',
        sequence: 1,
        timestamp: DateTime.utc(2026),
        fact: SyncJournalFact.attemptStarted,
      ),
    );
    await journal.loadIncompleteAttempts();
    await owner.disposeAsync();

    expect(tracer.names, <String>[
      'Drift database open',
      'Drift transaction',
      'Drift checkpoint write',
      'Drift checkpoint read',
      'Drift checkpoint remove',
      'Drift journal append',
      'Drift journal load',
      'Drift database close',
    ]);
    expect(tracer.attributes, everyElement(isEmpty));
    expect(tracer.ends, everyElement((error: null, stackTrace: null)));

    final failing = DriftInstrumentation(tracer: _ThrowingTracer());
    final value = await failing.trace(
      DriftInstrumentedOperation.checkpointRead,
      () => 42,
    );
    expect(value, 42);
    expect(failing.traceFailureCount, 1);

    final failingEnd = DriftInstrumentation(tracer: _EndThrowingTracer());
    expect(
      await failingEnd.trace(
        DriftInstrumentedOperation.checkpointWrite,
        () => 7,
      ),
      7,
    );
    expect(failingEnd.traceFailureCount, 1);
  });
}

Never _throwMutation() => throw const _UnexpectedMutation();

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Condition did not become true.');
}

bool _sameDomainRows(List<DomainItem> left, List<DomainItem> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _MutationFailure implements Exception {}

final class _UnexpectedMutation implements Exception {
  const _UnexpectedMutation();
}

final class _ConfigureFailure implements Exception {
  const _ConfigureFailure();
}

final class _CloseFailure implements Exception {
  const _CloseFailure();
}

final class _StaleFence implements Exception {
  const _StaleFence();
}

final class _RecordingTracer extends Tracer {
  final List<String> names = <String>[];
  final List<Map<String, Object?>> attributes = <Map<String, Object?>>[];
  final List<({Object? error, StackTrace? stackTrace})> ends =
      <({Object? error, StackTrace? stackTrace})>[];

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    names.add(name);
    this.attributes.add(attributes);
    return _RecordingSpan(ends);
  }
}

final class _RecordingSpan extends Span {
  _RecordingSpan(this.ends);

  final List<({Object? error, StackTrace? stackTrace})> ends;

  @override
  final TraceContext context = TraceContext(
    traceId: '00000000000000000000000000000001',
    spanId: '0000000000000001',
  );

  @override
  bool isEnded = false;

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
    isEnded = true;
    ends.add((error: error, stackTrace: stackTrace));
  }
}

final class _ThrowingTracer extends Tracer {
  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) => throw StateError('tracer unavailable');
}

final class _EndThrowingTracer extends Tracer {
  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) => _EndThrowingSpan();
}

final class _EndThrowingSpan extends Span {
  @override
  final TraceContext context = TraceContext(
    traceId: '00000000000000000000000000000002',
    spanId: '0000000000000002',
  );

  @override
  bool isEnded = false;

  @override
  void addEvent(String name, {Map<String, Object?> attributes = const {}}) {}

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) => throw StateError('span unavailable');
}
