import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

/// Equality-aware derived value owned independently from Flutter widgets.
final class ReactiveSelector<S extends Listenable, T>
    implements ValueListenable<T>, Disposable {
  /// Creates a selector and immediately subscribes to its borrowed [source].
  ReactiveSelector({
    required S source,
    required T Function(S source) select,
    bool Function(T previous, T next)? equals,
  }) : _source = source,
       _select = select,
       _equals = equals ?? _defaultEquals,
       _value = select(source) {
    _source.addListener(_sourceChanged);
  }

  final S _source;
  final T Function(S source) _select;
  final bool Function(T previous, T next) _equals;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  T _value;
  var _selectionCount = 1;
  var _notificationCount = 0;
  var _disposed = false;

  /// Latest distinct selected value.
  @override
  T get value {
    _ensureActive();
    return _value;
  }

  /// Number of selector evaluations, including the initial one.
  int get selectionCount => _selectionCount;

  /// Number of distinct publications made to downstream listeners.
  int get notificationCount => _notificationCount;

  /// Number of downstream callbacks retained by this selector.
  int get listenerCount => _listeners.length;

  /// Whether this selector has detached from its source.
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _source.removeListener(_sourceChanged);
    _listeners.clear();
  }

  void _sourceChanged() {
    if (_disposed) return;
    final next = _select(_source);
    _selectionCount += 1;
    if (_equals(_value, next)) return;
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
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ReactiveSelector is disposed.');
  }

  static bool _defaultEquals<T>(T previous, T next) => previous == next;
}
