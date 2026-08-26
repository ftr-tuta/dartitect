import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'live_resource.dart';

/// Activation-local one-shot/Future source with explicit cancellation.
final class FutureReactiveSource<T, F extends Object>
    implements ReactiveSource<T, F> {
  /// Creates a source that invokes [load] for initial activation and refresh.
  const FutureReactiveSource(this.load);

  /// Borrowed async read callback.
  final Future<Result<T, F>> Function(CancellationSignal signal) load;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() async =>
      Ok<ReactiveSourceSession<T, F>>(_FutureReactiveSourceSession<T, F>(load));
}

final class _FutureReactiveSourceSession<T, F extends Object>
    implements ReactiveSourceSession<T, F> {
  _FutureReactiveSourceSession(this._load);

  final Future<Result<T, F>> Function(CancellationSignal signal) _load;
  static const Stream<void> _signals = Stream<void>.empty();
  var _closed = false;

  @override
  Stream<void> get signals => _signals;

  @override
  Future<Result<T, F>> read(CancellationSignal signal) {
    if (_closed) {
      throw const CancellationException('Future source session closed');
    }
    signal.throwIfCancelled();
    return _load(signal);
  }

  @override
  Future<void> close() async => _closed = true;
}

/// Stream bridge whose events remain inside one activation-local session.
///
/// Expected failures travel as `Err<F>` events. Stream errors remain unexpected
/// crashes and preserve their original stack through [LiveResource].
final class StreamReactiveSource<T, F extends Object>
    implements ReactiveSource<T, F> {
  /// Creates a source from a fresh stream factory for each hot activation.
  const StreamReactiveSource(this.createStream);

  /// Creates an activation-local stream of typed results.
  final Stream<Result<T, F>> Function() createStream;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() async =>
      Ok<ReactiveSourceSession<T, F>>(
        _StreamReactiveSourceSession<T, F>(createStream()),
      );
}

final class _StreamReactiveSourceSession<T, F extends Object>
    implements ReactiveSourceSession<T, F> {
  _StreamReactiveSourceSession(Stream<Result<T, F>> stream)
    : _signals = StreamController<void>.broadcast(sync: true) {
    _subscription = stream.listen(
      _onData,
      onError: (Object error, StackTrace stackTrace) {
        if (!_closed) _signals.addError(error, stackTrace);
        final waiter = _waiter;
        _waiter = null;
        if (waiter != null && !waiter.isCompleted) {
          waiter.completeError(error, stackTrace);
        }
      },
      onDone: () {
        final waiter = _waiter;
        _waiter = null;
        if (waiter != null && !waiter.isCompleted) {
          waiter.completeError(
            StateError('Stream source closed before its first value.'),
            StackTrace.current,
          );
        }
      },
    );
  }

  final StreamController<void> _signals;
  late final StreamSubscription<Result<T, F>> _subscription;
  Result<T, F>? _latest;
  Completer<Result<T, F>>? _waiter;
  var _hasLatest = false;
  var _closed = false;
  Future<void>? _closeFuture;

  @override
  Stream<void> get signals => _signals.stream;

  @override
  Future<Result<T, F>> read(CancellationSignal signal) async {
    if (_closed) {
      throw const CancellationException('Stream source session closed');
    }
    signal.throwIfCancelled();
    if (_hasLatest) return _latest as Result<T, F>;
    final waiter = _waiter ??= Completer<Result<T, F>>();
    final cancellation = signal.register((reason) {
      if (!waiter.isCompleted) {
        waiter.completeError(CancellationException(reason), StackTrace.current);
      }
    });
    try {
      return await waiter.future;
    } finally {
      cancellation.dispose();
      if (identical(_waiter, waiter) && waiter.isCompleted) {
        _waiter = null;
      }
    }
  }

  void _onData(Result<T, F> result) {
    if (_closed) return;
    _latest = result;
    _hasLatest = true;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(result);
    } else {
      _signals.add(null);
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(
        const CancellationException('Stream source session closed'),
        StackTrace.current,
      );
    }
    await _subscription.cancel();
    await _signals.close();
  }
}

/// Borrowed Flutter-listenable bridge with an authoritative read callback.
final class ListenableReactiveSource<T, F extends Object>
    implements ReactiveSource<T, F> {
  /// Creates a source that reads once initially and after each notification.
  const ListenableReactiveSource({
    required this.listenable,
    required this.read,
  });

  /// Borrowed notifier; the session removes its listener before close returns.
  final Listenable listenable;

  /// Synchronous authoritative snapshot read.
  final Result<T, F> Function() read;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() async =>
      Ok<ReactiveSourceSession<T, F>>(
        _ListenableReactiveSourceSession<T, F>(listenable, read),
      );
}

/// Convenience source that publishes the current value of a borrowed
/// [ValueListenable] as successful data.
final class ValueListenableReactiveSource<T, F extends Object>
    implements ReactiveSource<T, F> {
  /// Creates a direct Flutter-native value bridge.
  const ValueListenableReactiveSource(this.listenable);

  /// Borrowed value listenable.
  final ValueListenable<T> listenable;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() async =>
      Ok<ReactiveSourceSession<T, F>>(
        _ListenableReactiveSourceSession<T, F>(
          listenable,
          () => Ok<T>(listenable.value),
        ),
      );
}

final class _ListenableReactiveSourceSession<T, F extends Object>
    implements ReactiveSourceSession<T, F> {
  _ListenableReactiveSourceSession(this._listenable, this._read)
    : _signals = StreamController<void>.broadcast(sync: true) {
    _listenable.addListener(_changed);
  }

  final Listenable _listenable;
  final Result<T, F> Function() _read;
  final StreamController<void> _signals;
  var _closed = false;

  @override
  Stream<void> get signals => _signals.stream;

  @override
  Future<Result<T, F>> read(CancellationSignal signal) async {
    if (_closed) {
      throw const CancellationException('Listenable source session closed');
    }
    signal.throwIfCancelled();
    return _read();
  }

  void _changed() {
    if (!_closed) _signals.add(null);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _listenable.removeListener(_changed);
    await _signals.close();
  }
}
