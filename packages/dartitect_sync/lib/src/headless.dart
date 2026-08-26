import 'dart:async';

import 'package:dartitect/dartitect.dart';

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
  }) : _createGraph = createGraph,
       _validatePayload = validatePayload ?? ((_) => true),
       _clock = clock {
    if (maxRememberedRequests <= 0) {
      throw ArgumentError.value(maxRememberedRequests, 'maxRememberedRequests');
    }
  }

  final Future<OwnedGraph<HeadlessSyncHandler<P, R, F>>> Function(P payload)
  _createGraph;
  final bool Function(P payload) _validatePayload;
  final SyncClock _clock;

  /// Bound for active requests plus retained deduplicated completions.
  final int maxRememberedRequests;

  final Map<String, Future<SyncCommandAck<R, F>>> _requests =
      <String, Future<SyncCommandAck<R, F>>>{};
  final Set<Future<SyncCommandAck<R, F>>> _inFlight =
      <Future<SyncCommandAck<R, F>>>{};
  final List<String> _completedRequestIds = <String>[];
  final Set<CancellationSource> _active = <CancellationSource>{};
  var _closing = false;

  /// Whether the endpoint can accept new commands.
  bool get isReady => !_closing;

  /// Accepts or rejects a command without waiting for its terminal result.
  SyncCommandReceipt<R, F> accept(SyncCommandEnvelope<P> envelope) {
    final rejection = _validate(envelope);
    if (rejection != null) {
      final ack = SyncCommandRejected<R, F>(envelope.requestId, rejection);
      return SyncCommandReceipt<R, F>(ack: ack, terminal: Future.value(ack));
    }
    final existing = _requests[envelope.requestId];
    if (existing != null) {
      return SyncCommandReceipt<R, F>(
        ack: SyncCommandAccepted<R, F>(envelope.requestId),
        terminal: existing,
      );
    }
    while (_requests.length >= maxRememberedRequests &&
        _completedRequestIds.isNotEmpty) {
      final evicted = _requests.remove(_completedRequestIds.removeAt(0));
      if (evicted != null) {
        unawaited(evicted.then<void>((_) {}, onError: (_, _) {}));
      }
    }
    if (_requests.length >= maxRememberedRequests) {
      final ack = SyncCommandRejected<R, F>(
        envelope.requestId,
        SyncCommandRejection.notReady,
      );
      return SyncCommandReceipt<R, F>(ack: ack, terminal: Future.value(ack));
    }
    final terminal = _execute(envelope);
    _requests[envelope.requestId] = terminal;
    _inFlight.add(terminal);
    unawaited(
      terminal.then<void>(
        (_) => _markCompleted(envelope.requestId, terminal),
        onError: (_, _) => _markCompleted(envelope.requestId, terminal),
      ),
    );
    return SyncCommandReceipt<R, F>(
      ack: SyncCommandAccepted<R, F>(envelope.requestId),
      terminal: terminal,
    );
  }

  void _markCompleted(String requestId, Future<SyncCommandAck<R, F>> terminal) {
    _inFlight.remove(terminal);
    _completedRequestIds.add(requestId);
  }

  /// Accepts a command and waits for its terminal ACK.
  Future<SyncCommandAck<R, F>> handle(SyncCommandEnvelope<P> envelope) =>
      accept(envelope).terminal;

  SyncCommandRejection? _validate(SyncCommandEnvelope<P> envelope) {
    if (_closing) return SyncCommandRejection.notReady;
    if (envelope.protocolVersion != currentSyncCommandProtocolVersion) {
      return SyncCommandRejection.unsupportedProtocol;
    }
    if (!_clock.now().isBefore(envelope.deadline.toUtc())) {
      return SyncCommandRejection.deadlineExceeded;
    }
    if (!_validatePayload(envelope.payload)) {
      return SyncCommandRejection.invalidPayload;
    }
    return null;
  }

  Future<SyncCommandAck<R, F>> _execute(SyncCommandEnvelope<P> envelope) async {
    final cancellation = CancellationSource();
    _active.add(cancellation);
    OwnedGraph<HeadlessSyncHandler<P, R, F>>? graph;
    Timer? deadlineTimer;
    try {
      final remaining = envelope.deadline.toUtc().difference(_clock.now());
      if (remaining <= Duration.zero) {
        return SyncCommandRejected<R, F>(
          envelope.requestId,
          SyncCommandRejection.deadlineExceeded,
        );
      }
      deadlineTimer = Timer(remaining, () => cancellation.cancel('deadline'));
      graph = await _createGraph(envelope.payload);
      final result = await graph.use(
        (handler) => handler.execute(envelope.payload, cancellation.signal),
      );
      return switch (result) {
        Ok<dynamic>(:final value) => SyncCommandCompleted<R, F>(
          envelope.requestId,
          value as R,
        ),
        Err<Object>(:final failure, :final stackTrace) =>
          SyncCommandFailed<R, F>(envelope.requestId, failure as F, stackTrace),
      };
    } finally {
      deadlineTimer?.cancel();
      await graph?.disposeAsync();
      cancellation.dispose();
      _active.remove(cancellation);
    }
  }

  /// Rejects new commands, cancels active handlers, and drains their graphs.
  @override
  Future<void> disposeAsync() async {
    if (_closing) return;
    _closing = true;
    for (final cancellation in _active.toList(growable: false)) {
      cancellation.cancel('HeadlessSyncEndpoint disposed');
    }
    await Future.wait<void>(
      _inFlight
          .toList(growable: false)
          .map((terminal) => terminal.then<void>((_) {}, onError: (_, _) {})),
    );
    _requests.clear();
    _inFlight.clear();
    _completedRequestIds.clear();
  }
}
