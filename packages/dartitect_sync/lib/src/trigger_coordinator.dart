import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Trigger causes in ascending priority order.
enum SyncTriggerCause {
  /// Periodic or platform scheduler request.
  scheduler(10),

  /// Foreground/lifecycle transition.
  lifecycle(20),

  /// Connectivity became usable or requested re-evaluation.
  connectivity(30),

  /// Remote push hint.
  push(40),

  /// Authenticated session generation changed or requested synchronization.
  session(50),

  /// Explicit user/application request.
  manual(60);

  const SyncTriggerCause(this.priority);

  /// Stable precedence used when coalescing work.
  final int priority;
}

/// Public coordinator phases; none implies an automatic retry policy.
enum SyncTriggerPhase {
  /// No selected or executing work.
  idle,

  /// Work has been coalesced for the next microtask.
  scheduled,

  /// One runner invocation is active.
  running,

  /// Consumer policy blocked work until [SyncTriggerCoordinator.resumeBlocked].
  blocked,

  /// Connectivity blocks work until an injected online event arrives.
  offline,

  /// Consumer policy requires explicit [SyncTriggerCoordinator.resumeBackoff].
  backoff,
}

/// Stable cooperative cancellation reasons emitted by the coordinator.
enum SyncTriggerCancellationReason {
  /// A new session generation fenced the active run.
  sessionChanged,

  /// Injected connectivity reported offline.
  offline,

  /// The selected batch reached its deadline.
  deadlineExceeded,

  /// The coordinator is tearing down.
  disposed,
}

/// One event emitted by an injected trigger source.
final class SyncTriggerIntent<K> {
  SyncTriggerIntent._({
    required Set<K> datasets,
    required this.online,
    required this.generation,
    required this.deadline,
  }) : datasets = Set<K>.unmodifiable(datasets);

  /// Requests work for an explicit non-empty dataset set.
  factory SyncTriggerIntent.work(Iterable<K> datasets, {DateTime? deadline}) {
    final selected = datasets.toSet();
    if (selected.isEmpty) {
      throw ArgumentError.value(
        datasets,
        'datasets',
        'At least one dataset is required.',
      );
    }
    return SyncTriggerIntent<K>._(
      datasets: selected,
      online: null,
      generation: null,
      deadline: deadline,
    );
  }

  /// Reports connectivity and optionally requests datasets when online.
  factory SyncTriggerIntent.connectivity({
    required bool online,
    Iterable<K> datasets = const <Never>[],
    DateTime? deadline,
  }) => SyncTriggerIntent<K>._(
    datasets: datasets.toSet(),
    online: online,
    generation: null,
    deadline: deadline,
  );

  /// Changes session generation and optionally requests its initial datasets.
  factory SyncTriggerIntent.session({
    required int generation,
    Iterable<K> datasets = const <Never>[],
    DateTime? deadline,
  }) {
    if (generation < 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'Must not be negative.',
      );
    }
    return SyncTriggerIntent<K>._(
      datasets: datasets.toSet(),
      online: null,
      generation: generation,
      deadline: deadline,
    );
  }

  /// Selected dataset keys; empty for a control-only event.
  final Set<K> datasets;

  /// Connectivity update, present only for connectivity-source events.
  final bool? online;

  /// Session generation update, present only for session-source events.
  final int? generation;

  /// Optional absolute deadline for selected work.
  final DateTime? deadline;
}

/// Exactly six injected sources; construction starts no subscriptions.
final class SyncTriggerSources<K> {
  /// Creates the complete source set.
  const SyncTriggerSources({
    required this.manual,
    required this.lifecycle,
    required this.connectivity,
    required this.scheduler,
    required this.push,
    required this.session,
  });

  /// Explicit application/user requests.
  final Stream<SyncTriggerIntent<K>> manual;

  /// Lifecycle requests.
  final Stream<SyncTriggerIntent<K>> lifecycle;

  /// Connectivity status and requests.
  final Stream<SyncTriggerIntent<K>> connectivity;

  /// Platform scheduler requests.
  final Stream<SyncTriggerIntent<K>> scheduler;

  /// Remote push hints.
  final Stream<SyncTriggerIntent<K>> push;

  /// Session generation and requests.
  final Stream<SyncTriggerIntent<K>> session;
}

/// One immutable, generation-fenced runner invocation.
final class SyncTriggerBatch<K> {
  SyncTriggerBatch._({
    required this.cause,
    required this.datasets,
    required this.generation,
    required this.deadline,
  });

  /// Highest-priority coalesced cause.
  final SyncTriggerCause cause;

  /// Union of every coalesced dataset.
  final Set<K> datasets;

  /// Session generation current when the batch was scheduled.
  final int generation;

  /// Earliest coalesced deadline, when any trigger supplied one.
  final DateTime? deadline;
}

/// Consumer result for one run; the coordinator never invents a retry.
enum SyncTriggerRunDisposition {
  /// Selected work reached a terminal result.
  completed,

  /// Consumer policy blocked subsequent work.
  blocked,

  /// Consumer/provider observed an offline boundary.
  offline,

  /// Consumer policy selected backoff and will resume explicitly.
  backoff,
}

/// Immutable public state snapshot.
final class SyncTriggerSnapshot<K> {
  SyncTriggerSnapshot._({
    required this.phase,
    required this.generation,
    required Set<K> pendingDatasets,
    required this.cause,
  }) : pendingDatasets = Set<K>.unmodifiable(pendingDatasets);

  /// Current phase.
  final SyncTriggerPhase phase;

  /// Current session generation.
  final int generation;

  /// Coalesced selected work not yet terminal.
  final Set<K> pendingDatasets;

  /// Highest pending/running cause, when work exists.
  final SyncTriggerCause? cause;
}

/// Runner boundary invoked once per coalesced batch.
typedef SyncTriggerRunner<K> = Future<SyncTriggerRunDisposition> Function(
  SyncTriggerBatch<K> batch,
  CancellationSignal cancellation,
);

/// Coordinates explicit foreground, background, connectivity, push, and
/// session triggers without hidden retry or scheduling policy.
final class SyncTriggerCoordinator<K> implements AsyncDisposable {
  /// Creates an inert coordinator. Call [start] to subscribe.
  SyncTriggerCoordinator({
    required SyncTriggerSources<K> sources,
    required SyncTriggerRunner<K> run,
    required void Function(Object error, StackTrace stackTrace) reportCrash,
    DateTime Function()? now,
  }) : _sources = sources,
       _run = run,
       _reportCrash = reportCrash,
       _now = now ?? DateTime.now,
       _snapshot = SyncTriggerSnapshot<K>._(
         phase: SyncTriggerPhase.idle,
         generation: 0,
         pendingDatasets: <K>{},
         cause: null,
       );

  final SyncTriggerSources<K> _sources;
  final SyncTriggerRunner<K> _run;
  final void Function(Object error, StackTrace stackTrace) _reportCrash;
  final DateTime Function() _now;
  final StreamController<SyncTriggerSnapshot<K>> _states =
      StreamController<SyncTriggerSnapshot<K>>.broadcast(sync: true);
  final List<StreamSubscription<SyncTriggerIntent<K>>> _subscriptions =
      <StreamSubscription<SyncTriggerIntent<K>>>[];

  SyncTriggerSnapshot<K> _snapshot;
  _PendingTrigger<K>? _scheduled;
  _PendingTrigger<K>? _followUp;
  _PendingTrigger<K>? _pending;
  CancellationSource? _activeCancellation;
  Future<void>? _activeRun;
  Timer? _deadlineTimer;
  bool _online = true;
  bool _started = false;
  bool _disposed = false;

  /// State transitions; the current value is also available via [snapshot].
  Stream<SyncTriggerSnapshot<K>> get states => _states.stream;

  /// Current synchronous state.
  SyncTriggerSnapshot<K> get snapshot => _snapshot;

  /// Whether source subscriptions have started and teardown has not begun.
  bool get isRunning => _started && !_disposed;

  /// Subscribes exactly once to every injected source.
  void start() {
    if (_disposed) throw StateError('SyncTriggerCoordinator is disposed.');
    if (_started) throw StateError('SyncTriggerCoordinator already started.');
    _started = true;
    _listen(_sources.manual, SyncTriggerCause.manual);
    _listen(_sources.lifecycle, SyncTriggerCause.lifecycle);
    _listen(_sources.connectivity, SyncTriggerCause.connectivity);
    _listen(_sources.scheduler, SyncTriggerCause.scheduler);
    _listen(_sources.push, SyncTriggerCause.push);
    _listen(_sources.session, SyncTriggerCause.session);
  }

  /// Releases consumer-selected blocked state without creating a retry timer.
  void resumeBlocked() {
    _requireLive();
    if (_snapshot.phase != SyncTriggerPhase.blocked) {
      throw StateError('Coordinator is not blocked.');
    }
    _resumeExplicitly();
  }

  /// Releases consumer-selected backoff without creating a retry timer.
  void resumeBackoff() {
    _requireLive();
    if (_snapshot.phase != SyncTriggerPhase.backoff) {
      throw StateError('Coordinator is not in backoff.');
    }
    _resumeExplicitly();
  }

  void _resumeExplicitly() {
    _emit(_online ? SyncTriggerPhase.idle : SyncTriggerPhase.offline, _pending);
    if (_online) _schedulePending();
  }

  void _listen(Stream<SyncTriggerIntent<K>> source, SyncTriggerCause cause) {
    _subscriptions.add(
      source.listen(
        (intent) => _accept(cause, intent),
        onError: (Object error, StackTrace stackTrace) {
          if (_disposed) return;
          _reportCrash(error, stackTrace);
          _emit(SyncTriggerPhase.blocked, _pending);
        },
      ),
    );
  }

  void _accept(SyncTriggerCause cause, SyncTriggerIntent<K> intent) {
    if (_disposed) return;
    if (intent.online != null && cause != SyncTriggerCause.connectivity) {
      _sourceContractError('Only connectivity may publish online status.');
      return;
    }
    if (intent.generation != null && cause != SyncTriggerCause.session) {
      _sourceContractError('Only session may publish a generation.');
      return;
    }
    if (intent.generation case final generation?) {
      _changeGeneration(generation);
    }
    if (intent.online case final online?) {
      _changeConnectivity(online);
    }
    if (intent.datasets.isEmpty) return;
    final trigger = _PendingTrigger<K>(
      cause: cause,
      datasets: intent.datasets,
      generation: _snapshot.generation,
      deadline: intent.deadline,
    );
    _enqueue(trigger);
  }

  void _sourceContractError(String message) {
    _reportCrash(StateError(message), StackTrace.current);
    _emit(SyncTriggerPhase.blocked, _pending);
  }

  void _changeGeneration(int generation) {
    if (generation == _snapshot.generation) return;
    _activeCancellation?.cancel(SyncTriggerCancellationReason.sessionChanged);
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _scheduled = null;
    _followUp = null;
    _pending = null;
    _snapshot = SyncTriggerSnapshot<K>._(
      phase: _online ? SyncTriggerPhase.idle : SyncTriggerPhase.offline,
      generation: generation,
      pendingDatasets: <K>{},
      cause: null,
    );
    _states.add(_snapshot);
  }

  void _changeConnectivity(bool online) {
    if (_online == online) return;
    _online = online;
    if (!online) {
      _activeCancellation?.cancel(SyncTriggerCancellationReason.offline);
      final selected = _scheduled ?? _followUp;
      if (selected != null) _pending = _pending?.merge(selected) ?? selected;
      _scheduled = null;
      _followUp = null;
      _emit(SyncTriggerPhase.offline, _pending);
      return;
    }
    if (_snapshot.phase == SyncTriggerPhase.offline) {
      _emit(SyncTriggerPhase.idle, _pending);
      _schedulePending();
    }
  }

  void _enqueue(_PendingTrigger<K> trigger) {
    if (trigger.generation != _snapshot.generation) return;
    switch (_snapshot.phase) {
      case SyncTriggerPhase.idle:
        _scheduled = trigger;
        _emit(SyncTriggerPhase.scheduled, trigger);
        scheduleMicrotask(_launchScheduled);
      case SyncTriggerPhase.scheduled:
        _scheduled = _scheduled!.merge(trigger);
        _emit(SyncTriggerPhase.scheduled, _scheduled);
      case SyncTriggerPhase.running:
        _followUp = _followUp?.merge(trigger) ?? trigger;
        _emit(SyncTriggerPhase.running, _followUp);
      case SyncTriggerPhase.blocked ||
          SyncTriggerPhase.offline ||
          SyncTriggerPhase.backoff:
        _pending = _pending?.merge(trigger) ?? trigger;
        _emit(_snapshot.phase, _pending);
    }
  }

  void _schedulePending() {
    final pending = _pending;
    _pending = null;
    if (pending != null) _enqueue(pending);
  }

  void _launchScheduled() {
    if (_disposed || _snapshot.phase != SyncTriggerPhase.scheduled) return;
    final selected = _scheduled;
    _scheduled = null;
    if (selected == null || selected.generation != _snapshot.generation) {
      _emit(_online ? SyncTriggerPhase.idle : SyncTriggerPhase.offline, null);
      return;
    }
    if (!_online) {
      _pending = _pending?.merge(selected) ?? selected;
      _emit(SyncTriggerPhase.offline, _pending);
      return;
    }
    final deadline = selected.deadline;
    if (deadline != null && !deadline.isAfter(_now())) {
      _emit(SyncTriggerPhase.idle, null);
      return;
    }
    final cancellation = CancellationSource();
    _activeCancellation = cancellation;
    if (deadline != null) {
      _deadlineTimer = Timer(deadline.difference(_now()), () {
        cancellation.cancel(SyncTriggerCancellationReason.deadlineExceeded);
      });
    }
    final batch = selected.toBatch();
    _emit(SyncTriggerPhase.running, selected);
    final run = _execute(batch, selected, cancellation);
    _activeRun = run;
  }

  Future<void> _execute(
    SyncTriggerBatch<K> batch,
    _PendingTrigger<K> selected,
    CancellationSource cancellation,
  ) async {
    SyncTriggerRunDisposition? disposition;
    Object? crash;
    StackTrace? crashStack;
    Object? cancellationReason;
    try {
      disposition = await _run(batch, cancellation.signal);
    } on CancellationException {
      // Expected session/offline/deadline/disposal control flow.
    } on Object catch (error, stackTrace) {
      crash = error;
      crashStack = stackTrace;
    } finally {
      cancellationReason = cancellation.signal.isCancelled
          ? cancellation.signal.reason
          : null;
      _deadlineTimer?.cancel();
      _deadlineTimer = null;
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      cancellation.dispose();
    }
    if (_disposed || batch.generation != _snapshot.generation) return;
    if (cancellationReason == SyncTriggerCancellationReason.deadlineExceeded) {
      disposition = null;
    }
    final followUp = _followUp;
    _followUp = null;
    if (!_online) {
      if (followUp != null) _pending = _pending?.merge(followUp) ?? followUp;
      _emit(SyncTriggerPhase.offline, _pending);
      return;
    }
    if (crash != null) {
      _reportCrash(crash, crashStack!);
      _pending = _pending?.merge(selected) ?? selected;
      if (followUp != null) _pending = _pending!.merge(followUp);
      _emit(SyncTriggerPhase.blocked, _pending);
      return;
    }
    switch (disposition) {
      case SyncTriggerRunDisposition.completed:
        _emit(SyncTriggerPhase.idle, followUp);
        if (followUp != null) _enqueue(followUp);
      case SyncTriggerRunDisposition.blocked:
        if (followUp != null) _pending = _pending?.merge(followUp) ?? followUp;
        _emit(SyncTriggerPhase.blocked, _pending);
      case SyncTriggerRunDisposition.offline:
        _online = false;
        if (followUp != null) _pending = _pending?.merge(followUp) ?? followUp;
        _emit(SyncTriggerPhase.offline, _pending);
      case SyncTriggerRunDisposition.backoff:
        if (followUp != null) _pending = _pending?.merge(followUp) ?? followUp;
        _emit(SyncTriggerPhase.backoff, _pending);
      case null:
        _emit(SyncTriggerPhase.idle, followUp);
        if (followUp != null) _enqueue(followUp);
    }
  }

  void _emit(SyncTriggerPhase phase, _PendingTrigger<K>? selected) {
    if (_disposed) return;
    _snapshot = SyncTriggerSnapshot<K>._(
      phase: phase,
      generation: _snapshot.generation,
      pendingDatasets: selected?.datasets ?? <K>{},
      cause: selected?.cause,
    );
    _states.add(_snapshot);
  }

  void _requireLive() {
    if (_disposed) throw StateError('SyncTriggerCoordinator is disposed.');
    if (!_started) throw StateError('SyncTriggerCoordinator is not started.');
  }

  /// Cancels and drains work, removes all source listeners, and closes states.
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _activeCancellation?.cancel(SyncTriggerCancellationReason.disposed);
    for (final subscription in _subscriptions.reversed) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _activeRun;
    _scheduled = null;
    _followUp = null;
    _pending = null;
    await _states.close();
  }
}

final class _PendingTrigger<K> {
  _PendingTrigger({
    required this.cause,
    required Set<K> datasets,
    required this.generation,
    required this.deadline,
  }) : datasets = Set<K>.unmodifiable(datasets);

  final SyncTriggerCause cause;
  final Set<K> datasets;
  final int generation;
  final DateTime? deadline;

  _PendingTrigger<K> merge(_PendingTrigger<K> other) {
    if (generation != other.generation) return other;
    return _PendingTrigger<K>(
      cause: cause.priority >= other.cause.priority ? cause : other.cause,
      datasets: <K>{...datasets, ...other.datasets},
      generation: generation,
      deadline: _earliest(deadline, other.deadline),
    );
  }

  SyncTriggerBatch<K> toBatch() => SyncTriggerBatch<K>._(
    cause: cause,
    datasets: datasets,
    generation: generation,
    deadline: deadline,
  );

  static DateTime? _earliest(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return left.isBefore(right) ? left : right;
  }
}
