import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test('DisposalProbe records calls and shared order', () async {
    final order = <String>[];
    final first = DisposalProbe(label: 'first', order: order);
    final second = DisposalProbe(label: 'second', order: order);

    first.dispose();
    await second.disposeAsync();

    expect(order, <String>['first:dispose', 'second:disposeAsync']);
    expect(first.disposeCalls, 1);
    expect(second.disposeAsyncCalls, 1);
  });

  test('ManualClock advances without global overrides', () {
    final clock = ManualClock(DateTime.utc(2026, 8, 22));
    final injectedNow = clock.now;
    clock.advance(const Duration(hours: 3));

    expect(injectedNow(), DateTime.utc(2026, 8, 22, 3));
    expect(
      () => clock.advance(const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });

  test('ManualScheduler and census finish with zero residuals', () async {
    final scheduler = ManualScheduler();
    final delayed = scheduler.wait(const Duration(seconds: 2));
    final census = ResourceCensus();
    final timer = census.acquire('timer');

    scheduler.advance(const Duration(seconds: 2));
    await delayed;
    timer.dispose();

    expect(scheduler.pendingCount, 0);
    expect(census.total, 0);
    expect(census.verifyZero, returnsNormally);
  });

  test('FakeArchitectureObserver filters captured events', () {
    final observer = FakeArchitectureObserver();
    observer.onEvent(
      const ArchitectureEvent(
        ArchitectureEventKind.resourceAcquired,
        source: 'test',
      ),
    );

    expect(
      observer.whereKind(ArchitectureEventKind.resourceAcquired),
      hasLength(1),
    );
  });

  test('Command harness records notifications and always disposes', () async {
    final listeners = <void Function()>[];
    var disposed = false;
    final harness = CommandContractHarness<int>(
      execute: () async {
        for (final listener in List<void Function()>.of(listeners)) {
          listener();
        }
        return 7;
      },
      addListener: listeners.add,
      removeListener: listeners.remove,
      dispose: () => disposed = true,
    );

    final run = await harness.run();

    expect(run.outcome, 7);
    expect(run.notificationCount, 1);
    expect(run.disposeAttempted, isTrue);
    expect(disposed, isTrue);
    expect(listeners, isEmpty);
  });

  test('LifecycleHarness attempts disposal after start failure', () async {
    final probe = DisposalProbe();
    final harness = LifecycleHarness<DisposalProbe>(
      create: () => probe,
      start: (_) => throw StateError('start'),
      dispose: (value) => value.disposeAsync(),
    );

    final run = await harness.run<void>((_) {});

    expect(run.failure?.phase, 'start');
    expect(run.disposeAttempted, isTrue);
    expect(probe.disposeAsyncCalls, 1);
  });

  test('repository harness continues after a failing case', () async {
    final harness = RepositoryContractHarness<List<int>>(
      create: () => <int>[],
      cases: <RepositoryContractCase<List<int>>>[
        RepositoryContractCase<List<int>>('empty', (repository) {
          if (repository.isNotEmpty) throw StateError('not empty');
        }),
        RepositoryContractCase<List<int>>(
          'failure',
          (_) => throw StateError('expected'),
        ),
      ],
    );

    final results = await harness.run();
    expect(results.map((result) => result.succeeded), <bool>[true, false]);
  });

  test(
    'effect harness records FIFO, second consumer, and post-dispose',
    () async {
      final fake = _EffectFake(capacity: 2);
      final harness = EffectContractHarness<int, String>(
        emit: fake.emit,
        listen: fake.listen,
        dispose: fake.dispose,
      );

      final result = await harness.run(
        beforeListener: const <int>[1, 2],
        postDisposeEffect: 3,
      );

      expect(result.publishResults, <String>['accepted', 'accepted']);
      expect(result.delivered, <int>[1, 2]);
      expect(result.secondConsumerRejected, isTrue);
      expect(result.postDisposeResult, 'disposed');
    },
  );

  test('effect harness disposes after a scheduler failure', () async {
    final fake = _EffectFake(capacity: 1);
    final harness = EffectContractHarness<int, String>(
      emit: fake.emit,
      listen: fake.listen,
      dispose: fake.dispose,
      drain: () => throw StateError('scheduler failed'),
    );

    await expectLater(
      harness.run(beforeListener: const <int>[1], postDisposeEffect: 2),
      throwsA(isA<StateError>()),
    );
    expect(fake.isDisposed, isTrue);
  });

  for (final kind in OwnedScopeKind.values) {
    test('owned ${kind.name} harness drains to zero', () async {
      final timeline = <String>[];
      final harness = OwnedScopeHarness<String>(
        kind: kind,
        create: (transaction) {
          transaction.own<int>(1, (value) => timeline.add('close:$value'));
          return kind.name;
        },
      );

      final result = await harness.run((root) => root.length);

      expect(result.value, kind.name.length);
      expect(result.error, isNull);
      expect(result.activeOperationsAfterDispose, 0);
      expect(result.disposed, isTrue);
      expect(timeline, <String>['close:1']);
    });
  }

  test('stream helper collects count and cancels', () async {
    final controller = StreamController<int>();
    final pending = collectStreamEvents<int>(
      controller.stream,
      count: 2,
      timeout: const Duration(seconds: 1),
    );
    controller
      ..add(1)
      ..add(2);

    expect(await pending, <int>[1, 2]);
    await controller.close();
  });

  test(
    'recording observability fakes expose events and exact ownership',
    () async {
      final sink = RecordingLogSink();
      final reporter = RecordingErrorReporter();
      final tracer = RecordingTracer();
      final runtime = ObservabilityRuntime(
        logSinks: <LogSinkRegistration>[LogSinkRegistration.owned(sink)],
        errorReporter: reporter,
        ownsErrorReporter: true,
        tracer: tracer,
        ownsTracer: true,
        samplingPolicy: FixedSamplingPolicy(spanRate: 1),
      );

      runtime.logger.info('hello');
      runtime.reporter.report(
        ErrorEvent(
          timestamp: DateTime.utc(2026),
          error: StateError('boom'),
          stackTrace: StackTrace.current,
        ),
      );
      final span = runtime.tracing.startSpan('work');
      await span.end(status: SpanStatus.ok);
      await runtime.disposeAsync();

      expect(sink.events, hasLength(1));
      expect(reporter.events, hasLength(1));
      expect(tracer.spans.single.endCalls, 1);
      expect(sink.disposeCalls, 1);
      expect(reporter.disposeCalls, 1);
      expect(tracer.disposeCalls, 1);
    },
  );

  test('OwnedGraphHarness detects rollback order and zero residuals', () async {
    final result = await OwnedGraphHarness(resourceCount: 3).run(failAfter: 2);

    expect(result.error, isA<StateError>());
    expect(result.liveResourceCount, 0);
    expect(result.timeline, <String>[
      'acquire:1',
      'acquire:2',
      'release:2',
      'release:1',
    ]);
  });

  test(
    'sync fakes model checkpoint crash, restart, lease, and cleanup',
    () async {
      final clock = ManualClock(DateTime.utc(2026, 8, 24));
      final checkpoints = InMemorySyncCheckpointStore<String, int>();
      final crashing = CheckpointCrashHarness<String, int>(checkpoints)
        ..arm(CheckpointFaultPoint.write);
      final leases = ManualSyncLeaseStore(clock);
      final engine = SyncEngine<String, int, _SyncFailure>(
        datasets: <SyncDataset<String, int, _SyncFailure>>[
          SyncDataset<String, int, _SyncFailure>(
            key: 'notes',
            synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(1),
            ),
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: crashing,
        leases: leases,
        clock: clock,
        ids: SequenceSyncIdGenerator(),
      );

      final result = await SyncContractHarness<String, int, _SyncFailure>(
        engine,
      ).run();

      expect(
        result.error,
        isA<SyncRunTerminalException<String, int, _SyncFailure>>(),
      );
      expect(
        (result.error! as SyncRunTerminalException<String, int, _SyncFailure>)
            .cause,
        isA<StateError>(),
      );
      expect(result.activeRunsAfterDispose, 0);
      expect(checkpoints.values, isEmpty);
      expect(leases.liveLeaseCount, 0);
    },
  );

  test(
    'journal and real isolate harness preserve facts and teardown',
    () async {
      final journal = InMemorySyncRunJournal<String>();
      await journal.append(
        SyncJournalEntry<String>(
          attemptId: 'test',
          sequence: 1,
          timestamp: DateTime.utc(2026),
          fact: SyncJournalFact.attemptStarted,
        ),
      );
      final worker = await IsolateWorkerContractHarness<int, int, _SyncFailure>(
        _double,
      ).run(2);

      expect(journal.entries, hasLength(1));
      expect(worker.result, const Ok<int>(4));
      expect(worker.acknowledged, isTrue);
      expect(worker.activeRequestsAfterStop, 0);
      expect(worker.disposed, isTrue);
    },
    onPlatform: <String, dynamic>{
      'browser': const Skip('Real isolates are VM-only.'),
    },
  );

  test('matrix auditor detects row-order and invalid-cell mutations', () {
    final valid = TestingMatrix(
      columns: const <String>['owner', 'cleanup'],
      rows: <TestingMatrixRow>[
        TestingMatrixRow(name: 'graph', cells: const <String>['root', 'LIFO']),
        TestingMatrixRow(
          name: 'worker',
          cells: const <String>['caller', 'stop'],
        ),
      ],
    );
    final reordered = TestingMatrix(
      columns: const <String>['seam'],
      rows: <TestingMatrixRow>[
        TestingMatrixRow(name: 'worker', cells: const <String>['real isolate']),
        TestingMatrixRow(name: 'graph', cells: const <String>['fault point']),
      ],
    );
    final invalid = TestingMatrix(
      columns: const <String>['seam'],
      rows: <TestingMatrixRow>[
        TestingMatrixRow(name: 'graph', cells: const <String>['']),
        TestingMatrixRow(name: 'worker', cells: const <String>['real isolate']),
      ],
    );

    expect(TestingMatrixAuditor().audit(valid, valid), isEmpty);
    expect(
      TestingMatrixAuditor().audit(valid, reordered),
      contains(contains('Row 0 differs')),
    );
    expect(
      TestingMatrixAuditor().audit(valid, invalid),
      contains(contains('empty cell')),
    );
  });
}

Future<Result<int, _SyncFailure>> _double(
  int value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value * 2);
}

final class _SyncFailure implements Exception {
  const _SyncFailure();
}

final class _EffectFake {
  _EffectFake({required this.capacity});

  final int capacity;
  final List<int> _pending = <int>[];
  FutureOr<void> Function(int)? _consumer;
  var _disposed = false;

  bool get isDisposed => _disposed;

  String emit(int effect) {
    if (_disposed) return 'disposed';
    final consumer = _consumer;
    if (consumer != null) {
      unawaited(Future<void>.sync(() => consumer(effect)));
      return 'accepted';
    }
    if (_pending.length >= capacity) return 'full';
    _pending.add(effect);
    return 'accepted';
  }

  Disposable listen(FutureOr<void> Function(int) consumer) {
    if (_disposed) throw StateError('Effect fake is disposed.');
    if (_consumer != null) throw StateError('Effect fake has one consumer.');
    _consumer = consumer;
    final pending = List<int>.of(_pending);
    _pending.clear();
    for (final effect in pending) {
      unawaited(Future<void>.sync(() => consumer(effect)));
    }
    return _EffectFakeSubscription(() {
      if (identical(_consumer, consumer)) _consumer = null;
    });
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _consumer = null;
  }
}

final class _EffectFakeSubscription implements Disposable {
  _EffectFakeSubscription(this._onDispose);

  final void Function() _onDispose;
  var _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose();
  }
}
