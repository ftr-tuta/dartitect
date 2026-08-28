import 'dart:collection';

import 'package:dartitect/dartitect.dart' show ValueEquality;

/// Immutable value wrapper for an ordered collection.
///
/// The source iterable is copied immediately. Elements remain responsible for
/// their own immutability; nested collection cycles are rejected eagerly.
final class ImmutableValueList<T> extends ValueEquality with IterableMixin<T> {
  /// Creates a defensive, structurally comparable list value.
  factory ImmutableValueList(Iterable<T> values) {
    final copy = List<T>.unmodifiable(List<T>.of(values));
    _rejectCycles(copy);
    return ImmutableValueList<T>._(copy);
  }

  const ImmutableValueList._(this._values);

  final List<T> _values;

  /// Reads the value at [index]. No mutable list interface is exposed.
  T operator [](int index) => _values[index];

  /// Whether a structurally equal [value] is retained.
  @override
  bool contains(Object? value) =>
      _values.any((candidate) => ValueEquality.equals(candidate, value));

  @override
  int get length => _values.length;

  @override
  Iterator<T> get iterator => _values.iterator;

  @override
  Iterable<Object?> get equalityFields => <Object?>[_values];
}

/// Immutable value wrapper for an unordered collection of unique values.
///
/// The source iterable is copied immediately. Elements remain responsible for
/// their own immutability; nested collection cycles are rejected eagerly.
final class ImmutableValueSet<T> extends ValueEquality with IterableMixin<T> {
  /// Creates a defensive, structurally comparable set value.
  factory ImmutableValueSet(Iterable<T> values) {
    final retained = <T>[];
    final hashes = <int, List<T>>{};
    for (final value in values) {
      final hash = ValueEquality.hash(value);
      final bucket = hashes.putIfAbsent(hash, () => <T>[]);
      if (bucket.any((candidate) => ValueEquality.equals(candidate, value))) {
        continue;
      }
      bucket.add(value);
      retained.add(value);
    }
    final copy = Set<T>.unmodifiable(Set<T>.of(retained));
    _rejectCycles(copy);
    return ImmutableValueSet<T>._(copy);
  }

  const ImmutableValueSet._(this._values);

  final Set<T> _values;

  /// Whether [value] is retained by this value set.
  @override
  bool contains(Object? value) =>
      _values.any((candidate) => ValueEquality.equals(candidate, value));

  @override
  int get length => _values.length;

  @override
  Iterator<T> get iterator => _values.iterator;

  @override
  Iterable<Object?> get equalityFields => <Object?>[_values];
}

/// Immutable value wrapper for key/value associations.
///
/// The source map is copied immediately and no mutable map interface is
/// implemented. Keys and values remain responsible for their own immutability;
/// nested collection cycles are rejected eagerly.
final class ImmutableValueMap<K, V> extends ValueEquality {
  /// Creates a defensive, structurally comparable map value.
  factory ImmutableValueMap(Map<K, V> values) {
    final entries = <MapEntry<K, V>>[];
    final hashes = <int, List<int>>{};
    for (final entry in values.entries) {
      final hash = ValueEquality.hash(entry.key);
      final bucket = hashes.putIfAbsent(hash, () => <int>[]);
      final existing = bucket.where(
        (index) => ValueEquality.equals(entries[index].key, entry.key),
      );
      if (existing.isNotEmpty) {
        final index = existing.first;
        entries[index] = MapEntry<K, V>(entries[index].key, entry.value);
      } else {
        bucket.add(entries.length);
        entries.add(MapEntry<K, V>(entry.key, entry.value));
      }
    }
    final copy = Map<K, V>.unmodifiable(Map<K, V>.fromEntries(entries));
    _rejectCycles(copy);
    return ImmutableValueMap<K, V>._(copy);
  }

  const ImmutableValueMap._(this._values);

  final Map<K, V> _values;

  /// Number of associations.
  int get length => _values.length;

  /// Whether the map contains no associations.
  bool get isEmpty => _values.isEmpty;

  /// Whether the map contains at least one association.
  bool get isNotEmpty => _values.isNotEmpty;

  /// Read-only keys in source iteration order.
  Iterable<K> get keys => _values.keys;

  /// Read-only values in source iteration order.
  Iterable<V> get values => _values.values;

  /// Read-only entries in source iteration order.
  Iterable<MapEntry<K, V>> get entries => _values.entries;

  /// Reads the value associated with [key].
  V? operator [](Object? key) {
    for (final entry in _values.entries) {
      if (ValueEquality.equals(entry.key, key)) return entry.value;
    }
    return null;
  }

  /// Whether [key] is present.
  bool containsKey(Object? key) =>
      _values.keys.any((candidate) => ValueEquality.equals(candidate, key));

  /// Whether [value] is present.
  bool containsValue(Object? value) =>
      _values.values.any((candidate) => ValueEquality.equals(candidate, value));

  @override
  Iterable<Object?> get equalityFields => <Object?>[_values];
}

void _rejectCycles(Object collection) {
  ValueEquality.hash(collection);
}
