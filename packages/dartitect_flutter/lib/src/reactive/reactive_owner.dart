import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'live_resource.dart';

/// Equality used to suppress unchanged reactive publication.
typedef Equality<T> = bool Function(T previous, T next);

/// Reports an unexpected failure while a reactive computed is evaluated.
abstract interface class ReactiveComputeReporter {
  /// Reports [error] with its original [stackTrace].
  void report(Object error, StackTrace stackTrace);
}

/// A reporter that deliberately ignores compute failures.
final class NoOpReactiveComputeReporter implements ReactiveComputeReporter {
  /// Creates a no-op reporter.
  const NoOpReactiveComputeReporter();

  @override
  void report(Object error, StackTrace stackTrace) {}
}

/// An explicit, typed identity used to share a node inside one owner.
final class ReactiveKey<T> {
  /// Creates a key with a stable, non-empty [name].
  const ReactiveKey(this.name) : assert(name != '');

  /// Human-readable static name of this key.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ReactiveKey<T> && other.name == name;

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => 'ReactiveKey<$T>($name)';
}

/// Base type for values and derived values owned by a [ReactiveOwner].
sealed class ReactiveNode<T> extends _ReactiveNodeBase
    implements ValueListenable<T> {
  ReactiveNode(
    super.owner,
    super.ordinal,
    super.initialValue,
    this.equality,
    this.usesDefaultEquality,
  );

  /// Equality policy selected when this node was created.
  final Equality<T> equality;

  /// Whether this node uses the documented `==` equality default.
  final bool usesDefaultEquality;

  /// Last stable value published by the owner.
  T get value {
    owner._ensureActive();
    return stableValue as T;
  }

  /// Revision of the logical owner commit that last changed this node.
  int get revision => nodeRevision;

  /// Number of active callbacks observing this node.
  int get listenerCount => listeners.length;

  @override
  void addListener(VoidCallback listener) {
    owner._ensureActive();
    listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    final index = listeners.indexOf(listener);
    if (index >= 0) listeners.removeAt(index);
  }

  @override
  bool valuesEqual(Object? previous, Object? next) =>
      equality(previous as T, next as T);
}

/// A directly writable node.
final class ReactiveValue<T> extends ReactiveNode<T> {
  /// Creates an owner-internal writable node.
  ReactiveValue(
    super.owner,
    super.ordinal,
    super.initialValue,
    super.equality,
    super.usesDefaultEquality,
  );
}

/// A value derived from explicit dependencies.
final class ReactiveComputed<T> extends ReactiveNode<T> {
  /// Creates an owner-internal derived node.
  ReactiveComputed(
    super.owner,
    super.ordinal,
    super.initialValue,
    this.key,
    this._dependencies,
    this._compute,
    super.equality,
    super.usesDefaultEquality,
  );

  /// Typed identity used to share this computed inside its owner.
  final ReactiveKey<T> key;
  final List<_ReactiveNodeBase> _dependencies;
  final T Function(ReactiveRead read) _compute;
}

/// Read-only access supplied to a computed callback.
final class ReactiveRead {
  ReactiveRead._(this._owner, this._allowed);

  final ReactiveOwner _owner;
  final Set<_ReactiveNodeBase> _allowed;

  /// Reads one of the computed's explicitly declared dependencies.
  T read<T>(ReactiveNode<T> node) {
    if (!identical(node.owner, _owner) || !_allowed.contains(node)) {
      throw ArgumentError.value(
        node,
        'node',
        'A computed may read only its declared dependencies from this owner.',
      );
    }
    return _owner._read(node) as T;
  }
}

/// Write access supplied only for the duration of [ReactiveOwner.update].
final class ReactiveWriter {
  ReactiveWriter._(this._owner);

  final ReactiveOwner _owner;

  /// Stages [value] for [node] in the current outer transaction.
  void set<T>(ReactiveValue<T> node, T value) => _owner._write(node, value);

  /// Stages a value produced from the latest value in this transaction.
  void mutate<T>(ReactiveValue<T> node, T Function(T current) change) {
    set(node, change(_owner._read(node) as T));
  }
}

/// Immutable counters for lifecycle and leak assertions.
final class ReactiveOwnerDiagnostics {
  /// Creates a diagnostics snapshot.
  const ReactiveOwnerDiagnostics({
    required this.nodeCount,
    required this.edgeCount,
    required this.listenerCount,
    required this.pendingWriteCount,
    required this.disposed,
  });

  /// Nodes retained by the owner.
  final int nodeCount;

  /// Direct dependency edges retained by the owner.
  final int edgeCount;

  /// Callbacks retained by every node.
  final int listenerCount;

  /// Writes waiting for an outer or reentrant flush.
  final int pendingWriteCount;

  /// Whether the owner is terminal.
  final bool disposed;
}

/// Thrown when the owned dependency graph is cyclic.
final class ReactiveCycleException implements Exception {
  /// Creates a cycle error for [keys].
  const ReactiveCycleException(this.keys);

  /// Static computed keys participating in the cycle.
  final List<String> keys;

  @override
  String toString() => 'ReactiveCycleException(${keys.join(' -> ')})';
}

/// Thrown when an explicit key is reused for an incompatible node.
final class ReactiveKeyConflictException implements Exception {
  /// Creates a conflict for [key].
  const ReactiveKeyConflictException(this.key);

  /// Conflicting key description.
  final String key;

  @override
  String toString() => 'ReactiveKeyConflictException($key)';
}

/// Owns a local incremental graph and publishes atomic logical commits.
final class ReactiveOwner {
  /// Creates an isolated owner.
  ReactiveOwner({
    ReactiveComputeReporter reporter = const NoOpReactiveComputeReporter(),
    ReactiveObserverRegistration observer =
        const ReactiveObserverRegistration.borrowed(NoOpReactiveObserver()),
    ChangeCauseRegistry? causeRegistry,
    int Function()? monotonicMicroseconds,
  }) : _reporter = reporter,
       _observerRegistration = observer,
       _causeRegistry = causeRegistry ?? ChangeCauseRegistry(),
       _monotonicMicroseconds = monotonicMicroseconds {
    _events = SafeReactiveObserver(
      observer: observer.observer,
      onFailure: _report,
    );
    _eventStopwatch.start();
  }

  final ReactiveComputeReporter _reporter;
  final ReactiveObserverRegistration _observerRegistration;
  final ChangeCauseRegistry _causeRegistry;
  final int Function()? _monotonicMicroseconds;
  final Stopwatch _eventStopwatch = Stopwatch();
  late final SafeReactiveObserver _events;
  final List<_ReactiveNodeBase> _nodes = <_ReactiveNodeBase>[];
  final Map<Object, _ReactiveNodeBase> _keyed = <Object, _ReactiveNodeBase>{};
  Map<_ReactiveNodeBase, Object?>? _activeWrites;
  final Map<_ReactiveNodeBase, Object?> _deferredWrites =
      <_ReactiveNodeBase, Object?>{};
  final List<VoidCallback> _invalidationGroupDisposers = <VoidCallback>[];
  Map<_ReactiveNodeBase, Object?>? _pendingValues;
  var _depth = 0;
  var _revision = 0;
  var _notifying = false;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Current logical commit revision.
  int get revision => _revision;

  /// Whether this owner has begun terminal disposal.
  bool get isDisposed => _disposed;

  /// Observer failures isolated from graph behavior.
  int get observerFailureCount => _events.failureCount;

  /// Recursive observer emissions dropped to prevent loops.
  int get droppedReentrantEvents => _events.droppedReentrantEvents;

  /// Current counters suitable for deterministic leak assertions.
  ReactiveOwnerDiagnostics get diagnostics => ReactiveOwnerDiagnostics(
    nodeCount: _nodes.length,
    edgeCount: _nodes.whereType<ReactiveComputed<Object?>>().fold<int>(
      0,
      (count, node) => count + node._dependencies.length,
    ),
    listenerCount: _nodes.fold<int>(
      0,
      (count, node) => count + node.listeners.length,
    ),
    pendingWriteCount: (_activeWrites?.length ?? 0) + _deferredWrites.length,
    disposed: _disposed,
  );

  /// Creates or returns a value shared by [key] in this owner.
  ReactiveValue<T> value<T>(
    T initial, {
    ReactiveKey<T>? key,
    Equality<T>? equality,
  }) {
    _ensureActive();
    final resolvedEquality = equality ?? _defaultEquality;
    if (key != null) {
      final existing = _keyed[key];
      if (existing != null) {
        if (existing is ReactiveValue<T> &&
            ((equality == null && existing.usesDefaultEquality) ||
                identical(existing.equality, equality))) {
          return existing;
        }
        throw ReactiveKeyConflictException(key.toString());
      }
    }
    final node = ReactiveValue<T>(
      this,
      _nodes.length,
      initial,
      resolvedEquality,
      equality == null,
    );
    _nodes.add(node);
    if (key != null) _keyed[key] = node;
    return node;
  }

  /// Creates an invalidation group whose registrations this owner disposes.
  InvalidationGroup<K> invalidationGroup<K>() {
    _ensureActive();
    final group = InvalidationGroup<K>();
    _invalidationGroupDisposers.add(group.dispose);
    return group;
  }

  /// Creates or returns a computed shared by [key] in this owner.
  ReactiveComputed<T> computed<T>(
    ReactiveKey<T> key,
    Iterable<ReactiveNode<Object?>> dependencies,
    T Function(ReactiveRead read) compute, {
    Equality<T>? equality,
  }) {
    _ensureActive();
    final resolvedEquality = equality ?? _defaultEquality;
    final declared = dependencies.cast<_ReactiveNodeBase>().toList(
      growable: false,
    );
    if (declared.toSet().length != declared.length) {
      throw ArgumentError.value(
        dependencies,
        'dependencies',
        'Dependencies must be unique.',
      );
    }
    for (final dependency in declared) {
      if (!identical(dependency.owner, this) || !_nodes.contains(dependency)) {
        throw ArgumentError.value(
          dependency,
          'dependencies',
          'Every dependency must be an active node from this owner.',
        );
      }
    }
    final existing = _keyed[key];
    if (existing != null) {
      if (existing is! ReactiveComputed<T> ||
          !_sameNodes(existing._dependencies, declared) ||
          !((equality == null && existing.usesDefaultEquality) ||
              identical(existing.equality, equality))) {
        throw ReactiveKeyConflictException(key.toString());
      }
      return existing;
    }

    late final T initial;
    try {
      initial = compute(ReactiveRead._(this, declared.toSet()));
    } catch (error, stackTrace) {
      _report(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
    final node = ReactiveComputed<T>(
      this,
      _nodes.length,
      initial,
      key,
      declared,
      compute,
      resolvedEquality,
      equality == null,
    );
    _nodes.add(node);
    _keyed[key] = node;
    try {
      _topologicalComputeds();
    } catch (_) {
      _keyed.remove(key);
      _nodes.removeLast();
      rethrow;
    }
    return node;
  }

  /// Stages writes and publishes them as one atomic outer transaction.
  R update<R>(
    R Function(ReactiveWriter write) body, {
    ChangeCause cause = ChangeCauses.reactiveUpdate,
  }) {
    _ensureActive();
    final staticCause = _causeRegistry.requireStatic(cause);
    final outer = _depth == 0;
    final previousRevision = _revision;
    final started = outer ? _eventNow() : 0;
    if (outer) _activeWrites = <_ReactiveNodeBase, Object?>{};
    _depth += 1;
    late final R result;
    try {
      result = body(ReactiveWriter._(this));
    } catch (error, stackTrace) {
      _depth -= 1;
      if (outer) _activeWrites = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
    _depth -= 1;
    if (outer) {
      final writes = _activeWrites!;
      _activeWrites = null;
      var eventKind = ReactiveEventKind.updated;
      try {
        if (_notifying) {
          _deferredWrites.addAll(writes);
        } else {
          _drainFlushes(writes);
        }
      } catch (error, stackTrace) {
        eventKind = ReactiveEventKind.crashed;
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        if (_revision != previousRevision ||
            eventKind == ReactiveEventKind.crashed) {
          _events.onChange(
            ReactiveChangeEvent(
              source: ReactiveEventSource.reactiveOwner,
              kind: eventKind,
              cause: staticCause,
              previousRevision: previousRevision,
              nextRevision: _revision,
              duration: _eventDuration(started),
              listenerCount: diagnostics.listenerCount,
            ),
          );
        }
      }
    }
    return result;
  }

  /// Marks this owner terminal and releases every node and listener.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _activeWrites = null;
    _deferredWrites.clear();
    _pendingValues = null;
    for (final disposeGroup in _invalidationGroupDisposers.reversed) {
      disposeGroup();
    }
    _invalidationGroupDisposers.clear();
    for (final node in _nodes.reversed) {
      node.listeners.clear();
    }
    _keyed.clear();
    _nodes.clear();
    await _observerRegistration.disposeOwned();
  }

  Object? _read(_ReactiveNodeBase node) {
    if (!identical(node.owner, this)) {
      throw ArgumentError.value(node, 'node', 'Node belongs to another owner.');
    }
    final writes = _activeWrites;
    if (writes != null && writes.containsKey(node)) return writes[node];
    final pending = _pendingValues;
    if (pending != null && pending.containsKey(node)) return pending[node];
    return node.stableValue;
  }

  void _write<T>(ReactiveValue<T> node, T value) {
    _ensureActive();
    if (!identical(node.owner, this)) {
      throw ArgumentError.value(node, 'node', 'Node belongs to another owner.');
    }
    final writes = _activeWrites;
    if (writes == null) {
      throw StateError('Reactive writes are allowed only inside update().');
    }
    writes[node] = value;
  }

  void _drainFlushes(Map<_ReactiveNodeBase, Object?> firstWrites) {
    var writes = firstWrites;
    Object? notificationError;
    StackTrace? notificationStackTrace;
    while (writes.isNotEmpty) {
      final failure = _flushCycle(writes);
      notificationError ??= failure?.error;
      notificationStackTrace ??= failure?.stackTrace;
      writes = Map<_ReactiveNodeBase, Object?>.of(_deferredWrites);
      _deferredWrites.clear();
      if (_disposed) break;
    }
    if (notificationError != null) {
      Error.throwWithStackTrace(notificationError, notificationStackTrace!);
    }
  }

  _NotificationFailure? _flushCycle(Map<_ReactiveNodeBase, Object?> writes) {
    _ensureActive();
    final pending = <_ReactiveNodeBase, Object?>{};
    final changed = <_ReactiveNodeBase>{};
    for (final entry in writes.entries) {
      if (!entry.key.valuesEqual(entry.key.stableValue, entry.value)) {
        pending[entry.key] = entry.value;
        changed.add(entry.key);
      }
    }
    if (changed.isEmpty) return null;

    _pendingValues = pending;
    try {
      for (final computed in _topologicalComputeds()) {
        if (!computed._dependencies.any(changed.contains)) continue;
        final next = computed._compute(
          ReactiveRead._(this, computed._dependencies.toSet()),
        );
        if (!computed.valuesEqual(computed.stableValue, next)) {
          pending[computed] = next;
          changed.add(computed);
        }
      }
    } catch (error, stackTrace) {
      _pendingValues = null;
      _report(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
    _pendingValues = null;

    _revision += 1;
    final ordered = changed.toList()
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    for (final node in ordered) {
      node
        ..stableValue = pending[node]
        ..nodeRevision = _revision;
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    _notifying = true;
    try {
      for (final node in ordered) {
        if (_disposed) break;
        final failure = node.notifyListenersSafely();
        firstError ??= failure?.error;
        firstStackTrace ??= failure?.stackTrace;
      }
    } finally {
      _notifying = false;
    }
    return firstError == null
        ? null
        : _NotificationFailure(firstError, firstStackTrace!);
  }

  List<ReactiveComputed<Object?>> _topologicalComputeds() {
    final computeds = _nodes.whereType<ReactiveComputed<Object?>>().toList();
    final indegree = <ReactiveComputed<Object?>, int>{
      for (final node in computeds)
        node: node._dependencies.whereType<ReactiveComputed<Object?>>().length,
    };
    final ready = computeds.where((node) => indegree[node] == 0).toList()
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    final result = <ReactiveComputed<Object?>>[];
    while (ready.isNotEmpty) {
      final node = ready.removeAt(0);
      result.add(node);
      for (final candidate in computeds) {
        if (!candidate._dependencies.contains(node)) continue;
        final next = indegree[candidate]! - 1;
        indegree[candidate] = next;
        if (next == 0) {
          ready.add(candidate);
          ready.sort((left, right) => left.ordinal.compareTo(right.ordinal));
        }
      }
    }
    if (result.length != computeds.length) {
      final cyclic = computeds
          .where((node) => !result.contains(node))
          .map((node) => node.key.name)
          .toList(growable: false);
      throw ReactiveCycleException(cyclic);
    }
    return result;
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      _reporter.report(error, stackTrace);
    } catch (_) {
      // Reporting is deliberately isolated from graph behavior.
      return;
    }
  }

  int _eventNow() {
    try {
      return _monotonicMicroseconds?.call() ??
          _eventStopwatch.elapsedMicroseconds;
    } on Object {
      return 0;
    }
  }

  Duration _eventDuration(int started) {
    final elapsed = _eventNow() - started;
    return Duration(microseconds: elapsed < 0 ? 0 : elapsed);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ReactiveOwner is disposed.');
  }
}

base class _ReactiveNodeBase {
  _ReactiveNodeBase(this.owner, this.ordinal, this.stableValue);

  final ReactiveOwner owner;
  final int ordinal;
  Object? stableValue;
  int nodeRevision = 0;
  final List<VoidCallback> listeners = <VoidCallback>[];

  bool valuesEqual(Object? previous, Object? next) => previous == next;

  _NotificationFailure? notifyListenersSafely() {
    Object? firstError;
    StackTrace? firstStackTrace;
    final snapshot = List<VoidCallback>.of(listeners);
    for (final listener in snapshot) {
      if (owner.isDisposed) break;
      if (!listeners.contains(listener)) continue;
      try {
        listener();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    return firstError == null
        ? null
        : _NotificationFailure(firstError, firstStackTrace!);
  }
}

bool _defaultEquality<T>(T previous, T next) => previous == next;

final class _NotificationFailure {
  const _NotificationFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

bool _sameNodes(List<_ReactiveNodeBase> left, List<_ReactiveNodeBase> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (!identical(left[index], right[index])) return false;
  }
  return true;
}
