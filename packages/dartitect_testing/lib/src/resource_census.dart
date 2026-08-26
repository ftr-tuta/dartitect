import 'package:dartitect/dartitect.dart';

/// Scoped resource counter used by teardown assertions without a test runner.
final class ResourceCensus {
  final Map<String, int> _live = <String, int>{};

  /// Acquires one named resource and returns its exact-once lease.
  CensusLease acquire(String kind) {
    if (kind.trim().isEmpty) {
      throw ArgumentError.value(kind, 'kind', 'must not be empty');
    }
    _live.update(kind, (value) => value + 1, ifAbsent: () => 1);
    return CensusLease._(this, kind);
  }

  /// Immutable positive counts by kind.
  Map<String, int> get live => Map<String, int>.unmodifiable(<String, int>{
    for (final entry in _live.entries)
      if (entry.value > 0) entry.key: entry.value,
  });

  /// Total live resources.
  int get total => _live.values.fold<int>(0, (sum, value) => sum + value);

  /// Throws with bounded kind/count evidence when anything remains.
  void verifyZero() {
    if (total != 0) {
      throw StateError('Resource census is not zero: $live');
    }
  }

  void _release(String kind) {
    final count = _live[kind] ?? 0;
    if (count <= 0) throw StateError('Census underflow for $kind.');
    if (count == 1) {
      _live.remove(kind);
    } else {
      _live[kind] = count - 1;
    }
  }
}

/// Exact-once census registration.
final class CensusLease implements Disposable {
  CensusLease._(this._owner, this.kind);

  final ResourceCensus _owner;

  /// Resource kind.
  final String kind;

  /// Whether the registration was released.
  bool isDisposed = false;

  @override
  void dispose() {
    if (isDisposed) return;
    isDisposed = true;
    _owner._release(kind);
  }
}
