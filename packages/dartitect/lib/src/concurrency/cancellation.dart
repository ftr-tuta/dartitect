import 'dart:async';

import '../lifecycle/contracts.dart';

/// Cooperative cancellation observed by an asynchronous operation.
final class CancellationSignal {
  CancellationSignal._();

  final List<void Function(Object? reason)> _listeners =
      <void Function(Object? reason)>[];
  final Completer<Object?> _cancelled = Completer<Object?>();
  Object? _reason;

  /// Whether cancellation has been requested.
  bool get isCancelled => _cancelled.isCompleted;

  /// Optional static or provider-owned cancellation reason.
  Object? get reason => _reason;

  /// Completes once with the cancellation reason.
  Future<Object?> get whenCancelled => _cancelled.future;

  /// Throws [CancellationException] if cancellation was already requested.
  void throwIfCancelled() {
    if (isCancelled) throw CancellationException(_reason);
  }

  /// Registers a synchronous callback and returns explicit unregistration.
  CancellationRegistration register(void Function(Object? reason) listener) {
    if (isCancelled) {
      _invoke(listener, _reason);
      return CancellationRegistration._();
    }
    _listeners.add(listener);
    return CancellationRegistration._(() => _listeners.remove(listener));
  }

  void _cancel(Object? reason) {
    if (isCancelled) return;
    _reason = reason;
    _cancelled.complete(reason);
    final snapshot = List<void Function(Object?)>.of(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      _invoke(listener, reason);
    }
  }

  static void _invoke(void Function(Object?) listener, Object? reason) {
    try {
      listener(reason);
    } catch (_) {
      // Cancellation listeners are isolated from the source and each other.
      return;
    }
  }
}

/// Owns one [CancellationSignal] and may cancel it exactly once.
final class CancellationSource implements Disposable {
  /// Creates a cancellation source.
  CancellationSource() : signal = CancellationSignal._();

  /// Borrowed signal passed to operations.
  final CancellationSignal signal;

  /// Requests cooperative cancellation exactly once.
  void cancel([Object? reason]) => signal._cancel(reason);

  /// Cancels with a static disposal reason.
  @override
  void dispose() => cancel('CancellationSource disposed');
}

/// Explicit registration owned by the callback consumer.
final class CancellationRegistration implements Disposable {
  CancellationRegistration._([this._remove]);

  void Function()? _remove;

  /// Whether this callback has been unregistered.
  bool get isDisposed => _remove == null;

  /// Unregisters the callback idempotently.
  @override
  void dispose() {
    final remove = _remove;
    _remove = null;
    remove?.call();
  }
}

/// Expected cooperative cancellation control flow, not a domain failure.
final class CancellationException implements Exception {
  /// Creates a cancellation exception with an optional [reason].
  const CancellationException(this.reason);

  /// Cancellation reason supplied by the owner.
  final Object? reason;

  @override
  String toString() => reason == null
      ? 'CancellationException'
      : 'CancellationException($reason)';
}
