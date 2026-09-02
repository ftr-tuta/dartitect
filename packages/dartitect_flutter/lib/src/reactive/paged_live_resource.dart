import 'dart:async';
import 'dart:collection';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'listener_registry.dart';
import 'live_collection.dart';
import 'live_resource.dart';
import 'resource_lifecycle.dart';

/// Reason one page pipeline was started.
enum PageOperation {
  /// Reloads the first page and joins an existing refresh.
  refresh,

  /// Appends the current cursor and drops duplicate calls while busy.
  loadMore,

  /// Replaces the current search generation using restart-latest.
  search,
}

/// Ordered phases exposed for deterministic causal timeline tests.
enum PageTimelinePhase {
  /// Remote work has been admitted.
  requestStarted,

  /// A typed remote page was received.
  responseReceived,

  /// The consumer-owned local transaction returned its receipt.
  localWriteCommitted,

  /// The local source published the receipt revision.
  localObserved,

  /// Cursor publication completed.
  completed,

  /// An expected typed failure completed the pipeline.
  failed,
}

/// Sanitized dependents-first teardown phase for a paged resource.
enum PagedDisposePhase {
  /// New page work may still be admitted.
  active,

  /// Page command lanes are cancelling and draining.
  lanes,

  /// Receipt waiters and their timers are being released.
  waiters,

  /// The borrowed local-resource observation is detaching.
  localObservation,

  /// Owned collection nodes are being released.
  collection,

  /// The payload-free timeline is closing.
  timeline,

  /// Teardown completed.
  complete,
}

/// Typed request passed to the injected remote page callback.
final class PageRequest<C> {
  /// Creates an immutable page request.
  const PageRequest({
    required this.operation,
    required this.cursor,
    required this.reset,
  });

  /// Scheduling operation that admitted this request.
  final PageOperation operation;

  /// Typed cursor used for the remote request.
  final C cursor;

  /// Whether the local transaction should replace the previous result set.
  final bool reset;
}

/// Remote page data that is not itself published to presentation.
final class PageBatch<C, T> {
  /// Creates a remote batch and its next cursor.
  const PageBatch({required this.items, required this.nextCursor});

  /// Consumer entities returned by the remote boundary.
  final List<T> items;

  /// Cursor for the next page, or null when pagination is exhausted.
  final C? nextCursor;
}

/// Deduplicated write input passed to the consumer-owned local transaction.
final class PageWrite<C, T> {
  /// Creates one immutable local write request.
  const PageWrite({
    required this.operation,
    required this.items,
    required this.nextCursor,
    required this.reset,
    required this.duplicateCount,
  });

  /// Operation that produced the remote batch.
  final PageOperation operation;

  /// Stable-key-deduplicated items in first-seen order.
  final List<T> items;

  /// Cursor supplied by the remote batch.
  final C? nextCursor;

  /// Whether the local transaction should replace prior page data.
  final bool reset;

  /// Number of duplicate keys removed before the local transaction.
  final int duplicateCount;
}

/// Receipt returned only after the consumer-owned local transaction commits.
final class PageWriteReceipt<C> {
  /// Creates a receipt that must later be observed from the local source.
  const PageWriteReceipt({
    required this.localRevision,
    required this.nextCursor,
  });

  /// Typed repository revision expected from the authoritative local source.
  final Object localRevision;

  /// Cursor that becomes public only after [localRevision] is observed.
  final C? nextCursor;
}

/// Authoritative local page snapshot consumed by [PagedLiveResource].
final class PagedLocalSnapshot<K, T> {
  /// Creates a local snapshot with one transaction/query revision.
  const PagedLocalSnapshot({required this.revision, required this.items});

  /// Revision matching a [PageWriteReceipt.localRevision].
  final Object revision;

  /// Complete ordered local result set for presentation.
  final List<T> items;
}

/// One causal page phase emitted without retaining an unbounded transcript.
final class PageTimelineEvent<C> {
  /// Creates a timeline event with a resource-local monotonic [sequence].
  const PageTimelineEvent({
    required this.sequence,
    required this.operation,
    required this.phase,
    required this.cursor,
    this.localRevision,
  });

  /// Monotonic sequence within one paged resource.
  final int sequence;

  /// Operation that owns this event.
  final PageOperation operation;

  /// Causal phase.
  final PageTimelinePhase phase;

  /// Cursor used by the request or published by the receipt.
  final C? cursor;

  /// Local revision for write/observation phases.
  final Object? localRevision;
}

/// Receives an unexpected local projection crash.
abstract interface class PagedResourceCrashReporter {
  /// Reports [error] while preserving [stackTrace].
  void report(Object error, StackTrace stackTrace);
}

/// Reporter that deliberately ignores unexpected page pipeline crashes.
final class NoOpPagedResourceCrashReporter
    implements PagedResourceCrashReporter {
  /// Creates a no-op reporter.
  const NoOpPagedResourceCrashReporter();

  @override
  void report(Object error, StackTrace stackTrace) {}
}

/// Local-first paged collection with explicit concurrency and causal cursors.
final class PagedLiveResource<C, K, T, F extends Object>
    implements Listenable, AsyncDisposable {
  /// Creates a resource around a borrowed authoritative [local] source.
  ///
  /// [requestPage] performs remote I/O only. [writePage] owns the consumer's
  /// local transaction. Presentation changes exclusively through [local].
  PagedLiveResource({
    required LiveResource<PagedLocalSnapshot<K, T>, F> local,
    required C initialCursor,
    required Future<Result<PageBatch<C, T>, F>> Function(
      PageRequest<C> request,
      CancellationSignal signal,
    )
    requestPage,
    required Future<Result<PageWriteReceipt<C>, F>> Function(
      PageWrite<C, T> write,
      CancellationSignal signal,
    )
    writePage,
    required K Function(T item) keyOf,
    required Duration observationTimeout,
    required F Function(PageWriteReceipt<C> receipt) mapObservationTimeout,
    CollectionUpdatePolicy collectionPolicy = CollectionUpdatePolicy.diffByKey,
    Object? Function(T item)? versionOf,
    T Function(T item)? project,
    Duration tombstoneRetention = const Duration(minutes: 5),
    ReactiveTimerFactory timerFactory = const SystemReactiveTimerFactory(),
    PagedResourceCrashReporter reporter =
        const NoOpPagedResourceCrashReporter(),
    int recentRevisionLimit = 128,
  }) : _initialCursor = initialCursor,
       _requestPage = requestPage,
       _writePage = writePage,
       _keyOf = keyOf,
       _observationTimeout = _positive(observationTimeout),
       _mapObservationTimeout = mapObservationTimeout,
       _collectionPolicy = collectionPolicy,
       _versionOf = versionOf,
       _project = project ?? _identity,
       _timerFactory = timerFactory,
       _reporter = reporter,
       _recentRevisionLimit = _positiveCount(recentRevisionLimit),
       collection = LiveCollection<K, T>(
         tombstoneRetention: tombstoneRetention,
         timerFactory: timerFactory,
       ),
       _localObservation = local.observe() {
    if (collectionPolicy == CollectionUpdatePolicy.versionedByKey &&
        versionOf == null) {
      throw ArgumentError.notNull('versionOf');
    }
    _refreshLane = CommandLane<PageWriteReceipt<C>, F>(
      action: (signal) => _runPage(
        PageRequest<C>(
          operation: PageOperation.refresh,
          cursor: _initialCursor,
          reset: true,
        ),
        signal,
      ),
      concurrency: const CommandConcurrency.join(),
    );
    _loadMoreLane = CommandLane<PageWriteReceipt<C>, F>(
      action: (signal) {
        final cursor = _nextCursor;
        if (cursor == null) {
          throw StateError('No next page cursor is available.');
        }
        return _runPage(
          PageRequest<C>(
            operation: PageOperation.loadMore,
            cursor: cursor,
            reset: false,
          ),
          signal,
        );
      },
      concurrency: const CommandConcurrency.drop(),
    );
    _searchLane = KeyedCommandLane<_SearchLane, C, PageWriteReceipt<C>, F>(
      action: (_, cursor, signal) => _runPage(
        PageRequest<C>(
          operation: PageOperation.search,
          cursor: cursor,
          reset: true,
        ),
        signal,
      ),
      concurrency: const CommandConcurrency.keyed(
        perKey: CommandConcurrency.restartLatest(),
        maxConcurrent: 1,
      ),
    );
    _localObservation.addListener(_localChanged);
    _localChanged();
  }

  final Future<Result<PageBatch<C, T>, F>> Function(
    PageRequest<C> request,
    CancellationSignal signal,
  )
  _requestPage;
  final Future<Result<PageWriteReceipt<C>, F>> Function(
    PageWrite<C, T> write,
    CancellationSignal signal,
  )
  _writePage;
  final K Function(T item) _keyOf;
  final Duration _observationTimeout;
  final F Function(PageWriteReceipt<C> receipt) _mapObservationTimeout;
  final CollectionUpdatePolicy _collectionPolicy;
  final Object? Function(T item)? _versionOf;
  final T Function(T item) _project;
  final ReactiveTimerFactory _timerFactory;
  final PagedResourceCrashReporter _reporter;
  final int _recentRevisionLimit;
  final ReactiveObservation<PagedLocalSnapshot<K, T>, F> _localObservation;
  final ListenerRegistry _listeners = ListenerRegistry();
  final LinkedHashSet<Object> _recentRevisions = LinkedHashSet<Object>();
  final Map<Object, List<_PageObservationWaiter<C, F>>> _waiters =
      <Object, List<_PageObservationWaiter<C, F>>>{};
  final StreamController<PageTimelineEvent<C>> _timeline =
      StreamController<PageTimelineEvent<C>>.broadcast(sync: true);
  late final CommandLane<PageWriteReceipt<C>, F> _refreshLane;
  late final CommandLane<PageWriteReceipt<C>, F> _loadMoreLane;
  late final KeyedCommandLane<_SearchLane, C, PageWriteReceipt<C>, F>
  _searchLane;
  C _initialCursor;
  C? _nextCursor;
  F? _lastFailure;
  Object? _crash;
  StackTrace? _crashStackTrace;
  var _refreshCallers = 0;
  var _loadMoreCallers = 0;
  var _searchCallers = 0;
  var _timelineSequence = 0;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Incremental local collection presented to consumers.
  final LiveCollection<K, T> collection;

  /// Cursor admitted for the next load-more request, if any.
  C? get nextCursor => _nextCursor;

  /// Initial cursor used by refresh and last successful search generation.
  C get initialCursor => _initialCursor;

  /// Latest expected failure; cancellations and stale generations do not set it.
  F? get lastFailure => _lastFailure;

  /// Latest unexpected crash from projection or a command action.
  Object? get crash => _crash;

  /// Stack trace paired with [crash].
  StackTrace? get crashStackTrace => _crashStackTrace;

  /// Whether at least one refresh caller is awaiting the joined execution.
  bool get isRefreshing => _refreshCallers > 0;

  /// Whether at least one load-more caller is awaiting an execution/outcome.
  bool get isLoadingMore => _loadMoreCallers > 0;

  /// Whether at least one search generation caller has not settled.
  bool get isSearching => _searchCallers > 0;

  /// Whether any public page operation is awaiting an outcome.
  bool get isBusy => isRefreshing || isLoadingMore || isSearching;

  /// Number of receipt observations currently retained.
  int get observationWaiterCount =>
      _waiters.values.fold(0, (count, values) => count + values.length);

  /// Number of active receipt timeout handles.
  int get activeTimerCount => _waiters.values
      .expand((values) => values)
      .where((waiter) => waiter.timer?.isActive ?? false)
      .length;

  /// Number of recently observed revisions retained for write-before-wait races.
  int get retainedRevisionCount => _recentRevisions.length;

  /// Causal timeline stream; events are not retained by the resource.
  Stream<PageTimelineEvent<C>> get timeline => _timeline.stream;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Current sanitized teardown phase.
  PagedDisposePhase get disposePhase => _disposePhase;

  PagedDisposePhase _disposePhase = PagedDisposePhase.active;

  /// Latest lifecycle transition of the borrowed local resource.
  Future<void> get settled => _localObservation.settled;

  @override
  void addListener(VoidCallback listener) {
    _ensureActive();
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Reloads from [initialCursor], joining an already running refresh.
  Future<CommandOutcome<PageWriteReceipt<C>, F>> refresh() {
    _ensureActive();
    return _track(PageOperation.refresh, _refreshLane.execute());
  }

  /// Loads [nextCursor], dropping duplicate calls while one is running.
  Future<CommandOutcome<PageWriteReceipt<C>, F>> loadMore() {
    _ensureActive();
    if (_nextCursor == null) {
      return Future<CommandOutcome<PageWriteReceipt<C>, F>>.value(
        CommandDropped<PageWriteReceipt<C>, F>(),
      );
    }
    return _track(PageOperation.loadMore, _loadMoreLane.execute());
  }

  /// Restarts search from [initialCursor], cancelling any stale generation.
  Future<CommandOutcome<PageWriteReceipt<C>, F>> search(C initialCursor) {
    _ensureActive();
    return _track(
      PageOperation.search,
      _searchLane.execute(_SearchLane.only, initialCursor),
    );
  }

  /// Cancels/drains page work, then releases observation and collection nodes.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  @override
  Future<void> disposeAsync() => dispose();

  Future<Result<PageWriteReceipt<C>, F>> _runPage(
    PageRequest<C> request,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    _emit(request.operation, PageTimelinePhase.requestStarted, request.cursor);
    final requested = await _requestPage(request, signal);
    signal.throwIfCancelled();
    late final PageBatch<C, T> page;
    switch (requested) {
      case Ok<dynamic>(:final value):
        page = value as PageBatch<C, T>;
      case Err<Object>(:final failure, :final stackTrace):
        return _failed<PageWriteReceipt<C>>(request, failure as F, stackTrace);
    }
    _emit(
      request.operation,
      PageTimelinePhase.responseReceived,
      request.cursor,
    );

    final unique = LinkedHashMap<K, T>();
    for (final item in page.items) {
      unique[_keyOf(item)] = item;
    }
    final write = PageWrite<C, T>(
      operation: request.operation,
      items: List<T>.unmodifiable(unique.values),
      nextCursor: page.nextCursor,
      reset: request.reset,
      duplicateCount: page.items.length - unique.length,
    );
    signal.throwIfCancelled();
    final written = await _writePage(write, signal);
    signal.throwIfCancelled();
    late final PageWriteReceipt<C> committed;
    switch (written) {
      case Ok<dynamic>(:final value):
        committed = value as PageWriteReceipt<C>;
      case Err<Object>(:final failure, :final stackTrace):
        return _failed<PageWriteReceipt<C>>(request, failure as F, stackTrace);
    }
    _emit(
      request.operation,
      PageTimelinePhase.localWriteCommitted,
      committed.nextCursor,
      localRevision: committed.localRevision,
    );

    final observed = await _waitForLocal(request, committed, signal);
    signal.throwIfCancelled();
    if (observed case Err<Object>(:final failure, :final stackTrace)) {
      return _failed<PageWriteReceipt<C>>(request, failure as F, stackTrace);
    }
    _nextCursor = committed.nextCursor;
    if (request.operation == PageOperation.search) {
      _initialCursor = request.cursor;
    }
    _lastFailure = null;
    _emit(
      request.operation,
      PageTimelinePhase.completed,
      committed.nextCursor,
      localRevision: committed.localRevision,
    );
    _notify();
    return Ok<PageWriteReceipt<C>>(committed);
  }

  Result<R, F> _failed<R>(
    PageRequest<C> request,
    F failure,
    StackTrace stackTrace,
  ) {
    _emit(request.operation, PageTimelinePhase.failed, request.cursor);
    return Err<F>(failure, stackTrace);
  }

  Future<Result<void, F>> _waitForLocal(
    PageRequest<C> request,
    PageWriteReceipt<C> receipt,
    CancellationSignal signal,
  ) {
    if (_recentRevisions.contains(receipt.localRevision)) {
      _emit(
        request.operation,
        PageTimelinePhase.localObserved,
        receipt.nextCursor,
        localRevision: receipt.localRevision,
      );
      return Future<Result<void, F>>.value(Ok<void>(null));
    }
    final waiter = _PageObservationWaiter<C, F>(request, receipt);
    _waiters
        .putIfAbsent(
          receipt.localRevision,
          () => <_PageObservationWaiter<C, F>>[],
        )
        .add(waiter);
    waiter.timer = _timerFactory.schedule(
      _observationTimeout,
      () => _timeoutWaiter(waiter),
    );
    waiter.cancellation = signal.register((reason) {
      if (waiter.completer.isCompleted) return;
      _removeWaiter(waiter);
      waiter.timer?.cancel();
      waiter.timer = null;
      waiter.cancellation?.dispose();
      waiter.cancellation = null;
      waiter.completer.completeError(CancellationException(reason));
    });
    return waiter.completer.future;
  }

  void _localChanged() {
    if (_disposed || !_localObservation.state.hasData) return;
    final snapshot = _localObservation.state.lastData;
    if (snapshot == null) return;
    try {
      collection.update<T>(
        snapshot.items,
        keyOf: _keyOf,
        project: _project,
        policy: _collectionPolicy,
        versionOf: _versionOf,
      );
      _rememberRevision(snapshot.revision);
      final waiters = _waiters.remove(snapshot.revision);
      if (waiters != null) {
        for (final waiter in waiters) {
          waiter.timer?.cancel();
          waiter.timer = null;
          waiter.cancellation?.dispose();
          waiter.cancellation = null;
          if (!waiter.completer.isCompleted) {
            _emit(
              waiter.request.operation,
              PageTimelinePhase.localObserved,
              waiter.receipt.nextCursor,
              localRevision: waiter.receipt.localRevision,
            );
            waiter.completer.complete(Ok<void>(null));
          }
        }
      }
    } catch (error, stackTrace) {
      _recordCrash(error, stackTrace);
    }
  }

  void _rememberRevision(Object revision) {
    _recentRevisions.remove(revision);
    _recentRevisions.add(revision);
    while (_recentRevisions.length > _recentRevisionLimit) {
      _recentRevisions.remove(_recentRevisions.first);
    }
  }

  void _timeoutWaiter(_PageObservationWaiter<C, F> waiter) {
    if (_disposed || waiter.completer.isCompleted) return;
    _removeWaiter(waiter);
    waiter.timer = null;
    waiter.cancellation?.dispose();
    waiter.cancellation = null;
    try {
      waiter.completer.complete(
        Err<F>(_mapObservationTimeout(waiter.receipt), StackTrace.current),
      );
    } catch (error, stackTrace) {
      waiter.completer.completeError(error, stackTrace);
    }
  }

  void _removeWaiter(_PageObservationWaiter<C, F> waiter) {
    final values = _waiters[waiter.receipt.localRevision];
    values?.remove(waiter);
    if (values?.isEmpty ?? false) {
      _waiters.remove(waiter.receipt.localRevision);
    }
  }

  Future<CommandOutcome<PageWriteReceipt<C>, F>> _track(
    PageOperation operation,
    Future<CommandOutcome<PageWriteReceipt<C>, F>> outcome,
  ) async {
    _adjustCallers(operation, 1);
    _notify();
    try {
      final value = await outcome;
      if (value case CommandFailed<PageWriteReceipt<C>, F>(:final failure)) {
        _lastFailure = failure;
        _notify();
      }
      return value;
    } catch (error, stackTrace) {
      _recordCrash(error, stackTrace);
      rethrow;
    } finally {
      _adjustCallers(operation, -1);
      _notify();
    }
  }

  void _adjustCallers(PageOperation operation, int delta) {
    switch (operation) {
      case PageOperation.refresh:
        _refreshCallers += delta;
      case PageOperation.loadMore:
        _loadMoreCallers += delta;
      case PageOperation.search:
        _searchCallers += delta;
    }
  }

  void _recordCrash(Object error, StackTrace stackTrace) {
    if (_crash != null || _disposed) return;
    _crash = error;
    _crashStackTrace = stackTrace;
    _reportCrash(error, stackTrace);
    final waiters = _waiters.values.expand((values) => values).toList();
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.timer?.cancel();
      waiter.timer = null;
      waiter.cancellation?.dispose();
      waiter.cancellation = null;
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(error, stackTrace);
      }
    }
    _notify();
  }

  void _reportCrash(Object error, StackTrace stackTrace) {
    try {
      _reporter.report(error, stackTrace);
    } catch (_) {
      // Reporting must not alter page or local state.
      return;
    }
  }

  void _emit(
    PageOperation operation,
    PageTimelinePhase phase,
    C? cursor, {
    Object? localRevision,
  }) {
    if (_disposed || _timeline.isClosed) return;
    _timeline.add(
      PageTimelineEvent<C>(
        sequence: ++_timelineSequence,
        operation: operation,
        phase: phase,
        cursor: cursor,
        localRevision: localRevision,
      ),
    );
  }

  void _notify() {
    if (_disposed) return;
    _listeners.notifySafely(shouldContinue: () => !_disposed);
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _disposePhase = PagedDisposePhase.lanes;
    await Future.wait<void>(<Future<void>>[
      _searchLane.dispose(),
      _loadMoreLane.dispose(),
      _refreshLane.dispose(),
    ]);
    _disposePhase = PagedDisposePhase.waiters;
    final waiters = _waiters.values.expand((values) => values).toList();
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.timer?.cancel();
      waiter.cancellation?.dispose();
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(
          const CancellationException('PagedLiveResource disposed'),
        );
      }
    }
    _disposePhase = PagedDisposePhase.localObservation;
    _localObservation.removeListener(_localChanged);
    await _localObservation.close();
    _disposePhase = PagedDisposePhase.collection;
    await collection.dispose();
    _recentRevisions.clear();
    _listeners.clear();
    _disposePhase = PagedDisposePhase.timeline;
    await _timeline.close();
    _disposePhase = PagedDisposePhase.complete;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('PagedLiveResource is disposed.');
  }

  static Duration _positive(Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(
        value,
        'observationTimeout',
        'Must be positive.',
      );
    }
    return value;
  }

  static int _positiveCount(int value) {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'recentRevisionLimit',
        'Must be positive.',
      );
    }
    return value;
  }

  static T _identity<T>(T value) => value;
}

enum _SearchLane { only }

final class _PageObservationWaiter<C, F extends Object> {
  _PageObservationWaiter(this.request, this.receipt);

  final PageRequest<C> request;
  final PageWriteReceipt<C> receipt;
  final Completer<Result<void, F>> completer = Completer<Result<void, F>>();
  ReactiveTimerHandle? timer;
  CancellationRegistration? cancellation;
}
