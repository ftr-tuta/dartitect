/// Invalid dataset dependency graph.
final class SyncDependencyGraphException<K> implements Exception {
  /// Creates a graph validation failure.
  const SyncDependencyGraphException(this.message, {this.key});

  /// Stable, payload-free explanation.
  final String message;

  /// Dataset key involved in the failure, when available.
  final K? key;

  @override
  String toString() => key == null
      ? 'SyncDependencyGraphException: $message'
      : 'SyncDependencyGraphException($key): $message';
}

/// Validated consumer-supplied DAG with stable topological ordering.
final class SyncDependencyGraph<K> {
  /// Validates [keys] and their direct [dependencies].
  ///
  /// Iterable order is retained as the stable tie breaker. Missing keys,
  /// self-edges, duplicate keys, and cycles fail before provider work starts.
  factory SyncDependencyGraph({
    required Iterable<K> keys,
    Map<K, Iterable<K>> dependencies = const <Never, Never>{},
  }) {
    final orderedKeys = <K>[];
    final seen = <K>{};
    for (final key in keys) {
      if (!seen.add(key)) {
        throw SyncDependencyGraphException<K>(
          'duplicate dataset key',
          key: key,
        );
      }
      orderedKeys.add(key);
    }
    final normalized = <K, List<K>>{};
    for (final key in orderedKeys) {
      final values = <K>[];
      final dependencySeen = <K>{};
      for (final dependency in dependencies[key] ?? <K>[]) {
        if (dependency == key) {
          throw SyncDependencyGraphException<K>('self dependency', key: key);
        }
        if (!seen.contains(dependency)) {
          throw SyncDependencyGraphException<K>(
            'dependency key is not declared',
            key: dependency,
          );
        }
        if (dependencySeen.add(dependency)) values.add(dependency);
      }
      normalized[key] = List<K>.unmodifiable(values);
    }
    for (final key in dependencies.keys) {
      if (!seen.contains(key)) {
        throw SyncDependencyGraphException<K>(
          'dataset key is not declared',
          key: key,
        );
      }
    }

    final visiting = <K>{};
    final visited = <K>{};
    void visit(K key) {
      if (visited.contains(key)) return;
      if (!visiting.add(key)) {
        throw SyncDependencyGraphException<K>('dependency cycle', key: key);
      }
      for (final dependency in normalized[key]!) {
        visit(dependency);
      }
      visiting.remove(key);
      visited.add(key);
    }

    for (final key in orderedKeys) {
      visit(key);
    }
    return SyncDependencyGraph<K>._(orderedKeys, normalized);
  }

  SyncDependencyGraph._(List<K> keys, Map<K, List<K>> dependencies)
    : keys = List<K>.unmodifiable(keys),
      dependencies = Map<K, List<K>>.unmodifiable(dependencies);

  /// Dataset keys in consumer-declared stable order.
  final List<K> keys;

  /// Direct prerequisites for every key.
  final Map<K, List<K>> dependencies;

  /// Returns whether [candidate] transitively depends on [dependency].
  bool dependsOn(K candidate, K dependency) {
    final pending = <K>[...?dependencies[candidate]];
    final visited = <K>{};
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (next == dependency) return true;
      if (visited.add(next)) pending.addAll(dependencies[next] ?? <K>[]);
    }
    return false;
  }

  /// Builds an immutable stable plan for [eligible] keys.
  SyncPlan<K> plan({Iterable<K>? eligible}) {
    final selected = eligible == null ? keys.toSet() : eligible.toSet();
    final unknown = selected.difference(keys.toSet());
    if (unknown.isNotEmpty) {
      throw SyncDependencyGraphException<K>(
        'eligible key is not declared',
        key: unknown.first,
      );
    }
    final order = <K>[];
    final emitted = <K>{};
    void emit(K key) {
      if (!selected.contains(key) || !emitted.add(key)) return;
      for (final dependency in dependencies[key]!) {
        if (selected.contains(dependency)) emit(dependency);
      }
      order.add(key);
    }

    for (final key in keys) {
      emit(key);
    }
    return SyncPlan<K>._(order, dependencies);
  }
}

/// Immutable stable execution order chosen from a validated graph.
final class SyncPlan<K> {
  SyncPlan._(List<K> order, Map<K, List<K>> dependencies)
    : order = List<K>.unmodifiable(order),
      dependencies = Map<K, List<K>>.unmodifiable(<K, List<K>>{
        for (final key in order)
          key: List<K>.unmodifiable(
            (dependencies[key] ?? <K>[]).where(order.contains),
          ),
      });

  /// Stable topological order.
  final List<K> order;

  /// Direct selected dependencies for every planned dataset.
  final Map<K, List<K>> dependencies;
}
