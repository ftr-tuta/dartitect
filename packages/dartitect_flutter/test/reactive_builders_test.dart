import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('value and collection builders detach while ticker is off', (
    tester,
  ) async {
    final value = ValueNotifier<int>(0);
    final collection = LiveCollection<int, String>();
    collection.update<(int, String)>(
      const <(int, String)>[(1, 'one'), (2, 'two')],
      keyOf: (item) => item.$1,
      project: (item) => item.$2,
      policy: CollectionUpdatePolicy.diffByKey,
    );
    var enabled = true;
    var valueBuilds = 0;
    var collectionBuilds = 0;
    final diagnostics = <FlutterBindingBuildEvent>[];

    Widget buildTree() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: Column(
          children: <Widget>[
            ReactiveValueBuilder<int>(
              value: value,
              onBuild: diagnostics.add,
              builder: (context, current, child) {
                valueBuilds += 1;
                return Text('value:$current');
              },
            ),
            LiveCollectionBuilder<int, String>(
              collection: collection,
              builder: (context, current, keys, child) {
                collectionBuilds += 1;
                return Text('keys:${keys.join(',')}');
              },
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(buildTree());
    final initialValueBuilds = valueBuilds;
    final initialCollectionBuilds = collectionBuilds;
    value.value = 1;
    collection.update<(int, String)>(
      const <(int, String)>[(1, 'changed'), (2, 'two')],
      keyOf: (item) => item.$1,
      project: (item) => item.$2,
      policy: CollectionUpdatePolicy.diffByKey,
    );
    await tester.pump();
    expect(valueBuilds, initialValueBuilds + 1);
    expect(diagnostics.last.kind, FlutterBindingKind.reactiveValue);
    expect(diagnostics.last.liveHandleCount, 1);
    expect(
      collectionBuilds,
      initialCollectionBuilds,
      reason: 'item-only changes do not rebuild structure',
    );

    collection.update<(int, String)>(
      const <(int, String)>[(2, 'two'), (1, 'changed')],
      keyOf: (item) => item.$1,
      project: (item) => item.$2,
      policy: CollectionUpdatePolicy.diffByKey,
    );
    await tester.pump();
    expect(collectionBuilds, initialCollectionBuilds + 1);

    enabled = false;
    await tester.pumpWidget(buildTree());
    final pausedValueBuilds = valueBuilds;
    final pausedCollectionBuilds = collectionBuilds;
    value.value = 2;
    collection.update<(int, String)>(
      const <(int, String)>[(3, 'three')],
      keyOf: (item) => item.$1,
      project: (item) => item.$2,
      policy: CollectionUpdatePolicy.diffByKey,
    );
    await tester.pump();
    expect(valueBuilds, pausedValueBuilds);
    expect(collectionBuilds, pausedCollectionBuilds);

    enabled = true;
    await tester.pumpWidget(buildTree());
    expect(find.text('value:2'), findsOneWidget);
    expect(find.text('keys:3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final unmountedValueBuilds = valueBuilds;
    value.value = 3;
    await tester.pump();
    expect(valueBuilds, unmountedValueBuilds);

    value.dispose();
    await collection.dispose();
  });

  testWidgets('resource builder owns ticker-aware observation and last data', (
    tester,
  ) async {
    final source = _QueueSource<int, String>(<Result<int, String>>[
      const Ok<int>(7),
      Err<String>('offline', StackTrace.current),
    ]);
    final resource = LiveResource<int, String>(
      source: source,
      policy: const ActivationPolicy.alwaysHot(),
    );
    var enabled = true;
    var builds = 0;
    ResourceDataState<int, String>? latest;

    Widget buildTree() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: LiveResourceBuilder<int, String>(
          resource: resource,
          builder: (context, state, temperature, isStale, child) {
            builds += 1;
            latest = state;
            return Text('${state.runtimeType}:${state.lastData}');
          },
        ),
      ),
    );

    await tester.pumpWidget(buildTree());
    await _pumpUntil(
      tester,
      () => resource.state is ResourceReady<int, String>,
    );
    expect(resource.observerCount, 1);
    expect(latest, isA<ResourceReady<int, String>>());
    expect(latest?.lastData, 7);

    enabled = false;
    await tester.pumpWidget(buildTree());
    final pausedBuilds = builds;
    expect(resource.observerCount, 0);
    source.latestSession.emit();
    await _pumpUntil(
      tester,
      () => resource.state is ResourceFailed<int, String>,
    );
    expect(builds, pausedBuilds, reason: 'inactive observation does not build');
    expect(latest, isA<ResourceReady<int, String>>());
    await tester.pump();
    expect(builds, pausedBuilds);

    enabled = true;
    await tester.pumpWidget(buildTree());
    expect(resource.observerCount, 1);
    expect(latest, isA<ResourceFailed<int, String>>());
    expect(latest?.lastData, 7, reason: 'expected failure retains local data');
    expect(source.openCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUntil(tester, () => resource.observerCount == 0);
    expect(resource.observerCount, 0);
    expect(resource.isDisposed, isFalse, reason: 'resource remains borrowed');
    unawaited(resource.dispose());
  });

  testWidgets('paged builder tracks structure only while ticker-enabled', (
    tester,
  ) async {
    final source = _QueueSource<PagedLocalSnapshot<int, String>, String>(
      <Result<PagedLocalSnapshot<int, String>, String>>[],
    );
    final local = LiveResource<PagedLocalSnapshot<int, String>, String>(
      source: source,
      policy: const ActivationPolicy.manual(),
    );
    final paged = PagedLiveResource<int, int, String, String>(
      local: local,
      initialCursor: 0,
      requestPage: (request, signal) async => const Ok<PageBatch<int, String>>(
        PageBatch<int, String>(items: <String>[], nextCursor: null),
      ),
      writePage: (write, signal) async => const Ok<PageWriteReceipt<int>>(
        PageWriteReceipt<int>(localRevision: 1, nextCursor: null),
      ),
      keyOf: (item) => item.length,
      observationTimeout: const Duration(seconds: 1),
      mapObservationTimeout: (receipt) => 'timeout',
    );
    var enabled = true;
    var builds = 0;

    Widget buildTree() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: PagedLiveBuilder<int, int, String, String>(
          resource: paged,
          builder: (context, resource, keys, child) {
            builds += 1;
            return Text('page:${keys.join(',')}');
          },
        ),
      ),
    );

    await tester.pumpWidget(buildTree());
    paged.collection.update<String>(
      const <String>['one'],
      keyOf: (item) => item.length,
      project: (item) => item,
      policy: CollectionUpdatePolicy.diffByKey,
    );
    await tester.pump();
    expect(find.text('page:3'), findsOneWidget);

    enabled = false;
    await tester.pumpWidget(buildTree());
    final pausedBuilds = builds;
    paged.collection.update<String>(
      const <String>['four'],
      keyOf: (item) => item.length,
      project: (item) => item,
      policy: CollectionUpdatePolicy.diffByKey,
    );
    await tester.pump();
    expect(builds, pausedBuilds);

    enabled = true;
    await tester.pumpWidget(buildTree());
    expect(find.text('page:4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final unmountedBuilds = builds;
    paged.collection.update<String>(
      const <String>['three'],
      keyOf: (item) => item.length,
      project: (item) => item,
      policy: CollectionUpdatePolicy.diffByKey,
    );
    await tester.pump();
    expect(builds, unmountedBuilds);

    final disposal = paged.dispose();
    expect(paged.isDisposed, isTrue);
    unawaited(disposal.then((_) => local.dispose()));
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump();
    if (predicate()) {
      await tester.pump();
      return;
    }
  }
  fail('Widget/resource state did not settle.');
}

final class _QueueSource<T, F extends Object> implements ReactiveSource<T, F> {
  _QueueSource(this.results);

  final List<Result<T, F>> results;
  late _QueueSession<T, F> latestSession;
  var openCount = 0;
  var closeCount = 0;

  @override
  Future<Result<ReactiveSourceSession<T, F>, F>> open() async {
    openCount += 1;
    latestSession = _QueueSession<T, F>(this);
    return Ok<ReactiveSourceSession<T, F>>(latestSession);
  }

  Result<T, F> take() {
    if (results.isEmpty) throw StateError('No queued source result.');
    return results.removeAt(0);
  }
}

final class _QueueSession<T, F extends Object>
    implements ReactiveSourceSession<T, F> {
  _QueueSession(this.source);

  final _QueueSource<T, F> source;
  final StreamController<void> _signals = StreamController<void>.broadcast(
    sync: true,
  );
  var _closed = false;

  @override
  Stream<void> get signals => _signals.stream;

  void emit() {
    if (!_closed) _signals.add(null);
  }

  @override
  Future<Result<T, F>> read(CancellationSignal signal) async {
    signal.throwIfCancelled();
    return source.take();
  }

  @override
  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    source.closeCount += 1;
    unawaited(_signals.close());
    return Future<void>.value();
  }
}
