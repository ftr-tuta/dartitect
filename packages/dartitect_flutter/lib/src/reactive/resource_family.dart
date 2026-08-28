import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'lifecycle_barrier.dart';
import 'live_resource.dart';
import 'resource_lifecycle.dart';

/// Bounded retention policy for idle entries in a [ResourceFamily].
final class FamilyCachePolicy<K, T> {
  /// Creates a deterministic TTL, count, and weight policy.
  FamilyCachePolicy({
    this.idleTtl = const Duration(minutes: 5),
    this.maxIdleEntries = 128,
    this.maxIdleWeight = 1024,
    int Function(K key, T? value)? weightOf,
    int Function(K key)? recreationCostOf,
  }) : weightOf = weightOf ?? _unitWeight,
       recreationCostOf = recreationCostOf ?? _zeroCost {
    if (idleTtl <= Duration.zero) {
      throw ArgumentError.value(idleTtl, 'idleTtl', 'Must be positive.');
    }
    if (maxIdleEntries < 0) {
      throw ArgumentError.value(
        maxIdleEntries,
        'maxIdleEntries',
        'Must not be negative.',
      );
    }
    if (maxIdleWeight < 0) {
      throw ArgumentError.value(
        maxIdleWeight,
        'maxIdleWeight',
        'Must not be negative.',
      );
    }
  }

  /// Maximum time an unretained entry remains idle.
  final Duration idleTtl;

  /// Maximum number of idle entries retained after reconciliation.
  final int maxIdleEntries;

  /// Maximum aggregate weight of idle entries after reconciliation.
  final int maxIdleWeight;

  /// Computes a positive weight from a key and optional retained value.
  final int Function(K key, T? value) weightOf;

  /// Computes a non-negative recreation cost used before LRU ordering.
  final int Function(K key) recreationCostOf;

  static int _unitWeight(Object? key, Object? value) => 1;

  static int _zeroCost(Object? key) => 0;
}

/// Explicit retain handle for one keyed family entry.
final class FamilyLease<K, T, F extends Object> {
  FamilyLease._(this._family, this.key, this._entry);

  ResourceFamily<K, T, F>? _family;
  _FamilyEntry<K, T, F>? _entry;

  /// Key retained by this lease.
  final K key;

  /// Whether this lease has already been released.
  bool get isReleased => _family == null;

  /// Shared resource retained by this lease.
  LiveResource<T, F> get resource {
    final entry = _entry;
    if (entry == null) throw StateError('FamilyLease is released.');
    return entry.resource;
  }

  /// Releases this lease and waits for resulting cache reconciliation.
  Future<void> release() async {
    final family = _family;
    final entry = _entry;
    if (family == null || entry == null) return;
    _family = null;
    _entry = null;
    family._release(entry);
    await family.settled;
  }
}

/// Owned keyed resource cache with deterministic bounded idle retention.
final class ResourceFamily<K, T, F extends Object> implements AsyncDisposable {
  /// Creates an isolated family that owns every resource returned by [create].
  ResourceFamily({
    required LiveResource<T, F> Function(K key) create,
    FamilyCachePolicy<K, T>? policy,
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
    Future<void> Function(LiveResource<T, F> resource)? disposeResource,
    DartitectDiagnosticSubject? diagnostics,
  }) : _create = create,
       policy = policy ?? FamilyCachePolicy<K, T>(),
       _timerFactory = timerFactory,
       _diagnostics = diagnostics,
       _disposeResource =
           disposeResource ?? ((resource) => resource.dispose()) {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.family) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'ResourceFamily requires a family diagnostic subject.',
      );
    }
  }

  final LiveResource<T, F> Function(K key) _create;
  final ReactiveTimerFactory _timerFactory;
  final Future<void> Function(LiveResource<T, F> resource) _disposeResource;
  final DartitectDiagnosticSubject? _diagnostics;
  final Map<K, _FamilyEntry<K, T, F>> _entries = <K, _FamilyEntry<K, T, F>>{};
  final Set<_FamilyPrewarm<K, T, F>> _prewarms = <_FamilyPrewarm<K, T, F>>{};
  final InvalidationGroup<K> _invalidations = InvalidationGroup<K>();
  final List<K> _evictionTranscript = <K>[];
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposeFuture;
  Object? _transitionError;
  StackTrace? _transitionStackTrace;
  var _ordinal = 0;
  var _accessSequence = 0;
  var _idleWeight = 0;
  var _peakIdleWeight = 0;
  var _disposed = false;

  /// Applied idle cache policy.
  final FamilyCachePolicy<K, T> policy;

  /// Number of indexed entries, excluding entries already being disposed.
  int get entryCount => _entries.length;

  /// Number of currently evictable idle entries.
  int get idleEntryCount => _entries.values.where((entry) => entry.idle).length;

  /// Aggregate weight of currently idle entries.
  int get idleWeight => _idleWeight;

  /// Highest transient idle weight observed before deterministic enforcement.
  int get peakIdleWeight => _peakIdleWeight;

  /// Active TTL and prewarm timers owned by this family.
  int get activeTimerCount =>
      _prewarms.where((prewarm) => prewarm.timer?.isActive ?? false).length +
      _entries.values
          .where((entry) => entry.idleTimer?.isActive ?? false)
          .length;

  /// Stable eviction order observed so far.
  List<K> get evictionTranscript => List<K>.unmodifiable(_evictionTranscript);

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Latest serialized cache transition and any deferred cleanup failure.
  Future<void> get settled async {
    while (true) {
      final tail = _tail;
      await tail;
      if (identical(tail, _tail)) break;
    }
    final error = _transitionError;
    if (error != null) {
      final stackTrace = _transitionStackTrace!;
      _transitionError = null;
      _transitionStackTrace = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Acquires an explicit lease, sharing one resource for an equal key.
  FamilyLease<K, T, F> acquire(K key) {
    _ensureActive();
    final entry = _obtain(key);
    _retain(entry);
    _diagnostics?.emit(
      DartitectDiagnosticPhase.updated,
      revision: _entries.length,
    );
    return FamilyLease<K, T, F>._(this, key, entry);
  }

  /// Invalidates all currently indexed resources matching [key].
  int invalidate(K key) {
    _ensureActive();
    return _invalidations.invalidate(key);
  }

  /// Invalidates a typed subset of currently indexed resources.
  int invalidateWhere(bool Function(K key) predicate) {
    _ensureActive();
    return _invalidations.invalidateWhere(predicate);
  }

  /// Retains and activates [key] for at least [duration].
  Future<void> prewarm(K key, Duration duration) async {
    _ensureActive();
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive.');
    }
    final entry = _obtain(key);
    _retain(entry);
    final observation = entry.resource.observe();
    void listener() {}
    final prewarm = _FamilyPrewarm<K, T, F>(entry, observation, listener);
    _prewarms.add(prewarm);
    observation.addListener(listener);
    try {
      await observation.settled;
      if (_disposed || prewarm.finished) {
        await _finishPrewarm(prewarm);
        return;
      }
      prewarm.timer = _timerFactory.schedule(
        duration,
        () => _schedule(() => _finishPrewarm(prewarm)),
      );
    } catch (error, stackTrace) {
      await _finishPrewarm(prewarm);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Disposes all timers, registrations, and resources exactly once.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  @override
  Future<void> disposeAsync() => dispose();

  _FamilyEntry<K, T, F> _obtain(K key) {
    final existing = _entries[key];
    if (existing != null) return existing;
    final resource = _create(key);
    if (resource.isDisposed) {
      throw StateError('ResourceFamily factory returned a disposed resource.');
    }
    late final _FamilyEntry<K, T, F> entry;
    void changed() => _queueReconcile(entry);
    entry = _FamilyEntry<K, T, F>(
      key: key,
      resource: resource,
      ordinal: _ordinal++,
      changed: changed,
    );
    _entries[key] = entry;
    entry.invalidationBinding = _invalidations.bind(key, resource);
    resource.addListener(changed);
    _touch(entry);
    return entry;
  }

  void _retain(_FamilyEntry<K, T, F> entry) {
    if (entry.idle) _leaveIdle(entry);
    entry.leaseCount += 1;
    _touch(entry);
  }

  void _release(_FamilyEntry<K, T, F> entry) {
    if (entry.leaseCount > 0) entry.leaseCount -= 1;
    _touch(entry);
    _queueReconcile(entry);
  }

  void _queueReconcile(_FamilyEntry<K, T, F> entry) {
    if (_disposed || entry.reconcileQueued) return;
    entry.reconcileQueued = true;
    _schedule(() async {
      entry.reconcileQueued = false;
      if (_disposed || !identical(_entries[entry.key], entry)) return;
      await _reconcileEntry(entry);
      await _enforceLimits();
    });
  }

  Future<void> _reconcileEntry(_FamilyEntry<K, T, F> entry) async {
    final active =
        entry.leaseCount > 0 ||
        entry.resource.observerCount > 0 ||
        entry.resource.temperature == ResourceTemperature.hot;
    if (active) {
      if (entry.idle) _leaveIdle(entry);
      return;
    }
    if (entry.idle) return;
    final value = entry.resource.state.hasData
        ? entry.resource.state.lastData
        : null;
    final weight = policy.weightOf(entry.key, value);
    final cost = policy.recreationCostOf(entry.key);
    if (weight <= 0) {
      await _evictInvalidPolicy(
        entry,
        StateError('Family weight must be positive for key ${entry.key}.'),
      );
      return;
    }
    if (cost < 0) {
      await _evictInvalidPolicy(
        entry,
        StateError(
          'Family recreation cost must not be negative for key ${entry.key}.',
        ),
      );
      return;
    }
    if (policy.maxIdleEntries == 0 || weight > policy.maxIdleWeight) {
      await _evictUnretained(entry);
      return;
    }
    entry
      ..idle = true
      ..expired = false
      ..weight = weight
      ..recreationCost = cost;
    _idleWeight += weight;
    if (_idleWeight > _peakIdleWeight) _peakIdleWeight = _idleWeight;
    entry.idleTimer = _timerFactory.schedule(policy.idleTtl, () {
      if (_disposed || !identical(_entries[entry.key], entry) || !entry.idle) {
        return;
      }
      entry.expired = true;
      _schedule(_enforceLimits);
    });
  }

  Future<void> _enforceLimits() async {
    while (true) {
      final idle = _entries.values.where((entry) => entry.idle).toList();
      final expired = idle.any((entry) => entry.expired);
      final overCount = idle.length > policy.maxIdleEntries;
      final overWeight = _idleWeight > policy.maxIdleWeight;
      if (!expired && !overCount && !overWeight) return;
      if (idle.isEmpty) return;
      idle.sort(_compareEviction);
      await _evict(idle.first);
    }
  }

  int _compareEviction(
    _FamilyEntry<K, T, F> left,
    _FamilyEntry<K, T, F> right,
  ) {
    if (left.expired != right.expired) return left.expired ? -1 : 1;
    final cost = left.recreationCost.compareTo(right.recreationCost);
    if (cost != 0) return cost;
    final access = left.lastAccess.compareTo(right.lastAccess);
    if (access != 0) return access;
    return left.ordinal.compareTo(right.ordinal);
  }

  Future<void> _evict(_FamilyEntry<K, T, F> entry) async {
    if (!entry.idle || !identical(_entries[entry.key], entry)) return;
    await _evictUnretained(entry);
  }

  Future<void> _evictUnretained(_FamilyEntry<K, T, F> entry) async {
    _evictionTranscript.add(entry.key);
    _diagnostics?.emit(
      DartitectDiagnosticPhase.evicted,
      revision: _evictionTranscript.length,
    );
    try {
      await _removeAndDispose(entry);
    } catch (error, stackTrace) {
      throw AsyncLifecycleCleanupException(<AsyncLifecycleCleanupFailure>[
        AsyncLifecycleCleanupFailure(error, stackTrace),
      ]);
    }
  }

  Future<void> _evictInvalidPolicy(
    _FamilyEntry<K, T, F> entry,
    Object error,
  ) async {
    final stackTrace = StackTrace.current;
    _evictionTranscript.add(entry.key);
    try {
      await _removeAndDispose(entry);
    } catch (disposeError, disposeStackTrace) {
      throw AsyncLifecycleCleanupException(<AsyncLifecycleCleanupFailure>[
        AsyncLifecycleCleanupFailure(error, stackTrace),
        AsyncLifecycleCleanupFailure(disposeError, disposeStackTrace),
      ]);
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  Future<void> _removeAndDispose(_FamilyEntry<K, T, F> entry) async {
    if (!identical(_entries[entry.key], entry)) return;
    _entries.remove(entry.key);
    if (entry.idle) _leaveIdle(entry);
    entry.invalidationBinding?.dispose();
    entry.invalidationBinding = null;
    entry.resource.removeListener(entry.changed);
    await _disposeResource(entry.resource);
  }

  void _leaveIdle(_FamilyEntry<K, T, F> entry) {
    if (!entry.idle) return;
    entry.idleTimer?.cancel();
    entry.idleTimer = null;
    _idleWeight -= entry.weight;
    entry
      ..idle = false
      ..expired = false
      ..weight = 0;
  }

  void _touch(_FamilyEntry<K, T, F> entry) {
    _accessSequence += 1;
    entry.lastAccess = _accessSequence;
  }

  Future<void> _finishPrewarm(_FamilyPrewarm<K, T, F> prewarm) async {
    if (prewarm.finished) return;
    prewarm.finished = true;
    prewarm.timer?.cancel();
    prewarm.timer = null;
    _prewarms.remove(prewarm);
    prewarm.observation.removeListener(prewarm.listener);
    await prewarm.observation.settled;
    await prewarm.observation.close();
    final entry = prewarm.entry;
    if (entry.leaseCount > 0) entry.leaseCount -= 1;
    _touch(entry);
    if (!_disposed && identical(_entries[entry.key], entry)) {
      await _reconcileEntry(entry);
      await _enforceLimits();
    }
  }

  void _schedule(Future<void> Function() operation) {
    if (_disposed) return;
    _tail = _tail
        .then<void>(
          (_) => operation(),
          onError: (Object _, StackTrace _) => operation(),
        )
        .catchError((Object error, StackTrace stackTrace) {
          _transitionError ??= error;
          _transitionStackTrace ??= stackTrace;
        });
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _diagnostics?.emit(
      DartitectDiagnosticPhase.started,
      revision: _entries.length,
    );
    final failures = <AsyncLifecycleCleanupFailure>[];
    await _tail;
    final transitionError = _transitionError;
    if (transitionError != null) {
      failures.add(
        AsyncLifecycleCleanupFailure(transitionError, _transitionStackTrace!),
      );
      _transitionError = null;
      _transitionStackTrace = null;
    }
    for (final prewarm in _prewarms.toList(growable: false).reversed) {
      try {
        await _finishPrewarm(prewarm);
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    _invalidations.dispose();
    for (final entry in _entries.values.toList(growable: false).reversed) {
      try {
        await _removeAndDispose(entry);
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    _entries.clear();
    _idleWeight = 0;
    if (failures.isNotEmpty) {
      _diagnostics?.emit(DartitectDiagnosticPhase.crashed);
      throw AsyncLifecycleCleanupException(
        List<AsyncLifecycleCleanupFailure>.unmodifiable(failures),
      );
    }
    _diagnostics?.emit(DartitectDiagnosticPhase.disposed);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ResourceFamily is disposed.');
  }
}

final class _FamilyEntry<K, T, F extends Object> {
  _FamilyEntry({
    required this.key,
    required this.resource,
    required this.ordinal,
    required this.changed,
  });

  final K key;
  final LiveResource<T, F> resource;
  final int ordinal;
  final VoidCallback changed;
  InvalidationBinding<K>? invalidationBinding;
  ReactiveTimerHandle? idleTimer;
  var leaseCount = 0;
  var lastAccess = 0;
  var weight = 0;
  var recreationCost = 0;
  var idle = false;
  var expired = false;
  var reconcileQueued = false;
}

final class _FamilyPrewarm<K, T, F extends Object> {
  _FamilyPrewarm(this.entry, this.observation, this.listener);

  final _FamilyEntry<K, T, F> entry;
  final ReactiveObservation<T, F> observation;
  final VoidCallback listener;
  ReactiveTimerHandle? timer;
  var finished = false;
}
