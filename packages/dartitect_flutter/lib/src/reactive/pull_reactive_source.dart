import 'dart:async';

import 'package:dartitect/dartitect.dart';

import 'live_resource.dart';

/// Creates one activation-local invalidation stream.
typedef PullInvalidationTrigger = Stream<void> Function();

/// Releases activation-local state created alongside invalidation triggers.
typedef PullSourceRelease = FutureOr<void> Function();

/// A reactive source that separates invalidation signals from authoritative
/// reads.
///
/// Triggers never carry presentation data. Every accepted invalidation invokes
/// [pull] through the owning [LiveResource]'s cancellation and backpressure
/// policy, keeping one authoritative source and no parallel UI cache.
final class PullReactiveSource<T, F extends Object>
    implements ReactiveSource<T, F> {
  /// Creates a pull source from activation-local [triggers].
  PullReactiveSource({
    required Iterable<PullInvalidationTrigger> triggers,
    required Future<Result<T, F>> Function(CancellationSignal signal) pull,
    PullSourceRelease? release,
    F Function(Object error, StackTrace stackTrace)? mapOpenFailure,
  }) : _triggers = List<PullInvalidationTrigger>.unmodifiable(triggers),
       _pull = pull,
       _release = release,
       _mapOpenFailure = mapOpenFailure {
    if (_triggers.isEmpty) {
      throw ArgumentError.value(triggers, 'triggers', 'must not be empty');
    }
  }

  final List<PullInvalidationTrigger> _triggers;
  final Future<Result<T, F>> Function(CancellationSignal signal) _pull;
  final PullSourceRelease? _release;
  final F Function(Object error, StackTrace stackTrace)? _mapOpenFailure;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() async {
    try {
      return Ok<ReactiveSourceSession<T, F>>(
        _PullReactiveSourceSession<T, F>(
          triggers: _triggers,
          pull: _pull,
          release: _release,
        ),
      );
    } catch (error, stackTrace) {
      final mapper = _mapOpenFailure;
      if (mapper == null) Error.throwWithStackTrace(error, stackTrace);
      return Err<F>(mapper(error, stackTrace), stackTrace);
    }
  }
}

final class _PullReactiveSourceSession<T, F extends Object>
    implements ReactiveSourceSession<T, F> {
  _PullReactiveSourceSession({
    required Iterable<PullInvalidationTrigger> triggers,
    required Future<Result<T, F>> Function(CancellationSignal signal) pull,
    required PullSourceRelease? release,
  }) : _pull = pull,
       _release = release,
       _signals = StreamController<void>.broadcast(sync: true) {
    try {
      for (final trigger in triggers) {
        final subscription = trigger().listen(
          (_) {
            if (!_closed) _signals.add(null);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_closed) _signals.addError(error, stackTrace);
          },
        );
        _subscriptions.add(subscription);
      }
    } catch (_) {
      for (final subscription in _subscriptions.reversed) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      unawaited(_signals.close());
      rethrow;
    }
  }

  final Future<Result<T, F>> Function(CancellationSignal signal) _pull;
  final PullSourceRelease? _release;
  final StreamController<void> _signals;
  final List<StreamSubscription<void>> _subscriptions =
      <StreamSubscription<void>>[];
  var _closed = false;
  Future<void>? _closeFuture;

  @override
  Stream<void> get signals => _signals.stream;

  @override
  Future<Result<T, F>> read(CancellationSignal signal) {
    if (_closed) {
      throw const CancellationException('Pull source session closed');
    }
    signal.throwIfCancelled();
    return _pull(signal);
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    Object? firstError;
    StackTrace? firstStack;
    for (final subscription in _subscriptions.reversed) {
      try {
        await subscription.cancel();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    _subscriptions.clear();
    await _signals.close();
    try {
      await _release?.call();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}
