import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:test/test.dart';

void main() {
  test(
    'atomic local enqueue precedes committed at-least-once delivery',
    () async {
      final store = _FakeStore();
      final command = MutationCommand<String, int, String, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) => 'op-$key',
        synchronize: (operation, signal) async {
          store.transcript.add(
            'deliver:${operation.idempotencyKey}:${operation.attempt}',
          );
          expect(store.local[operation.key], operation.argument);
          expect(store.operations, contains(operation.idempotencyKey));
          return const Ok<String>('remote-ok');
        },
      );

      final outcome = await command.execute(7, 'local-value');
      expect(
        outcome,
        isA<
          CommandSucceeded<
            MutationExecution<String, int, String, _Failure>,
            _Failure
          >
        >(),
      );
      final execution =
          (outcome
                  as CommandSucceeded<
                    MutationExecution<String, int, String, _Failure>,
                    _Failure
                  >)
              .value;
      expect(execution.disposition, CommitDisposition.committed);
      expect(execution.syncState, EntitySyncState.synced);
      expect(execution.remoteValue, 'remote-ok');
      expect(execution.hasRemoteValue, isTrue);
      expect(execution.operation.attempt, 1);
      expect(store.transcript, <String>[
        'apply:op-7',
        'mark:op-7:syncing:1',
        'deliver:op-7:1',
        'mark:op-7:synced:1',
      ]);

      await command.dispose();
    },
  );

  test('local atomic failure neither enqueues nor delivers', () async {
    final store = _FakeStore()..applyFailure = const _Failure('disk-full');
    var deliveries = 0;
    final command = MutationCommand<String, int, void, _Failure>(
      store: store,
      createIdempotencyKey: (key, argument) => 'atomic-failure',
      synchronize: (operation, signal) async {
        deliveries += 1;
        return const Ok<void>(null);
      },
    );

    final outcome = await command.execute(1, 'must-not-commit');

    expect(
      outcome,
      isA<
        CommandFailed<MutationExecution<String, int, void, _Failure>, _Failure>
      >(),
    );
    expect(store.local, isEmpty);
    expect(store.operations, isEmpty);
    expect(deliveries, 0);
    await command.dispose();
  });

  test(
    'manual offline failure queues without rollback or automatic retry',
    () async {
      final store = _FakeStore();
      var deliveries = 0;
      final command = MutationCommand<String, int, void, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) => 'offline-$key',
        synchronize: (operation, signal) async {
          deliveries += 1;
          return Err<_Failure>(const _Failure('offline'), StackTrace.current);
        },
      );

      final outcome = await command.execute(1, 'kept-local');
      final execution =
          (outcome
                  as CommandSucceeded<
                    MutationExecution<String, int, void, _Failure>,
                    _Failure
                  >)
              .value;

      expect(execution.disposition, CommitDisposition.queued);
      expect(execution.syncState, EntitySyncState.pending);
      expect(execution.syncFailure, const _Failure('offline'));
      expect(execution.syncFailureStackTrace, isNotNull);
      expect(store.local[1], 'kept-local');
      expect(store.operations['offline-1']?.syncState, EntitySyncState.pending);
      expect(deliveries, 1);
      await command.dispose();
    },
  );

  test(
    'transient retry is bounded exponential and keeps idempotency key',
    () async {
      final store = _FakeStore();
      final deliveries = <String>[];
      final delays = <Duration>[];
      final command = MutationCommand<String, int, String, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) => 'stable-id',
        classifyFailure: (_) => MutationFailurePolicy.queued(
          retry: RetryClassification.transient(
            maxAttempts: 3,
            initialDelay: const Duration(milliseconds: 10),
            multiplier: 2,
            maxDelay: const Duration(milliseconds: 20),
          ),
        ),
        waitBeforeRetry: (delay, signal) async {
          signal.throwIfCancelled();
          delays.add(delay);
        },
        synchronize: (operation, signal) async {
          deliveries.add('${operation.idempotencyKey}:${operation.attempt}');
          if (operation.attempt < 3) {
            return Err<_Failure>(
              const _Failure('temporary'),
              StackTrace.current,
            );
          }
          return const Ok<String>('done');
        },
      );

      final outcome = await command.execute(1, 'value');
      final execution =
          (outcome
                  as CommandSucceeded<
                    MutationExecution<String, int, String, _Failure>,
                    _Failure
                  >)
              .value;

      expect(execution.disposition, CommitDisposition.committed);
      expect(execution.operation.attempt, 3);
      expect(deliveries, <String>['stable-id:1', 'stable-id:2', 'stable-id:3']);
      expect(delays, const <Duration>[
        Duration(milliseconds: 10),
        Duration(milliseconds: 20),
      ]);
      await command.dispose();
    },
  );

  test('same key is sequential while another key may run', () async {
    final store = _FakeStore();
    final first = Completer<Result<String, _Failure>>();
    final second = Completer<Result<String, _Failure>>();
    final other = Completer<Result<String, _Failure>>();
    var sequence = 0;
    final command = MutationCommand<String, int, String, _Failure>(
      store: store,
      createIdempotencyKey: (key, argument) => 'op-${sequence++}',
      synchronize: (operation, signal) {
        return switch (operation.idempotencyKey) {
          'op-0' => first.future,
          'op-1' => second.future,
          _ => other.future,
        };
      },
    );

    final firstOutcome = command.execute(1, 'first');
    final secondOutcome = command.execute(1, 'second');
    final otherOutcome = command.execute(2, 'other');
    await _waitFor(() => store.applyCalls == 2);
    expect(store.local[1], 'first');
    expect(store.local[2], 'other');
    expect(command.runningCount, 2);
    expect(command.queuedCount, 1);

    other.complete(const Ok<String>('other-ok'));
    first.complete(const Ok<String>('first-ok'));
    await firstOutcome;
    await _waitFor(() => store.applyCalls == 3);
    expect(store.local[1], 'second');
    second.complete(const Ok<String>('second-ok'));
    await Future.wait(<Future<Object?>>[secondOutcome, otherOutcome]);
    expect(command.runningCount, 0);
    expect(command.queuedCount, 0);
    await command.dispose();
  });

  test(
    'crash marks uncertain, reports once, stops key, and needs audit resume',
    () async {
      final store = _FakeStore();
      final reports = <Object>[];
      final journal = ReactiveJournal(capacity: 4);
      var deliveries = 0;
      var crash = true;
      final command = MutationCommand<String, int, String, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) => 'crash-$key',
        reporter: _CrashReporter(reports.add),
        observer: ReactiveObserverRegistration.borrowed(journal),
        synchronize: (operation, signal) async {
          deliveries += 1;
          if (crash) throw StateError('transport invariant');
          return const Ok<String>('recovered');
        },
      );

      await expectLater(command.execute(1, 'local'), throwsStateError);
      expect(deliveries, 1);
      expect(reports, hasLength(1));
      expect(command.stoppedKeyCount, 1);
      expect(journal.entries.single.kind, ReactiveEventKind.crashed);
      final uncertain = store.operations['crash-1']!;
      expect(uncertain.syncState, EntitySyncState.uncertain);
      expect(store.local[1], 'local');

      final rejected = await command.execute(1, 'must-not-run');
      expect(
        rejected,
        isA<
          CommandRejected<
            MutationExecution<String, int, String, _Failure>,
            _Failure
          >
        >(),
      );
      expect(deliveries, 1);
      expect(() => command.retry(uncertain), throwsStateError);

      final audited = uncertain.withState(syncState: EntitySyncState.pending);
      final auditSource = CancellationSource();
      await store.markState(audited, auditSource.signal);
      auditSource.dispose();
      crash = false;
      command.resume(1);
      final recovered = await command.retry(audited);
      expect(
        recovered,
        isA<
          CommandSucceeded<
            MutationExecution<String, int, String, _Failure>,
            _Failure
          >
        >(),
      );
      expect(deliveries, 2);
      expect(store.operations['crash-1']?.syncState, EntitySyncState.synced);
      await command.dispose();
      journal.dispose();
    },
  );

  test(
    'restart deduplicates pending and preserves uncertain records',
    () async {
      final store = _FakeStore();
      final pending = OutboxOperation<int, String>(
        idempotencyKey: 'pending',
        key: 1,
        argument: 'one',
      );
      final duplicate = pending.withState(attempt: 2);
      final uncertain = OutboxOperation<int, String>(
        idempotencyKey: 'uncertain',
        key: 2,
        argument: 'two',
        syncState: EntitySyncState.uncertain,
      );
      store
        ..operations[pending.idempotencyKey] = pending
        ..operations[uncertain.idempotencyKey] = uncertain
        ..recoveryRows = <OutboxOperation<int, String>>[
          pending,
          duplicate,
          uncertain,
        ];
      final delivered = <String>[];
      final restarted = MutationCommand<String, int, void, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) => 'unused',
        synchronize: (operation, signal) async {
          delivered.add(operation.idempotencyKey);
          return const Ok<void>(null);
        },
      );

      final recovered = await restarted.recoverPending();
      expect(
        recovered,
        isA<
          Ok<
            List<
              CommandOutcome<
                MutationExecution<String, int, void, _Failure>,
                _Failure
              >
            >
          >
        >(),
      );
      expect(delivered, <String>['pending']);
      expect(restarted.recoveredOperationCount, 1);
      expect(
        store.applyCalls,
        0,
        reason: 'recovery never reapplies local data',
      );
      expect(store.operations['pending']?.syncState, EntitySyncState.synced);
      expect(
        store.operations['uncertain']?.syncState,
        EntitySyncState.uncertain,
      );
      await restarted.dispose();
    },
  );

  test('conflict and expected uncertain outcomes remain durable', () async {
    for (final scenario
        in <
          ({
            MutationFailurePolicy policy,
            CommitDisposition disposition,
            EntitySyncState state,
          })
        >[
          (
            policy: const MutationFailurePolicy.conflicted(),
            disposition: CommitDisposition.rejected,
            state: EntitySyncState.conflicted,
          ),
          (
            policy: const MutationFailurePolicy.uncertain(),
            disposition: CommitDisposition.uncertain,
            state: EntitySyncState.uncertain,
          ),
        ]) {
      final store = _FakeStore();
      final command = MutationCommand<String, int, void, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) => scenario.state.name,
        classifyFailure: (_) => scenario.policy,
        synchronize: (operation, signal) async => Err<_Failure>(
          const _Failure('remote-decision'),
          StackTrace.current,
        ),
      );

      final outcome = await command.execute(1, 'preserved-local');
      final execution =
          (outcome
                  as CommandSucceeded<
                    MutationExecution<String, int, void, _Failure>,
                    _Failure
                  >)
              .value;
      expect(execution.disposition, scenario.disposition);
      expect(execution.syncState, scenario.state);
      expect(store.local[1], 'preserved-local');
      expect(store.operations[scenario.state.name]?.syncState, scenario.state);
      await command.dispose();
    }
  });

  test(
    'emits payload-free mutation events and rejects dynamic cause',
    () async {
      final store = _FakeStore();
      final journal = ReactiveJournal(capacity: 4);
      final clock = _SequenceClock(<int>[10, 30]);
      final command = MutationCommand<String, int, void, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) =>
            'person@example.com-token=secret',
        synchronize: (operation, signal) async => const Ok<void>(null),
        observer: ReactiveObserverRegistration.borrowed(journal),
        monotonicMicroseconds: clock.now,
      );
      final dynamicCause = ChangeCause(
        <String>['mutation', 'execute'].join('.'),
        'Mutation execute',
      );

      expect(
        () => command.execute(
          1,
          'password=secret person@example.com',
          cause: dynamicCause,
        ),
        throwsArgumentError,
      );
      expect(store.applyCalls, 0);
      await command.execute(1, 'password=secret person@example.com');

      final event = journal.entries.single;
      expect(event.source, ReactiveEventSource.mutationCommand);
      expect(event.kind, ReactiveEventKind.updated);
      expect(event.cause, same(ChangeCauses.mutationExecute));
      expect(event.previousRevision, 0);
      expect(event.nextRevision, 1);
      expect(event.duration, const Duration(microseconds: 20));
      expect('$event', isNot(contains('secret')));
      expect('$event', isNot(contains('person@example.com')));
      await command.dispose();
      journal.dispose();
    },
  );

  test(
    'observer failure is reported once and never changes outcomes',
    () async {
      final store = _FakeStore();
      final reported = <Object>[];
      var observerCalls = 0;
      final command = MutationCommand<String, int, void, _Failure>(
        store: store,
        createIdempotencyKey: (key, argument) => 'isolated-$key',
        synchronize: (operation, signal) async => const Ok<void>(null),
        reporter: _CrashReporter(reported.add),
        observer: ReactiveObserverRegistration.borrowed(
          _ReactiveObserver((event) {
            observerCalls += 1;
            throw StateError('observer unavailable');
          }),
        ),
      );

      final first = await command.execute(1, 'first');
      final second = await command.execute(2, 'second');

      expect(first, isA<CommandSucceeded<Object?, _Failure>>());
      expect(second, isA<CommandSucceeded<Object?, _Failure>>());
      expect(store.local, <int, String>{1: 'first', 2: 'second'});
      expect(command.revision, 2);
      expect(observerCalls, 1);
      expect(command.observerFailureCount, 1);
      expect(reported, hasLength(1));
      await command.dispose();
    },
  );

  test('definitive reject compensates only through explicit call', () async {
    final store = _FakeStore();
    final command = MutationCommand<String, int, void, _Failure>(
      store: store,
      createIdempotencyKey: (key, argument) => 'reject-$key',
      classifyFailure: (_) => const MutationFailurePolicy.rejected(),
      synchronize: (operation, signal) async =>
          Err<_Failure>(const _Failure('invalid'), StackTrace.current),
    );

    final outcome = await command.execute(3, 'local-valid-until-compensated');
    final execution =
        (outcome
                as CommandSucceeded<
                  MutationExecution<String, int, void, _Failure>,
                  _Failure
                >)
            .value;
    expect(execution.disposition, CommitDisposition.rejected);
    expect(execution.syncState, EntitySyncState.rejected);
    expect(store.local[3], 'local-valid-until-compensated');
    expect(store.compensationCalls, 0);

    expect(await command.compensate(execution.operation), isA<Ok<void>>());
    expect(store.local, isNot(contains(3)));
    expect(store.operations, isNot(contains('reject-3')));
    expect(store.compensationCalls, 1);
    await command.dispose();
  });
}

final class _FakeStore implements MutationOutboxStore<int, String, _Failure> {
  final Map<int, String> local = <int, String>{};
  final Map<String, OutboxOperation<int, String>> operations =
      <String, OutboxOperation<int, String>>{};
  final List<String> transcript = <String>[];
  _Failure? applyFailure;
  List<OutboxOperation<int, String>>? recoveryRows;
  var applyCalls = 0;
  var compensationCalls = 0;

  @override
  Future<Result<void, _Failure>> applyLocalAndEnqueue(
    OutboxOperation<int, String> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    applyCalls += 1;
    final failure = applyFailure;
    if (failure != null) return Err<_Failure>(failure, StackTrace.current);
    local[operation.key] = operation.argument;
    operations[operation.idempotencyKey] = operation;
    transcript.add('apply:${operation.idempotencyKey}');
    return const Ok<void>(null);
  }

  @override
  Future<Result<void, _Failure>> markState(
    OutboxOperation<int, String> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    operations[operation.idempotencyKey] = operation;
    transcript.add(
      'mark:${operation.idempotencyKey}:${operation.syncState.name}:${operation.attempt}',
    );
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<OutboxOperation<int, String>>, _Failure>> loadRecoverable(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    return Ok<List<OutboxOperation<int, String>>>(
      List<OutboxOperation<int, String>>.of(recoveryRows ?? operations.values),
    );
  }

  @override
  Future<Result<void, _Failure>> compensate(
    OutboxOperation<int, String> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    compensationCalls += 1;
    local.remove(operation.key);
    operations.remove(operation.idempotencyKey);
    transcript.add('compensate:${operation.idempotencyKey}');
    return const Ok<void>(null);
  }
}

final class _Failure implements Exception {
  const _Failure(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is _Failure && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

final class _CrashReporter implements CommandCrashReporter {
  const _CrashReporter(this.callback);

  final void Function(Object error) callback;

  @override
  void report(Object error, StackTrace stackTrace) => callback(error);
}

final class _SequenceClock {
  _SequenceClock(this.values);

  final List<int> values;
  var _index = 0;

  int now() => values[_index++];
}

final class _ReactiveObserver implements ReactiveObserver {
  const _ReactiveObserver(this.callback);

  final void Function(ReactiveChangeEvent event) callback;

  @override
  void onChange(ReactiveChangeEvent event) => callback(event);
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not settle.');
}
