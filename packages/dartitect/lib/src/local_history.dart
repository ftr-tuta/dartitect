import 'dart:async';

import 'lifecycle/contracts.dart';

/// Bounded undo/redo history for synchronous local values only.
///
/// This type has no callback or asynchronous operation API. It represents
/// reversible in-memory values and must not be used to claim reversal of HTTP,
/// uploads, synchronization, printing, persistence, or another external
/// effect.
final class BoundedLocalHistory<T> implements Disposable {
  /// Creates a history containing [initialValue].
  BoundedLocalHistory({
    required T initialValue,
    this.maxEntries = 64,
    this.maxWeight,
    int Function(T value)? weightOf,
    bool Function(T previous, T next)? equality,
  }) : _current = initialValue,
       _weightOf = weightOf ?? _unitWeight,
       _equality = equality ?? _defaultEquality {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
    }
    if (maxWeight != null && maxWeight! <= 0) {
      throw ArgumentError.value(maxWeight, 'maxWeight', 'Must be positive.');
    }
    _validateValue(initialValue);
    _validateWeight(initialValue);
  }

  /// Maximum total snapshots, including the current value.
  final int maxEntries;

  /// Optional maximum total consumer-defined weight.
  final int? maxWeight;

  final int Function(T value) _weightOf;
  final bool Function(T previous, T next) _equality;
  final List<T> _past = <T>[];
  final List<T> _future = <T>[];
  T _current;
  var _revision = 0;
  var _disposed = false;

  /// Current local value.
  T get value {
    _ensureActive();
    return _current;
  }

  /// Monotonic revision changed by edit, undo, or redo.
  int get revision => _revision;

  /// Whether an older value is retained.
  bool get canUndo => !_disposed && _past.isNotEmpty;

  /// Whether a reverted value is retained.
  bool get canRedo => !_disposed && _future.isNotEmpty;

  /// Number of retained snapshots, including the current value.
  int get retainedEntryCount =>
      _disposed ? 0 : _past.length + 1 + _future.length;

  /// Total consumer-defined retained weight.
  int get retainedWeight => _disposed
      ? 0
      : <T>[
          ..._past,
          _current,
          ..._future,
        ].fold<int>(0, (total, value) => total + _weight(value));

  /// Immutable oldest-to-newest undo values.
  List<T> get undoValues => List<T>.unmodifiable(_past);

  /// Immutable nearest-to-farthest redo values.
  List<T> get redoValues => List<T>.unmodifiable(_future.reversed);

  /// Records [next] and discards the redo branch.
  ///
  /// Returns `false` when equality suppresses the edit.
  bool edit(T next) {
    _ensureActive();
    _validateValue(next);
    _validateWeight(next);
    if (_equality(_current, next)) return false;
    _past.add(_current);
    _current = next;
    _future.clear();
    _revision += 1;
    _trimOldestPast();
    return true;
  }

  /// Restores the nearest older value, if one exists.
  bool undo() {
    _ensureActive();
    if (_past.isEmpty) return false;
    _future.add(_current);
    _current = _past.removeLast();
    _revision += 1;
    return true;
  }

  /// Reapplies the nearest reverted value, if one exists.
  bool redo() {
    _ensureActive();
    if (_future.isEmpty) return false;
    _past.add(_current);
    _current = _future.removeLast();
    _revision += 1;
    return true;
  }

  void _trimOldestPast() {
    while (_past.isNotEmpty && retainedEntryCount > maxEntries) {
      _past.removeAt(0);
    }
    final weightLimit = maxWeight;
    if (weightLimit == null) return;
    while (_past.isNotEmpty && retainedWeight > weightLimit) {
      _past.removeAt(0);
    }
  }

  void _validateValue(T value) {
    if (value is Function ||
        value is Future<Object?> ||
        value is Stream<Object?>) {
      throw ArgumentError.value(
        value,
        'value',
        'History accepts local values, not callbacks or asynchronous effects.',
      );
    }
  }

  void _validateWeight(T value) {
    final weight = _weight(value);
    final limit = maxWeight;
    if (limit != null && weight > limit) {
      throw ArgumentError.value(
        weight,
        'weightOf(value)',
        'One value cannot exceed maxWeight.',
      );
    }
  }

  int _weight(T value) {
    final weight = _weightOf(value);
    if (weight < 0) {
      throw ArgumentError.value(
        weight,
        'weightOf(value)',
        'Must not be negative.',
      );
    }
    return weight;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('BoundedLocalHistory is disposed.');
  }

  /// Clears every retained value and makes the history terminal.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _past.clear();
    _future.clear();
  }

  static int _unitWeight<T>(T _) => 1;

  static bool _defaultEquality<T>(T previous, T next) => previous == next;
}
