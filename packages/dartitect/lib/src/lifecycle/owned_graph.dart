import 'dart:async';

import '../observer.dart';
import 'contracts.dart';
import 'resource_owner.dart';

/// A failure raised while rolling back a failed graph construction.
///
/// [creationError] remains the primary failure and keeps its original stack;
/// [rollbackError] records the independent cleanup failure.
final class ResourceTransactionException implements Exception {
  /// Creates a combined construction and rollback failure.
  const ResourceTransactionException({
    required this.creationError,
    required this.creationStackTrace,
    required this.rollbackError,
    required this.rollbackStackTrace,
  });

  /// Error that prevented graph construction.
  final Object creationError;

  /// Original construction stack trace.
  final StackTrace creationStackTrace;

  /// Error raised while releasing partially acquired resources.
  final Object rollbackError;

  /// Original rollback stack trace.
  final StackTrace rollbackStackTrace;

  @override
  String toString() =>
      'ResourceTransactionException(creation: $creationError; '
      'rollback: $rollbackError)';
}

/// A replacement that published successfully but could not clean up the
/// previous graph completely.
///
/// [publishedGeneration] is authoritative: callers must not retry the
/// replacement blindly. [cleanupError] and [cleanupStackTrace] describe only
/// the secondary teardown outcome for the previous generation.
final class OwnedRuntimeReplacementCleanupException implements Exception {
  /// Creates a typed post-publication cleanup failure.
  const OwnedRuntimeReplacementCleanupException({
    required this.publishedGeneration,
    required this.cleanupError,
    required this.cleanupStackTrace,
  });

  /// Generation already installed before cleanup failed.
  final int publishedGeneration;

  /// Failure raised by disposal of the previous generation.
  final Object cleanupError;

  /// Original cleanup stack trace.
  final StackTrace cleanupStackTrace;

  @override
  String toString() =>
      'OwnedRuntimeReplacementCleanupException('
      'publishedGeneration: $publishedGeneration; cleanup: $cleanupError)';
}

/// Transactionally acquires resources for one owned object graph.
///
/// Owned resources are registered only after successful acquisition and are
/// released in LIFO order if construction fails. Borrowed resources are
/// deliberately returned unchanged and never enter the rollback owner. A
/// transaction is terminal after [commit] or [rollback].
final class ResourceTransaction implements AsyncDisposable {
  /// Creates one graph-construction attempt.
  ResourceTransaction({
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    String label = 'ResourceTransaction',
  }) : _observer = observer,
       _label = label,
       _owner = ResourceOwner(observer: observer, label: '$label.owner');

  final ArchitectureObserver _observer;
  final String _label;
  ResourceOwner? _owner;
  var _terminal = false;

  /// Whether this construction attempt has committed or rolled back.
  bool get isTerminal => _terminal;

  /// Registers an acquired owned [value] for LIFO cleanup.
  T own<T>(T value, FutureOr<void> Function(T value) release, {String? label}) {
    final owner = _activeOwner();
    return owner.own(value, release, label: label);
  }

  /// Marks [value] as borrowed and returns it without registering cleanup.
  ///
  /// The provider remains responsible for teardown and must outlive the graph
  /// being built. Borrowed values are not included in [commit] or [rollback].
  T borrow<T>(T value) {
    _activeOwner();
    return value;
  }

  /// Commits the complete graph and transfers all acquired ownership.
  ///
  /// This is the transaction's ownership-transfer boundary: the complete set
  /// of owned resources moves atomically into the returned graph, while
  /// borrowed values remain with their providers. The transaction is terminal
  /// after this call and cannot acquire, borrow, or commit again.
  OwnedGraph<T> commit<T>(T root) {
    final owner = _activeOwner();
    _terminal = true;
    _owner = null;
    return OwnedGraph<T>._(
      root: root,
      owner: owner,
      observer: _observer,
      label: '$_label.graph',
    );
  }

  /// Releases every partially acquired resource exactly once.
  Future<void> rollback() async {
    final owner = _owner;
    if (_terminal || owner == null) return;
    _terminal = true;
    _owner = null;
    await owner.disposeAsync();
  }

  /// Builds and commits a graph, rolling back if [build] throws.
  static Future<OwnedGraph<T>> create<T>(
    FutureOr<T> Function(ResourceTransaction transaction) build, {
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    String label = 'ResourceTransaction',
  }) async {
    final transaction = ResourceTransaction(observer: observer, label: label);
    try {
      final root = await build(transaction);
      return transaction.commit(root);
    } catch (creationError, creationStackTrace) {
      try {
        await transaction.rollback();
      } catch (rollbackError, rollbackStackTrace) {
        Error.throwWithStackTrace(
          ResourceTransactionException(
            creationError: creationError,
            creationStackTrace: creationStackTrace,
            rollbackError: rollbackError,
            rollbackStackTrace: rollbackStackTrace,
          ),
          creationStackTrace,
        );
      }
      Error.throwWithStackTrace(creationError, creationStackTrace);
    }
  }

  @override
  Future<void> disposeAsync() => rollback();

  ResourceOwner _activeOwner() {
    final owner = _owner;
    if (_terminal || owner == null) {
      throw StateError('$_label is terminal.');
    }
    return owner;
  }
}

/// Owns one complete graph and drains admitted operations before teardown.
final class OwnedGraph<T> implements AsyncDisposable {
  OwnedGraph._({
    required this.root,
    required ResourceOwner owner,
    required ArchitectureObserver observer,
    required String label,
  }) : _owner = owner,
       _observer = observer,
       _label = label;

  /// Root value published only after its transaction commits.
  final T root;

  final ResourceOwner _owner;
  final ArchitectureObserver _observer;
  final String _label;
  final Set<Completer<void>> _operations = <Completer<void>>{};
  var _accepting = true;
  Future<void>? _disposal;

  /// Whether new operations may still be admitted.
  bool get isAccepting => _accepting && _disposal == null;

  /// Number of operations admitted and not yet completed.
  int get activeOperationCount => _operations.length;

  /// Whether teardown has completed.
  bool get isDisposed => _owner.isDisposed;

  /// Runs [operation] in this graph generation.
  ///
  /// Admission is synchronous, so a slot replacement can close the old
  /// generation without racing a new callback into it.
  Future<R> use<R>(FutureOr<R> Function(T root) operation) async {
    if (!isAccepting) {
      _emit(ArchitectureEventKind.operationAfterDispose);
      throw StateError('$_label is no longer accepting operations.');
    }
    final completion = Completer<void>();
    _operations.add(completion);
    try {
      return await operation(root);
    } finally {
      _operations.remove(completion);
      completion.complete();
    }
  }

  void _closeAdmission() => _accepting = false;

  /// Closes admission, drains admitted work, then releases resources in LIFO
  /// order. Concurrent callers share one completion.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _closeAdmission();
    while (_operations.isNotEmpty) {
      await Future.wait<void>(
        _operations.map((operation) => operation.future).toList(),
      );
    }
    await _owner.disposeAsync();
  }

  void _emit(ArchitectureEventKind kind) {
    try {
      _observer.onEvent(ArchitectureEvent(kind, source: _label));
    } on Object {
      // Optional diagnostics never change lifecycle behavior.
      return;
    }
  }
}

/// Atomically publishes and replaces owned graph generations.
///
/// Replacements are serialized. A new graph is built completely before it is
/// visible; construction failure keeps the previous generation valid. During
/// a successful replacement, old admission closes before publication and
/// already admitted work drains before old resources are released.
final class OwnedRuntimeSlot<T> implements AsyncDisposable {
  /// Creates an empty runtime slot.
  OwnedRuntimeSlot({
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    String label = 'OwnedRuntimeSlot',
  }) : _observer = observer,
       _label = label;

  final ArchitectureObserver _observer;
  final String _label;
  OwnedGraph<T>? _current;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  var _generation = 0;
  var _closing = false;

  /// Monotonic generation number; zero means no graph was installed.
  int get generation => _generation;

  /// Whether a committed graph is currently published.
  bool get hasCurrent => _current != null && !_closing;

  /// Runs [operation] against the generation current at admission time.
  Future<R> use<R>(FutureOr<R> Function(T root) operation) {
    final graph = _current;
    if (_closing || graph == null) {
      _emit(ArchitectureEventKind.operationAfterDispose);
      throw StateError('$_label has no active graph.');
    }
    return graph.use(operation);
  }

  /// Creates and installs a graph transactionally.
  Future<int> replace(
    FutureOr<T> Function(ResourceTransaction transaction) build,
  ) => replaceGraph(
    () => ResourceTransaction.create<T>(
      build,
      observer: _observer,
      label: '$_label.transaction',
    ),
  );

  /// Installs and assumes ownership of a pre-built graph after serializing.
  ///
  /// Once [create] returns a graph, this slot is responsible for disposing it,
  /// including when shutdown wins the race before publication.
  Future<int> replaceGraph(FutureOr<OwnedGraph<T>> Function() create) {
    if (_closing) throw StateError('$_label is shutting down.');
    final completer = Completer<int>();
    _tail = _tail
        .then((_) async {
          if (_closing) throw StateError('$_label is shutting down.');
          final next = await create();
          if (_closing) {
            await next.disposeAsync();
            throw StateError('$_label shut down during graph construction.');
          }
          final previous = _current;
          previous?._closeAdmission();
          _current = next;
          _generation += 1;
          final publishedGeneration = _generation;
          if (previous != null) {
            try {
              await previous.disposeAsync();
            } catch (cleanupError, cleanupStackTrace) {
              Error.throwWithStackTrace(
                OwnedRuntimeReplacementCleanupException(
                  publishedGeneration: publishedGeneration,
                  cleanupError: cleanupError,
                  cleanupStackTrace: cleanupStackTrace,
                ),
                cleanupStackTrace,
              );
            }
          }
          completer.complete(publishedGeneration);
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted)
            completer.completeError(error, stackTrace);
        });
    return completer.future;
  }

  /// Prevents replacements and closes the current generation.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _closing = true;
    await _tail;
    final current = _current;
    _current = null;
    await current?.disposeAsync();
  }

  void _emit(ArchitectureEventKind kind) {
    try {
      _observer.onEvent(ArchitectureEvent(kind, source: _label));
    } on Object {
      // Optional diagnostics never change lifecycle behavior.
      return;
    }
  }
}
