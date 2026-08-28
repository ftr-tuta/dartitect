import 'package:dartitect/dartitect.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';

import 'ports.dart';

/// Current provider-neutral headless command protocol version.
const int currentSyncCommandProtocolVersion = 1;

/// Transferable command metadata plus consumer-validated payload.
final class SyncCommandEnvelope<P> {
  /// Creates a command envelope.
  SyncCommandEnvelope({
    this.protocolVersion = currentSyncCommandProtocolVersion,
    required this.requestId,
    required this.deadline,
    required this.payload,
  }) {
    if (protocolVersion <= 0) {
      throw ArgumentError.value(protocolVersion, 'protocolVersion');
    }
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'must not be empty');
    }
  }

  /// Version negotiated before provider work starts.
  final int protocolVersion;

  /// Consumer-safe idempotency identifier for delivery/ACK deduplication.
  final String requestId;

  /// UTC command deadline.
  final DateTime deadline;

  /// Consumer-defined, validated transferable payload; never live resources.
  final P payload;
}

/// Stable rejection reason before work starts.
enum SyncCommandRejection {
  /// Endpoint does not support the envelope version.
  unsupportedProtocol,

  /// Deadline elapsed before admission.
  deadlineExceeded,

  /// Consumer payload validation failed.
  invalidPayload,

  /// Endpoint is shutting down or not ready.
  notReady,
}

/// Acceptance or terminal acknowledgement for one command request.
sealed class SyncCommandAck<R, F extends Object> {
  const SyncCommandAck(this.requestId);

  /// Request identifier copied from the envelope.
  final String requestId;
}

/// Command was accepted and a terminal ACK will follow.
final class SyncCommandAccepted<R, F extends Object>
    extends SyncCommandAck<R, F> {
  /// Creates an acceptance ACK.
  const SyncCommandAccepted(super.requestId);
}

/// Command was rejected before building a graph.
final class SyncCommandRejected<R, F extends Object>
    extends SyncCommandAck<R, F> {
  /// Creates a rejection ACK.
  const SyncCommandRejected(super.requestId, this.reason);

  /// Closed rejection reason.
  final SyncCommandRejection reason;
}

/// Command completed successfully.
final class SyncCommandCompleted<R, F extends Object>
    extends SyncCommandAck<R, F> {
  /// Creates a successful terminal ACK.
  const SyncCommandCompleted(super.requestId, this.result);

  /// Consumer-defined terminal result.
  final R result;
}

/// Command completed with an expected typed failure.
final class SyncCommandFailed<R, F extends Object>
    extends SyncCommandAck<R, F> {
  /// Creates an expected-failure terminal ACK.
  const SyncCommandFailed(super.requestId, this.failure, this.stackTrace);

  /// Expected failure.
  final F failure;

  /// Stack captured at the failure boundary.
  final StackTrace stackTrace;
}

/// Accepted command and its deduplicated terminal acknowledgement.
final class SyncCommandReceipt<R, F extends Object> {
  /// Creates a receipt.
  const SyncCommandReceipt({required this.ack, required this.terminal});

  /// Immediate acceptance or rejection ACK.
  final SyncCommandAck<R, F> ack;

  /// Terminal ACK; equals [ack] when rejected.
  final Future<SyncCommandAck<R, F>> terminal;
}

/// Isolate-local handler built inside an owned graph.
abstract interface class HeadlessSyncHandler<P, R, F extends Object> {
  /// Executes one validated command. Expected failures use [Err].
  Future<Result<R, F>> execute(P payload, CancellationSignal cancellation);
}

/// Provider-neutral headless endpoint with fresh-graph and duplicate handling.
final class HeadlessSyncEndpoint<P, R, F extends Object>
    implements AsyncDisposable {
  /// Creates a ready endpoint after handlers/factories are installed.
  HeadlessSyncEndpoint({
    required Future<OwnedGraph<HeadlessSyncHandler<P, R, F>>> Function(
      P payload,
    )
    createGraph,
    bool Function(P payload)? validatePayload,
    SyncClock clock = const SystemSyncClock(),
    this.maxRememberedRequests = 128,
  }) {
    if (maxRememberedRequests <= 0) {
      throw ArgumentError.value(maxRememberedRequests, 'maxRememberedRequests');
    }
    _dispatcher = JobDispatcher<P, R, F, Never>(
      definitions: <JobDefinition<P, R, F, Never>>[
        JobDefinition<P, R, F, Never>(
          name: _definitionName,
          validatePayload: validatePayload,
          createGraph: (payload) async {
            final syncGraph = await createGraph(payload);
            return ResourceTransaction.create((transaction) {
              transaction.own(
                syncGraph,
                (graph) => graph.disposeAsync(),
                label: 'headless-sync.graph',
              );
              return _HeadlessSyncJobHandler<P, R, F>(syncGraph);
            }, label: 'HeadlessSyncEndpoint.job');
          },
        ),
      ],
      maxConcurrent: maxRememberedRequests,
      maxRememberedJobs: maxRememberedRequests,
      clock: _SyncJobClock(clock),
    );
  }

  static const _definitionName = 'dartitect.sync.headless';

  late final JobDispatcher<P, R, F, Never> _dispatcher;

  /// Bound for active requests plus retained deduplicated completions.
  final int maxRememberedRequests;

  /// Whether the endpoint can accept new commands.
  bool get isReady => _dispatcher.isReady;

  /// Accepts or rejects a command without waiting for its terminal result.
  SyncCommandReceipt<R, F> accept(SyncCommandEnvelope<P> envelope) {
    final receipt = _dispatcher.accept(
      JobEnvelope<P>(
        protocolVersion: envelope.protocolVersion,
        jobId: envelope.requestId,
        definition: _definitionName,
        deadline: envelope.deadline.toUtc(),
        payload: envelope.payload,
      ),
    );
    return SyncCommandReceipt<R, F>(
      ack: _mapAck(receipt.ack),
      terminal: receipt.terminal.then(_mapAck),
    );
  }

  /// Accepts a command and waits for its terminal ACK.
  Future<SyncCommandAck<R, F>> handle(SyncCommandEnvelope<P> envelope) =>
      accept(envelope).terminal;

  SyncCommandAck<R, F> _mapAck(JobAck<R, F> ack) {
    return switch (ack) {
      JobAccepted<R, F>() => SyncCommandAccepted<R, F>(ack.jobId),
      JobRejected<R, F>(:final reason) => SyncCommandRejected<R, F>(
        ack.jobId,
        switch (reason) {
          JobRejection.unsupportedProtocol =>
            SyncCommandRejection.unsupportedProtocol,
          JobRejection.deadlineExceeded =>
            SyncCommandRejection.deadlineExceeded,
          JobRejection.invalidPayload => SyncCommandRejection.invalidPayload,
          JobRejection.unknownDefinition ||
          JobRejection.notReady ||
          JobRejection.atCapacity ||
          JobRejection.leaseUnavailable => SyncCommandRejection.notReady,
        },
      ),
      JobCompleted<R, F>(:final result) => SyncCommandCompleted<R, F>(
        ack.jobId,
        result,
      ),
      JobFailed<R, F>(:final failure, :final stackTrace) =>
        SyncCommandFailed<R, F>(ack.jobId, failure, stackTrace),
    };
  }

  /// Rejects new commands, cancels active handlers, and drains their graphs.
  @override
  Future<void> disposeAsync() => _dispatcher.disposeAsync();
}

final class _HeadlessSyncJobHandler<P, R, F extends Object>
    implements JobHandler<P, R, F, Never> {
  const _HeadlessSyncJobHandler(this.graph);

  final OwnedGraph<HeadlessSyncHandler<P, R, F>> graph;

  @override
  Future<Result<R, F>> execute(P payload, JobExecutionContext<Never> context) =>
      graph.use(
        (handler) => handler.execute(payload, context.command.cancellation),
      );
}

final class _SyncJobClock implements JobClock {
  const _SyncJobClock(this.clock);

  final SyncClock clock;

  @override
  DateTime now() => clock.now().toUtc();
}
