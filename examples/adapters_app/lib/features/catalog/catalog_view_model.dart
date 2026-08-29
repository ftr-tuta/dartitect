import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';

import 'catalog_model.dart';
import 'catalog_remote.dart';

/// Route-owned transient reactions produced by the catalog ViewModel.
enum CatalogEffect {
  /// The authoritative local collection has no next page.
  endOfList,
}

/// Large remote-read workload ViewModel with local-authority presentation.
final class CatalogViewModel(
  final CatalogRemote _remote, {
  PagedResourceCrashReporter reporter = const NoOpPagedResourceCrashReporter(),
}) extends DartitectViewModel {
  /// Creates a ViewModel around a borrowed provider-neutral remote port.
  this {
    own(_store, (store) => store.disposeAsync(), label: 'catalogStore');
    local = own(
      LiveResource<PagedLocalSnapshot<int, CatalogItem>, CatalogFailure>(
        source: _CatalogSource(_store),
        policy: const ActivationPolicy.whileObserved(),
      ),
      (resource) => resource.dispose(),
      label: 'localCatalog',
    );
    final pagedResource =
        PagedLiveResource<CatalogCursor, int, CatalogItem, CatalogFailure>(
          local: local,
          initialCursor: const CatalogCursor(),
          requestPage: _remote.page,
          writePage: _store.write,
          keyOf: (item) => item.id,
          versionOf: (item) => item.version,
          collectionPolicy: CollectionUpdatePolicy.versionedByKey,
          observationTimeout: const Duration(seconds: 2),
          mapObservationTimeout: (_) =>
              const CatalogFailure('observation-timeout'),
          reporter: reporter,
        );
    paged = own(
      pagedResource,
      (resource) => resource.dispose(),
      listenable: pagedResource,
      label: 'pagedCatalog',
    );
    refreshCommand = ownCommand(
      Command0(_refresh, concurrency: const CommandConcurrency.join()),
      label: 'refreshCommand',
    );
    loadMoreCommand = ownCommand(
      Command0(_loadMore, concurrency: const CommandConcurrency.drop()),
      label: 'loadMoreCommand',
    );
    searchCommand = ownCommand(
      Command1(_search, concurrency: const CommandConcurrency.restartLatest()),
      label: 'searchCommand',
    );
    effects = own(
      EffectChannel<CatalogEffect>(
        capacity: 8,
        owner: EffectOwnerIdentity(
          kind: EffectOwnerKind.route,
          generation: Object(),
        ),
      ),
      (channel) => channel.disposeAsync(),
      label: 'catalogEffects',
    );
  }

  final _CatalogStore _store = _CatalogStore();

  /// Authoritative local reactive source.
  late final LiveResource<PagedLocalSnapshot<int, CatalogItem>, CatalogFailure>
  local;

  /// Paged local collection; remote responses are never published directly.
  late final PagedLiveResource<CatalogCursor, int, CatalogItem, CatalogFailure>
  paged;

  /// Bounded, single-consumer route-effect channel borrowed by the page.
  late final EffectChannel<CatalogEffect> effects;

  /// Refresh action state.
  late final Command0<PageWriteReceipt<CatalogCursor>, CatalogFailure>
  refreshCommand;

  /// Load-more action state.
  late final Command0<PageWriteReceipt<CatalogCursor>, CatalogFailure>
  loadMoreCommand;

  /// Restart-latest search action state.
  late final Command1<String, PageWriteReceipt<CatalogCursor>, CatalogFailure>
  searchCommand;

  bool _started = false;

  /// Starts the workload once without acting as a readiness barrier.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refreshCommand.execute();
  }

  Future<Result<PageWriteReceipt<CatalogCursor>, CatalogFailure>>
  _refresh() async {
    _store.select(const CatalogCursor(), reset: true);
    return _asResult(await paged.refresh());
  }

  Future<Result<PageWriteReceipt<CatalogCursor>, CatalogFailure>>
  _loadMore() async {
    final cursor = paged.nextCursor;
    if (cursor == null) {
      effects.sink.emit(CatalogEffect.endOfList);
      return Err<CatalogFailure>(
        const CatalogFailure('end-of-list'),
        StackTrace.current,
      );
    }
    _store.select(cursor, reset: false);
    final result = _asResult(await paged.loadMore());
    if (result is Ok<PageWriteReceipt<CatalogCursor>> &&
        paged.nextCursor == null) {
      effects.sink.emit(CatalogEffect.endOfList);
    }
    return result;
  }

  Future<Result<PageWriteReceipt<CatalogCursor>, CatalogFailure>> _search(
    String query,
  ) async {
    final cursor = CatalogCursor(query: query.trim());
    _store.select(cursor, reset: true);
    return _asResult(await paged.search(cursor));
  }

  Result<PageWriteReceipt<CatalogCursor>, CatalogFailure> _asResult(
    CommandOutcome<PageWriteReceipt<CatalogCursor>, CatalogFailure> outcome,
  ) => switch (outcome) {
    CommandSucceeded<PageWriteReceipt<CatalogCursor>, CatalogFailure>(
      :final value,
    ) =>
      Ok<PageWriteReceipt<CatalogCursor>>(value),
    CommandFailed<PageWriteReceipt<CatalogCursor>, CatalogFailure>(
      :final failure,
      :final stackTrace,
    ) =>
      Err<CatalogFailure>(failure, stackTrace),
    _ => Err<CatalogFailure>(
      const CatalogFailure('page-not-admitted'),
      StackTrace.current,
    ),
  };
}

final class _CatalogStore implements AsyncDisposable {
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Map<int, CatalogItem> _items = <int, CatalogItem>{};
  var _query = '';
  var _limit = 25;
  var _revision = 0;

  void select(CatalogCursor cursor, {required bool reset}) {
    _query = cursor.query.toLowerCase();
    if (reset) _limit = 25;
  }

  Future<Result<PageWriteReceipt<CatalogCursor>, CatalogFailure>> write(
    PageWrite<CatalogCursor, CatalogItem> write,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    if (write.reset) _items.clear();
    for (final item in write.items) {
      _items[item.id] = item;
    }
    _limit = write.reset ? write.items.length : _limit + write.items.length;
    _revision += 1;
    _changes.add(null);
    return Ok<PageWriteReceipt<CatalogCursor>>(
      PageWriteReceipt<CatalogCursor>(
        localRevision: _revision,
        nextCursor: write.nextCursor,
      ),
    );
  }

  Future<Result<PagedLocalSnapshot<int, CatalogItem>, CatalogFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final items = _items.values
        .where((item) => item.title.toLowerCase().contains(_query))
        .take(_limit)
        .toList(growable: false);
    return Ok<PagedLocalSnapshot<int, CatalogItem>>(
      PagedLocalSnapshot<int, CatalogItem>(revision: _revision, items: items),
    );
  }

  Stream<void> watch() => _changes.stream;

  @override
  Future<void> disposeAsync() => _changes.close();
}

final class _CatalogSource
    implements
        ReactiveSource<PagedLocalSnapshot<int, CatalogItem>, CatalogFailure> {
  const _CatalogSource(this.store);

  final _CatalogStore store;

  @override
  Future<
    Result<
      ReactiveSourceSession<
        PagedLocalSnapshot<int, CatalogItem>,
        CatalogFailure
      >,
      CatalogFailure
    >
  >
  open() async => Ok(_CatalogSession(store));
}

final class _CatalogSession
    implements
        ReactiveSourceSession<
          PagedLocalSnapshot<int, CatalogItem>,
          CatalogFailure
        > {
  const _CatalogSession(this.store);

  final _CatalogStore store;

  @override
  Stream<void> get signals => store.watch();

  @override
  Future<Result<PagedLocalSnapshot<int, CatalogItem>, CatalogFailure>> read(
    CancellationSignal signal,
  ) => store.read(signal);

  @override
  Future<void> close() async {}
}
