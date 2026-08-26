import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:objectbox/objectbox.dart';

/// One activation-local invalidation stream derived from a borrowed [Store].
typedef ObjectBoxStoreWatch = Stream<void> Function(Store store);

/// Creates a typed ObjectBox entity watch without retaining an observation.
ObjectBoxStoreWatch watchObjectBoxEntity<E>() =>
    (store) => store.watch<E>();

/// Pull source invalidated by one or more ObjectBox entity watches.
///
/// The Store is borrowed. Each activation creates fresh watch subscriptions,
/// performs the authoritative read through [pull], then cancels every watch
/// before the session closes.
final class ObjectBoxStoreWatchSource<T, F extends Object>
    implements ReactiveSource<T, F> {
  /// Creates a multi-entity Store-watch source.
  ObjectBoxStoreWatchSource({
    required Store store,
    required Iterable<ObjectBoxStoreWatch> watches,
    required Future<Result<T, F>> Function(
      Store store,
      CancellationSignal cancellation,
    )
    pull,
    F Function(Object error, StackTrace stackTrace)? mapOpenFailure,
  }) : _store = store,
       _watches = List<ObjectBoxStoreWatch>.unmodifiable(watches),
       _pull = pull,
       _mapOpenFailure = mapOpenFailure {
    if (_watches.isEmpty) {
      throw ArgumentError.value(watches, 'watches', 'must not be empty');
    }
  }

  final Store _store;
  final List<ObjectBoxStoreWatch> _watches;
  final Future<Result<T, F>> Function(
    Store store,
    CancellationSignal cancellation,
  )
  _pull;
  final F Function(Object error, StackTrace stackTrace)? _mapOpenFailure;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() {
    final source = PullReactiveSource<T, F>(
      triggers: _watches.map(
        (watch) =>
            () => watch(_store),
      ),
      pull: (cancellation) => _pull(_store, cancellation),
      mapOpenFailure: _mapOpenFailure,
    );
    return source.open();
  }
}
