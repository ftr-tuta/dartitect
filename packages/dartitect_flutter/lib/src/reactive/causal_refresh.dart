import 'dart:async';

import 'package:dartitect/dartitect.dart';

import 'live_resource.dart';
import 'resource_lifecycle.dart';

/// Typed proof that a repository completed one authoritative local commit.
final class LocalCommitReceipt<R> {
  /// Creates a receipt for the repository-defined [revision].
  const LocalCommitReceipt(this.revision);

  /// Revision that must later appear in an authoritative source value.
  final R revision;
}

/// Authoritative value paired with the local revision that produced it.
final class ObservedValue<T, R> {
  /// Creates an observed value.
  const ObservedValue(this.value, this.revision);

  /// Authoritative domain value.
  final T value;

  /// Repository-defined revision observed with [value].
  final R revision;
}

/// Remote refresh whose completion point is the remote action itself.
final class RemoteRefresh<T, F extends Object> {
  /// Creates a remote refresh from an injected action.
  const RemoteRefresh(this._action);

  final Future<Result<T, F>> Function() _action;

  /// Executes the remote action without implying local observation.
  Future<Result<T, F>> execute() => _action();
}

/// Local refresh whose completion point is an authoritative commit receipt.
final class LocalCommitRefresh<R, F extends Object> {
  /// Creates a local commit refresh from an injected repository action.
  const LocalCommitRefresh(this._action);

  final Future<Result<LocalCommitReceipt<R>, F>> Function() _action;

  /// Executes the action and returns its typed local commit receipt.
  Future<Result<LocalCommitReceipt<R>, F>> execute() => _action();
}

/// Local refresh that completes only after its receipt revision is published.
final class ObservedLocalRefresh<T, R, F extends Object> {
  /// Creates a bounded causal refresh.
  ObservedLocalRefresh({
    required LocalCommitRefresh<R, F> commit,
    required LiveResource<ObservedValue<T, R>, F> resource,
    required Duration timeout,
    required F Function(LocalCommitReceipt<R> receipt) mapTimeout,
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
  }) : _commit = commit,
       _timeout = _positive(timeout),
       _mapTimeout = mapTimeout,
       _timerFactory = timerFactory,
       _observation = resource.observe();

  final LocalCommitRefresh<R, F> _commit;
  final Duration _timeout;
  final F Function(LocalCommitReceipt<R> receipt) _mapTimeout;
  final ReactiveTimerFactory _timerFactory;
  final ReactiveObservation<ObservedValue<T, R>, F> _observation;
  final Map<R, List<_ObservedWaiter<T, R, F>>> _waiters =
      <R, List<_ObservedWaiter<T, R, F>>>{};
  var _listening = false;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Number of receipt waits currently retained.
  int get waiterCount =>
      _waiters.values.fold(0, (count, values) => count + values.length);

  /// Number of active timeout handles retained by current waits.
  int get activeTimerCount => _waiters.values
      .expand((values) => values)
      .where((waiter) => waiter.timer?.isActive ?? false)
      .length;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Commits locally, then waits for the matching published revision.
  Future<Result<ObservedValue<T, R>, F>> execute() async {
    _ensureActive();
    final committed = await _commit.execute();
    _ensureActive();
    return switch (committed) {
      Ok<dynamic>(:final value) => _waitFor(value as LocalCommitReceipt<R>),
      Err<Object>(:final failure, :final stackTrace) => Err<F>(
        failure as F,
        stackTrace,
      ),
    };
  }

  /// Cancels every wait and releases the internal observation.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<Result<ObservedValue<T, R>, F>> _waitFor(
    LocalCommitReceipt<R> receipt,
  ) {
    final waiter = _ObservedWaiter<T, R, F>(receipt);
    _waiters.putIfAbsent(receipt.revision, () => <_ObservedWaiter<T, R, F>>[])
      ..add(waiter);
    waiter.timer = _timerFactory.schedule(
      _timeout,
      () => _timeoutWaiter(waiter),
    );
    if (!_listening) {
      _listening = true;
      _observation.addListener(_observed);
    }
    _observed();
    return waiter.completer.future;
  }

  void _observed() {
    if (_disposed || !_observation.state.hasData) return;
    final value = _observation.state.lastData;
    if (value == null) return;
    final matches = _waiters.remove(value.revision);
    if (matches == null) return;
    for (final waiter in matches) {
      waiter.timer?.cancel();
      waiter.timer = null;
      if (!waiter.completer.isCompleted) {
        waiter.completer.complete(Ok<ObservedValue<T, R>>(value));
      }
    }
    _detachWhenIdle();
  }

  void _timeoutWaiter(_ObservedWaiter<T, R, F> waiter) {
    if (_disposed || waiter.completer.isCompleted) return;
    _remove(waiter);
    waiter.timer = null;
    try {
      final failure = _mapTimeout(waiter.receipt);
      waiter.completer.complete(Err<F>(failure, StackTrace.current));
    } catch (error, stackTrace) {
      waiter.completer.completeError(error, stackTrace);
    }
    _detachWhenIdle();
  }

  void _remove(_ObservedWaiter<T, R, F> waiter) {
    final values = _waiters[waiter.receipt.revision];
    values?.remove(waiter);
    if (values?.isEmpty ?? false) _waiters.remove(waiter.receipt.revision);
  }

  void _detachWhenIdle() {
    if (_waiters.isNotEmpty || !_listening) return;
    _listening = false;
    _observation.removeListener(_observed);
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    final waiters = _waiters.values.expand((values) => values).toList();
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.timer?.cancel();
      waiter.timer = null;
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(
          const CancellationException('ObservedLocalRefresh disposed'),
        );
      }
    }
    if (_listening) {
      _listening = false;
      _observation.removeListener(_observed);
    }
    await _observation.close();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ObservedLocalRefresh is disposed.');
  }

  static Duration _positive(Duration timeout) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    return timeout;
  }
}

final class _ObservedWaiter<T, R, F extends Object> {
  _ObservedWaiter(this.receipt);

  final LocalCommitReceipt<R> receipt;
  final Completer<Result<ObservedValue<T, R>, F>> completer =
      Completer<Result<ObservedValue<T, R>, F>>();
  ReactiveTimerHandle? timer;
}
