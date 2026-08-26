import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'resource_lifecycle.dart';

/// Owned debounce node that publishes only the latest source value.
final class DebouncedReactiveValue<T>
    implements ValueListenable<T>, Disposable {
  /// Creates a node subscribed to the borrowed [source].
  DebouncedReactiveValue({
    required ValueListenable<T> source,
    required this.delay,
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
    bool Function(T previous, T next)? equals,
  }) : _source = source,
       _timerFactory = timerFactory,
       _equals = equals ?? _defaultEquals,
       _value = source.value {
    if (delay <= Duration.zero) {
      throw ArgumentError.value(delay, 'delay', 'Must be positive.');
    }
    _source.addListener(_sourceChanged);
  }

  final ValueListenable<T> _source;
  final ReactiveTimerFactory _timerFactory;
  final bool Function(T previous, T next) _equals;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  ReactiveTimerHandle? _timer;
  T _value;
  T? _pendingValue;
  var _hasPendingValue = false;
  var _notificationCount = 0;
  var _disposed = false;

  /// Quiet period required before a pending value is published.
  final Duration delay;

  /// Latest published value.
  @override
  T get value {
    _ensureActive();
    return _value;
  }

  /// Whether a source value is waiting for the quiet period.
  bool get isPending => _hasPendingValue;

  /// Number of active timer handles owned by this node.
  int get activeTimerCount => (_timer?.isActive ?? false) ? 1 : 0;

  /// Number of distinct debounced publications.
  int get notificationCount => _notificationCount;

  /// Number of downstream callbacks retained by this node.
  int get listenerCount => _listeners.length;

  /// Whether this node has detached from its source.
  bool get isDisposed => _disposed;

  @override
  void addListener(VoidCallback listener) {
    _ensureActive();
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    final index = _listeners.indexOf(listener);
    if (index >= 0) _listeners.removeAt(index);
  }

  /// Publishes a pending value immediately, if it is distinct.
  bool flush() {
    _ensureActive();
    if (!_hasPendingValue) return false;
    _timer?.cancel();
    _timer = null;
    return _publishPending();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _source.removeListener(_sourceChanged);
    _timer?.cancel();
    _timer = null;
    _pendingValue = null;
    _hasPendingValue = false;
    _listeners.clear();
  }

  void _sourceChanged() {
    if (_disposed) return;
    _pendingValue = _source.value;
    _hasPendingValue = true;
    _timer?.cancel();
    _timer = _timerFactory.schedule(delay, _timerFired);
  }

  void _timerFired() {
    if (_disposed) return;
    _timer = null;
    _publishPending();
  }

  bool _publishPending() {
    if (!_hasPendingValue) return false;
    final next = _pendingValue as T;
    _pendingValue = null;
    _hasPendingValue = false;
    if (_equals(_value, next)) return false;
    _value = next;
    _notificationCount += 1;
    final snapshot = List<VoidCallback>.of(_listeners);
    for (final listener in snapshot) {
      if (_disposed || !_listeners.contains(listener)) continue;
      try {
        listener();
      } catch (_) {
        continue;
      }
    }
    return true;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('DebouncedReactiveValue is disposed.');
  }

  static bool _defaultEquals<T>(T previous, T next) => previous == next;
}
