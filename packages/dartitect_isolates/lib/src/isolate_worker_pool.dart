import 'dart:async';
import 'dart:collection';
import 'dart:isolate' show TransferableTypedData;

import 'package:dartitect/dartitect.dart';

import 'isolate_worker.dart';

/// Failure policy for a worker that becomes terminal unexpectedly.
sealed class IsolateWorkerCrashPolicy {
  const IsolateWorkerCrashPolicy._();

  /// Makes the complete pool terminal after the first worker loss.
  const factory IsolateWorkerCrashPolicy.failPool() = _FailPoolPolicy;

  /// Replaces lost workers at most [maxReplacements] times pool-wide.
  const factory IsolateWorkerCrashPolicy.replaceWorker(int maxReplacements) =
      _ReplaceWorkerPolicy;
}

final class _FailPoolPolicy extends IsolateWorkerCrashPolicy {
  const _FailPoolPolicy() : super._();
}

final class _ReplaceWorkerPolicy extends IsolateWorkerCrashPolicy {
  const _ReplaceWorkerPolicy(this.maxReplacements) : super._();

  final int maxReplacements;
}

/// Base class for bounded worker-pool admission and lifecycle failures.
sealed class IsolateWorkerPoolException implements Exception {
  const IsolateWorkerPoolException(this.message);

  /// Payload-free explanation.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The bounded pending queue has no remaining admission capacity.
final class IsolateWorkerPoolCapacityException
    extends IsolateWorkerPoolException {
  /// Creates one capacity rejection.
  const IsolateWorkerPoolCapacityException(super.message);
}

/// The pool stopped accepting work because its crash policy became terminal.
final class IsolateWorkerPoolTerminalException
    extends IsolateWorkerPoolException {
  /// Creates one terminal pool failure while preserving its original cause.
  const IsolateWorkerPoolTerminalException(super.message, this.cause);

  /// Original worker startup or terminal failure.
  final Object cause;
}

/// The pool has closed admission for graceful disposal.
final class IsolateWorkerPoolClosedException
    extends IsolateWorkerPoolException {
  /// Creates one closed-admission rejection.
  const IsolateWorkerPoolClosedException(super.message);
}

/// Fixed-size isolate pool with bounded FIFO admission.
///
/// Payloads and results cross the isolate boundary unchanged. In particular,
/// [TransferableTypedData] is never materialized by this runtime.
final class IsolateWorkerPool<P, R, F extends Object>
    implements AsyncDisposable {
  IsolateWorkerPool._({
    required this.size,
    required this.maxInFlight,
    required this.maxQueued,
    required IsolateRequestHandler<P, R, F> handler,
    required IsolateWorkerCrashPolicy crashPolicy,
    required Duration readinessTimeout,
    required Duration heartbeatInterval,
    required Duration heartbeatTimeout,
    required IdGenerator ids,
  }) : _handler = handler,
       _crashPolicy = crashPolicy,
       _readinessTimeout = readinessTimeout,
       _heartbeatInterval = heartbeatInterval,
       _heartbeatTimeout = heartbeatTimeout,
       _ids = ids;

  /// Spawns [size] VM workers and waits until all are ready.
  static Future<IsolateWorkerPool<P, R, F>> spawn<P, R, F extends Object>({
    required int size,
    required int maxInFlight,
    required int maxQueued,
    required IsolateRequestHandler<P, R, F> handler,
    IsolateWorkerCrashPolicy crashPolicy =
        const IsolateWorkerCrashPolicy.failPool(),
    Duration readinessTimeout = const Duration(seconds: 10),
    Duration heartbeatInterval = const Duration(seconds: 1),
    Duration heartbeatTimeout = const Duration(seconds: 5),
    IdGenerator? ids,
  }) async {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'must be positive');
    }
    if (maxInFlight <= 0) {
      throw ArgumentError.value(maxInFlight, 'maxInFlight', 'must be positive');
    }
    if (maxQueued < 0) {
      throw ArgumentError.value(maxQueued, 'maxQueued', 'must not be negative');
    }
    final replacementPolicy = crashPolicy;
    if (replacementPolicy is _ReplaceWorkerPolicy &&
        replacementPolicy.maxReplacements <= 0) {
      throw ArgumentError.value(
        replacementPolicy.maxReplacements,
        'crashPolicy.maxReplacements',
        'must be positive',
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
    final pool = IsolateWorkerPool<P, R, F>._(
      size: size,
      maxInFlight: maxInFlight,
      maxQueued: maxQueued,
      handler: handler,
      crashPolicy: crashPolicy,
      readinessTimeout: readinessTimeout,
      heartbeatInterval: heartbeatInterval,
      heartbeatTimeout: heartbeatTimeout,
      ids: ids ?? SecureUuidV4Generator(),
    );
    try {
      await pool._spawnInitialWorkers();
      return pool;
    } catch (_) {
      await pool._stopWorkers();
      rethrow;
    }
  }

  /// Number of owned worker isolates.
  final int size;

  /// Maximum admitted requests executing across all workers.
  final int maxInFlight;

  /// Maximum requests retained in the FIFO pending queue.
  final int maxQueued;

  final IsolateRequestHandler<P, R, F> _handler;
  final IsolateWorkerCrashPolicy _crashPolicy;
  final Duration _readinessTimeout;
  final Duration _heartbeatInterval;
  final Duration _heartbeatTimeout;
  final IdGenerator _ids;
  final List<_PoolWorkerSlot<P, R, F>> _workers = <_PoolWorkerSlot<P, R, F>>[];
  final ListQueue<_PoolRequest<P, R, F>> _queue =
      ListQueue<_PoolRequest<P, R, F>>();
  final Set<String> _requestIds = <String>{};
  final Set<Future<void>> _replacementWork = <Future<void>>{};
  final List<Completer<void>> _capacityWaiters = <Completer<void>>[];
  var _active = 0;
  var _nextWorker = 0;
  var _nextGeneration = 0;
  var _replacementCount = 0;
  var _closing = false;
  var _disposed = false;
  Object? _terminalError;
  Completer<void>? _drainWaiter;
  Future<void>? _disposal;

  /// Requests currently executing in worker isolates.
  int get activeRequestCount => _active;

  /// Requests waiting in FIFO admission order.
  int get queuedRequestCount => _queue.length;

  /// Number of workers successfully replaced after terminal loss.
  int get replacementCount => _replacementCount;

  /// Whether new requests can still be admitted.
  bool get isAccepting => !_closing && _terminalError == null && !_disposed;

  /// Whether every worker supervisor completed cleanup.
  bool get isDisposed => _disposed;

  Future<void> _spawnInitialWorkers() async {
    for (var index = 0; index < size; index += 1) {
      final worker = await _spawnWorker();
      _workers.add(_PoolWorkerSlot<P, R, F>(worker));
    }
  }

  Future<IsolateWorker<P, R, F>> _spawnWorker() => IsolateWorker.spawn<P, R, F>(
    handler: _handler,
    generation: ++_nextGeneration,
    readinessTimeout: _readinessTimeout,
    heartbeatInterval: _heartbeatInterval,
    heartbeatTimeout: _heartbeatTimeout,
  );

  /// Admits one request immediately or into the bounded FIFO queue.
  Future<Result<R, F>> execute(
    P payload, {
    Duration timeout = const Duration(seconds: 30),
    String? requestId,
    CancellationSignal? cancellation,
  }) {
    if (!isAccepting) {
      final terminal = _terminalError;
      if (terminal != null) {
        throw IsolateWorkerPoolTerminalException(
          'The worker pool is terminal.',
          terminal,
        );
      }
      throw const IsolateWorkerPoolClosedException(
        'The worker pool is not accepting requests.',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    cancellation?.throwIfCancelled();
    final id = requestId ?? _ids.nextId();
    if (id.trim().isEmpty || !_requestIds.add(id)) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'must be non-empty and unique among admitted requests',
      );
    }
    final request = _PoolRequest<P, R, F>(
      payload: payload,
      requestId: id,
      timeout: timeout,
      cancellation: cancellation,
    );
    request.registration = cancellation?.register((reason) {
      if (!request.started) {
        _cancelQueued(request, reason);
      }
    });
    final worker = _selectWorker();
    if (_active < maxInFlight && worker != null) {
      _startRequest(request, worker);
    } else if (_queue.length < maxQueued) {
      _queue.addLast(request);
    } else {
      request.registration?.dispose();
      _requestIds.remove(id);
      throw const IsolateWorkerPoolCapacityException(
        'The worker pool queue is at capacity.',
      );
    }
    return request.result.future;
  }

  /// Maps a stream through the bounded pool with input backpressure.
  ///
  /// With [preserveOrder], at most the pool's total admission capacity can be
  /// retained waiting for an earlier result. Cancelling the returned stream
  /// cancels and drains its input subscription and admitted requests.
  Stream<Result<R, F>> mapSequence(
    Stream<P> input, {
    bool preserveOrder = true,
    Duration timeout = const Duration(seconds: 30),
    CancellationSignal? cancellation,
  }) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    final session = _PoolMapSession<P, R, F>(
      pool: this,
      input: input,
      preserveOrder: preserveOrder,
      timeout: timeout,
      cancellation: cancellation,
    );
    return session.stream;
  }

  void _cancelQueued(_PoolRequest<P, R, F> request, Object? reason) {
    if (request.started || request.result.isCompleted) return;
    if (!_queue.remove(request)) return;
    _completeRequestError(
      request,
      CancellationException(reason),
      StackTrace.current,
    );
    _notifyCapacity();
    _checkDrain();
  }

  _PoolWorkerSlot<P, R, F>? _selectWorker() {
    if (_workers.isEmpty) return null;
    for (var offset = 0; offset < _workers.length; offset += 1) {
      final index = (_nextWorker + offset) % _workers.length;
      final slot = _workers[index];
      if (slot.isAvailable) {
        _nextWorker = (index + 1) % _workers.length;
        return slot;
      }
    }
    return null;
  }

  void _startRequest(
    _PoolRequest<P, R, F> request,
    _PoolWorkerSlot<P, R, F> slot,
  ) {
    request.started = true;
    _active += 1;
    slot.active += 1;
    final worker = slot.worker;
    unawaited(_runRequest(request, slot, worker));
  }

  Future<void> _runRequest(
    _PoolRequest<P, R, F> request,
    _PoolWorkerSlot<P, R, F> slot,
    IsolateWorker<P, R, F> worker,
  ) async {
    try {
      final result = await worker.execute(
        request.payload,
        timeout: request.timeout,
        requestId: request.requestId,
        cancellation: request.cancellation,
      );
      if (!request.result.isCompleted) request.result.complete(result);
    } catch (error, stackTrace) {
      _completeRequestError(request, error, stackTrace);
      if (worker.isDisposed) {
        _handleWorkerFailure(slot, worker, error);
      }
    } finally {
      request.registration?.dispose();
      _requestIds.remove(request.requestId);
      _active -= 1;
      slot.active -= 1;
      _dispatch();
      _notifyCapacity();
      _checkDrain();
    }
  }

  void _completeRequestError(
    _PoolRequest<P, R, F> request,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!request.result.isCompleted) {
      request.result.completeError(error, stackTrace);
    }
    request.registration?.dispose();
    _requestIds.remove(request.requestId);
  }

  void _dispatch() {
    if (_terminalError != null) {
      _failQueued(_terminalError!);
      return;
    }
    while (_queue.isNotEmpty && _active < maxInFlight) {
      final worker = _selectWorker();
      if (worker == null) return;
      final request = _queue.removeFirst();
      if (request.result.isCompleted) continue;
      _startRequest(request, worker);
    }
    _checkDrain();
  }

  void _handleWorkerFailure(
    _PoolWorkerSlot<P, R, F> slot,
    IsolateWorker<P, R, F> failedWorker,
    Object error,
  ) {
    if (!identical(slot.worker, failedWorker) || slot.replacing) return;
    slot.available = false;
    final policy = _crashPolicy;
    if (policy is _FailPoolPolicy) {
      _failPool(error);
      return;
    }
    slot.replacing = true;
    late final Future<void> work;
    work = _replaceWorker(slot, policy as _ReplaceWorkerPolicy, error)
        .whenComplete(() {
          slot.replacing = false;
          _replacementWork.remove(work);
          _dispatch();
          _notifyCapacity();
          _checkDrain();
        });
    _replacementWork.add(work);
    unawaited(work);
  }

  Future<void> _replaceWorker(
    _PoolWorkerSlot<P, R, F> slot,
    _ReplaceWorkerPolicy policy,
    Object originalError,
  ) async {
    var lastError = originalError;
    while (_replacementCount < policy.maxReplacements) {
      _replacementCount += 1;
      try {
        final replacement = await _spawnWorker();
        slot.worker = replacement;
        slot.available = true;
        return;
      } catch (error) {
        lastError = error;
      }
    }
    _failPool(lastError);
  }

  void _failPool(Object error) {
    if (_terminalError != null) return;
    _terminalError = error;
    _closing = true;
    _failQueued(error);
    _disposal ??= _drainAndStop();
    _checkDrain();
    _notifyCapacity();
  }

  void _failQueued(Object error) {
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _completeRequestError(
        request,
        IsolateWorkerPoolTerminalException(
          'The worker pool became terminal before dispatch.',
          error,
        ),
        StackTrace.current,
      );
    }
  }

  bool get _hasAdmissionCapacity {
    if (!isAccepting) return false;
    if (_active < maxInFlight && _selectableWorkerExists) return true;
    return _queue.length < maxQueued;
  }

  bool get _selectableWorkerExists =>
      _workers.any((worker) => worker.isAvailable);

  Future<void> _waitForAdmission() {
    if (_hasAdmissionCapacity) return Future<void>.value();
    if (!isAccepting) {
      return Future<void>.error(
        _terminalError == null
            ? const IsolateWorkerPoolClosedException(
                'The worker pool closed while waiting for capacity.',
              )
            : IsolateWorkerPoolTerminalException(
                'The worker pool became terminal while waiting for capacity.',
                _terminalError!,
              ),
      );
    }
    final waiter = Completer<void>();
    _capacityWaiters.add(waiter);
    return waiter.future;
  }

  void _notifyCapacity() {
    if (!_hasAdmissionCapacity && isAccepting) return;
    final waiters = _capacityWaiters.toList(growable: false);
    _capacityWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void _checkDrain() {
    final waiter = _drainWaiter;
    if (waiter != null &&
        !waiter.isCompleted &&
        _active == 0 &&
        _queue.isEmpty) {
      waiter.complete();
    }
  }

  /// Closes admission, drains every admitted request, then safe-stops workers.
  @override
  Future<void> disposeAsync() {
    _closing = true;
    _disposal ??= _drainAndStop();
    _dispatch();
    _checkDrain();
    _notifyCapacity();
    return _disposal!;
  }

  Future<void> _drainAndStop() async {
    _drainWaiter ??= Completer<void>();
    _checkDrain();
    await _drainWaiter!.future;
    if (_replacementWork.isNotEmpty) {
      await Future.wait<void>(_replacementWork.toList(growable: false));
    }
    await _stopWorkers();
    _disposed = true;
    _notifyCapacity();
  }

  Future<void> _stopWorkers() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final slot in _workers) {
      try {
        await slot.worker.safeStop();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace ?? StackTrace.current);
    }
  }
}

final class _PoolWorkerSlot<P, R, F extends Object> {
  _PoolWorkerSlot(this.worker);

  IsolateWorker<P, R, F> worker;
  var active = 0;
  var available = true;
  var replacing = false;

  bool get isAvailable => available && worker.isReady;
}

final class _PoolRequest<P, R, F extends Object> {
  _PoolRequest({
    required this.payload,
    required this.requestId,
    required this.timeout,
    required this.cancellation,
  }) {
    result.future.ignore();
  }

  final P payload;
  final String requestId;
  final Duration timeout;
  final CancellationSignal? cancellation;
  final Completer<Result<R, F>> result = Completer<Result<R, F>>();
  CancellationRegistration? registration;
  var started = false;
}

final class _PoolMapSession<P, R, F extends Object> {
  _PoolMapSession({
    required this.pool,
    required this.input,
    required this.preserveOrder,
    required this.timeout,
    required this.cancellation,
  }) {
    _controller = StreamController<Result<R, F>>(
      onListen: _listen,
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancel,
    );
  }

  final IsolateWorkerPool<P, R, F> pool;
  final Stream<P> input;
  final bool preserveOrder;
  final Duration timeout;
  final CancellationSignal? cancellation;
  late final StreamController<Result<R, F>> _controller;
  StreamSubscription<P>? _inputSubscription;
  CancellationRegistration? _cancellationRegistration;
  final Map<int, _MapCompletion<R, F>> _completed =
      <int, _MapCompletion<R, F>>{};
  final Map<int, CancellationSource> _requests = <int, CancellationSource>{};
  final Set<Future<void>> _requestWork = <Future<void>>{};
  var _nextInput = 0;
  var _nextOutput = 0;
  var _outstanding = 0;
  var _inputDone = false;
  var _stopping = false;

  Stream<Result<R, F>> get stream => _controller.stream;

  int get _capacity => pool.maxInFlight + pool.maxQueued;

  void _listen() {
    _cancellationRegistration = cancellation?.register((reason) {
      unawaited(_abort(CancellationException(reason), StackTrace.current));
    });
    _inputSubscription = input.listen(
      _onData,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_abort(error, stackTrace));
      },
      onDone: () {
        _inputDone = true;
        _finishIfDone();
      },
      cancelOnError: false,
    );
  }

  void _onData(P payload) {
    if (_stopping) return;
    _inputSubscription?.pause();
    final sequence = _nextInput++;
    unawaited(_submit(sequence, payload));
  }

  Future<void> _submit(int sequence, P payload) async {
    try {
      while (!_stopping) {
        await pool._waitForAdmission();
        if (_stopping) return;
        final source = CancellationSource();
        try {
          final result = pool.execute(
            payload,
            timeout: timeout,
            cancellation: source.signal,
          );
          _requests[sequence] = source;
          _outstanding += 1;
          late final Future<void> work;
          work = _receive(sequence, result).whenComplete(() {
            _requestWork.remove(work);
          });
          _requestWork.add(work);
          if (_outstanding < _capacity && !_controller.isPaused) {
            _inputSubscription?.resume();
          }
          return;
        } on IsolateWorkerPoolCapacityException {
          source.dispose();
          continue;
        }
      }
    } catch (error, stackTrace) {
      await _abort(error, stackTrace);
    }
  }

  Future<void> _receive(int sequence, Future<Result<R, F>> result) async {
    _MapCompletion<R, F> completion;
    try {
      completion = _MapCompletion<R, F>.result(await result);
    } catch (error, stackTrace) {
      completion = _MapCompletion<R, F>.error(error, stackTrace);
    }
    _requests.remove(sequence);
    _outstanding -= 1;
    if (_stopping) return;
    if (preserveOrder) {
      _completed[sequence] = completion;
      _flushOrdered();
    } else {
      _emit(completion);
    }
    if (_outstanding < _capacity && !_controller.isPaused) {
      _inputSubscription?.resume();
    }
    _finishIfDone();
  }

  void _flushOrdered() {
    while (true) {
      final completion = _completed.remove(_nextOutput);
      if (completion == null) return;
      _emit(completion);
      _nextOutput += 1;
    }
  }

  void _emit(_MapCompletion<R, F> completion) {
    if (_controller.isClosed || _stopping) return;
    final error = completion.error;
    if (error == null) {
      _controller.add(completion.value!);
    } else {
      _controller.addError(error, completion.stackTrace);
    }
  }

  void _pause() => _inputSubscription?.pause();

  void _resume() {
    if (!_stopping && _outstanding < _capacity) {
      _inputSubscription?.resume();
    }
  }

  Future<void> _cancel() => _stop(closeController: false);

  Future<void> _abort(Object error, StackTrace stackTrace) async {
    if (_stopping) return;
    if (!_controller.isClosed) _controller.addError(error, stackTrace);
    await _stop(closeController: true);
  }

  Future<void> _stop({required bool closeController}) async {
    if (_stopping) return;
    _stopping = true;
    _cancellationRegistration?.dispose();
    await _inputSubscription?.cancel();
    for (final source in _requests.values.toList(growable: false)) {
      source.cancel('mapSequence consumer stopped');
    }
    if (_requestWork.isNotEmpty) {
      await Future.wait<void>(_requestWork.toList(growable: false));
    }
    _requests.clear();
    _completed.clear();
    if (closeController && !_controller.isClosed) await _controller.close();
  }

  void _finishIfDone() {
    if (!_inputDone || _outstanding != 0 || _stopping) return;
    _stopping = true;
    _cancellationRegistration?.dispose();
    unawaited(_controller.close());
  }
}

final class _MapCompletion<R, F extends Object> {
  const _MapCompletion.result(this.value) : error = null, stackTrace = null;

  const _MapCompletion.error(this.error, this.stackTrace) : value = null;

  final Result<R, F>? value;
  final Object? error;
  final StackTrace? stackTrace;
}
