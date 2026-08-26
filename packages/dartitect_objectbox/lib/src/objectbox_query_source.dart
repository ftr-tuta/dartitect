import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:objectbox/objectbox.dart';

/// Static lifecycle facts emitted by [ObjectBoxQuerySource].
enum ObjectBoxQueryLifecycleEvent {
  /// A fresh query watcher subscribed for one hot activation.
  watcherStarted,

  /// The watcher subscription was cancelled.
  watcherCancelled,

  /// Every watcher-created query was closed.
  queriesClosed,
}

/// ObjectBox source that creates watcher/query state per activation.
///
/// The Store captured by [builderFactory] remains borrowed. The session owns
/// only the watcher subscription and every Query emitted by that watcher.
final class ObjectBoxQuerySource<T, F extends Object>
    implements ReactiveSource<List<T>, F> {
  /// Creates a query source from the consumer's generated query builder.
  ObjectBoxQuerySource({
    required QueryBuilder<T> Function() builderFactory,
    F Function(Object error, StackTrace stackTrace)? mapFailure,
    bool findAsync = true,
    void Function(ObjectBoxQueryLifecycleEvent event)? lifecycleObserver,
  }) : _builderFactory = builderFactory,
       _mapFailure = mapFailure,
       _findAsync = findAsync,
       _lifecycleObserver = lifecycleObserver;

  final QueryBuilder<T> Function() _builderFactory;
  final F Function(Object error, StackTrace stackTrace)? _mapFailure;
  final bool _findAsync;
  final void Function(ObjectBoxQueryLifecycleEvent event)? _lifecycleObserver;

  @override
  Future<Result<ReactiveSourceSession<List<T>, F>, F>> open() async {
    try {
      final builder = _builderFactory();
      return Ok<ReactiveSourceSession<List<T>, F>>(
        _ObjectBoxQuerySession<T, F>(
          builder,
          mapFailure: _mapFailure,
          findAsync: _findAsync,
          lifecycleObserver: _lifecycleObserver,
        ),
      );
    } catch (error, stackTrace) {
      final mapper = _mapFailure;
      if (mapper == null) Error.throwWithStackTrace(error, stackTrace);
      return Err<F>(mapper(error, stackTrace), stackTrace);
    }
  }
}

final class _ObjectBoxQuerySession<T, F extends Object>
    implements ReactiveSourceSession<List<T>, F> {
  _ObjectBoxQuerySession(
    this._builder, {
    required F Function(Object error, StackTrace stackTrace)? mapFailure,
    required bool findAsync,
    required void Function(ObjectBoxQueryLifecycleEvent event)?
    lifecycleObserver,
  }) : _mapFailure = mapFailure,
       _findAsync = findAsync,
       _lifecycleObserver = lifecycleObserver {
    _signals = StreamController<void>.broadcast(onListen: _startWatcher);
  }

  final QueryBuilder<T> _builder;
  final F Function(Object error, StackTrace stackTrace)? _mapFailure;
  final bool _findAsync;
  final void Function(ObjectBoxQueryLifecycleEvent event)? _lifecycleObserver;
  final Completer<Query<T>?> _firstQuery = Completer<Query<T>?>();
  final List<Query<T>> _queries = <Query<T>>[];
  late final StreamController<void> _signals;
  Future<void> Function()? _cancelWatcher;
  Query<T>? _currentQuery;
  var _closed = false;
  Future<void>? _closeFuture;

  @override
  Stream<void> get signals => _signals.stream;

  @override
  Future<Result<List<T>, F>> read(CancellationSignal signal) async {
    signal.throwIfCancelled();
    final query =
        _currentQuery ??
        await Future.any<Query<T>?>(<Future<Query<T>?>>[
          _firstQuery.future,
          signal.whenCancelled.then<Query<T>?>((_) => null),
        ]);
    if (query == null || _closed) {
      throw CancellationException(signal.reason ?? 'Query session closed');
    }
    try {
      final values = _findAsync
          ? await query.findAsync()
          : await Future<List<T>>.sync(query.find);
      signal.throwIfCancelled();
      return Ok<List<T>>(values);
    } on CancellationException {
      rethrow;
    } catch (error, stackTrace) {
      final mapper = _mapFailure;
      if (mapper == null) Error.throwWithStackTrace(error, stackTrace);
      return Err<F>(mapper(error, stackTrace), stackTrace);
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  void _startWatcher() {
    if (_closed || _cancelWatcher != null) return;
    try {
      _cancelWatcher = _builder
          .watch(triggerImmediately: true)
          .listen(
            (query) {
              if (_closed) {
                query.close();
                return;
              }
              if (!_queries.any((existing) => identical(existing, query))) {
                _queries.add(query);
              }
              _currentQuery = query;
              if (!_firstQuery.isCompleted) {
                // LiveResource already starts the authoritative initial read.
                // The immediate watcher event only supplies its query, avoiding
                // a redundant dirty rerun on activation.
                _firstQuery.complete(query);
              } else {
                _signals.add(null);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!_closed) _signals.addError(error, stackTrace);
            },
          )
          .cancel;
      _emit(ObjectBoxQueryLifecycleEvent.watcherStarted);
    } catch (error, stackTrace) {
      _signals.addError(error, stackTrace);
    }
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    if (!_firstQuery.isCompleted) _firstQuery.complete(null);
    final cancelWatcher = _cancelWatcher;
    _cancelWatcher = null;
    if (cancelWatcher != null) {
      await cancelWatcher();
      _emit(ObjectBoxQueryLifecycleEvent.watcherCancelled);
    }
    for (final query in _queries.reversed) {
      query.close();
    }
    _queries.clear();
    _currentQuery = null;
    _emit(ObjectBoxQueryLifecycleEvent.queriesClosed);
    await _signals.close();
  }

  void _emit(ObjectBoxQueryLifecycleEvent event) {
    try {
      _lifecycleObserver?.call(event);
    } catch (_) {
      return;
    }
  }
}
