/// Immutable authoritative local value plus consumer-owned metadata.
final class ResourceSnapshot<T, M> {
  /// Creates a local snapshot.
  const ResourceSnapshot({
    required this.value,
    required this.metadata,
    required this.revision,
    required this.observedAt,
    required this.isStale,
  });

  /// Authoritative local value used by presentation.
  final T value;

  /// Consumer-defined metadata; Dartitect never persists or interprets it.
  final M metadata;

  /// Consumer-defined monotonic causal revision.
  final int revision;

  /// Instant at which the local value was observed.
  final DateTime observedAt;

  /// Whether the consumer considers this snapshot older than an invalidation.
  final bool isStale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceSnapshot<T, M> &&
          value == other.value &&
          metadata == other.metadata &&
          revision == other.revision &&
          observedAt == other.observedAt &&
          isStale == other.isStale;

  @override
  int get hashCode =>
      Object.hash(value, metadata, revision, observedAt, isStale);

  @override
  String toString() =>
      'ResourceSnapshot<$T, $M>(revision: $revision, '
      'observedAt: $observedAt, isStale: $isStale)';
}
