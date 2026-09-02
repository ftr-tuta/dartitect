import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lifecycle_barrier.dart';
import 'listener_registry.dart';

/// Data state of a resource, independent from its upstream temperature.
sealed class ResourceDataState<T, F extends Object> {
  const ResourceDataState();

  /// Last known authoritative data, when [hasData] is true.
  T? get lastData;

  /// Whether [lastData] is present, including a valid nullable value.
  bool get hasData;
}

/// Resource is waiting for authoritative local data.
final class ResourceWaiting<T, F extends Object>
    extends ResourceDataState<T, F> {
  /// Creates a waiting state, optionally retaining last-known data.
  const ResourceWaiting({this.lastData, this.hasData = false});

  @override
  final T? lastData;

  @override
  final bool hasData;
}

/// Resource has authoritative data ready for presentation.
final class ResourceReady<T, F extends Object> extends ResourceDataState<T, F> {
  /// Creates a ready state for [data].
  const ResourceReady(this.data);

  /// Current authoritative data.
  final T data;

  @override
  T get lastData => data;

  @override
  bool get hasData => true;
}

/// Resource hit an expected typed failure and may retain data.
final class ResourceFailed<T, F extends Object>
    extends ResourceDataState<T, F> {
  /// Creates a failed state.
  const ResourceFailed(this.failure, {this.lastData, this.hasData = false});

  /// Expected failure value.
  final F failure;

  @override
  final T? lastData;

  @override
  final bool hasData;
}

/// Resource hit an unexpected crash and may retain data.
final class ResourceCrashed<T, F extends Object>
    extends ResourceDataState<T, F> {
  /// Creates a crashed state with the original stack trace.
  const ResourceCrashed(
    this.error,
    this.stackTrace, {
    this.lastData,
    this.hasData = false,
  });

  /// Unexpected error.
  final Object error;

  /// Original error stack trace.
  final StackTrace stackTrace;

  @override
  final T? lastData;

  @override
  final bool hasData;
}

/// Upstream and snapshot retention state.
enum ResourceTemperature {
  /// Upstream is active.
  hot,

  /// Upstream is closed while a snapshot may be retained.
  warm,

  /// Upstream and snapshot are both absent.
  cold,
}

/// Activation mode selected for one resource.
enum ActivationMode {
  /// Keep upstream active for the owner's lifetime.
  alwaysHot,

  /// Keep upstream active only while there is an active observer.
  whileObserved,

  /// Retain a warm snapshot for a bounded duration after observation stops.
  keepWarm,

  /// Change temperature only through explicit activation calls.
  manual,
}

/// Explicit activation policy for an owned resource.
final class ActivationPolicy {
  /// Keeps upstream hot until disposal.
  const ActivationPolicy.alwaysHot()
    : mode = ActivationMode.alwaysHot,
      warmDuration = null;

  /// Activates only while observed and goes cold when observation stops.
  const ActivationPolicy.whileObserved()
    : mode = ActivationMode.whileObserved,
      warmDuration = null;

  /// Keeps the snapshot warm for [duration] after observation stops.
  ActivationPolicy.keepWarm(Duration duration)
    : mode = ActivationMode.keepWarm,
      warmDuration = _positiveDuration(duration);

  /// Requires explicit [ResourceLifecycle.activate] and deactivate calls.
  const ActivationPolicy.manual()
    : mode = ActivationMode.manual,
      warmDuration = null;

  /// Selected activation mode.
  final ActivationMode mode;

  /// Warm retention duration for [ActivationMode.keepWarm].
  final Duration? warmDuration;

  static Duration _positiveDuration(Duration duration) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive.');
    }
    return duration;
  }
}

/// Minimal owned timer handle used by lifecycle policies.
abstract interface class ReactiveTimerHandle {
  /// Whether this timer has not fired or been cancelled.
  bool get isActive;

  /// Cancels the timer idempotently.
  void cancel();
}

/// Injectable factory for lifecycle timers.
abstract interface class ReactiveTimerFactory {
  /// Schedules a one-shot callback.
  ReactiveTimerHandle schedule(Duration duration, VoidCallback callback);
}

/// Default one-shot timer factory backed by [Timer].
final class SystemReactiveTimerFactory implements ReactiveTimerFactory {
  /// Creates the system timer factory.
  const SystemReactiveTimerFactory();

  @override
  ReactiveTimerHandle schedule(Duration duration, VoidCallback callback) =>
      _SystemReactiveTimerHandle(Timer(duration, callback));
}

/// Explicit activity retention owned by a consumer.
///
/// A lease keeps `whileObserved` and `keepWarm` lifecycles hot without adding a
/// listener. Manual activation remains explicit. Owner disposal terminally
/// releases every outstanding lease.
final class ResourceLease {
  ResourceLease._(this._resource);

  ResourceLifecycle<Object?, Object>? _resource;

  /// Whether this lease has been released.
  bool get isReleased => _resource == null;

  /// Releases this lease idempotently and awaits temperature reconciliation.
  Future<void> release() async {
    final resource = _resource;
    if (resource == null) return;
    _resource = null;
    resource._releaseLease(this);
    await resource.settled;
  }

  void _releaseFromOwner() => _resource = null;
}

/// A ticker-aware listenable view of a [ResourceLifecycle].
final class ReactiveObservation<T, F extends Object> implements Listenable {
  ReactiveObservation._(this._resource, {required bool tickerEnabled})
    : _tickerEnabled = tickerEnabled;

  final ResourceLifecycle<T, F> _resource;
  final ListenerRegistry _listeners = ListenerRegistry();
  bool _tickerEnabled;
  var _closed = false;
  var _active = false;

  /// Current resource data state.
  ResourceDataState<T, F> get state => _resource.state;

  /// Current upstream temperature.
  ResourceTemperature get temperature => _resource.temperature;

  /// Whether ticker activity currently permits observation.
  bool get tickerEnabled => _tickerEnabled;

  /// Whether this observation currently contributes upstream activity.
  bool get isActive => _active;

  /// Whether this observation has been terminally closed.
  bool get isClosed => _closed;

  /// Latest serialized lifecycle transition triggered by this observation.
  Future<void> get settled => _resource.settled;

  @override
  void addListener(VoidCallback listener) {
    if (_closed) throw StateError('ReactiveObservation is closed.');
    _listeners.add(listener);
    _refreshActivity();
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _refreshActivity();
  }

  /// Enables or pauses upstream observation according to [enabled].
  Future<void> setTickerEnabled(bool enabled) {
    if (_closed || _tickerEnabled == enabled) return settled;
    _tickerEnabled = enabled;
    _refreshActivity();
    return settled;
  }

  /// Closes this observation and removes all retained callbacks.
  Future<void> close() {
    if (_closed) return settled;
    _closed = true;
    _listeners.clear();
    _refreshActivity();
    _resource._removeObservation(this);
    return settled;
  }

  void _refreshActivity() {
    final next = !_closed && _tickerEnabled && _listeners.isNotEmpty;
    if (_active == next) return;
    _active = next;
    _resource._observationActivityChanged();
  }

  void _notify() {
    if (!_active || _closed) return;
    _listeners.notifySafely(shouldContinue: () => !_closed && _active);
  }
}

/// Owned state machine for resource data, temperature, leases, and teardown.
final class ResourceLifecycle<T, F extends Object> {
  /// Creates a cold lifecycle with an explicit activation policy.
  ResourceLifecycle({
    required this.policy,
    required Future<void> Function(int generation) onActivate,
    required Future<void> Function() onDeactivate,
    VoidCallback? onDiscardSnapshot,
    VoidCallback? onChanged,
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
    AsyncLifecycleBarrier? barrier,
  }) : _onActivate = onActivate,
       _onDeactivate = onDeactivate,
       _onDiscardSnapshot = onDiscardSnapshot,
       _onChanged = onChanged,
       _timerFactory = timerFactory,
       barrier = barrier ?? AsyncLifecycleBarrier();

  /// Activation policy for this lifecycle.
  final ActivationPolicy policy;

  /// Admission and drain barrier shared with source operations.
  final AsyncLifecycleBarrier barrier;

  final Future<void> Function(int generation) _onActivate;
  final Future<void> Function() _onDeactivate;
  final VoidCallback? _onDiscardSnapshot;
  final VoidCallback? _onChanged;
  final ReactiveTimerFactory _timerFactory;
  final Set<ReactiveObservation<T, F>> _observations =
      <ReactiveObservation<T, F>>{};
  final Set<ResourceLease> _leases = <ResourceLease>{};
  ResourceDataState<T, F> _state = ResourceWaiting<T, F>();
  ResourceTemperature _temperature = ResourceTemperature.cold;
  ReactiveTimerHandle? _warmTimer;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposeFuture;
  Object? _transitionError;
  StackTrace? _transitionStackTrace;
  var _generation = 0;
  var _manualHot = false;
  var _manualRetainSnapshot = true;
  var _forceCold = false;
  var _suspended = false;
  var _suspendRetainsSnapshot = true;
  var _disposed = false;

  /// Current independent data state.
  ResourceDataState<T, F> get state => _state;

  /// Current upstream/snapshot temperature.
  ResourceTemperature get temperature => _temperature;

  /// Current source generation used to reject stale publication.
  int get generation => _generation;

  /// Active external lifetime leases.
  int get leaseCount => _leases.length;

  /// Ticker-enabled observations with at least one listener.
  int get observerCount => _observations.where((item) => item.isActive).length;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Latest serialized temperature transition.
  Future<void> get settled async {
    await _tail;
    final error = _transitionError;
    if (error != null) {
      final stackTrace = _transitionStackTrace!;
      _transitionError = null;
      _transitionStackTrace = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Starts policy reconciliation, including an always-hot activation.
  Future<void> start() {
    _ensureActive();
    _requestReconcile();
    return settled;
  }

  /// Acquires an activity lease for an automatic activation policy.
  ResourceLease acquireLease() {
    _ensureActive();
    final lease = ResourceLease._(this as ResourceLifecycle<Object?, Object>);
    _leases.add(lease);
    _warmTimer?.cancel();
    _warmTimer = null;
    _forceCold = false;
    _requestReconcile();
    return lease;
  }

  /// Creates a ticker-aware observation owned by the caller.
  ReactiveObservation<T, F> observe({bool tickerEnabled = true}) {
    _ensureActive();
    final observation = ReactiveObservation<T, F>._(
      this,
      tickerEnabled: tickerEnabled,
    );
    _observations.add(observation);
    return observation;
  }

  /// Explicitly activates a manual lifecycle.
  Future<void> activate() {
    _ensureManual();
    _manualHot = true;
    _forceCold = false;
    _requestReconcile();
    return settled;
  }

  /// Explicitly deactivates a manual lifecycle.
  Future<void> deactivate({bool retainSnapshot = true}) {
    _ensureManual();
    _manualHot = false;
    _manualRetainSnapshot = retainSnapshot;
    _requestReconcile();
    return settled;
  }

  /// Suspends automatic activation after a source failure or crash.
  Future<void> suspend({bool retainSnapshot = true}) {
    _ensureActive();
    _suspended = true;
    _suspendRetainsSnapshot = retainSnapshot;
    _warmTimer?.cancel();
    _warmTimer = null;
    _requestReconcile();
    return settled;
  }

  /// Explicitly resumes policy-driven activation after [suspend].
  Future<void> resume() {
    _ensureActive();
    _suspended = false;
    _forceCold = false;
    _requestReconcile();
    return settled;
  }

  /// Publishes [next] only for the current hot generation.
  bool publish(ResourceDataState<T, F> next, {required int generation}) {
    if (_disposed ||
        !barrier.isOpen ||
        generation != _generation ||
        _temperature != ResourceTemperature.hot) {
      return false;
    }
    _state = next;
    _notifyObservations();
    return true;
  }

  /// Marks terminal state, cancels/drains operations, and discards snapshot.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _warmTimer?.cancel();
    _warmTimer = null;
    for (final observation in _observations.toList(growable: false)) {
      unawaited(observation.close());
    }
    for (final lease in _leases) {
      lease._releaseFromOwner();
    }
    _leases.clear();
    final failures = <AsyncLifecycleCleanupFailure>[];
    try {
      await barrier.close();
    } catch (error, stackTrace) {
      failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
    }
    await _tail;
    if (_temperature == ResourceTemperature.hot) {
      try {
        await _onDeactivate();
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    _temperature = ResourceTemperature.cold;
    _discardSnapshot();
    _observations.clear();
    if (failures.isNotEmpty) {
      throw AsyncLifecycleCleanupException(
        List<AsyncLifecycleCleanupFailure>.unmodifiable(failures),
      );
    }
  }

  void _releaseLease(ResourceLease lease) {
    if (!_leases.remove(lease) || _disposed) return;
    _requestReconcile();
  }

  void _removeObservation(ReactiveObservation<T, F> observation) {
    _observations.remove(observation);
  }

  void _observationActivityChanged() {
    if (_disposed) return;
    if (observerCount > 0) {
      _warmTimer?.cancel();
      _warmTimer = null;
      _forceCold = false;
    }
    _requestReconcile();
  }

  void _requestReconcile() {
    if (_disposed) return;
    _tail = _tail
        .then<void>(
          (_) => _reconcile(),
          onError: (Object _, StackTrace _) => _reconcile(),
        )
        .catchError((Object error, StackTrace stackTrace) {
          _transitionError = error;
          _transitionStackTrace = stackTrace;
        });
  }

  Future<void> _reconcile() async {
    if (_disposed) return;
    final target = _targetTemperature();
    if (target == _temperature) return;
    if (target == ResourceTemperature.hot) {
      _warmTimer?.cancel();
      _warmTimer = null;
      _generation += 1;
      _temperature = ResourceTemperature.hot;
      _notifyObservations();
      try {
        await _onActivate(_generation);
      } catch (error, stackTrace) {
        _temperature = ResourceTemperature.cold;
        _discardSnapshot();
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }

    if (_temperature == ResourceTemperature.hot) {
      _generation += 1;
      await _onDeactivate();
    }
    _temperature = target;
    if (target == ResourceTemperature.cold) {
      _discardSnapshot();
    } else {
      _scheduleWarmExpiry();
      _notifyObservations();
    }
  }

  ResourceTemperature _targetTemperature() {
    if (_forceCold) return ResourceTemperature.cold;
    if (_suspended) {
      return _suspendRetainsSnapshot && _temperature != ResourceTemperature.cold
          ? ResourceTemperature.warm
          : ResourceTemperature.cold;
    }
    return switch (policy.mode) {
      ActivationMode.alwaysHot => ResourceTemperature.hot,
      ActivationMode.whileObserved =>
        observerCount > 0 || leaseCount > 0
            ? ResourceTemperature.hot
            : ResourceTemperature.cold,
      ActivationMode.keepWarm =>
        observerCount > 0 || leaseCount > 0
            ? ResourceTemperature.hot
            : (_temperature == ResourceTemperature.cold
                  ? ResourceTemperature.cold
                  : ResourceTemperature.warm),
      ActivationMode.manual =>
        _manualHot
            ? ResourceTemperature.hot
            : (_manualRetainSnapshot && _temperature != ResourceTemperature.cold
                  ? ResourceTemperature.warm
                  : ResourceTemperature.cold),
    };
  }

  void _scheduleWarmExpiry() {
    _warmTimer?.cancel();
    _warmTimer = null;
    if (policy.mode != ActivationMode.keepWarm) return;
    _warmTimer = _timerFactory.schedule(policy.warmDuration!, () {
      if (_disposed || observerCount > 0) return;
      _forceCold = true;
      _requestReconcile();
    });
  }

  void _discardSnapshot() {
    _state = ResourceWaiting<T, F>();
    _onDiscardSnapshot?.call();
    _notifyObservations();
  }

  void _notifyObservations() {
    try {
      _onChanged?.call();
    } catch (_) {
      // Passive lifecycle probes never alter resource behavior.
      return _notifyActiveObservations();
    }
    _notifyActiveObservations();
  }

  void _notifyActiveObservations() {
    for (final observation in _observations.toList(growable: false)) {
      observation._notify();
    }
  }

  void _ensureManual() {
    _ensureActive();
    if (policy.mode != ActivationMode.manual) {
      throw StateError('Explicit activation requires ActivationPolicy.manual.');
    }
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ResourceLifecycle is disposed.');
  }
}

final class _SystemReactiveTimerHandle implements ReactiveTimerHandle {
  _SystemReactiveTimerHandle(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
