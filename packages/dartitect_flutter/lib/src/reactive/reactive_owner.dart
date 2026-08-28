import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'live_resource.dart';

/// Equality used to suppress unchanged reactive publication.
typedef Equality<T> = bool Function(T previous, T next);

/// Reports an unexpected compute or post-commit listener failure.
abstract interface class ReactiveComputeReporter {
  /// Reports [error] with its original [stackTrace].
  void report(Object error, StackTrace stackTrace);
}

/// A reporter that deliberately ignores reactive runtime failures.
final class NoOpReactiveComputeReporter implements ReactiveComputeReporter {
  /// Creates a no-op reporter.
  const NoOpReactiveComputeReporter();

  @override
  void report(Object error, StackTrace stackTrace) {}
}

/// An explicit, typed definition identity used to share a node inside one
/// owner.
final class ReactiveKey<T> {
  /// Creates a namespaced key with explicit definition metadata.
  const ReactiveKey(
    this.name, {
    required this.namespace,
    required this.definitionRevision,
    required this.definitionFingerprint,
  }) : assert(name != ''),
       assert(namespace != ''),
       assert(definitionRevision > 0),
       assert(definitionFingerprint != '');

  /// Human-readable static name of this key.
  final String name;

  /// Static namespace that prevents unrelated features from sharing a node.
  final String namespace;

  /// Positive revision of the node definition.
  final int definitionRevision;

  /// Stable, non-empty fingerprint chosen by the definition owner.
  final String definitionFingerprint;

  /// Owner-independent identity used only inside one [ReactiveOwner].
  String get identity => '$namespace::$name<$T>';

  /// Full definition label used in diagnostics.
  String get definition =>
      '$identity@$definitionRevision#$definitionFingerprint';

  bool _hasSameDefinition(ReactiveKey<T> other) =>
      definitionRevision == other.definitionRevision &&
      definitionFingerprint == other.definitionFingerprint;

  @override
  bool operator ==(Object other) =>
      other is ReactiveKey<T> &&
      other.name == name &&
      other.namespace == namespace;

  @override
  int get hashCode => Object.hash(T, namespace, name);

  @override
  String toString() => 'ReactiveKey($definition)';
}

/// Observable phase of one [ReactiveOwner] state machine.
enum ReactiveOwnerPhase {
  /// No transaction or teardown is active.
  idle,

  /// An outer or nested update body is staging writes.
  write,

  /// Derived values are being evaluated against one pending snapshot.
  compute,

  /// A complete pending snapshot is being published atomically.
  commit,

  /// Stable committed values are notifying external listeners.
  notify,

  /// Terminal teardown has begun.
  dispose,

  /// Terminal teardown has completed.
  disposed,
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
    this.key,
    super.equality,
    super.usesDefaultEquality,
  );

  /// Typed definition identity when this value is shared by key.
  final ReactiveKey<T>? key;
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
  T Function(ReactiveRead read) _compute;
}

/// Read-only access to the explicit dependencies of a lazy computed value.
final class ReactiveLazyRead {
  ReactiveLazyRead._(this._owner, this._allowed);

  final ReactiveOwner _owner;
  final Set<ValueListenable<Object?>> _allowed;

  /// Reads one explicitly declared dependency.
  T read<T>(ValueListenable<T> dependency) {
    if (!_allowed.any((candidate) => identical(candidate, dependency))) {
      throw ArgumentError.value(
        dependency,
        'dependency',
        'A lazy computed may read only an explicitly declared dependency.',
      );
    }
    if (dependency case final ReactiveNode<T> node) {
      return _owner._read(node) as T;
    }
    return dependency.value;
  }
}

/// An owner-bound computed value evaluated only after first use.
///
/// Dependencies are supplied explicitly and resolved on first read or
/// observation. Once evaluated, this node listens only to those dependencies:
/// while unobserved it marks itself dirty, and while observed it recomputes
/// against the owner's complete committed revision. A failed computation
/// preserves the last valid value and remains dirty.
final class ReactiveLazyComputed<T> implements ValueListenable<T> {
  ReactiveLazyComputed._({
    required ReactiveOwner owner,
    required this.label,
    required Iterable<ValueListenable<Object?>> Function() dependencies,
    required T Function(ReactiveLazyRead read) compute,
    required Equality<T> equality,
    required this.usesDefaultEquality,
  }) : _owner = owner,
       _dependenciesProvider = dependencies,
       _compute = compute,
       equality = equality;

  final ReactiveOwner _owner;

  /// Static, payload-free definition label used for cycle diagnostics.
  final String label;

  /// Equality used to suppress unchanged publication.
  final Equality<T> equality;

  /// Whether equality uses the documented `==` default.
  final bool usesDefaultEquality;

  Iterable<ValueListenable<Object?>> Function() _dependenciesProvider;
  T Function(ReactiveLazyRead read) _compute;
  final List<ValueListenable<Object?>> _dependencies =
      <ValueListenable<Object?>>[];
  final List<VoidCallback> _listeners = <VoidCallback>[];
  Object? _stableValue;
  var _hasValue = false;
  var _dirty = true;
  var _bound = false;
  var _evaluating = false;
  var _disposed = false;
  var _revision = 0;

  /// Owner revision at which this node last published a changed value.
  int get revision => _revision;

  /// Whether a dependency changed after the last successful evaluation.
  bool get isDirty => _dirty;

  /// Number of callbacks currently observing this node.
  int get listenerCount => _listeners.length;

  /// Number of explicitly bound dependencies, or zero before first use.
  int get dependencyCount => _dependencies.length;

  /// Whether a valid value has been computed at least once.
  bool get hasValue => _hasValue;

  @override
  T get value {
    _ensureActive();
    _evaluate(throwOnFailure: true);
    return _stableValue as T;
  }

  @override
  void addListener(VoidCallback listener) {
    _ensureActive();
    if (_listeners.contains(listener)) return;
    _evaluate(throwOnFailure: true);
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Refreshes dependency and compute closures for Flutter hot reload.
  ///
  /// The retained value and equality policy remain unchanged. The node is
  /// marked dirty and an observed node recomputes immediately.
  void rebind({
    required Iterable<ValueListenable<Object?>> Function() dependencies,
    required T Function(ReactiveLazyRead read) compute,
  }) {
    _ensureActive();
    _owner._ensureDefinitionRegistrationAllowed();
    _detachDependencies();
    _dependenciesProvider = dependencies;
    _compute = compute;
    _dirty = true;
    if (_listeners.isNotEmpty) _evaluate(throwOnFailure: false);
  }

  void _bindDependencies() {
    if (_bound) return;
    final declared = _dependenciesProvider().toList(growable: false);
    if (declared.isEmpty) {
      throw ArgumentError.value(
        declared,
        'dependencies',
        'A lazy computed requires at least one explicit dependency.',
      );
    }
    if (_identityCount(declared) != declared.length) {
      throw ArgumentError.value(
        declared,
        'dependencies',
        'Dependencies must be identity-unique.',
      );
    }
    for (final dependency in declared) {
      final belongsToOwner = switch (dependency) {
        ReactiveNode<Object?>(:final owner) => identical(owner, _owner),
        ReactiveLazyComputed<Object?>() => identical(dependency._owner, _owner),
        _ => false,
      };
      if (!belongsToOwner) {
        throw ArgumentError.value(
          dependency,
          'dependencies',
          'Every dependency must belong to the same ReactiveOwner.',
        );
      }
    }
    _dependencies.addAll(declared);
    _bound = true;
    try {
      for (final dependency in _dependencies) {
        dependency.addListener(_dependencyChanged);
      }
    } catch (_) {
      _detachDependencies();
      rethrow;
    }
  }

  void _dependencyChanged() {
    if (_disposed || _owner.isDisposed) return;
    _dirty = true;
    if (_listeners.isNotEmpty) _evaluate(throwOnFailure: false);
  }

  void _evaluate({required bool throwOnFailure}) {
    if (_evaluating) {
      throw ReactiveCycleException(<String>[label, label]);
    }
    final previousPhase = _owner._phase;
    final hadValue = _hasValue;
    final previous = _stableValue;
    _evaluating = true;
    try {
      _bindDependencies();
      if (!_dirty) return;
      if (_owner.phase == ReactiveOwnerPhase.write ||
          _owner.phase == ReactiveOwnerPhase.compute ||
          _owner.phase == ReactiveOwnerPhase.commit) {
        throw StateError(
          'A dirty lazy computed cannot evaluate during '
          '${_owner.phase.name}.',
        );
      }
      _owner._phase = ReactiveOwnerPhase.compute;
      final next = _compute(ReactiveLazyRead._(_owner, _dependencies.toSet()));
      final changed = !hadValue || !equality(previous as T, next);
      _stableValue = next;
      _hasValue = true;
      _dirty = false;
      if (changed) {
        _revision = _owner.revision;
        if (hadValue) _notifyListeners();
      }
    } catch (error, stackTrace) {
      _dirty = true;
      _owner._report(error, stackTrace);
      if (!hadValue || throwOnFailure) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      _evaluating = false;
      if (!_owner.isDisposed) _owner._phase = previousPhase;
    }
  }

  void _notifyListeners() {
    final snapshot = List<VoidCallback>.of(_listeners);
    for (final listener in snapshot) {
      if (_disposed || _owner.isDisposed) break;
      if (!_listeners.contains(listener)) continue;
      try {
        listener();
      } catch (error, stackTrace) {
        _owner._report(error, stackTrace);
      }
    }
  }

  void _detachDependencies() {
    for (final dependency in _dependencies) {
      dependency.removeListener(_dependencyChanged);
    }
    _dependencies.clear();
    _bound = false;
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _detachDependencies();
    _listeners.clear();
    _stableValue = null;
    _hasValue = false;
    _dirty = true;
  }

  void _ensureActive() {
    _owner._ensureActive();
    if (_disposed) throw StateError('ReactiveLazyComputed is disposed.');
  }
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
  /// Creates a diagnosable definition conflict.
  const ReactiveKeyConflictException({
    required this.key,
    required this.existingDefinition,
    required this.incomingDefinition,
    required this.reason,
  });

  /// Conflicting owner-local key identity.
  final String key;

  /// Definition already registered by this owner.
  final String existingDefinition;

  /// Definition presented by the conflicting registration.
  final String incomingDefinition;

  /// Static explanation of the incompatibility.
  final String reason;

  @override
  String toString() =>
      'ReactiveKeyConflictException($key; $reason; '
      'existing: $existingDefinition; incoming: $incomingDefinition)';
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
  final List<ReactiveLazyComputed<Object?>> _lazyComputeds =
      <ReactiveLazyComputed<Object?>>[];
  final Map<Object, _ReactiveNodeBase> _keyed = <Object, _ReactiveNodeBase>{};
  Map<_ReactiveNodeBase, Object?>? _activeWrites;
  final Map<_ReactiveNodeBase, Object?> _deferredWrites =
      <_ReactiveNodeBase, Object?>{};
  final List<VoidCallback> _invalidationGroupDisposers = <VoidCallback>[];
  Map<_ReactiveNodeBase, Object?>? _pendingValues;
  var _depth = 0;
  var _revision = 0;
  var _phase = ReactiveOwnerPhase.idle;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Current logical commit revision.
  int get revision => _revision;

  /// Whether this owner has begun terminal disposal.
  bool get isDisposed => _disposed;

  /// Current write/compute/commit/notify/dispose phase.
  ReactiveOwnerPhase get phase => _phase;

  /// Observer failures isolated from graph behavior.
  int get observerFailureCount => _events.failureCount;

  /// Recursive observer emissions dropped to prevent loops.
  int get droppedReentrantEvents => _events.droppedReentrantEvents;

  /// Current counters suitable for deterministic leak assertions.
  ReactiveOwnerDiagnostics get diagnostics => ReactiveOwnerDiagnostics(
    nodeCount: _nodes.length + _lazyComputeds.length,
    edgeCount:
        _nodes.whereType<ReactiveComputed<Object?>>().fold<int>(
          0,
          (count, node) => count + node._dependencies.length,
        ) +
        _lazyComputeds.fold<int>(
          0,
          (count, node) => count + node.dependencyCount,
        ),
    listenerCount:
        _nodes.fold<int>(0, (count, node) => count + node.listeners.length) +
        _lazyComputeds.fold<int>(
          0,
          (count, node) => count + node.listenerCount,
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
    _ensureDefinitionRegistrationAllowed();
    final resolvedEquality = equality ?? _defaultEquality;
    if (key != null) {
      final existing = _keyed[key];
      if (existing != null) {
        if (existing is ReactiveValue<T> &&
            existing.key!._hasSameDefinition(key) &&
            ((equality == null && existing.usesDefaultEquality) ||
                identical(existing.equality, equality))) {
          return existing;
        }
        throw _keyConflict(
          existing,
          key,
          'value kind, definition, or equality differs',
        );
      }
    }
    final node = ReactiveValue<T>(
      this,
      _nodes.length,
      initial,
      key,
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
    _ensureDefinitionRegistrationAllowed();
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
    _ensureDefinitionRegistrationAllowed();
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
          !existing.key._hasSameDefinition(key) ||
          !_sameNodes(existing._dependencies, declared) ||
          !((equality == null && existing.usesDefaultEquality) ||
              identical(existing.equality, equality))) {
        throw _keyConflict(
          existing,
          key,
          'computed kind, definition, dependencies, or equality differs',
        );
      }
      existing._compute = compute;
      return existing;
    }

    late final T initial;
    try {
      _phase = ReactiveOwnerPhase.compute;
      initial = compute(ReactiveRead._(this, declared.toSet()));
    } catch (error, stackTrace) {
      _report(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!_disposed) _phase = ReactiveOwnerPhase.idle;
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

  /// Creates a lazily evaluated value with explicit owner-local dependencies.
  ReactiveLazyComputed<T> lazyComputed<T>({
    required String label,
    required Iterable<ValueListenable<Object?>> Function() dependencies,
    required T Function(ReactiveLazyRead read) compute,
    Equality<T>? equality,
  }) {
    _ensureActive();
    _ensureDefinitionRegistrationAllowed();
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'Must not be empty.');
    }
    final node = ReactiveLazyComputed<T>._(
      owner: this,
      label: label,
      dependencies: dependencies,
      compute: compute,
      equality: equality ?? _defaultEquality,
      usesDefaultEquality: equality == null,
    );
    _lazyComputeds.add(node as ReactiveLazyComputed<Object?>);
    return node;
  }

  /// Stages writes and publishes them as one atomic outer transaction.
  R update<R>(
    R Function(ReactiveWriter write) body, {
    ChangeCause cause = ChangeCauses.reactiveUpdate,
  }) {
    _ensureActive();
    if (_phase == ReactiveOwnerPhase.compute ||
        _phase == ReactiveOwnerPhase.commit) {
      throw StateError(
        'Reactive writes are not allowed during ${_phase.name}.',
      );
    }
    final staticCause = _causeRegistry.requireStatic(cause);
    final outer = _depth == 0;
    final previousPhase = _phase;
    final previousRevision = _revision;
    final started = outer ? _eventNow() : 0;
    if (outer) _activeWrites = <_ReactiveNodeBase, Object?>{};
    _phase = ReactiveOwnerPhase.write;
    _depth += 1;
    late final R result;
    try {
      result = body(ReactiveWriter._(this));
    } catch (error, stackTrace) {
      _depth -= 1;
      if (outer) _activeWrites = null;
      _phase = previousPhase;
      Error.throwWithStackTrace(error, stackTrace);
    }
    _depth -= 1;
    _phase = previousPhase;
    if (outer) {
      final writes = _activeWrites!;
      _activeWrites = null;
      var eventKind = ReactiveEventKind.updated;
      try {
        if (previousPhase == ReactiveOwnerPhase.notify) {
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
  Future<void> dispose() {
    if (!_disposed &&
        (_phase == ReactiveOwnerPhase.write ||
            _phase == ReactiveOwnerPhase.compute ||
            _phase == ReactiveOwnerPhase.commit)) {
      throw StateError(
        'ReactiveOwner cannot dispose during ${_phase.name}; '
        'finish or roll back the transaction first.',
      );
    }
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _phase = ReactiveOwnerPhase.dispose;
    _activeWrites = null;
    _deferredWrites.clear();
    _pendingValues = null;
    for (final disposeGroup in _invalidationGroupDisposers.reversed) {
      disposeGroup();
    }
    _invalidationGroupDisposers.clear();
    for (final computed in _lazyComputeds.reversed) {
      computed._dispose();
    }
    _lazyComputeds.clear();
    for (final node in _nodes.reversed) {
      node.listeners.clear();
    }
    _keyed.clear();
    _nodes.clear();
    try {
      await _observerRegistration.disposeOwned();
    } finally {
      _phase = ReactiveOwnerPhase.disposed;
    }
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
    while (writes.isNotEmpty) {
      _flushCycle(writes);
      writes = Map<_ReactiveNodeBase, Object?>.of(_deferredWrites);
      _deferredWrites.clear();
      if (_disposed) break;
    }
  }

  void _flushCycle(Map<_ReactiveNodeBase, Object?> writes) {
    _ensureActive();
    _phase = ReactiveOwnerPhase.compute;
    final pending = <_ReactiveNodeBase, Object?>{};
    final changed = <_ReactiveNodeBase>{};
    try {
      for (final entry in writes.entries) {
        if (!entry.key.valuesEqual(entry.key.stableValue, entry.value)) {
          pending[entry.key] = entry.value;
          changed.add(entry.key);
        }
      }
      if (changed.isEmpty) {
        _phase = ReactiveOwnerPhase.idle;
        return;
      }

      _pendingValues = pending;
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
      if (!_disposed) _phase = ReactiveOwnerPhase.idle;
      Error.throwWithStackTrace(error, stackTrace);
    }
    _pendingValues = null;

    _phase = ReactiveOwnerPhase.commit;
    _revision += 1;
    final ordered = changed.toList()
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    for (final node in ordered) {
      node
        ..stableValue = pending[node]
        ..nodeRevision = _revision;
    }

    _phase = ReactiveOwnerPhase.notify;
    try {
      for (final node in ordered) {
        if (_disposed) break;
        for (final failure in node.notifyListenersSafely()) {
          _report(failure.error, failure.stackTrace);
        }
      }
    } finally {
      if (!_disposed) _phase = ReactiveOwnerPhase.idle;
    }
  }

  ReactiveKeyConflictException _keyConflict<T>(
    _ReactiveNodeBase existing,
    ReactiveKey<T> incoming,
    String reason,
  ) {
    final existingKey = switch (existing) {
      ReactiveValue<Object?>(:final key) => key,
      ReactiveComputed<Object?>(:final key) => key,
      _ => null,
    };
    return ReactiveKeyConflictException(
      key: incoming.identity,
      existingDefinition: existingKey?.definition ?? '<unkeyed>',
      incomingDefinition: incoming.definition,
      reason: reason,
    );
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

  void _ensureDefinitionRegistrationAllowed() {
    if (_phase != ReactiveOwnerPhase.idle) {
      throw StateError(
        'Reactive definitions may be registered only while the owner is idle; '
        'current phase: ${_phase.name}.',
      );
    }
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

  List<_NotificationFailure> notifyListenersSafely() {
    final failures = <_NotificationFailure>[];
    final snapshot = List<VoidCallback>.of(listeners);
    for (final listener in snapshot) {
      if (owner.isDisposed) break;
      if (!listeners.contains(listener)) continue;
      try {
        listener();
      } catch (error, stackTrace) {
        failures.add(_NotificationFailure(error, stackTrace));
      }
    }
    return failures;
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

int _identityCount(List<Object?> values) {
  final unique = <Object?>[];
  for (final value in values) {
    if (!unique.any((candidate) => identical(candidate, value))) {
      unique.add(value);
    }
  }
  return unique.length;
}
