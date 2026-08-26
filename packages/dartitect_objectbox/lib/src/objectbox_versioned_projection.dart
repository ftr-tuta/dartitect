import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';

/// Typed incremental projection from consumer-owned ObjectBox entities.
final class ObjectBoxVersionedProjection<E, K, T, V> {
  /// Creates an adapter from consumer-owned key, version, and projection logic.
  const ObjectBoxVersionedProjection({
    required K Function(E entity) keyOf,
    required V Function(E entity) versionOf,
    required T Function(E entity) project,
  }) : _keyOf = keyOf,
       _versionOf = versionOf,
       _project = project;

  final K Function(E entity) _keyOf;
  final V Function(E entity) _versionOf;
  final T Function(E entity) _project;

  /// Applies [entities] atomically and returns the number reprojected.
  int apply(LiveCollection<K, T> collection, Iterable<E> entities) {
    collection.update<E>(
      entities,
      keyOf: _keyOf,
      project: _project,
      versionOf: _versionOf,
      policy: CollectionUpdatePolicy.versionedByKey,
    );
    return collection.lastProjectionCount;
  }
}
