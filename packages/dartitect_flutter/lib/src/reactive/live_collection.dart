import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'resource_lifecycle.dart';

/// Explicit projection strategy for one [LiveCollection.update] cycle.
enum CollectionUpdatePolicy {
  /// Reprojects every source item.
  replaceAll,

  /// Reprojects only new or unequal source items for a stable key.
  diffByKey,

  /// Reprojects only new items or keys whose explicit version changed.
  versionedByKey,
}

/// Diagnostic state of explicit background collection projection.
enum CollectionProjectionStatus {
  /// No background projection is running and the latest attempt succeeded.
  idle,

  /// One background generation is running.
  running,

  /// The latest current generation crashed and requires an explicit new call.
  crashed,

  /// The collection is terminally disposed.
  disposed,
}

/// Transferable input selected for one background collection projection.
final class CollectionProjectionInput<K, S> {
  /// Creates one keyed source/value-version input.
  const CollectionProjectionInput({
    required this.key,
    required this.source,
    required this.version,
  });

  /// Stable collection key computed in the main isolate.
  final K key;

  /// Consumer-provided transferable source value.
  final S source;

  /// Optional transferable version used by versioned projection policy.
  final Object? version;
}

/// Transferable output returned by one background collection projection.
final class CollectionProjectionOutput<K, T> {
  /// Creates one projected value for [key].
  const CollectionProjectionOutput({required this.key, required this.value});

  /// Stable key copied from the corresponding input.
  final K key;

  /// Transferable projected value.
  final T value;
}

/// Kind of one structural or item change in a collection batch.
enum CollectionChangeKind {
  /// A key entered the collection.
  added,

  /// A key left the collection.
  removed,

  /// A projected value changed for an existing key.
  updated,

  /// An existing key changed index.
  moved,
}

/// Immutable change emitted after one atomic collection publication.
final class CollectionChange<K> {
  /// Creates a typed collection change.
  const CollectionChange({
    required this.kind,
    required this.key,
    this.oldIndex,
    this.newIndex,
  });

  /// Change classification.
  final CollectionChangeKind kind;

  /// Stable item key.
  final K key;

  /// Previous index when applicable.
  final int? oldIndex;

  /// New index when applicable.
  final int? newIndex;
}

/// Duplicate key failure raised before a collection cycle mutates state.
final class DuplicateCollectionKeyException<K> implements Exception {
  /// Creates a duplicate-key failure.
  const DuplicateCollectionKeyException(this.key);

  /// Key encountered more than once.
  final K key;

  @override
  String toString() => 'DuplicateCollectionKeyException($key)';
}

/// Stable listenable node for one keyed projected value.
final class LiveItem<K, T> implements ValueListenable<T?> {
  LiveItem._(this.key, this._onListenerChanged);

  final VoidCallback _onListenerChanged;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  T? _value;
  var _present = false;
  var _attached = true;

  /// Stable key represented by this node.
  final K key;

  /// Projected value, or null for a tombstone/nullable value.
  @override
  T? get value => _value;

  /// Distinguishes a present nullable value from a tombstone.
  bool get isPresent => _present;

  /// Whether the collection still retains this node.
  bool get isAttached => _attached;

  /// Number of callbacks retaining this item node.
  int get listenerCount => _listeners.length;

  @override
  void addListener(VoidCallback listener) {
    if (!_attached) throw StateError('LiveItem is detached.');
    _listeners.add(listener);
    _onListenerChanged();
  }

  @override
  void removeListener(VoidCallback listener) {
    final index = _listeners.indexOf(listener);
    if (index >= 0) _listeners.removeAt(index);
    if (_attached) _onListenerChanged();
  }

  bool _stage(T? value, {required bool present}) {
    final changed = _present != present || _value != value;
    _present = present;
    _value = value;
    return changed;
  }

  void _notify() {
    final snapshot = List<VoidCallback>.of(_listeners);
    for (final listener in snapshot) {
      if (!_attached || !_listeners.contains(listener)) continue;
      try {
        listener();
      } catch (_) {
        continue;
      }
    }
  }

  void _detach() {
    _attached = false;
    _present = false;
    _value = null;
    _listeners.clear();
  }
}

/// Owned incremental projection cache with item-specific listenable nodes.
final class LiveCollection<K, T> implements AsyncDisposable {
  /// Creates an empty collection with bounded tombstone retention.
  LiveCollection({
    this.tombstoneRetention = const Duration(minutes: 5),
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
  }) : _timerFactory = timerFactory {
    if (tombstoneRetention < Duration.zero) {
      throw ArgumentError.value(
        tombstoneRetention,
        'tombstoneRetention',
        'Must not be negative.',
      );
    }
    _keys = _CollectionValue<List<K>>(<K>[]);
    _length = _CollectionValue<int>(0);
  }

  final ReactiveTimerFactory _timerFactory;
  final Map<K, _ProjectionEntry<T>> _entries = <K, _ProjectionEntry<T>>{};
  final Map<K, LiveItem<K, T>> _nodes = <K, LiveItem<K, T>>{};
  final Map<LiveItem<K, T>, ReactiveTimerHandle> _tombstoneTimers =
      <LiveItem<K, T>, ReactiveTimerHandle>{};
  final StreamController<CollectionChange<K>> _changes =
      StreamController<CollectionChange<K>>.broadcast(sync: true);
  late final _CollectionValue<List<K>> _keys;
  late final _CollectionValue<int> _length;
  List<K> _order = <K>[];
  var _revision = 0;
  var _projectionCount = 0;
  var _lastProjectionCount = 0;
  var _projectionGeneration = 0;
  CancellationSource? _backgroundCancellation;
  var _projectionStatus = CollectionProjectionStatus.idle;
  Object? _projectionError;
  StackTrace? _projectionStackTrace;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Duration a removed unobserved item remains reattachable.
  final Duration tombstoneRetention;

  /// Stable key order signal; item-only updates do not notify it.
  ValueListenable<List<K>> get keys => _keys;

  /// Stable length signal; reorder and item-only updates do not notify it.
  ValueListenable<int> get length => _length;

  /// Item and structural changes emitted after each atomic publication.
  Stream<CollectionChange<K>> get changes => _changes.stream;

  /// Logical publication revision.
  int get revision => _revision;

  /// Total successful projection calls across committed cycles.
  int get projectionCount => _projectionCount;

  /// Projection calls performed by the latest committed cycle.
  int get lastProjectionCount => _lastProjectionCount;

  /// Item nodes retained, including warm tombstones.
  int get nodeCount => _nodes.length;

  /// Removed nodes retained by listeners or warm tombstone timers.
  int get tombstoneCount =>
      _nodes.values.where((node) => !node.isPresent).length;

  /// Active warm tombstone timers.
  int get activeTimerCount =>
      _tombstoneTimers.values.where((timer) => timer.isActive).length;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Diagnostic status of opt-in background projection.
  CollectionProjectionStatus get projectionStatus => _projectionStatus;

  /// Latest current-generation background crash, if any.
  Object? get projectionError => _projectionError;

  /// Original stack paired with [projectionError].
  StackTrace? get projectionStackTrace => _projectionStackTrace;

  /// Returns one stable item node, creating a warm tombstone when absent.
  LiveItem<K, T> item(K key) {
    _ensureActive();
    final existing = _nodes[key];
    if (existing != null) return existing;
    final node = _createNode(key);
    _scheduleTombstone(node);
    return node;
  }

  LiveItem<K, T> _createNode(K key) {
    late final LiveItem<K, T> node;
    node = LiveItem<K, T>._(key, () => _itemListenersChanged(node));
    _nodes[key] = node;
    return node;
  }

  /// Applies one validated source snapshot using an explicit [policy].
  void update<S>(
    Iterable<S> source, {
    required K Function(S source) keyOf,
    required T Function(S source) project,
    required CollectionUpdatePolicy policy,
    Object? Function(S source)? versionOf,
  }) {
    _ensureActive();
    _invalidateBackgroundProjection('inline projection superseded background');
    _projectionStatus = CollectionProjectionStatus.idle;
    _projectionError = null;
    _projectionStackTrace = null;
    final orderedSources = _prepareSources(
      source,
      keyOf: keyOf,
      policy: policy,
      versionOf: versionOf,
    );

    final nextEntries = <K, _ProjectionEntry<T>>{};
    var projected = 0;
    for (final item in orderedSources) {
      final previous = _entries[item.key];
      final reuse = _canReuse(previous, item, policy);
      final projection = reuse ? previous!.value : project(item.source);
      if (!reuse) projected += 1;
      nextEntries[item.key] = _ProjectionEntry<T>(
        item.source,
        item.version,
        projection,
      );
    }

    final nextOrder = orderedSources
        .map((item) => item.key)
        .toList(growable: false);
    _publish(nextEntries, nextOrder, projected);
  }

  /// Projects inline by default or through an explicitly injected executor.
  ///
  /// Background work receives only [CollectionProjectionInput] values. A new
  /// update, cancellation, or disposal invalidates its generation before any
  /// result can publish. Returns false only when a custom executor completes a
  /// stale generation instead of observing cancellation.
  Future<bool> updateProjected<S>(
    Iterable<S> source, {
    required K Function(S source) keyOf,
    required T Function(S source) project,
    required CollectionUpdatePolicy policy,
    Object? Function(S source)? versionOf,
    ProjectionExecution execution = ProjectionExecution.inline,
    ProjectionExecutor<
      List<CollectionProjectionInput<K, S>>,
      List<CollectionProjectionOutput<K, T>>
    >?
    executor,
    CancellationSignal? cancellationSignal,
  }) async {
    if (execution == ProjectionExecution.inline) {
      update<S>(
        source,
        keyOf: keyOf,
        project: project,
        policy: policy,
        versionOf: versionOf,
      );
      return true;
    }
    _ensureActive();
    if (executor == null) throw ArgumentError.notNull('executor');
    final orderedSources = _prepareSources(
      source,
      keyOf: keyOf,
      policy: policy,
      versionOf: versionOf,
    );
    _invalidateBackgroundProjection('newer background projection');
    final generation = _projectionGeneration;
    final operationCancellation = CancellationSource();
    _backgroundCancellation = operationCancellation;
    _projectionStatus = CollectionProjectionStatus.running;
    _projectionError = null;
    _projectionStackTrace = null;
    final externalCancellation = cancellationSignal?.register(
      operationCancellation.cancel,
    );

    final inputs = <CollectionProjectionInput<K, S>>[];
    final previousByKey = <K, _ProjectionEntry<T>>{};
    for (final item in orderedSources) {
      final previous = _entries[item.key];
      if (_canReuse(previous, item, policy)) {
        previousByKey[item.key] = previous!;
      } else {
        inputs.add(
          CollectionProjectionInput<K, S>(
            key: item.key,
            source: item.source,
            version: item.version,
          ),
        );
      }
    }

    try {
      if (inputs.isEmpty) {
        operationCancellation.signal.throwIfCancelled();
        final nextEntries = <K, _ProjectionEntry<T>>{
          for (final item in orderedSources) item.key: previousByKey[item.key]!,
        };
        _publish(
          nextEntries,
          orderedSources.map((item) => item.key).toList(growable: false),
          0,
        );
        _projectionStatus = CollectionProjectionStatus.idle;
        return true;
      }
      final response = await executor.execute(
        TransferableProjectionRequest<List<CollectionProjectionInput<K, S>>>(
          generation: generation,
          payload: List<CollectionProjectionInput<K, S>>.unmodifiable(inputs),
        ),
        operationCancellation.signal,
      );
      operationCancellation.signal.throwIfCancelled();
      if (_disposed || generation != _projectionGeneration) return false;
      if (response.generation != generation) {
        throw StateError(
          'Projection executor returned a mismatched generation.',
        );
      }

      final projectedByKey = <K, T>{};
      final expectedKeys = inputs.map((input) => input.key).toSet();
      for (final output in response.value) {
        if (!expectedKeys.contains(output.key)) {
          throw StateError('Projection executor returned an unknown key.');
        }
        if (projectedByKey.containsKey(output.key)) {
          throw DuplicateCollectionKeyException<K>(output.key);
        }
        projectedByKey[output.key] = output.value;
      }
      if (projectedByKey.length != inputs.length) {
        throw StateError('Projection executor omitted one or more keys.');
      }

      final nextEntries = <K, _ProjectionEntry<T>>{};
      for (final item in orderedSources) {
        final previous = previousByKey[item.key];
        nextEntries[item.key] =
            previous ??
            _ProjectionEntry<T>(
              item.source,
              item.version,
              projectedByKey[item.key] as T,
            );
      }
      final nextOrder = orderedSources
          .map((item) => item.key)
          .toList(growable: false);
      _publish(nextEntries, nextOrder, inputs.length);
      _projectionStatus = CollectionProjectionStatus.idle;
      return true;
    } catch (error, stackTrace) {
      if (!_disposed && generation == _projectionGeneration) {
        if (error is CancellationException) {
          _projectionStatus = CollectionProjectionStatus.idle;
        } else {
          _projectionStatus = CollectionProjectionStatus.crashed;
          _projectionError = error;
          _projectionStackTrace = stackTrace;
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      externalCancellation?.dispose();
      if (identical(_backgroundCancellation, operationCancellation)) {
        _backgroundCancellation = null;
      }
      operationCancellation.dispose();
    }
  }

  List<_CollectionSourceItem<K, S>> _prepareSources<S>(
    Iterable<S> source, {
    required K Function(S source) keyOf,
    required CollectionUpdatePolicy policy,
    required Object? Function(S source)? versionOf,
  }) {
    if (policy == CollectionUpdatePolicy.versionedByKey && versionOf == null) {
      throw ArgumentError.notNull('versionOf');
    }
    final orderedSources = <_CollectionSourceItem<K, S>>[];
    final keys = <K>{};
    for (final value in source) {
      final key = keyOf(value);
      if (!keys.add(key)) throw DuplicateCollectionKeyException<K>(key);
      orderedSources.add(
        _CollectionSourceItem<K, S>(key, value, versionOf?.call(value)),
      );
    }
    return orderedSources;
  }

  bool _canReuse<S>(
    _ProjectionEntry<T>? previous,
    _CollectionSourceItem<K, S> item,
    CollectionUpdatePolicy policy,
  ) => switch (policy) {
    CollectionUpdatePolicy.replaceAll => false,
    CollectionUpdatePolicy.diffByKey =>
      previous != null && previous.source == item.source,
    CollectionUpdatePolicy.versionedByKey =>
      previous != null && previous.version == item.version,
  };

  void _publish(
    Map<K, _ProjectionEntry<T>> nextEntries,
    List<K> nextOrder,
    int projected,
  ) {
    final oldOrder = _order;
    final oldIndices = <K, int>{
      for (var index = 0; index < oldOrder.length; index += 1)
        oldOrder[index]: index,
    };
    final nextIndices = <K, int>{
      for (var index = 0; index < nextOrder.length; index += 1)
        nextOrder[index]: index,
    };
    final changes = <CollectionChange<K>>[];
    for (final key in oldOrder) {
      if (!nextEntries.containsKey(key)) {
        changes.add(
          CollectionChange<K>(
            kind: CollectionChangeKind.removed,
            key: key,
            oldIndex: oldIndices[key],
          ),
        );
      }
    }
    for (final key in nextOrder) {
      final oldIndex = oldIndices[key];
      final newIndex = nextIndices[key]!;
      if (oldIndex == null) {
        changes.add(
          CollectionChange<K>(
            kind: CollectionChangeKind.added,
            key: key,
            newIndex: newIndex,
          ),
        );
        continue;
      }
      if (_entries[key]!.value != nextEntries[key]!.value) {
        changes.add(
          CollectionChange<K>(
            kind: CollectionChangeKind.updated,
            key: key,
            oldIndex: oldIndex,
            newIndex: newIndex,
          ),
        );
      }
      if (oldIndex != newIndex) {
        changes.add(
          CollectionChange<K>(
            kind: CollectionChangeKind.moved,
            key: key,
            oldIndex: oldIndex,
            newIndex: newIndex,
          ),
        );
      }
    }

    final itemNotifications = <LiveItem<K, T>>[];
    for (final key in oldOrder) {
      if (nextEntries.containsKey(key)) continue;
      final node = _nodes[key];
      if (node != null && node._stage(null, present: false)) {
        itemNotifications.add(node);
      }
    }
    for (final key in nextOrder) {
      final entry = nextEntries[key]!;
      final node = _nodes[key] ?? _createNode(key);
      _cancelTombstone(node);
      if (node._stage(entry.value, present: true)) {
        itemNotifications.add(node);
      }
    }

    final orderChanged = !_sameList(oldOrder, nextOrder);
    final lengthChanged = oldOrder.length != nextOrder.length;
    _entries
      ..clear()
      ..addAll(nextEntries);
    _order = List<K>.unmodifiable(nextOrder);
    _lastProjectionCount = projected;
    _projectionCount += projected;
    if (changes.isNotEmpty || orderChanged) _revision += 1;
    if (orderChanged) _keys._stage(_order);
    if (lengthChanged) _length._stage(_order.length);

    for (final node in itemNotifications) {
      node._notify();
    }
    if (orderChanged) _keys._notify();
    if (lengthChanged) _length._notify();
    for (final change in changes) {
      _changes.add(change);
    }
    for (final node in itemNotifications.where((node) => !node.isPresent)) {
      _scheduleTombstone(node);
    }
  }

  /// Cancels tombstones, detaches nodes, and closes the change stream.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  @override
  Future<void> disposeAsync() => dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _invalidateBackgroundProjection('LiveCollection disposed');
    _projectionStatus = CollectionProjectionStatus.disposed;
    for (final timer in _tombstoneTimers.values) {
      timer.cancel();
    }
    _tombstoneTimers.clear();
    for (final node in _nodes.values) {
      node._detach();
    }
    _nodes.clear();
    _entries.clear();
    _order = <K>[];
    _keys.dispose();
    _length.dispose();
    await _changes.close();
  }

  void _invalidateBackgroundProjection(Object reason) {
    _projectionGeneration += 1;
    _backgroundCancellation?.cancel(reason);
    _backgroundCancellation = null;
  }

  void _itemListenersChanged(LiveItem<K, T> node) {
    if (_disposed || node.isPresent) return;
    if (node.listenerCount > 0) {
      _cancelTombstone(node);
    } else {
      _scheduleTombstone(node);
    }
  }

  void _scheduleTombstone(LiveItem<K, T> node) {
    if (_disposed || node.isPresent || node.listenerCount > 0) return;
    if (_tombstoneTimers.containsKey(node)) return;
    if (tombstoneRetention == Duration.zero) {
      _releaseTombstone(node);
      return;
    }
    _tombstoneTimers[node] = _timerFactory.schedule(
      tombstoneRetention,
      () => _releaseTombstone(node),
    );
  }

  void _cancelTombstone(LiveItem<K, T> node) {
    _tombstoneTimers.remove(node)?.cancel();
  }

  void _releaseTombstone(LiveItem<K, T> node) {
    _tombstoneTimers.remove(node)?.cancel();
    if (_disposed || node.isPresent || node.listenerCount > 0) return;
    if (!identical(_nodes[node.key], node)) return;
    _nodes.remove(node.key);
    node._detach();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('LiveCollection is disposed.');
  }
}

final class _ProjectionEntry<T> {
  const _ProjectionEntry(this.source, this.version, this.value);

  final Object? source;
  final Object? version;
  final T value;
}

final class _CollectionSourceItem<K, S> {
  const _CollectionSourceItem(this.key, this.source, this.version);

  final K key;
  final S source;
  final Object? version;
}

final class _CollectionValue<V> implements ValueListenable<V> {
  _CollectionValue(this._value);

  final List<VoidCallback> _listeners = <VoidCallback>[];
  V _value;
  var _disposed = false;

  @override
  V get value => _value;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) throw StateError('Collection signal is disposed.');
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    final index = _listeners.indexOf(listener);
    if (index >= 0) _listeners.removeAt(index);
  }

  void _stage(V value) => _value = value;

  void _notify() {
    final snapshot = List<VoidCallback>.of(_listeners);
    for (final listener in snapshot) {
      if (_disposed || !_listeners.contains(listener)) continue;
      try {
        listener();
      } catch (_) {
        continue;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
