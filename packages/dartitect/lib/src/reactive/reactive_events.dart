import 'dart:async';

import '../lifecycle/contracts.dart';

/// Static, payload-free reason for one reactive state transition.
final class ChangeCause {
  /// Declares a cause intended to be stored in a [ChangeCauseRegistry].
  const ChangeCause(this.key, this.label);

  /// Stable machine key.
  final String key;

  /// Stable human-readable label.
  final String label;
}

/// Built-in static causes emitted by Dartitect runtime primitives.
abstract final class ChangeCauses {
  /// One explicit atomic graph update.
  static const reactiveUpdate = ChangeCause(
    'reactive.update',
    'Reactive update',
  );

  /// One new local-first mutation.
  static const mutationExecute = ChangeCause(
    'mutation.execute',
    'Mutation execute',
  );

  /// One explicit retry of a durable mutation.
  static const mutationRetry = ChangeCause('mutation.retry', 'Mutation retry');

  /// One pending mutation recovered during session start.
  static const mutationRecovery = ChangeCause(
    'mutation.recovery',
    'Mutation recovery',
  );

  /// Built-in identities accepted by the standard registry.
  static const values = <ChangeCause>[
    reactiveUpdate,
    mutationExecute,
    mutationRetry,
    mutationRecovery,
  ];
}

/// Identity registry that rejects reconstructed/dynamic cause instances.
final class ChangeCauseRegistry {
  /// Creates a registry from built-in and consumer-declared static identities.
  ChangeCauseRegistry({Iterable<ChangeCause> causes = ChangeCauses.values}) {
    for (final cause in causes) {
      _validateText(cause);
      final existing = _causes[cause.key];
      if (existing != null && !identical(existing, cause)) {
        throw ArgumentError.value(
          cause.key,
          'causes',
          'Cause keys must be unique identities.',
        );
      }
      _causes[cause.key] = cause;
    }
  }

  final Map<String, ChangeCause> _causes = <String, ChangeCause>{};

  /// Number of registered static identities.
  int get length => _causes.length;

  /// Returns [cause] only when its exact identity was registered.
  ChangeCause requireStatic(ChangeCause cause) {
    final registered = _causes[cause.key];
    if (!identical(registered, cause)) {
      throw ArgumentError.value(
        cause,
        'cause',
        'Use the exact static ChangeCause registered at composition.',
      );
    }
    return cause;
  }

  static void _validateText(ChangeCause cause) {
    if (!RegExp(r'^[a-z]+(?:[._][a-z]+)*$').hasMatch(cause.key)) {
      throw ArgumentError.value(
        cause.key,
        'cause.key',
        'Use lowercase static words separated by dot or underscore.',
      );
    }
    if (!RegExp(r'^[A-Za-z]+(?: [A-Za-z]+)*$').hasMatch(cause.label)) {
      throw ArgumentError.value(
        cause.label,
        'cause.label',
        'Use static alphabetic words separated by single spaces.',
      );
    }
  }
}

/// Fixed runtime source categories; no consumer payload enters an event.
enum ReactiveEventSource {
  /// Atomic `ReactiveOwner`-style graph updates in the Flutter package.
  reactiveOwner,

  /// Durable local-first mutation pipelines.
  mutationCommand,

  /// Lifecycle-aware local or adapter resources.
  liveResource,

  /// Incremental keyed collections.
  liveCollection,

  /// Local-first pagination pipelines.
  pagedResource,
}

/// Payload-free outcome category for one reactive event.
enum ReactiveEventKind {
  /// A stable state transition was published.
  updated,

  /// An expected typed failure ended an operation.
  failed,

  /// Cooperative cancellation ended an operation.
  cancelled,

  /// An unexpected crash occurred after safe recovery state was attempted.
  crashed,
}

/// Immutable allowlisted facts for one runtime transition.
final class ReactiveChangeEvent {
  /// Creates a payload-free event.
  ReactiveChangeEvent({
    required this.source,
    required this.kind,
    required this.cause,
    required this.previousRevision,
    required this.nextRevision,
    required this.duration,
    required this.listenerCount,
  }) {
    if (previousRevision < 0 || nextRevision < previousRevision) {
      throw ArgumentError(
        'Reactive revisions must be monotonic and non-negative.',
      );
    }
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    if (listenerCount < 0) {
      throw ArgumentError.value(
        listenerCount,
        'listenerCount',
        'Must not be negative.',
      );
    }
  }

  /// Static runtime source.
  final ReactiveEventSource source;

  /// Static transition category.
  final ReactiveEventKind kind;

  /// Registered static cause identity.
  final ChangeCause cause;

  /// Source revision before the transition.
  final int previousRevision;

  /// Source revision after the transition.
  final int nextRevision;

  /// Monotonic operation duration.
  final Duration duration;

  /// Downstream listener count at publication.
  final int listenerCount;
}

/// Synchronous observer for sanitized reactive facts.
abstract interface class ReactiveObserver {
  /// Receives one event without affecting runtime behavior.
  void onChange(ReactiveChangeEvent event);
}

/// Observer that deliberately ignores every event.
final class NoOpReactiveObserver implements ReactiveObserver {
  /// Creates a no-op observer.
  const NoOpReactiveObserver();

  @override
  void onChange(ReactiveChangeEvent event) {}
}

/// Explicit borrowed or owned observer registration.
final class ReactiveObserverRegistration {
  /// Borrows [observer] and never disposes it.
  const ReactiveObserverRegistration.borrowed(this.observer) : _dispose = null;

  /// Owns [observer] through the explicit [dispose] callback.
  const ReactiveObserverRegistration.owned(
    this.observer, {
    required FutureOr<void> Function() dispose,
  }) : _dispose = dispose;

  /// Registered observer.
  final ReactiveObserver observer;

  final FutureOr<void> Function()? _dispose;

  /// Whether this registration owns observer teardown.
  bool get isOwned => _dispose != null;

  /// Runs owned teardown, or completes immediately for a borrowed observer.
  Future<void> disposeOwned() async => _dispose?.call();
}

/// Failure-isolating and reentrancy-safe observer wrapper.
final class SafeReactiveObserver implements ReactiveObserver {
  /// Wraps a borrowed observer and optionally reports its first failure.
  SafeReactiveObserver({
    required ReactiveObserver observer,
    void Function(Object error, StackTrace stackTrace)? onFailure,
    this.disableAfterFailure = true,
  }) : _observer = observer,
       _onFailure = onFailure;

  final ReactiveObserver _observer;
  final void Function(Object error, StackTrace stackTrace)? _onFailure;
  var _emitting = false;
  var _disabled = false;
  var _failureCount = 0;
  var _droppedReentrantEvents = 0;

  /// Whether a failure disabled this observer.
  bool get isDisabled => _disabled;

  /// Observer failures seen by this wrapper.
  int get failureCount => _failureCount;

  /// Recursive emissions dropped to prevent observer loops.
  int get droppedReentrantEvents => _droppedReentrantEvents;

  /// Whether the observer is disabled after its first failure.
  final bool disableAfterFailure;

  @override
  void onChange(ReactiveChangeEvent event) {
    if (_disabled) return;
    if (_emitting) {
      _droppedReentrantEvents += 1;
      return;
    }
    _emitting = true;
    try {
      _observer.onChange(event);
    } catch (error, stackTrace) {
      _failureCount += 1;
      if (disableAfterFailure) _disabled = true;
      final report = _onFailure;
      if (report != null) {
        try {
          report(error, stackTrace);
        } on Object {
          return;
        }
      }
    } finally {
      _emitting = false;
    }
  }
}

/// Opt-in bounded in-memory ring journal.
final class ReactiveJournal implements ReactiveObserver, Disposable {
  /// Creates an empty journal with a positive [capacity].
  ReactiveJournal({int capacity = 200})
    : capacity = _positiveCapacity(capacity),
      _entries = List<ReactiveChangeEvent?>.filled(
        _positiveCapacity(capacity),
        null,
      );

  /// Maximum retained event count.
  final int capacity;

  final List<ReactiveChangeEvent?> _entries;
  var _start = 0;
  var _length = 0;
  var _disposed = false;

  /// Events retained from oldest to newest.
  List<ReactiveChangeEvent> get entries {
    if (_disposed) return const <ReactiveChangeEvent>[];
    return List<ReactiveChangeEvent>.unmodifiable(
      List<ReactiveChangeEvent>.generate(
        _length,
        (index) => _entries[(_start + index) % capacity]!,
      ),
    );
  }

  /// Current retained event count.
  int get length => _disposed ? 0 : _length;

  /// Whether the journal has been terminally cleared.
  bool get isDisposed => _disposed;

  @override
  void onChange(ReactiveChangeEvent event) {
    if (_disposed) return;
    if (_length < capacity) {
      _entries[(_start + _length) % capacity] = event;
      _length += 1;
      return;
    }
    _entries[_start] = event;
    _start = (_start + 1) % capacity;
  }

  /// Clears every retained event and rejects future retention.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (var index = 0; index < _entries.length; index += 1) {
      _entries[index] = null;
    }
    _start = 0;
    _length = 0;
  }

  static int _positiveCapacity(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'capacity', 'Must be positive.');
    }
    return value;
  }
}
