import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';
import 'package:test/test.dart';

void main() {
  test('dispatcher deduplicates and owns a fresh graph per job', () async {
    var graphCount = 0;
    var disposeCount = 0;
    final progress = BoundedProgressReporter<int>();
    final dispatcher = JobDispatcher<int, int, _Failure, int>(
      definitions: <JobDefinition<int, int, _Failure, int>>[
        JobDefinition<int, int, _Failure, int>(
          name: 'double',
          validatePayload: (payload) => payload >= 0,
          createGraph: (_) {
            graphCount += 1;
            return ResourceTransaction.create((transaction) {
              final handler = _Handler();
              transaction.own(handler, (_) => disposeCount += 1);
              return handler;
            });
          },
        ),
      ],
      progressReporter: (_) => progress,
    );
    final envelope = JobEnvelope<int>(
      jobId: 'job-1',
      definition: 'double',
      deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      payload: 4,
    );

    final first = dispatcher.accept(envelope);
    final duplicate = dispatcher.accept(envelope);
    expect(first.ack, isA<JobAccepted<int, _Failure>>());
    expect(await first.terminal, isA<JobCompleted<int, _Failure>>());
    expect(await duplicate.terminal, isA<JobCompleted<int, _Failure>>());
    expect(graphCount, 1);
    expect(disposeCount, 1);
    expect(progress.events.single.payload, 4);
    await dispatcher.disposeAsync();
  });

  test('dispatcher bounds concurrency without evicting active work', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final dispatcher = JobDispatcher<int, int, _Failure, void>(
      maxConcurrent: 1,
      definitions: <JobDefinition<int, int, _Failure, void>>[
        JobDefinition<int, int, _Failure, void>(
          name: 'blocked',
          createGraph: (_) => ResourceTransaction.create((transaction) {
            final handler = _BlockingHandler(entered, release);
            transaction.own(handler, (_) {});
            return handler;
          }),
        ),
      ],
    );
    JobEnvelope<int> envelope(String id) => JobEnvelope<int>(
      jobId: id,
      definition: 'blocked',
      deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      payload: 1,
    );

    final first = dispatcher.accept(envelope('first'));
    await entered.future;
    final duplicate = dispatcher.accept(envelope('first'));
    final rejected = dispatcher.accept(envelope('second'));
    expect(duplicate.ack, isA<JobAccepted<int, _Failure>>());
    expect(
      (rejected.ack as JobRejected<int, _Failure>).reason,
      JobRejection.atCapacity,
    );
    release.complete();
    await first.terminal;
    await duplicate.terminal;
    await dispatcher.disposeAsync();
  });

  test('lease fencing and persisted terminal receipt are reused', () async {
    final store = _Store();
    final leasePort = _LeasePort();
    int? observedFence;
    final dispatcher = JobDispatcher<int, int, _Failure, void>(
      definitions: <JobDefinition<int, int, _Failure, void>>[
        JobDefinition<int, int, _Failure, void>(
          name: 'fenced',
          createGraph: (_) => ResourceTransaction.create((_) {
            return _CallbackHandler((payload, context) async {
              observedFence = context.fencingToken;
              return Ok<int>(payload);
            });
          }),
        ),
      ],
      receiptStore: store,
      leasePort: leasePort,
    );
    final envelope = JobEnvelope<int>(
      jobId: 'stored',
      definition: 'fenced',
      deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      payload: 7,
    );
    expect(
      await dispatcher.handle(envelope),
      isA<JobCompleted<int, _Failure>>(),
    );
    expect(observedFence, 11);
    expect(store.writes, 1);
    expect(leasePort.lease.disposed, isTrue);
    await dispatcher.disposeAsync();

    final second = JobDispatcher<int, int, _Failure, void>(
      definitions: <JobDefinition<int, int, _Failure, void>>[
        JobDefinition<int, int, _Failure, void>(
          name: 'fenced',
          createGraph: (_) => throw StateError('must not build'),
        ),
      ],
      receiptStore: store,
    );
    expect(await second.handle(envelope), isA<JobCompleted<int, _Failure>>());
    await second.disposeAsync();
  });

  test('deadline cancellation drains the job graph', () async {
    var disposed = false;
    final dispatcher = JobDispatcher<int, int, _Failure, void>(
      definitions: <JobDefinition<int, int, _Failure, void>>[
        JobDefinition<int, int, _Failure, void>(
          name: 'wait',
          createGraph: (_) => ResourceTransaction.create((transaction) {
            final handler = _CancellationHandler();
            transaction.own(handler, (_) => disposed = true);
            return handler;
          }),
        ),
      ],
    );
    final terminal = dispatcher.handle(
      JobEnvelope<int>(
        jobId: 'deadline',
        definition: 'wait',
        deadline: DateTime.now().toUtc().add(const Duration(milliseconds: 10)),
        payload: 1,
      ),
    );
    await expectLater(terminal, throwsA(isA<CancellationException>()));
    expect(disposed, isTrue);
    await dispatcher.disposeAsync();
  });
}

final class _Failure implements Exception {}

final class _Handler implements JobHandler<int, int, _Failure, int> {
  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    JobExecutionContext<int> context,
  ) async {
    context.command.publish(payload);
    return Ok<int>(payload * 2);
  }
}

final class _BlockingHandler implements JobHandler<int, int, _Failure, void> {
  const _BlockingHandler(this.entered, this.release);

  final Completer<void> entered;
  final Completer<void> release;

  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    JobExecutionContext<void> context,
  ) async {
    entered.complete();
    await release.future;
    return Ok<int>(payload);
  }
}

final class _CallbackHandler implements JobHandler<int, int, _Failure, void> {
  const _CallbackHandler(this.callback);

  final Future<Result<int, _Failure>> Function(
    int payload,
    JobExecutionContext<void> context,
  )
  callback;

  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    JobExecutionContext<void> context,
  ) => callback(payload, context);
}

final class _CancellationHandler
    implements JobHandler<int, int, _Failure, void> {
  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    JobExecutionContext<void> context,
  ) async {
    await context.command.cancellation.whenCancelled;
    context.command.cancellation.throwIfCancelled();
    return Ok<int>(payload);
  }
}

final class _Store implements JobReceiptStore<int, _Failure> {
  JobAck<int, _Failure>? value;
  var writes = 0;

  @override
  Future<JobAck<int, _Failure>?> read(String jobId) async => value;

  @override
  Future<void> write(JobAck<int, _Failure> terminal) async {
    writes += 1;
    value = terminal;
  }
}

final class _LeasePort implements JobLeasePort {
  final _Lease lease = _Lease();

  @override
  Future<JobLease?> acquire(String jobId, DateTime deadline) async => lease;
}

final class _Lease implements JobLease {
  var disposed = false;

  @override
  int get fencingToken => 11;

  @override
  Future<void> disposeAsync() async => disposed = true;
}
