import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

/// One cursor page returned by a query transport.
final class DartitectQueryPage<T> {
  /// Creates an immutable page.
  DartitectQueryPage({required List<T> items, required this.nextCursor})
    : items = List<T>.unmodifiable(items);

  /// Decoded consumer values.
  final List<T> items;

  /// Opaque next cursor, or `null` at the end.
  final String? nextCursor;
}

/// Consumer query boundary with optional local authority.
abstract interface class DartitectQueryPort<Q, T, F extends Object> {
  /// Whether [watchLocal] is the only authority allowed to publish items.
  bool get localAuthority;

  /// Watches local authoritative values for [query].
  Stream<List<T>> watchLocal(Q query);

  /// Refreshes/fetches one remote or local page.
  Future<Result<DartitectQueryPage<T>, F>> fetch(
    Q query, {
    required String? cursor,
    required CancellationSignal cancellation,
  });
}

/// Consumer-owned restoration boundary for filters.
abstract interface class DartitectQueryRestorationStore<Q> {
  /// Loads previously serialized filters.
  Future<Q?> load();

  /// Persists current filters.
  Future<void> save(Q query);
}

/// Closed query presentation states.
sealed class DartitectQueryState<T, F extends Object> {
  const DartitectQueryState();
}

/// No query has completed yet.
final class DartitectQueryInitial<T, F extends Object>
    extends DartitectQueryState<T, F> {
  /// Creates the initial state.
  const DartitectQueryInitial();
}

/// Loading with optional stale content retained for rendering.
final class DartitectQueryLoading<T, F extends Object>
    extends DartitectQueryState<T, F> {
  /// Creates a loading state.
  DartitectQueryLoading({required List<T> staleItems})
    : staleItems = List<T>.unmodifiable(staleItems);

  /// Previously published content.
  final List<T> staleItems;
}

/// Successful query with no content.
final class DartitectQueryEmpty<T, F extends Object>
    extends DartitectQueryState<T, F> {
  /// Creates an empty state.
  const DartitectQueryEmpty();
}

/// Successful content, optionally stale during refresh.
final class DartitectQueryContent<T, F extends Object>
    extends DartitectQueryState<T, F> {
  /// Creates content state.
  DartitectQueryContent({
    required List<T> items,
    required this.stale,
    required this.hasMore,
  }) : items = List<T>.unmodifiable(items);

  /// Published values.
  final List<T> items;

  /// Whether a refresh is retaining old content.
  final bool stale;

  /// Whether another cursor page exists.
  final bool hasMore;
}

/// Expected typed query failure retaining optional stale content.
final class DartitectQueryFailure<T, F extends Object>
    extends DartitectQueryState<T, F> {
  /// Creates a failure state.
  DartitectQueryFailure({
    required this.failure,
    required this.stackTrace,
    required List<T> staleItems,
  }) : staleItems = List<T>.unmodifiable(staleItems);

  /// Consumer-owned expected failure.
  final F failure;

  /// Stack captured by the provider boundary.
  final StackTrace stackTrace;

  /// Previously published values.
  final List<T> staleItems;
}

/// Bulk-action boundary over the selected current values.
typedef DartitectQueryBulkAction<T, F extends Object> =
    Future<Result<void, F>> Function(
      List<T> selected,
      CancellationSignal cancellation,
    );

/// Debounced filters, local authority, pagination, selection, and restoration.
final class DartitectQueryController<Q, T, F extends Object>
    extends ChangeNotifier
    implements AsyncDisposable {
  /// Creates a query controller.
  DartitectQueryController({
    required Q initialQuery,
    required this.port,
    required this.identity,
    this.restoration,
    this.debounce = const Duration(milliseconds: 300),
  }) : _query = initialQuery {
    if (debounce.isNegative) {
      throw ArgumentError.value(debounce, 'debounce', 'Must be non-negative.');
    }
  }

  /// Query implementation.
  final DartitectQueryPort<Q, T, F> port;

  /// Stable item identity used by selection.
  final Object Function(T item) identity;

  /// Optional filter restoration store.
  final DartitectQueryRestorationStore<Q>? restoration;

  /// Restart-latest filter debounce.
  final Duration debounce;

  final CancellationSource _lifetime = CancellationSource();
  final Set<Object> _selection = <Object>{};
  Q _query;
  List<T> _items = <T>[];
  String? _nextCursor;
  StreamSubscription<List<T>>? _localSubscription;
  CancellationSource? _refreshSource;
  Timer? _debounceTimer;
  var _generation = 0;
  var _loadingMore = false;
  var _disposed = false;
  DartitectQueryState<T, F> _state = DartitectQueryInitial<T, F>();

  /// Current filters.
  Q get query => _query;

  /// Current closed presentation state.
  DartitectQueryState<T, F> get state => _state;

  /// Immutable selected identities.
  Set<Object> get selection => Set<Object>.unmodifiable(_selection);

  /// Selected values still present in current content.
  List<T> get selectedItems => List<T>.unmodifiable(
    _items.where((item) => _selection.contains(identity(item))),
  );

  /// Starts local observation and performs the initial refresh.
  Future<void> start({bool restore = true}) async {
    _ensureOpen();
    if (restore && restoration != null) {
      _query = await restoration!.load() ?? _query;
    }
    await _watchLocal();
    await refresh();
  }

  /// Replaces filters, persists them, and schedules restart-latest refresh.
  void setQuery(Q query) {
    _ensureOpen();
    _query = query;
    _debounceTimer?.cancel();
    _refreshSource?.cancel('Query filters changed');
    unawaited(restoration?.save(query));
    _debounceTimer = Timer(debounce, () {
      unawaited(_restartForQuery());
    });
  }

  Future<void> _restartForQuery() async {
    if (_disposed) return;
    await _watchLocal();
    await refresh();
  }

  Future<void> _watchLocal() async {
    await _localSubscription?.cancel();
    if (!port.localAuthority) {
      _localSubscription = null;
      return;
    }
    _localSubscription = port
        .watchLocal(_query)
        .listen(
          (items) {
            if (_disposed) return;
            _publish(items, stale: _refreshSource != null);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed) return;
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
  }

  /// Refreshes the first page while retaining stale content.
  Future<Result<void, F>> refresh() async {
    _ensureOpen();
    _refreshSource?.cancel('Query refresh restarted');
    final source = CancellationSource();
    _refreshSource = source;
    final registration = _lifetime.signal.register(source.cancel);
    final generation = ++_generation;
    _nextCursor = null;
    _state = DartitectQueryLoading<T, F>(staleItems: _items);
    notifyListeners();
    try {
      final result = await port.fetch(
        _query,
        cursor: null,
        cancellation: source.signal,
      );
      if (_disposed || generation != _generation) {
        return _asVoid(result);
      }
      switch (result) {
        case Ok<dynamic>(:final value):
          final page = value as DartitectQueryPage<T>;
          _nextCursor = page.nextCursor;
          if (!port.localAuthority) _publish(page.items, stale: false);
          if (port.localAuthority) _publish(_items, stale: false);
          return const Ok<void>(null);
        case Err<Object>(:final failure, :final stackTrace):
          _state = DartitectQueryFailure<T, F>(
            failure: failure as F,
            stackTrace: stackTrace,
            staleItems: _items,
          );
          notifyListeners();
          return Err<F>(failure, stackTrace);
      }
    } finally {
      registration.dispose();
      if (identical(_refreshSource, source)) _refreshSource = null;
      source.dispose();
    }
  }

  /// Fetches the next cursor page and appends it for non-local-authority ports.
  Future<Result<void, F>> loadNext() async {
    _ensureOpen();
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return const Ok<void>(null);
    _loadingMore = true;
    final source = CancellationSource();
    final registration = _lifetime.signal.register(source.cancel);
    try {
      final result = await port.fetch(
        _query,
        cursor: cursor,
        cancellation: source.signal,
      );
      switch (result) {
        case Ok<dynamic>(:final value):
          final page = value as DartitectQueryPage<T>;
          _nextCursor = page.nextCursor;
          if (!port.localAuthority) {
            _publish(<T>[..._items, ...page.items], stale: false);
          }
          return const Ok<void>(null);
        case Err<Object>(:final failure, :final stackTrace):
          _state = DartitectQueryFailure<T, F>(
            failure: failure as F,
            stackTrace: stackTrace,
            staleItems: _items,
          );
          notifyListeners();
          return Err<F>(failure, stackTrace);
      }
    } finally {
      _loadingMore = false;
      registration.dispose();
      source.dispose();
    }
  }

  /// Toggles one current item in the selection.
  void toggleSelection(T item) {
    _ensureOpen();
    final key = identity(item);
    if (!_selection.remove(key)) _selection.add(key);
    notifyListeners();
  }

  /// Selects every current item.
  void selectAll() {
    _ensureOpen();
    _selection.addAll(_items.map(identity));
    notifyListeners();
  }

  /// Clears selection.
  void clearSelection() {
    _ensureOpen();
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  /// Runs a consumer bulk action over a stable selected-value snapshot.
  Future<Result<void, F>> runBulk(DartitectQueryBulkAction<T, F> action) async {
    _ensureOpen();
    final source = CancellationSource();
    final registration = _lifetime.signal.register(source.cancel);
    try {
      return await action(selectedItems, source.signal);
    } finally {
      registration.dispose();
      source.dispose();
    }
  }

  void _publish(List<T> items, {required bool stale}) {
    _items = List<T>.unmodifiable(items);
    final present = _items.map(identity).toSet();
    _selection.removeWhere((key) => !present.contains(key));
    _state = _items.isEmpty
        ? DartitectQueryEmpty<T, F>()
        : DartitectQueryContent<T, F>(
            items: _items,
            stale: stale,
            hasMore: _nextCursor != null,
          );
    notifyListeners();
  }

  Result<void, F> _asVoid(Result<DartitectQueryPage<T>, F> result) =>
      switch (result) {
        Ok<dynamic>() => const Ok<void>(null),
        Err<Object>(:final failure, :final stackTrace) => Err<F>(
          failure as F,
          stackTrace,
        ),
      };

  void _ensureOpen() {
    if (_disposed) throw StateError('DartitectQueryController is disposed.');
  }

  /// Cancels timers, transport work, local observation, and listeners.
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _lifetime.cancel('DartitectQueryController disposed');
    _refreshSource?.cancel('DartitectQueryController disposed');
    await _localSubscription?.cancel();
    _localSubscription = null;
    _refreshSource = null;
    _lifetime.dispose();
    super.dispose();
  }

  // The async path is authoritative and cancels stream work.
  @override
  // ignore: must_call_super
  void dispose() => unawaited(disposeAsync());
}
