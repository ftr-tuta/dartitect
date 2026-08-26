import 'dart:collection';

/// Raised when structural equality encounters a cyclic collection graph.
///
/// Dartitect value models are deliberately acyclic. Rejecting cycles keeps
/// equality and hashing deterministic without retaining an object graph.
final class CyclicValueException implements Exception {
  /// Creates a cycle failure for the operation being performed.
  const CyclicValueException(this.operation);

  /// `equality` or `hashing`.
  final String operation;

  @override
  String toString() =>
      'CyclicValueException: cyclic collections are not supported during '
      '$operation.';
}

/// Structural equality and hashing for small, immutable, acyclic values.
///
/// Lists retain order. Sets and maps ignore iteration order. Nested lists,
/// sets, and maps are compared recursively; records and unknown objects use
/// their own `==` and `hashCode` contracts.
abstract class ValueEquality {
  /// Allows immutable subclasses to be `const`.
  const ValueEquality();

  /// Fields that define this value, in stable declaration order.
  Iterable<Object?> get equalityFields;

  /// Deeply compares two acyclic values.
  static bool equals(Object? left, Object? right) =>
      _DeepValueEquality().equals(left, right);

  /// Computes a hash compatible with [equals].
  static int hash(Object? value) => _DeepValueEquality().hash(value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is ValueEquality &&
          equals(equalityFields.toList(), other.equalityFields.toList());

  @override
  int get hashCode => Object.hash(runtimeType, hash(equalityFields.toList()));
}

/// Creates a defensive, unmodifiable list container.
List<T> immutableListCopy<T>(Iterable<T> values) =>
    List<T>.unmodifiable(List<T>.of(values));

/// Creates a defensive, unmodifiable set container.
Set<T> immutableSetCopy<T>(Iterable<T> values) =>
    Set<T>.unmodifiable(Set<T>.of(values));

/// Creates a defensive, unmodifiable map container.
Map<K, V> immutableMapCopy<K, V>(Map<K, V> values) =>
    Map<K, V>.unmodifiable(Map<K, V>.of(values));

final class _DeepValueEquality {
  final Set<Object> _leftActive = HashSet<Object>.identity();
  final Set<Object> _rightActive = HashSet<Object>.identity();
  final Set<Object> _hashActive = HashSet<Object>.identity();

  bool equals(Object? left, Object? right) {
    if (identical(left, right) && !_isCollection(left)) return true;
    if (left == null || right == null) return false;
    if (left is List<Object?> && right is List<Object?>) {
      return _withPair(left, right, () {
        if (left.length != right.length) return false;
        for (var index = 0; index < left.length; index += 1) {
          if (!equals(left[index], right[index])) return false;
        }
        return true;
      });
    }
    if (left is Set<Object?> && right is Set<Object?>) {
      return _withPair(left, right, () {
        if (left.length != right.length) return false;
        final unmatched = right.toList(growable: true);
        for (final value in left) {
          final index = unmatched.indexWhere(
            (candidate) => equals(value, candidate),
          );
          if (index < 0) return false;
          unmatched.removeAt(index);
        }
        return true;
      });
    }
    if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
      return _withPair(left, right, () {
        if (left.length != right.length) return false;
        final unmatched = right.entries.toList(growable: true);
        for (final entry in left.entries) {
          final index = unmatched.indexWhere(
            (candidate) =>
                equals(entry.key, candidate.key) &&
                equals(entry.value, candidate.value),
          );
          if (index < 0) return false;
          unmatched.removeAt(index);
        }
        return true;
      });
    }
    return left == right;
  }

  int hash(Object? value) {
    if (value == null) return 0;
    if (value is List<Object?>) {
      return _withHash(value, () {
        var result = 0x1f3d5b79;
        for (final item in value) {
          result = Object.hash(result, hash(item));
        }
        return Object.hash(value.length, result);
      });
    }
    if (value is Set<Object?>) {
      return _withHash(value, () => _unorderedHash(value.map(hash)));
    }
    if (value is Map<Object?, Object?>) {
      return _withHash(
        value,
        () => _unorderedHash(
          value.entries.map(
            (entry) => Object.hash(hash(entry.key), hash(entry.value)),
          ),
        ),
      );
    }
    return value.hashCode;
  }

  R _withPair<R>(Object left, Object right, R Function() body) {
    if (!_leftActive.add(left) || !_rightActive.add(right)) {
      throw const CyclicValueException('equality');
    }
    try {
      return body();
    } finally {
      _leftActive.remove(left);
      _rightActive.remove(right);
    }
  }

  R _withHash<R>(Object value, R Function() body) {
    if (!_hashActive.add(value)) {
      throw const CyclicValueException('hashing');
    }
    try {
      return body();
    } finally {
      _hashActive.remove(value);
    }
  }

  static bool _isCollection(Object? value) =>
      value is List<Object?> ||
      value is Set<Object?> ||
      value is Map<Object?, Object?>;

  static int _unorderedHash(Iterable<int> values) {
    var sum = 0;
    var xor = 0;
    var count = 0;
    for (final value in values) {
      final mixed = value ^ (value >>> 16);
      sum = (sum + mixed) & 0x3fffffff;
      xor ^= mixed;
      count += 1;
    }
    return Object.hash(count, sum, xor);
  }
}
