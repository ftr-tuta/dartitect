import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

/// In-memory payload-free sync journal with deterministic fault injection.
final class InMemorySyncRunJournal<K> implements SyncRunJournal<K> {
  /// Durable entries retained across harness engine restarts.
  final List<SyncJournalEntry<K>> entries = <SyncJournalEntry<K>>[];

  /// Consumer-supplied incomplete attempt reconstruction.
  List<IncompleteSyncAttempt<K>> incomplete = <IncompleteSyncAttempt<K>>[];

  /// When true, the next append crashes and disarms this fault.
  bool crashNextAppend = false;

  @override
  Future<void> append(SyncJournalEntry<K> entry) async {
    if (crashNextAppend) {
      crashNextAppend = false;
      throw StateError('journal append fault');
    }
    entries.add(entry);
  }

  @override
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts() async =>
      List<IncompleteSyncAttempt<K>>.unmodifiable(incomplete);
}

/// Deterministic non-empty IDs for sync tests.
final class SequenceSyncIdGenerator implements IdGenerator {
  /// Creates a generator starting after [seed].
  SequenceSyncIdGenerator({this.prefix = 'run', int seed = 0}) : _next = seed;

  /// Static identifier prefix.
  final String prefix;

  int _next;

  @override
  String nextId() {
    _next += 1;
    return '$prefix-$_next';
  }
}

/// In-memory opaque checkpoint port with explicit operation recordings.
final class InMemorySyncCheckpointStore<K, C>
    implements SyncCheckpointStore<K, C> {
  /// Creates a store seeded by [values].
  InMemorySyncCheckpointStore([Map<K, C> values = const <Never, Never>{}])
    : values = Map<K, C>.of(values);

  /// Confirmed checkpoint values.
  final Map<K, C> values;

  /// Stable operation timeline without checkpoint payloads.
  final List<String> operations = <String>[];

  @override
  Future<C?> read(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    operations.add('read');
    return values[key];
  }

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    operations.add('remove');
    values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    operations.add('write');
    values[key] = checkpoint;
  }
}

/// Fault location for checkpoint crash/restart scenarios.
enum CheckpointFaultPoint {
  /// Before a checkpoint read.
  read,

  /// Before a checkpoint write.
  write,

  /// Before a checkpoint removal.
  remove,
}

/// Checkpoint port that injects one deterministic crash at a named boundary.
final class CheckpointCrashHarness<K, C> implements SyncCheckpointStore<K, C> {
  /// Wraps [delegate].
  CheckpointCrashHarness(this.delegate);

  /// Persistence port that retains state across simulated restarts.
  final SyncCheckpointStore<K, C> delegate;

  CheckpointFaultPoint? _armed;

  /// Arms one exact fault; it disarms itself after throwing.
  void arm(CheckpointFaultPoint point) => _armed = point;

  void _hit(CheckpointFaultPoint point) {
    if (_armed != point) return;
    _armed = null;
    throw StateError('checkpoint fault: ${point.name}');
  }

  @override
  Future<C?> read(K key, CancellationSignal signal) {
    _hit(CheckpointFaultPoint.read);
    return delegate.read(key, signal);
  }

  @override
  Future<void> remove(K key, CancellationSignal signal) {
    _hit(CheckpointFaultPoint.remove);
    return delegate.remove(key, signal);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) {
    _hit(CheckpointFaultPoint.write);
    return delegate.write(key, checkpoint, signal, fencingToken: fencingToken);
  }
}

/// Manual in-memory lease port with expiry and fencing semantics.
final class ManualSyncLeaseStore implements SyncLeaseStore {
  /// Creates a lease store using [clock].
  ManualSyncLeaseStore(this.clock);

  /// Injected clock; no process/global time is changed.
  final SyncClock clock;

  _ManualSyncLease? _current;
  var _fencingToken = 0;

  /// Current live lease count.
  int get liveLeaseCount =>
      _current != null && _current!.expiresAt.isAfter(clock.now()) ? 1 : 0;

  @override
  Future<SyncLease?> acquire({
    required String ownerId,
    required Duration ttl,
  }) async {
    final current = _current;
    if (current != null &&
        !current.isReleased &&
        current.expiresAt.isAfter(clock.now())) {
      return null;
    }
    _fencingToken += 1;
    final lease = _ManualSyncLease(
      store: this,
      ownerId: ownerId,
      fencingToken: _fencingToken,
      expiresAt: clock.now().add(ttl),
    );
    _current = lease;
    return lease;
  }

  bool _renew(_ManualSyncLease lease, Duration ttl) {
    if (!identical(_current, lease) ||
        lease.isReleased ||
        !lease.expiresAt.isAfter(clock.now())) {
      return false;
    }
    lease.expiresAt = clock.now().add(ttl);
    return true;
  }

  void _release(_ManualSyncLease lease) {
    lease.isReleased = true;
    if (identical(_current, lease)) _current = null;
  }
}

final class _ManualSyncLease implements SyncLease {
  _ManualSyncLease({
    required this.store,
    required this.ownerId,
    required this.fencingToken,
    required this.expiresAt,
  });

  final ManualSyncLeaseStore store;

  @override
  final String ownerId;

  @override
  final int fencingToken;

  @override
  DateTime expiresAt;

  bool isReleased = false;

  @override
  Future<void> release() async => store._release(this);

  @override
  Future<bool> renew(Duration ttl) async => store._renew(this, ttl);
}

/// Outcome captured by [SyncContractHarness] through the public run API.
final class SyncContractHarnessResult<K, C, F extends Object> {
  /// Creates a harness outcome.
  const SyncContractHarnessResult({
    required this.progress,
    required this.activeRunsAfterDispose,
    this.report,
    this.error,
    this.stackTrace,
  });

  /// Terminal report, when execution did not crash.
  final SyncReport<K, C, F>? report;

  /// Original unexpected crash.
  final Object? error;

  /// Original crash stack.
  final StackTrace? stackTrace;

  /// Monotonic progress retained by the run.
  final List<SyncProgressEvent<K>> progress;

  /// Residual engine run count after teardown.
  final int activeRunsAfterDispose;
}

/// Runs success/failure/crash/cancel scenarios through [SyncEngine.start].
final class SyncContractHarness<K, C, F extends Object> {
  /// Creates a harness that owns [engine] for one scenario.
  const SyncContractHarness(this.engine);

  /// Engine under contract test.
  final SyncEngine<K, C, F> engine;

  /// Runs, optionally cancelling immediately after admission, then disposes.
  Future<SyncContractHarnessResult<K, C, F>> run({
    Iterable<K>? eligible,
    bool cancelImmediately = false,
  }) async {
    final run = engine.start(eligible: eligible);
    if (cancelImmediately) run.cancel('harness cancellation');
    SyncReport<K, C, F>? report;
    Object? error;
    StackTrace? stackTrace;
    try {
      report = await run.done;
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    }
    final progress = List<SyncProgressEvent<K>>.of(run.progress.recent);
    await engine.disposeAsync();
    return SyncContractHarnessResult<K, C, F>(
      report: report,
      error: error,
      stackTrace: stackTrace,
      progress: List<SyncProgressEvent<K>>.unmodifiable(progress),
      activeRunsAfterDispose: engine.activeRunCount,
    );
  }
}
