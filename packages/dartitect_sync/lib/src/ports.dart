import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Consumer-owned persistence port for opaque dataset checkpoints.
abstract interface class SyncCheckpointStore<K, C> {
  /// Reads the latest confirmed checkpoint, or `null` when none exists.
  Future<C?> read(K key, CancellationSignal signal);

  /// Persists a checkpoint only after consumer-defined local coverage commits.
  ///
  /// When [fencingToken] is present, the implementation must atomically reject
  /// a token older than the latest lease observed by its persistence boundary.
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  });

  /// Removes a checkpoint explicitly.
  Future<void> remove(K key, CancellationSignal signal);
}

/// Exclusive run lease with expiry and a fencing token.
abstract interface class SyncLease {
  /// Consumer-safe owner/run identifier.
  String get ownerId;

  /// Monotonic store-issued token used to reject stale commits.
  int get fencingToken;

  /// Current expiry instant.
  DateTime get expiresAt;

  /// Extends the lease when this owner and fencing token are still current.
  Future<bool> renew(Duration ttl);

  /// Releases this lease idempotently.
  Future<void> release();
}

/// Consumer-owned mutual-exclusion port for synchronization runs.
abstract interface class SyncLeaseStore {
  /// Acquires a lease, or returns `null` when another live owner holds it.
  Future<SyncLease?> acquire({required String ownerId, required Duration ttl});
}

/// Injectable UTC clock used by deadlines, leases, reports, and tests.
abstract interface class SyncClock {
  /// Current UTC instant.
  DateTime now();
}

/// System UTC clock.
final class SystemSyncClock implements SyncClock {
  /// Creates a system clock.
  const SystemSyncClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Compatibility name for the core injectable identifier contract.
@Deprecated('Use IdGenerator from package:dartitect/dartitect.dart.')
typedef SyncIdGenerator = IdGenerator;

/// Isolate-local monotonic ID generator seeded from UTC time.
@Deprecated('Inject SecureUuidV4Generator or another IdGenerator.')
final class MonotonicSyncIdGenerator implements IdGenerator {
  /// Creates an isolate-local generator.
  MonotonicSyncIdGenerator({SyncClock clock = const SystemSyncClock()})
    : _clock = clock;

  final SyncClock _clock;
  var _counter = 0;

  @override
  String nextId() {
    _counter += 1;
    return '${_clock.now().microsecondsSinceEpoch}-$_counter';
  }
}

/// Optional payload-free observer for sync lifecycle facts.
abstract interface class SyncObserver<K> {
  /// A run started.
  void runStarted(String runId, int datasetCount);

  /// A dataset step started.
  void datasetStarted(String runId, K key);

  /// A dataset step ended with [outcome].
  void datasetEnded(String runId, K key, String outcome);

  /// A run ended with [outcome].
  void runEnded(String runId, String outcome);
}

/// Observer that intentionally ignores sync facts.
final class NoOpSyncObserver<K> implements SyncObserver<K> {
  /// Creates a no-op observer.
  const NoOpSyncObserver();

  @override
  void datasetEnded(String runId, K key, String outcome) {}

  @override
  void datasetStarted(String runId, K key) {}

  @override
  void runEnded(String runId, String outcome) {}

  @override
  void runStarted(String runId, int datasetCount) {}
}
