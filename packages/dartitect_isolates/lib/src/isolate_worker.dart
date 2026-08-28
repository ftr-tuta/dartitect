import 'dart:async';
import 'dart:isolate';

import 'package:dartitect/dartitect.dart';

/// Current stable worker protocol version.
const int currentIsolateWorkerProtocolVersion = 2;

/// Isolate-local request handler built by the receiving composition root.
typedef IsolateRequestHandler<P, R, F extends Object> =
    Future<Result<R, F>> Function(P payload, CancellationSignal cancellation);

/// A worker protocol, remote crash, exit, or heartbeat failure.
sealed class IsolateWorkerException implements Exception {
  const IsolateWorkerException(this.message);

  /// Sanitized description without request payload.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Worker did not become ready before its startup deadline.
final class IsolateReadinessException extends IsolateWorkerException {
  /// Creates a readiness failure.
  const IsolateReadinessException(super.message);
}

/// One request exceeded its explicit deadline.
final class IsolateRequestDeadlineException extends IsolateWorkerException {
  /// Creates a request deadline failure.
  const IsolateRequestDeadlineException(super.message);
}

/// The remote handler crashed unexpectedly.
final class RemoteIsolateCrash extends IsolateWorkerException {
  /// Creates a remote crash with its sanitized remote stack.
  const RemoteIsolateCrash(super.message, this.remoteStackTrace);

  /// Stack received as text from the worker.
  final StackTrace remoteStackTrace;
}

/// Worker exited without completing an active protocol operation.
final class IsolateUnexpectedExitException extends IsolateWorkerException {
  /// Creates an unexpected exit failure.
  const IsolateUnexpectedExitException(super.message);
}

/// Worker stopped emitting heartbeat facts.
final class IsolateHeartbeatException extends IsolateWorkerException {
  /// Creates a heartbeat failure.
  const IsolateHeartbeatException(super.message);
}

/// Immediate ACK plus terminal result for one request.
final class IsolateRequestReceipt<R, F extends Object> {
  /// Creates a correlated request receipt.
  const IsolateRequestReceipt({
    required this.requestId,
    required this.accepted,
    required this.result,
  });

  /// Supervisor-generated or consumer-supplied non-empty request ID.
  final String requestId;

  /// Completes when the matching worker ACK arrives.
  final Future<void> accepted;

  /// Completes with expected [Result] or an unexpected protocol/crash error.
  final Future<Result<R, F>> result;
}

/// Supervisor of one versioned, generation-scoped isolate endpoint.
final class IsolateWorker<P, R, F extends Object> implements AsyncDisposable {
  IsolateWorker._({
    required this.generation,
    required this.protocolVersion,
    required this.heartbeatTimeout,
    required IdGenerator ids,
    required DartitectDiagnosticSubject? diagnostics,
  }) : _ids = ids,
       _diagnostics = diagnostics;

  /// Spawns a fresh worker and waits for generation readiness.
  static Future<IsolateWorker<P, R, F>> spawn<P, R, F extends Object>({
    required IsolateRequestHandler<P, R, F> handler,
    int generation = 1,
    int protocolVersion = currentIsolateWorkerProtocolVersion,
    Duration readinessTimeout = const Duration(seconds: 10),
    Duration heartbeatInterval = const Duration(seconds: 1),
    Duration heartbeatTimeout = const Duration(seconds: 5),
    IdGenerator? ids,
    DartitectDiagnosticSubject? diagnostics,
  }) async {
    if (generation <= 0) {
      throw ArgumentError.value(generation, 'generation', 'must be positive');
    }
    if (protocolVersion != currentIsolateWorkerProtocolVersion) {
      throw ArgumentError.value(
        protocolVersion,
        'protocolVersion',
        'unsupported worker protocol',
      );
    }
    if (readinessTimeout <= Duration.zero ||
        heartbeatInterval <= Duration.zero ||
        heartbeatTimeout <= heartbeatInterval) {
      throw ArgumentError(
        'Readiness/heartbeat durations must be positive and the heartbeat '
        'timeout must exceed its interval.',
      );
    }
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.isolate) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'IsolateWorker requires an isolate diagnostic subject.',
      );
    }
    final worker = IsolateWorker<P, R, F>._(
      generation: generation,
      protocolVersion: protocolVersion,
      heartbeatTimeout: heartbeatTimeout,
      ids: ids ?? SecureUuidV4Generator(),
      diagnostics: diagnostics,
    );
    await worker._spawn(
      handler,
      readinessTimeout: readinessTimeout,
      heartbeatInterval: heartbeatInterval,
    );
    return worker;
  }

  /// Worker generation, unique within the caller's composition lifetime.
  final int generation;

  /// Negotiated protocol version.
  final int protocolVersion;

  /// Maximum tolerated interval without a heartbeat.
  final Duration heartbeatTimeout;

  final ReceivePort _messages = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final ReceivePort _exit = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  final Map<int, _PendingRequest<R, F>> _pending =
      <int, _PendingRequest<R, F>>{};
  final Set<String> _activePublicRequestIds = <String>{};
  final IdGenerator _ids;
  final DartitectDiagnosticSubject? _diagnostics;
  Isolate? _isolate;
  SendPort? _commands;
  StreamSubscription<Object?>? _messageSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  Timer? _heartbeatMonitor;
  DateTime? _lastHeartbeat;
  var _closing = false;
  var _disposed = false;
  var _lastCorrelationId = 0;
  Future<void>? _stopFuture;

  /// Completes after the matching generation and protocol are ready.
  Future<void> get ready => _ready.future;

  /// Last local receipt time of a valid heartbeat.
  DateTime? get lastHeartbeat => _lastHeartbeat;

  /// Number of requests without a terminal result.
  int get activeRequestCount => _pending.length;

  /// Whether terminal supervisor cleanup completed.
  bool get isDisposed => _disposed;

  /// Whether the endpoint is ready and accepting requests.
  bool get isReady => _ready.isCompleted && !_closing && !_disposed;

  Future<void> _spawn(
    IsolateRequestHandler<P, R, F> handler, {
    required Duration readinessTimeout,
    required Duration heartbeatInterval,
  }) async {
    _diagnostics?.emit(
      DartitectDiagnosticPhase.started,
      generation: generation,
    );
    _messageSubscription = _messages.listen(_handleMessage);
    _errorSubscription = _errors.listen(_handleError);
    _exitSubscription = _exit.listen(_handleExit);
    try {
      _isolate = await Isolate.spawn<_WorkerBootstrap<P, R, F>>(
        _workerMain<P, R, F>,
        _WorkerBootstrap<P, R, F>(
          supervisor: _messages.sendPort,
          generation: generation,
          protocolVersion: protocolVersion,
          heartbeatIntervalMicros: heartbeatInterval.inMicroseconds,
          handler: handler,
        ),
        onError: _errors.sendPort,
        onExit: _exit.sendPort,
        errorsAreFatal: true,
        debugName: 'dartitect-worker-$generation',
      );
      await ready.timeout(readinessTimeout);
      _diagnostics?.emit(
        DartitectDiagnosticPhase.succeeded,
        generation: generation,
      );
      _heartbeatMonitor = Timer.periodic(
        Duration(microseconds: heartbeatTimeout.inMicroseconds ~/ 2),
        (_) => _checkHeartbeat(),
      );
    } on TimeoutException {
      _diagnostics?.emit(
        DartitectDiagnosticPhase.failed,
        generation: generation,
      );
      await _failAndClose(
        const IsolateReadinessException('Worker readiness deadline elapsed.'),
        forceKill: true,
      );
      throw const IsolateReadinessException(
        'Worker readiness deadline elapsed.',
      );
    } catch (_) {
      _diagnostics?.emit(
        DartitectDiagnosticPhase.crashed,
        generation: generation,
      );
      await _closeSupervisor(forceKill: true);
      rethrow;
    }
  }

  /// Sends a request and exposes its correlated acceptance ACK.
  IsolateRequestReceipt<R, F> send(
    P payload, {
    Duration timeout = const Duration(seconds: 30),
    String? requestId,
  }) {
    if (!isReady) throw StateError('IsolateWorker is not accepting requests.');
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    final id = requestId ?? _ids.nextId();
    if (id.trim().isEmpty || _activePublicRequestIds.contains(id)) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'must be non-empty and unique among active requests',
      );
    }
    final correlationId = ++_lastCorrelationId;
    final pending = _PendingRequest<R, F>(id);
    _pending[correlationId] = pending;
    _activePublicRequestIds.add(id);
    _diagnostics?.emit(
      DartitectDiagnosticPhase.updated,
      generation: generation,
      revision: _pending.length,
    );
    pending.deadline = Timer(timeout, () {
      _commands?.send(<String, Object?>{
        'kind': 'cancel',
        'generation': generation,
        'correlationId': correlationId,
      });
      _completeRequestError(
        correlationId,
        const IsolateRequestDeadlineException('Request deadline elapsed.'),
        StackTrace.current,
      );
    });
    try {
      _commands!.send(<String, Object?>{
        'kind': 'request',
        'protocolVersion': protocolVersion,
        'generation': generation,
        'correlationId': correlationId,
        'payload': payload,
      });
    } catch (error, stackTrace) {
      _completeRequestError(correlationId, error, stackTrace);
    }
    return IsolateRequestReceipt<R, F>(
      requestId: id,
      accepted: pending.accepted.future,
      result: pending.result.future,
    );
  }

  /// Sends and awaits one terminal result.
  Future<Result<R, F>> execute(
    P payload, {
    Duration timeout = const Duration(seconds: 30),
    String? requestId,
  }) => send(payload, timeout: timeout, requestId: requestId).result;

  /// Stops intake, waits for worker ACK, and force-kills only after [deadline].
  Future<void> safeStop({Duration deadline = const Duration(seconds: 5)}) =>
      _stopFuture ??= _safeStop(deadline);

  Future<void> _safeStop(Duration deadline) async {
    if (deadline <= Duration.zero) {
      throw ArgumentError.value(deadline, 'deadline', 'must be positive');
    }
    if (_disposed) return;
    _closing = true;
    _commands?.send(<String, Object?>{
      'kind': 'stop',
      'generation': generation,
    });
    var forced = false;
    try {
      await _stopped.future.timeout(deadline);
    } on TimeoutException {
      forced = true;
      _isolate?.kill(priority: Isolate.immediate);
    } finally {
      await _closeSupervisor(forceKill: forced);
    }
  }

  void _handleMessage(Object? message) {
    if (message is! Map<Object?, Object?> || _disposed) return;
    if (message['generation'] != generation) return;
    final kind = message['kind'];
    switch (kind) {
      case 'ready':
        if (message['protocolVersion'] != protocolVersion ||
            message['commands'] is! SendPort) {
          unawaited(
            _failAndClose(
              const IsolateReadinessException(
                'Worker returned an invalid readiness envelope.',
              ),
              forceKill: true,
            ),
          );
          return;
        }
        _commands = message['commands']! as SendPort;
        _lastHeartbeat = DateTime.now().toUtc();
        if (!_ready.isCompleted) _ready.complete();
      case 'heartbeat':
        _lastHeartbeat = DateTime.now().toUtc();
      case 'accepted':
        final correlationId = message['correlationId'];
        if (correlationId is! int) return;
        final pending = _pending[correlationId];
        if (pending != null && !pending.accepted.isCompleted) {
          pending.accepted.complete();
        }
      case 'result':
        final correlationId = message['correlationId'];
        if (correlationId is! int) return;
        final pending = _removePending(correlationId);
        if (pending == null) return;
        pending.deadline?.cancel();
        if (!pending.accepted.isCompleted) pending.accepted.complete();
        if (message['success'] == true) {
          pending.result.complete(Ok<R>(message['value'] as R));
        } else {
          pending.result.complete(
            Err<F>(
              message['failure'] as F,
              StackTrace.fromString(message['stack']! as String),
            ),
          );
        }
        _diagnostics?.emit(
          message['success'] == true
              ? DartitectDiagnosticPhase.succeeded
              : DartitectDiagnosticPhase.failed,
          generation: generation,
          revision: _pending.length,
        );
      case 'crash':
        final correlationId = message['correlationId'];
        if (correlationId is! int) return;
        _completeRequestError(
          correlationId,
          RemoteIsolateCrash(
            message['errorType'] is String
                ? 'Remote handler crashed as ${message['errorType']}.'
                : 'Remote handler crashed.',
            StackTrace.fromString(message['stack'] as String? ?? ''),
          ),
          StackTrace.current,
        );
      case 'stopped':
        if (!_stopped.isCompleted) _stopped.complete();
    }
  }

  void _handleError(Object? message) {
    final stack = message is List<Object?> && message.length > 1
        ? StackTrace.fromString('${message[1]}')
        : StackTrace.current;
    unawaited(
      _failAndClose(
        RemoteIsolateCrash('Worker isolate raised an unhandled error.', stack),
        forceKill: true,
      ),
    );
  }

  void _handleExit(Object? _) {
    if (_closing || _disposed) {
      if (!_stopped.isCompleted) _stopped.complete();
      return;
    }
    unawaited(
      _failAndClose(
        const IsolateUnexpectedExitException('Worker exited unexpectedly.'),
        forceKill: false,
      ),
    );
  }

  void _checkHeartbeat() {
    final heartbeat = _lastHeartbeat;
    if (_closing || _disposed || heartbeat == null) return;
    if (DateTime.now().toUtc().difference(heartbeat) > heartbeatTimeout) {
      unawaited(
        _failAndClose(
          const IsolateHeartbeatException('Worker heartbeat was lost.'),
          forceKill: true,
        ),
      );
    }
  }

  void _completeRequestError(
    int correlationId,
    Object error,
    StackTrace stackTrace,
  ) {
    final pending = _removePending(correlationId);
    if (pending == null) return;
    pending.deadline?.cancel();
    if (!pending.accepted.isCompleted) {
      pending.accepted.completeError(error, stackTrace);
    }
    if (!pending.result.isCompleted) {
      pending.result.completeError(error, stackTrace);
    }
  }

  _PendingRequest<R, F>? _removePending(int correlationId) {
    final pending = _pending.remove(correlationId);
    if (pending != null) _activePublicRequestIds.remove(pending.requestId);
    return pending;
  }

  Future<void> _failAndClose(Object error, {required bool forceKill}) async {
    if (_disposed) return;
    _closing = true;
    _diagnostics?.emit(
      DartitectDiagnosticPhase.crashed,
      generation: generation,
      revision: _pending.length,
    );
    if (!_ready.isCompleted) _ready.completeError(error, StackTrace.current);
    for (final correlationId in _pending.keys.toList(growable: false)) {
      _completeRequestError(correlationId, error, StackTrace.current);
    }
    if (!_stopped.isCompleted) _stopped.complete();
    await _closeSupervisor(forceKill: forceKill);
  }

  Future<void> _closeSupervisor({required bool forceKill}) async {
    if (_disposed) return;
    _disposed = true;
    _closing = true;
    _heartbeatMonitor?.cancel();
    _heartbeatMonitor = null;
    if (forceKill) _isolate?.kill(priority: Isolate.immediate);
    for (final correlationId in _pending.keys.toList(growable: false)) {
      _completeRequestError(
        correlationId,
        const IsolateUnexpectedExitException('Worker supervisor closed.'),
        StackTrace.current,
      );
    }
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _messages.close();
    _errors.close();
    _exit.close();
    _commands = null;
    _isolate = null;
    _activePublicRequestIds.clear();
    _diagnostics?.emit(
      DartitectDiagnosticPhase.disposed,
      generation: generation,
    );
  }

  @override
  Future<void> disposeAsync() => safeStop();
}

final class _PendingRequest<R, F extends Object> {
  _PendingRequest(this.requestId) {
    accepted.future.ignore();
    result.future.ignore();
  }

  final String requestId;
  final Completer<void> accepted = Completer<void>();
  final Completer<Result<R, F>> result = Completer<Result<R, F>>();
  Timer? deadline;
}

final class _WorkerBootstrap<P, R, F extends Object> {
  const _WorkerBootstrap({
    required this.supervisor,
    required this.generation,
    required this.protocolVersion,
    required this.heartbeatIntervalMicros,
    required this.handler,
  });

  final SendPort supervisor;
  final int generation;
  final int protocolVersion;
  final int heartbeatIntervalMicros;
  final IsolateRequestHandler<P, R, F> handler;
}

void _workerMain<P, R, F extends Object>(_WorkerBootstrap<P, R, F> bootstrap) {
  final commands = ReceivePort();
  final active = <int, CancellationSource>{};
  final work = <Future<void>>{};
  var closing = false;
  final heartbeat = Timer.periodic(
    Duration(microseconds: bootstrap.heartbeatIntervalMicros),
    (_) => bootstrap.supervisor.send(<String, Object?>{
      'kind': 'heartbeat',
      'generation': bootstrap.generation,
    }),
  );

  Future<void> runRequest(Map<Object?, Object?> message) async {
    final correlationId = message['correlationId']! as int;
    final cancellation = CancellationSource();
    active[correlationId] = cancellation;
    bootstrap.supervisor.send(<String, Object?>{
      'kind': 'accepted',
      'generation': bootstrap.generation,
      'correlationId': correlationId,
    });
    try {
      final result = await bootstrap.handler(
        message['payload'] as P,
        cancellation.signal,
      );
      if (cancellation.signal.isCancelled) return;
      switch (result) {
        case Ok<dynamic>(:final value):
          bootstrap.supervisor.send(<String, Object?>{
            'kind': 'result',
            'generation': bootstrap.generation,
            'correlationId': correlationId,
            'success': true,
            'value': value,
          });
        case Err<Object>(:final failure, :final stackTrace):
          bootstrap.supervisor.send(<String, Object?>{
            'kind': 'result',
            'generation': bootstrap.generation,
            'correlationId': correlationId,
            'success': false,
            'failure': failure,
            'stack': stackTrace.toString(),
          });
      }
    } catch (error, stackTrace) {
      bootstrap.supervisor.send(<String, Object?>{
        'kind': 'crash',
        'generation': bootstrap.generation,
        'correlationId': correlationId,
        'errorType': error.runtimeType.toString(),
        'stack': stackTrace.toString(),
      });
    } finally {
      cancellation.dispose();
      active.remove(correlationId);
    }
  }

  commands.listen((Object? raw) async {
    if (raw is! Map<Object?, Object?> ||
        raw['generation'] != bootstrap.generation) {
      return;
    }
    switch (raw['kind']) {
      case 'request':
        if (closing ||
            raw['protocolVersion'] != bootstrap.protocolVersion ||
            raw['correlationId'] is! int) {
          return;
        }
        late final Future<void> requestWork;
        requestWork = runRequest(raw)
            .whenComplete(() => work.remove(requestWork));
        work.add(requestWork);
      case 'cancel':
        active[raw['correlationId']]?.cancel('Request cancelled by supervisor');
      case 'stop':
        if (closing) return;
        closing = true;
        for (final source in active.values.toList(growable: false)) {
          source.cancel('Worker stopping');
        }
        await Future.wait<void>(work.toList(growable: false));
        heartbeat.cancel();
        bootstrap.supervisor.send(<String, Object?>{
          'kind': 'stopped',
          'generation': bootstrap.generation,
        });
        commands.close();
    }
  });

  bootstrap.supervisor.send(<String, Object?>{
    'kind': 'ready',
    'protocolVersion': bootstrap.protocolVersion,
    'generation': bootstrap.generation,
    'commands': commands.sendPort,
  });
}
