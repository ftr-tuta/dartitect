import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:test/test.dart';

void main() {
  test('graph validates edges and produces stable topological order', () {
    final graph = SyncDependencyGraph<String>(
      keys: const <String>['catalog', 'images', 'search'],
      dependencies: const <String, List<String>>{
        'search': <String>['catalog'],
      },
    );

    expect(graph.plan().order, <String>['catalog', 'images', 'search']);
    expect(
      () => SyncDependencyGraph<String>(
        keys: const <String>['a'],
        dependencies: const <String, List<String>>{
          'a': <String>['a'],
        },
      ),
      throwsA(isA<SyncDependencyGraphException<String>>()),
    );
    expect(
      () => SyncDependencyGraph<String>(
        keys: const <String>['a', 'b'],
        dependencies: const <String, List<String>>{
          'a': <String>['b'],
          'b': <String>['a'],
        },
      ),
      throwsA(isA<SyncDependencyGraphException<String>>()),
    );
  });

  test(
    'failure blocks dependents but preserves independent branches',
    () async {
      final calls = <String>[];
      final checkpoints = _MemoryCheckpoints<String, int>();
      final datasets = <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'catalog',
          synchronize: (_) async {
            calls.add('catalog');
            return Err<_Failure>(const _Failure(), StackTrace.current);
          },
        ),
        SyncDataset<String, int, _Failure>(
          key: 'images',
          synchronize: (_) async {
            calls.add('images');
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(2),
            );
          },
        ),
        SyncDataset<String, int, _Failure>(
          key: 'search',
          synchronize: (_) async {
            calls.add('search');
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
      ];
      final engine = SyncEngine<String, int, _Failure>(
        datasets: datasets,
        graph: SyncDependencyGraph<String>(
          keys: const <String>['catalog', 'images', 'search'],
          dependencies: const <String, List<String>>{
            'search': <String>['catalog'],
          },
        ),
        checkpoints: checkpoints,
      );

      final run = engine.start();
      final report = await run.done;

      expect(calls, <String>['catalog', 'images']);
      expect(
        report.datasets.map((dataset) => dataset.status),
        <SyncDatasetStatus>[
          SyncDatasetStatus.failed,
          SyncDatasetStatus.succeeded,
          SyncDatasetStatus.skipped,
        ],
      );
      expect(checkpoints.values['images'], 2);
      expect(run.progress.recent.last.phase, SyncProgressPhase.runCompleted);
      await engine.disposeAsync();
      expect(engine.activeRunCount, 0);
    },
  );

  test(
    'headless endpoint deduplicates and always disposes a fresh graph',
    () async {
      var graphCount = 0;
      var disposeCount = 0;
      final endpoint = HeadlessSyncEndpoint<int, int, _Failure>(
        createGraph: (payload) {
          graphCount += 1;
          return ResourceTransaction.create<
            HeadlessSyncHandler<int, int, _Failure>
          >((transaction) {
            transaction.own(
              _Handler(),
              (_) => disposeCount += 1,
              label: 'handler',
            );
            return _Handler();
          });
        },
        validatePayload: (payload) => payload >= 0,
      );
      final envelope = SyncCommandEnvelope<int>(
        requestId: 'request-1',
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        payload: 4,
      );

      final first = endpoint.accept(envelope);
      final duplicate = endpoint.accept(envelope);
      expect(first.ack, isA<SyncCommandAccepted<int, _Failure>>());
      expect(await first.terminal, isA<SyncCommandCompleted<int, _Failure>>());
      expect(
        await duplicate.terminal,
        isA<SyncCommandCompleted<int, _Failure>>(),
      );
      expect(graphCount, 1);
      expect(disposeCount, 1);

      final rejected = await endpoint.handle(
        SyncCommandEnvelope<int>(
          protocolVersion: 99,
          requestId: 'request-2',
          deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
          payload: 1,
        ),
      );
      expect(rejected, isA<SyncCommandRejected<int, _Failure>>());
      expect(graphCount, 1);
      await endpoint.disposeAsync();
    },
  );

  test(
    'headless dedup cache stays bounded without evicting active work',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var graphCount = 0;
      final endpoint = HeadlessSyncEndpoint<int, int, _Failure>(
        maxRememberedRequests: 1,
        createGraph: (_) {
          graphCount += 1;
          return ResourceTransaction.create((transaction) {
            final handler = _BlockingHandler(entered, release);
            transaction.own(handler, (_) {});
            return handler;
          });
        },
      );
      SyncCommandEnvelope<int> envelope(String id) => SyncCommandEnvelope<int>(
        requestId: id,
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        payload: 1,
      );

      final first = endpoint.accept(envelope('first'));
      await entered.future;
      final duplicate = endpoint.accept(envelope('first'));
      final atCapacity = endpoint.accept(envelope('second'));
      expect(duplicate.ack, isA<SyncCommandAccepted<int, _Failure>>());
      expect(atCapacity.ack, isA<SyncCommandRejected<int, _Failure>>());
      expect(
        (atCapacity.ack as SyncCommandRejected<int, _Failure>).reason,
        SyncCommandRejection.notReady,
      );
      expect(graphCount, 1);

      release.complete();
      await first.terminal;
      await duplicate.terminal;
      final afterCompletion = endpoint.accept(envelope('second'));
      expect(
        await afterCompletion.terminal,
        isA<SyncCommandCompleted<int, _Failure>>(),
      );
      expect(graphCount, 2);
      await endpoint.disposeAsync();
    },
  );

  test(
    'lease token fences checkpoints and progress history stays bounded',
    () async {
      final clock = _Clock(DateTime.utc(2026, 8, 24));
      final checkpoints = _MemoryCheckpoints<String, int>();
      final lease = _Lease(clock.now().add(const Duration(minutes: 2)), 7);
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>(
            key: 'notes',
            synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(3),
            ),
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: checkpoints,
        leases: _LeaseStore(lease),
        clock: clock,
        leaseTtl: const Duration(minutes: 1),
        maxRecentProgressEvents: 2,
      );

      final run = engine.start();
      final report = await run.done;

      expect(report.succeeded, isTrue);
      expect(checkpoints.fencingTokens, <int?>[7]);
      expect(lease.releaseCount, 1);
      expect(run.progress.recent, hasLength(2));
      expect(
        run.progress.recent.map((event) => event.sequence),
        orderedEquals(<int>[3, 4]),
      );
      await engine.disposeAsync();
    },
  );

  test('deadline and cooperative cancellation produce typed reports', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 24));
    var deadlineCalls = 0;
    final deadlineEngine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (_) async {
            deadlineCalls += 1;
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
      clock: clock,
    );
    final deadlineReport = await deadlineEngine
        .start(deadline: clock.now())
        .done;
    expect(deadlineCalls, 0);
    expect(
      deadlineReport.datasets.single.stopReason,
      SyncDatasetStopReason.deadlineExceeded,
    );
    await deadlineEngine.disposeAsync();

    final entered = Completer<void>();
    final cancellationEngine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (context) async {
            entered.complete();
            await context.cancellation.whenCancelled;
            context.cancellation.throwIfCancelled();
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
    );
    final cancelledRun = cancellationEngine.start();
    await entered.future;
    cancelledRun.cancel('test');
    final cancelledReport = await cancelledRun.done;
    expect(cancelledReport.cancelled, isTrue);
    expect(
      cancelledReport.datasets.single.stopReason,
      SyncDatasetStopReason.cancelled,
    );
    await cancellationEngine.disposeAsync();
  });

  test('unexpected dataset crash retains its original stack', () async {
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (_) => _crash(),
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
    );
    final run = engine.start();

    Object? caught;
    StackTrace? stack;
    try {
      await run.done;
    } catch (error, caughtStack) {
      caught = error;
      stack = caughtStack;
    }
    expect(caught, isA<StateError>());
    expect(stack.toString(), contains('_crash'));
    expect(run.progress.recent.last.phase, SyncProgressPhase.runCrashed);
    await engine.disposeAsync();
  });

  test(
    'journal records payload-free facts and resumes missing datasets',
    () async {
      final journal = _Journal<String>();
      final checkpoints = _MemoryCheckpoints<String, int>();
      final calls = <String>[];
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          for (final key in const <String>['catalog', 'images'])
            SyncDataset<String, int, _Failure>(
              key: key,
              synchronize: (_) async {
                calls.add(key);
                return const Ok<SyncDatasetOutcome<int>>(
                  SyncDatasetOutcome<int>.unchanged(),
                );
              },
            ),
        ],
        graph: SyncDependencyGraph<String>(
          keys: const <String>['catalog', 'images'],
        ),
        checkpoints: checkpoints,
        journal: journal,
        clock: _Clock(DateTime.utc(2026, 8, 24)),
      );

      await engine.start().done;

      expect(journal.entries.map((entry) => entry.fact), <SyncJournalFact>[
        SyncJournalFact.attemptStarted,
        SyncJournalFact.datasetStarted,
        SyncJournalFact.datasetSucceeded,
        SyncJournalFact.datasetStarted,
        SyncJournalFact.datasetSucceeded,
        SyncJournalFact.attemptCompleted,
      ]);
      expect(
        journal.entries.map((entry) => entry.sequence),
        orderedEquals(<int>[1, 2, 3, 4, 5, 6]),
      );
      journal.incomplete = <IncompleteSyncAttempt<String>>[
        IncompleteSyncAttempt<String>(
          attemptId: 'interrupted',
          startedAt: DateTime.utc(2026, 8, 23),
          completedDatasetKeys: const <String>['catalog'],
        ),
      ];

      final resumed = await engine.resumeIncomplete();
      expect(resumed, hasLength(1));
      await resumed.single.done;
      expect(calls, <String>['catalog', 'images', 'images']);
      await engine.disposeAsync();
    },
  );
}

Future<Result<SyncDatasetOutcome<int>, _Failure>> _crash() async {
  throw StateError('unexpected sync crash');
}

final class _Failure implements Exception {
  const _Failure();
}

final class _MemoryCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  final Map<K, C> values = <K, C>{};
  final List<int?> fencingTokens = <int?>[];

  @override
  Future<C?> read(K key, CancellationSignal signal) async => values[key];

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    fencingTokens.add(fencingToken);
    values[key] = checkpoint;
  }
}

final class _Clock implements SyncClock {
  _Clock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final class _Journal<K> implements SyncRunJournal<K> {
  final List<SyncJournalEntry<K>> entries = <SyncJournalEntry<K>>[];
  List<IncompleteSyncAttempt<K>> incomplete = <IncompleteSyncAttempt<K>>[];

  @override
  Future<void> append(SyncJournalEntry<K> entry) async {
    final previous = entries
        .where((candidate) => candidate.attemptId == entry.attemptId)
        .lastOrNull;
    if (previous != null && entry.sequence != previous.sequence + 1) {
      throw StateError('non-monotonic journal sequence');
    }
    entries.add(entry);
  }

  @override
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts() async =>
      List<IncompleteSyncAttempt<K>>.unmodifiable(incomplete);
}

final class _LeaseStore implements SyncLeaseStore {
  const _LeaseStore(this.lease);

  final SyncLease? lease;

  @override
  Future<SyncLease?> acquire({
    required String ownerId,
    required Duration ttl,
  }) async => lease;
}

final class _Lease implements SyncLease {
  _Lease(this.expiresAt, this.fencingToken);

  @override
  final int fencingToken;

  @override
  DateTime expiresAt;

  @override
  String get ownerId => 'lease-owner';

  int releaseCount = 0;

  @override
  Future<void> release() async => releaseCount += 1;

  @override
  Future<bool> renew(Duration ttl) async {
    expiresAt = expiresAt.add(ttl);
    return true;
  }
}

final class _Handler implements HeadlessSyncHandler<int, int, _Failure> {
  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    CancellationSignal cancellation,
  ) async => Ok<int>(payload * 2);
}

final class _BlockingHandler
    implements HeadlessSyncHandler<int, int, _Failure> {
  const _BlockingHandler(this.entered, this.release);

  final Completer<void> entered;
  final Completer<void> release;

  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    CancellationSignal cancellation,
  ) async {
    if (!entered.isCompleted) entered.complete();
    if (!release.isCompleted) await release.future;
    cancellation.throwIfCancelled();
    return Ok<int>(payload);
  }
}
