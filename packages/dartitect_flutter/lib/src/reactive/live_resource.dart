import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'lifecycle_barrier.dart';
import 'resource_lifecycle.dart';

/// Backpressure policy for source invalidation signals.
enum SourceBackpressure {
  /// Executes every signal serially in an externally bounded backlog.
  ///
  /// This mode never coalesces. The source must therefore provide its own
  /// finite signal bound.
  everyEmission,

  /// Coalesces into one microtask and at most one dirty rerun while busy.
  coalesceMicrotask,

  /// Coalesces into one frame and at most one dirty rerun while busy.
  coalesceFrame,

  /// Runs one read and remembers at most one dirty rerun while busy.
  latestWhileBusy,

  /// Cancels the active read and runs only the newest invalidation generation.
  ///
  /// The next read begins after the cancelled operation drains. A provider that
  /// ignores cooperative cancellation is still generation-guarded and cannot
  /// publish its late result.
  @experimentalDartitectApi
  restartLatest,
}

/// Last-known-data presentation while a live resource refreshes.
@experimentalDartitectApi
enum LiveResourceStalePolicy {
  /// Publishes waiting/failure/crash states with the last known data attached.
  preserveLastData,

  /// Clears last known data as soon as a new read starts.
  discardLastData,

  /// Keeps a ready state visible while a newer generation is in flight.
  staleWhileRevalidate,
}

/// One activation-local source session owned by a [LiveResource].
abstract interface class ReactiveSourceSession<T, F extends Object> {
  /// Invalidations that request a new authoritative read.
  Stream<void> get signals;

  /// Reads the latest authoritative value.
  Future<Result<T, F>> read(CancellationSignal signal);

  /// Closes watcher/query resources created by this session.
  Future<void> close();
}

/// Sanitized lifecycle phase of a live resource's current source session.
enum ReactiveSourceLifecyclePhase {
  /// No source session is active.
  inactive,

  /// A source session and its subscription are active.
  active,

  /// In-flight reads are cancelling and draining.
  drainingReads,

  /// The source signal subscription is cancelling.
  cancellingSubscription,

  /// The source session is closing.
  closingSession,
}

/// Factory-like source that creates a fresh session per hot activation.
abstract interface class ReactiveSource<T, F extends Object> {
  /// Opens a session or returns an expected typed failure.
  Future<Result<ReactiveSourceSession<T, F>, F>> open();
}

/// Owned typed invalidation registry with one monotonic group revision.
final class InvalidationGroup<K> implements Disposable {
  /// Creates an empty typed invalidation group.
  InvalidationGroup();

  final Set<InvalidationBinding<K>> _bindings = <InvalidationBinding<K>>{};
  var _revision = 0;
  var _disposed = false;

  /// Latest invalidation revision issued by this group.
  int get revision => _revision;

  /// Number of resource bindings retained by this group.
  int get bindingCount => _bindings.length;

  /// Whether this group has been terminally disposed.
  bool get isDisposed => _disposed;

  /// Binds [resource] to one typed [key] without taking ownership of it.
  InvalidationBinding<K> bind<T, F extends Object>(
    K key,
    LiveResource<T, F> resource,
  ) {
    _ensureActive();
    if (resource.isDisposed) {
      throw StateError('Cannot bind a disposed LiveResource.');
    }
    late final InvalidationBinding<K> binding;
    binding = InvalidationBinding<K>._(
      this,
      key,
      resource._invalidate,
      () => resource._detachInvalidationBinding(binding),
    );
    _bindings.add(binding);
    resource._attachInvalidationBinding(binding);
    return binding;
  }

  /// Invalidates every binding whose key equals [key].
  int invalidate(K key) => invalidateWhere((candidate) => candidate == key);

  /// Invalidates a typed subset and returns the new group revision.
  int invalidateWhere(bool Function(K key) predicate) {
    _ensureActive();
    final matches = _bindings
        .where((binding) => predicate(binding.key))
        .toList(growable: false);
    _revision += 1;
    for (final binding in matches) {
      binding._invalidate();
    }
    return _revision;
  }

  /// Detaches every binding without disposing borrowed resources.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final binding in _bindings.toList(growable: false).reversed) {
      binding.dispose();
    }
    _bindings.clear();
  }

  void _remove(InvalidationBinding<K> binding) => _bindings.remove(binding);

  void _ensureActive() {
    if (_disposed) throw StateError('InvalidationGroup is disposed.');
  }
}

/// Explicit registration owned by an [InvalidationGroup].
final class InvalidationBinding<K> implements Disposable {
  InvalidationBinding._(
    this._group,
    this.key,
    this._markInvalidated,
    this._detachResource,
  );

  InvalidationGroup<K>? _group;
  void Function()? _markInvalidated;
  void Function()? _detachResource;

  /// Typed key matched by group invalidation.
  final K key;

  /// Whether this binding has been detached.
  bool get isDisposed => _group == null;

  /// Detaches this binding without disposing the borrowed resource.
  @override
  void dispose() {
    final group = _group;
    if (group == null) return;
    _group = null;
    group._remove(this);
    final detachResource = _detachResource;
    _detachResource = null;
    _markInvalidated = null;
    detachResource?.call();
  }

  void _invalidate() => _markInvalidated?.call();
}

/// Injectable frame boundary used by [SourceBackpressure.coalesceFrame].
abstract interface class SourceFrameScheduler {
  /// Schedules [callback] for the next frame boundary.
  void schedule(VoidCallback callback);
}

/// Default frame scheduler backed by [SchedulerBinding].
final class FlutterSourceFrameScheduler implements SourceFrameScheduler {
  /// Creates the Flutter frame scheduler.
  const FlutterSourceFrameScheduler();

  @override
  void schedule(VoidCallback callback) {
    SchedulerBinding.instance.scheduleFrameCallback((_) => callback());
  }
}

/// Receives unexpected source crashes before the resource is suspended.
abstract interface class LiveResourceCrashReporter {
  /// Reports [error] with its original [stackTrace].
  void report(Object error, StackTrace stackTrace);
}

/// Reporter that deliberately ignores source crashes.
final class NoOpLiveResourceCrashReporter implements LiveResourceCrashReporter {
  /// Creates a no-op reporter.
  const NoOpLiveResourceCrashReporter();

  @override
  void report(Object error, StackTrace stackTrace) {}
}

/// Lifecycle-aware authoritative resource with bounded source backpressure.
final class LiveResource<T, F extends Object> implements Listenable {
  /// Creates a resource whose source is reopened for each hot generation.
  factory LiveResource({
    required ReactiveSource<T, F> source,
    ActivationPolicy policy = const ActivationPolicy.whileObserved(),
    SourceBackpressure backpressure = SourceBackpressure.latestWhileBusy,
    SourceFrameScheduler frameScheduler = const FlutterSourceFrameScheduler(),
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
    LiveResourceCrashReporter reporter = const NoOpLiveResourceCrashReporter(),
    @experimentalDartitectApi
    LiveResourceStalePolicy stalePolicy =
        LiveResourceStalePolicy.preserveLastData,
    @experimentalDartitectApi bool Function(T previous, T next)? dataEquals,
    @experimentalDartitectApi DartitectDiagnosticSubject? diagnostics,
  }) {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.resource) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'LiveResource requires a resource diagnostic subject.',
      );
    }
    late final LiveResource<T, F> resource;
    final lifecycle = ResourceLifecycle<T, F>(
      policy: policy,
      timerFactory: timerFactory,
      onActivate: (generation) => resource._activate(generation),
      onDeactivate: () => resource._deactivate(),
      onChanged: () => resource._notifyLifecycleListeners(),
    );
    resource = LiveResource<T, F>._(
      source,
      lifecycle,
      backpressure,
      frameScheduler,
      reporter,
      stalePolicy,
      dataEquals,
      diagnostics,
    );
    return resource;
  }

  LiveResource._(
    this._source,
    this._lifecycle,
    this.backpressure,
    this._frameScheduler,
    this._reporter,
    this.stalePolicy,
    this._dataEquals,
    this._diagnostics,
  );

  final ReactiveSource<T, F> _source;
  final ResourceLifecycle<T, F> _lifecycle;
  final SourceFrameScheduler _frameScheduler;
  final LiveResourceCrashReporter _reporter;
  final bool Function(T previous, T next)? _dataEquals;
  final DartitectDiagnosticSubject? _diagnostics;
  ReactiveSourceSession<T, F>? _session;
  Future<void> Function()? _cancelSubscription;
  _SourceCoordinator<T, F>? _coordinator;
  final Set<Disposable> _invalidationBindings = <Disposable>{};
  final List<VoidCallback> _lifecycleListeners = <VoidCallback>[];
  var _disposed = false;
  var _readCount = 0;
  var _crashedGeneration = -1;
  var _invalidationRevision = 0;
  var _observedInvalidationRevision = 0;
  var _activeReadInvalidationRevision = 0;
  var _stale = false;
  var _hasSucceeded = false;
  Future<void>? _disposeFuture;

  /// Configured backpressure policy.
  final SourceBackpressure backpressure;

  /// Configured last-known-data behavior during refresh.
  @experimentalDartitectApi
  final LiveResourceStalePolicy stalePolicy;

  /// Current data state.
  ResourceDataState<T, F> get state => _lifecycle.state;

  /// Current upstream/snapshot temperature.
  ResourceTemperature get temperature => _lifecycle.temperature;

  /// Current hot source generation.
  int get generation => _lifecycle.generation;

  /// Number of source reads started across activations.
  int get readCount => _readCount;

  /// Resource-local invalidation revision requested while hot or warm.
  int get invalidationRevision => _invalidationRevision;

  /// Latest invalidation revision covered by a successful publication.
  int get observedInvalidationRevision => _observedInvalidationRevision;

  /// Whether retained data predates an accepted invalidation.
  bool get isStale =>
      _stale && temperature != ResourceTemperature.cold && !_disposed;

  /// Active ticker-aware observation count.
  int get observerCount => _lifecycle.observerCount;

  /// Active read operations admitted by the lifecycle barrier.
  int get activeOperationCount => _lifecycle.barrier.activeOperationCount;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Latest lifecycle transition, including source close/drain.
  Future<void> get settled => _lifecycle.settled;

  /// Sanitized lifecycle phase of the current source session.
  ReactiveSourceLifecyclePhase get sourceLifecyclePhase => _sourcePhase;

  ReactiveSourceLifecyclePhase _sourcePhase =
      ReactiveSourceLifecyclePhase.inactive;

  /// Adds a passive listener without affecting activation or observer count.
  @override
  void addListener(VoidCallback listener) {
    if (_disposed) throw StateError('LiveResource is disposed.');
    _lifecycleListeners.add(listener);
  }

  /// Removes one passive lifecycle listener.
  @override
  void removeListener(VoidCallback listener) {
    final index = _lifecycleListeners.indexOf(listener);
    if (index >= 0) _lifecycleListeners.removeAt(index);
  }

  /// Reconciles the initial activation policy.
  Future<void> start() => _lifecycle.start();

  /// Keeps automatic activation hot until the returned lease is released.
  ResourceLease acquireLease() => _lifecycle.acquireLease();

  /// Creates a ticker-aware observation owned by the caller.
  ReactiveObservation<T, F> observe({bool tickerEnabled = true}) =>
      _lifecycle.observe(tickerEnabled: tickerEnabled);

  /// Requests a read if this resource is currently hot.
  bool refresh() {
    final coordinator = _coordinator;
    if (_disposed ||
        coordinator == null ||
        temperature != ResourceTemperature.hot) {
      return false;
    }
    _invalidationRevision += 1;
    _stale = true;
    coordinator.signal();
    return true;
  }

  /// Opens a fresh generation after an open failure or unexpected crash.
  Future<void> retry() => _lifecycle.resume();

  /// Cancels, drains, closes source resources, and blocks publication.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final binding in _invalidationBindings.toList(growable: false)) {
      binding.dispose();
    }
    _invalidationBindings.clear();
    await _lifecycle.dispose();
    _diagnostics?.emit(
      DartitectDiagnosticPhase.disposed,
      generation: generation,
      revision: _invalidationRevision,
    );
    _lifecycleListeners.clear();
  }

  Future<void> _activate(int generation) async {
    Result<ReactiveSourceSession<T, F>, F> opened;
    try {
      opened = await _source.open();
    } catch (error, stackTrace) {
      if (_publishCrash(error, stackTrace, generation)) _suspendLater();
      return;
    }
    if (_disposed || generation != _lifecycle.generation) {
      if (opened case Ok<dynamic>(:final value)) {
        await (value as ReactiveSourceSession<T, F>).close();
      }
      return;
    }
    if (opened case Err<Object>(:final failure, :final stackTrace)) {
      _publishFailure(failure as F, stackTrace, generation);
      _suspendLater();
      return;
    }
    final session = (opened as Ok<ReactiveSourceSession<T, F>>).value;
    _session = session;
    _sourcePhase = ReactiveSourceLifecyclePhase.active;
    final coordinator = _SourceCoordinator<T, F>(
      session: session,
      barrier: _lifecycle.barrier,
      policy: backpressure,
      frameScheduler: _frameScheduler,
      beforeRead: () {
        _activeReadInvalidationRevision = _invalidationRevision;
        _readCount += 1;
        _publishWaiting(generation);
      },
      onResult: (result) =>
          _publishResult(result, generation, _activeReadInvalidationRevision),
      onCrash: (error, stackTrace) {
        if (_publishCrash(error, stackTrace, generation)) _suspendLater();
      },
      onCancelled: () => _diagnostics?.emit(
        DartitectDiagnosticPhase.cancelled,
        generation: generation,
        revision: _invalidationRevision,
      ),
    );
    _coordinator = coordinator;
    _cancelSubscription = session.signals
        .listen(
          (_) => _onSourceInvalidation(coordinator),
          onError: (Object error, StackTrace stackTrace) {
            if (_publishCrash(error, stackTrace, generation)) _suspendLater();
          },
        )
        .cancel;
    coordinator.signal();
  }

  Future<void> _deactivate() async {
    final failures = <AsyncLifecycleCleanupFailure>[];
    final coordinator = _coordinator;
    _coordinator = null;
    if (coordinator != null) {
      _sourcePhase = ReactiveSourceLifecyclePhase.drainingReads;
      try {
        await coordinator.close();
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    final cancelSubscription = _cancelSubscription;
    _cancelSubscription = null;
    Future<void>? cancellingSubscription;
    if (cancelSubscription != null) {
      _sourcePhase = ReactiveSourceLifecyclePhase.cancellingSubscription;
      try {
        cancellingSubscription = cancelSubscription();
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    final session = _session;
    _session = null;
    Future<void>? closingSession;
    if (session != null) {
      _sourcePhase = ReactiveSourceLifecyclePhase.closingSession;
      try {
        // Initiate provider close after cancellation admission, without making
        // either future depend sequentially on the other. Some stream
        // providers complete subscription cancellation only when their owned
        // source is closed; both terminals are still awaited below.
        closingSession = session.close();
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    if (cancellingSubscription != null) {
      try {
        await cancellingSubscription;
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    if (closingSession != null) {
      try {
        await closingSession;
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    _sourcePhase = ReactiveSourceLifecyclePhase.inactive;
    if (failures.isNotEmpty) {
      throw AsyncLifecycleCleanupException(
        List<AsyncLifecycleCleanupFailure>.unmodifiable(failures),
      );
    }
  }

  void _publishWaiting(int generation) {
    final previous = state;
    if (stalePolicy == LiveResourceStalePolicy.staleWhileRevalidate &&
        previous is ResourceReady<T, F>) {
      return;
    }
    _lifecycle.publish(
      ResourceWaiting<T, F>(
        lastData: stalePolicy == LiveResourceStalePolicy.discardLastData
            ? null
            : previous.lastData,
        hasData:
            stalePolicy != LiveResourceStalePolicy.discardLastData &&
            previous.hasData,
      ),
      generation: generation,
    );
  }

  void _publishResult(
    Result<T, F> result,
    int generation,
    int readInvalidationRevision,
  ) {
    switch (result) {
      case Ok<dynamic>(:final value):
        final typedValue = value as T;
        final previous = state;
        final equals = _dataEquals;
        final deduplicated =
            equals != null &&
            previous is ResourceReady<T, F> &&
            equals(previous.data, typedValue);
        final published =
            deduplicated ||
            _lifecycle.publish(
              ResourceReady<T, F>(typedValue),
              generation: generation,
            );
        if (published) {
          if (readInvalidationRevision > _observedInvalidationRevision) {
            _observedInvalidationRevision = readInvalidationRevision;
          }
          _stale = _observedInvalidationRevision < _invalidationRevision;
        }
      case Err<Object>(:final failure, :final stackTrace):
        _publishFailure(failure as F, stackTrace, generation);
    }
  }

  void _invalidate() {
    if (_disposed || temperature == ResourceTemperature.cold) return;
    _invalidationRevision += 1;
    _stale = true;
    if (temperature == ResourceTemperature.hot) {
      _coordinator?.signal();
    }
  }

  void _onSourceInvalidation(_SourceCoordinator<T, F> coordinator) {
    if (_disposed || temperature == ResourceTemperature.cold) return;
    _invalidationRevision += 1;
    _stale = true;
    coordinator.signal();
  }

  void _attachInvalidationBinding(Disposable binding) {
    if (_disposed) {
      binding.dispose();
      return;
    }
    _invalidationBindings.add(binding);
  }

  void _detachInvalidationBinding(Disposable binding) {
    _invalidationBindings.remove(binding);
  }

  void _publishFailure(F failure, StackTrace stackTrace, int generation) {
    final previous = state;
    _lifecycle.publish(
      ResourceFailed<T, F>(
        failure,
        lastData: stalePolicy == LiveResourceStalePolicy.discardLastData
            ? null
            : previous.lastData,
        hasData:
            stalePolicy != LiveResourceStalePolicy.discardLastData &&
            previous.hasData,
      ),
      generation: generation,
    );
  }

  bool _publishCrash(Object error, StackTrace stackTrace, int generation) {
    if (_disposed ||
        generation != _lifecycle.generation ||
        generation == _crashedGeneration) {
      return false;
    }
    _crashedGeneration = generation;
    _report(error, stackTrace);
    final previous = state;
    return _lifecycle.publish(
      ResourceCrashed<T, F>(
        error,
        stackTrace,
        lastData: stalePolicy == LiveResourceStalePolicy.discardLastData
            ? null
            : previous.lastData,
        hasData:
            stalePolicy != LiveResourceStalePolicy.discardLastData &&
            previous.hasData,
      ),
      generation: generation,
    );
  }

  void _suspendLater() {
    scheduleMicrotask(() {
      if (_disposed) return;
      unawaited(_suspendAfterFailure());
    });
  }

  Future<void> _suspendAfterFailure() async {
    try {
      await _lifecycle.suspend();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      _reporter.report(error, stackTrace);
    } catch (_) {
      return;
    }
  }

  void _notifyLifecycleListeners() {
    if (_disposed) return;
    _emitStateDiagnostic();
    final snapshot = List<VoidCallback>.of(_lifecycleListeners);
    for (final listener in snapshot) {
      if (_disposed || !_lifecycleListeners.contains(listener)) continue;
      try {
        listener();
      } catch (_) {
        continue;
      }
    }
  }

  void _emitStateDiagnostic() {
    final subject = _diagnostics;
    if (subject == null) return;
    final phase = switch (state) {
      ResourceWaiting<T, F>() => DartitectDiagnosticPhase.waiting,
      ResourceReady<T, F>() =>
        _hasSucceeded
            ? DartitectDiagnosticPhase.updated
            : DartitectDiagnosticPhase.succeeded,
      ResourceFailed<T, F>() => DartitectDiagnosticPhase.failed,
      ResourceCrashed<T, F>() => DartitectDiagnosticPhase.crashed,
    };
    if (state is ResourceReady<T, F>) _hasSucceeded = true;
    subject.emit(
      phase,
      generation: generation,
      revision: _invalidationRevision,
    );
  }
}

final class _SourceCoordinator<T, F extends Object> {
  _SourceCoordinator({
    required this.session,
    required this.barrier,
    required this.policy,
    required this.frameScheduler,
    required this.beforeRead,
    required this.onResult,
    required this.onCrash,
    required this.onCancelled,
  });

  final ReactiveSourceSession<T, F> session;
  final AsyncLifecycleBarrier barrier;
  final SourceBackpressure policy;
  final SourceFrameScheduler frameScheduler;
  final VoidCallback beforeRead;
  final void Function(Result<T, F> result) onResult;
  final void Function(Object error, StackTrace stackTrace) onCrash;
  final VoidCallback onCancelled;
  CancellationSource? _cancellation;
  Future<void>? _active;
  var _busy = false;
  var _closed = false;
  var _dirty = false;
  var _scheduled = false;
  var _everyPending = 0;

  void signal() {
    if (_closed) return;
    switch (policy) {
      case SourceBackpressure.everyEmission:
        _everyPending += 1;
        if (!_busy) _startNext();
      case SourceBackpressure.latestWhileBusy:
        if (_busy) {
          _dirty = true;
        } else {
          _startRead();
        }
      case SourceBackpressure.restartLatest:
        if (_busy) {
          _dirty = true;
          _cancellation?.cancel('Superseded reactive source generation');
        } else {
          _startRead();
        }
      case SourceBackpressure.coalesceMicrotask:
        _scheduleCoalesced(frame: false);
      case SourceBackpressure.coalesceFrame:
        _scheduleCoalesced(frame: true);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _dirty = false;
    _everyPending = 0;
    _cancellation?.cancel('Reactive source deactivated');
    await _active;
  }

  void _scheduleCoalesced({required bool frame}) {
    if (_scheduled || _closed) {
      if (_busy) _dirty = true;
      return;
    }
    _scheduled = true;
    void fire() {
      _scheduled = false;
      if (_closed) return;
      if (_busy) {
        _dirty = true;
      } else {
        _startRead();
      }
    }

    if (frame) {
      frameScheduler.schedule(fire);
    } else {
      scheduleMicrotask(fire);
    }
  }

  void _startNext() {
    if (_closed || _busy) return;
    if (policy == SourceBackpressure.everyEmission) {
      if (_everyPending == 0) return;
      _everyPending -= 1;
      _startRead();
      return;
    }
    if (_dirty) {
      _dirty = false;
      _startRead();
    }
  }

  void _startRead() {
    if (_closed || _busy) return;
    _busy = true;
    final cancellation = CancellationSource();
    _cancellation = cancellation;
    beforeRead();
    final active = _execute(cancellation);
    _active = active;
    unawaited(
      active.whenComplete(() {
        cancellation.dispose();
        if (identical(_cancellation, cancellation)) _cancellation = null;
        if (identical(_active, active)) _active = null;
        _busy = false;
        if (!_closed) _startNext();
      }),
    );
  }

  Future<void> _execute(CancellationSource cancellation) async {
    try {
      final result = await barrier.run<Result<T, F>>(
        () => session.read(cancellation.signal),
        cancel: () => cancellation.cancel('Lifecycle barrier closed'),
      );
      if (!_closed && !cancellation.signal.isCancelled) {
        onResult(result);
      } else if (cancellation.signal.isCancelled) {
        onCancelled();
      }
    } on CancellationException {
      onCancelled();
      return;
    } catch (error, stackTrace) {
      if (!_closed && !cancellation.signal.isCancelled) {
        onCrash(error, stackTrace);
      }
    }
  }
}
