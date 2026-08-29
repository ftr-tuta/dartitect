import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'live_resource.dart';
import 'resource_lifecycle.dart';

/// One explicitly versioned read of an asynchronous derived resource.
final class DerivedAsyncRead {
  const DerivedAsyncRead._({
    required this.dependencyGeneration,
    required this.cancellation,
  });

  /// Dependency generation captured before the read began.
  final int dependencyGeneration;

  /// Cooperative cancellation requested by dependency or lifecycle changes.
  final CancellationSignal cancellation;
}

/// Computes one derived result from dependencies captured by application code.
typedef DerivedAsyncLoader<T, F extends Object> = Future<Result<T, F>> Function(
  DerivedAsyncRead read,
);

/// Stable async resource derived from explicit Flutter listenables.
///
/// Dependencies are subscribed only during a hot resource generation. A
/// dependency change cancels the active read, advances a generation, and waits
/// for the cancelled operation to drain before starting the newest read. A
/// provider that ignores cancellation still cannot publish its late result.
///
/// [liveResource] exposes the standard waiting/data/failure/crash state,
/// observation, lease, and disposal contracts. It can be returned directly by
/// a [ResourceFamily] factory, whose typed key, TTL, count, weight, and eviction
/// policy remain authoritative for family lifetime.
final class DerivedAsyncResource<T, F extends Object>
    implements Listenable, AsyncDisposable {
  /// Creates a derived resource with explicit [dependencies].
  DerivedAsyncResource({
    required Iterable<Listenable> dependencies,
    required DerivedAsyncLoader<T, F> load,
    ActivationPolicy policy = const ActivationPolicy.whileObserved(),
    LiveResourceStalePolicy stalePolicy =
        LiveResourceStalePolicy.preserveLastData,
    bool Function(T previous, T next)? dataEquals,
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
    LiveResourceCrashReporter reporter = const NoOpLiveResourceCrashReporter(),
    DartitectDiagnosticSubject? diagnostics,
  }) : liveResource = LiveResource<T, F>(
         source: _DerivedAsyncSource<T, F>(dependencies, load),
         policy: policy,
         backpressure: SourceBackpressure.restartLatest,
         stalePolicy: stalePolicy,
         dataEquals: dataEquals ?? _defaultEquals,
         timerFactory: timerFactory,
         reporter: reporter,
         diagnostics: diagnostics,
       );

  /// Underlying resource used by builders, invalidation groups, and families.
  final LiveResource<T, F> liveResource;

  /// Current waiting/data/failure/crash state.
  ResourceDataState<T, F> get state => liveResource.state;

  /// Current upstream and retention temperature.
  ResourceTemperature get temperature => liveResource.temperature;

  /// Current hot lifecycle generation.
  int get generation => liveResource.generation;

  /// Latest accepted dependency invalidation revision.
  int get dependencyRevision => liveResource.invalidationRevision;

  /// Whether retained data predates an accepted dependency generation.
  bool get isStale => liveResource.isStale;

  /// Whether terminal disposal has begun.
  bool get isDisposed => liveResource.isDisposed;

  /// Latest lifecycle transition and source drain.
  Future<void> get settled => liveResource.settled;

  /// Reconciles the initial activation policy.
  Future<void> start() => liveResource.start();

  /// Creates one ticker-aware observation owned by the caller.
  ReactiveObservation<T, F> observe({bool tickerEnabled = true}) =>
      liveResource.observe(tickerEnabled: tickerEnabled);

  /// Keeps automatic activation hot until the returned lease is released.
  ResourceLease acquireLease() => liveResource.acquireLease();

  /// Advances the dependency revision and requests a restart when hot.
  bool refresh() => liveResource.refresh();

  /// Opens a fresh generation after an open failure or unexpected crash.
  Future<void> retry() => liveResource.retry();

  @override
  void addListener(VoidCallback listener) => liveResource.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      liveResource.removeListener(listener);

  /// Cancels, drains, detaches every dependency, and blocks publication.
  Future<void> dispose() => liveResource.dispose();

  @override
  Future<void> disposeAsync() => dispose();
}

bool _defaultEquals<T>(T previous, T next) => previous == next;

final class _DerivedAsyncSource<T, F extends Object>
    implements ReactiveSource<T, F> {
  _DerivedAsyncSource(Iterable<Listenable> dependencies, this._load)
    : _dependencies = _validateDependencies(dependencies);

  final List<Listenable> _dependencies;
  final DerivedAsyncLoader<T, F> _load;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() async =>
      Ok<ReactiveSourceSession<T, F>>(
        _DerivedAsyncSession<T, F>(_dependencies, _load),
      );

  static List<Listenable> _validateDependencies(
    Iterable<Listenable> dependencies,
  ) {
    final values = List<Listenable>.unmodifiable(dependencies);
    if (values.isEmpty) {
      throw ArgumentError.value(
        dependencies,
        'dependencies',
        'Must contain at least one explicit Listenable.',
      );
    }
    final identities = Set<Listenable>.identity();
    for (final dependency in values) {
      if (!identities.add(dependency)) {
        throw ArgumentError.value(
          dependencies,
          'dependencies',
          'Must not repeat the same Listenable identity.',
        );
      }
    }
    return values;
  }
}

final class _DerivedAsyncSession<T, F extends Object>
    implements ReactiveSourceSession<T, F> {
  _DerivedAsyncSession(this._dependencies, this._load)
    : _signals = StreamController<void>.broadcast(sync: true) {
    try {
      for (final dependency in _dependencies) {
        dependency.addListener(_dependencyChanged);
        _attached.add(dependency);
      }
    } catch (_) {
      for (final dependency in _attached.reversed) {
        dependency.removeListener(_dependencyChanged);
      }
      _attached.clear();
      unawaited(_signals.close());
      rethrow;
    }
  }

  final List<Listenable> _dependencies;
  final DerivedAsyncLoader<T, F> _load;
  final StreamController<void> _signals;
  final List<Listenable> _attached = <Listenable>[];
  var _dependencyGeneration = 0;
  var _closed = false;
  Future<void>? _closeFuture;

  @override
  Stream<void> get signals => _signals.stream;

  @override
  Future<Result<T, F>> read(CancellationSignal signal) async {
    if (_closed) {
      throw const CancellationException('Derived async session closed');
    }
    signal.throwIfCancelled();
    final generation = _dependencyGeneration;
    final result = await _load(
      DerivedAsyncRead._(
        dependencyGeneration: generation,
        cancellation: signal,
      ),
    );
    signal.throwIfCancelled();
    if (_closed || generation != _dependencyGeneration) {
      throw const CancellationException(
        'Superseded derived dependency generation',
      );
    }
    return result;
  }

  void _dependencyChanged() {
    if (_closed) return;
    _dependencyGeneration += 1;
    _signals.add(null);
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    for (final dependency in _attached.reversed) {
      dependency.removeListener(_dependencyChanged);
    }
    _attached.clear();
    await _signals.close();
  }
}
