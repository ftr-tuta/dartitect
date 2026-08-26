import 'dart:async';
import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selector fan-out and causal page timeline stay specific', () async {
    const selectorCount = 1000;
    final model = _FanOutModel(selectorCount);
    final selectors = List<ReactiveSelector<_FanOutModel, int>>.generate(
      selectorCount,
      (index) => ReactiveSelector<_FanOutModel, int>(
        source: model,
        select: (source) => source.values[index],
      ),
    );
    var callbacks = 0;
    void listener() => callbacks += 1;
    for (final selector in selectors) {
      selector.addListener(listener);
    }

    final stopwatch = Stopwatch()..start();
    model.changeFirst(0);
    final zeroPercentCallbacks = callbacks;
    model.changeFirst(100);
    final tenPercentCallbacks = callbacks - zeroPercentCallbacks;
    model.changeFirst(1000);
    final allCallbacks = callbacks - tenPercentCallbacks;
    stopwatch.stop();

    final source = _PageSource();
    final paged = PagedLiveResource<int, int, int, String>(
      local: source.resource,
      initialCursor: 0,
      requestPage: (request, signal) async => const Ok<PageBatch<int, int>>(
        PageBatch<int, int>(items: <int>[1, 2, 2, 3], nextCursor: 1),
      ),
      writePage: (write, signal) async {
        const receipt = PageWriteReceipt<int>(
          localRevision: 'page-1',
          nextCursor: 1,
        );
        source.emit(
          PagedLocalSnapshot<int, int>(
            revision: receipt.localRevision,
            items: write.items,
          ),
        );
        return const Ok<PageWriteReceipt<int>>(receipt);
      },
      keyOf: (item) => item,
      observationTimeout: const Duration(seconds: 1),
      mapObservationTimeout: (_) => 'timeout',
      tombstoneRetention: Duration.zero,
    );
    final phases = <PageTimelinePhase>[];
    final subscription = paged.timeline.listen(
      (event) => phases.add(event.phase),
    );
    await _waitFor(() => source.readCount >= 1);
    final pageStopwatch = Stopwatch()..start();
    final outcome = await paged.refresh();
    pageStopwatch.stop();

    for (final selector in selectors.reversed) {
      selector.dispose();
    }
    model.dispose();
    await subscription.cancel();
    await paged.dispose();
    final pageNodesAfterDispose = paged.collection.nodeCount;
    final pageTimersAfterDispose = paged.collection.activeTimerCount;
    await source.resource.dispose();

    // ignore: avoid_print
    print(
      jsonEncode(<String, Object>{
        'selectors': selectorCount,
        'zeroPercentCallbacks': zeroPercentCallbacks,
        'tenPercentCallbacks': tenPercentCallbacks,
        'allCallbacks': allCallbacks,
        'fanOutMicroseconds': stopwatch.elapsedMicroseconds,
        'pageMicroseconds': pageStopwatch.elapsedMicroseconds,
        'pagePhases': phases.map((phase) => phase.name).toList(),
        'pageItems': 3,
        'pageNodesAfterDispose': pageNodesAfterDispose,
        'pageTimersAfterDispose': pageTimersAfterDispose,
      }),
    );

    expect(zeroPercentCallbacks, 0);
    expect(tenPercentCallbacks, 100);
    expect(allCallbacks, 1000);
    expect(outcome, isA<CommandSucceeded<PageWriteReceipt<int>, String>>());
    expect(
      phases,
      PageTimelinePhase.values
          .where((phase) => phase != PageTimelinePhase.failed)
          .toList(),
    );
    expect(pageNodesAfterDispose, 0);
    expect(pageTimersAfterDispose, 0);
  });
}

final class _FanOutModel extends ChangeNotifier {
  _FanOutModel(int size) : values = List<int>.filled(size, 0);

  final List<int> values;

  void changeFirst(int count) {
    for (var index = 0; index < count; index += 1) {
      values[index] += 1;
    }
    notifyListeners();
  }
}

final class _PageSource {
  factory _PageSource() {
    final delegate = _PageSourceDelegate();
    final source = _PageSource._(delegate);
    delegate.owner = source;
    return source;
  }

  _PageSource._(this.delegate)
    : resource = LiveResource<PagedLocalSnapshot<int, int>, String>(
        source: delegate,
      );

  final _PageSourceDelegate delegate;
  final LiveResource<PagedLocalSnapshot<int, int>, String> resource;
  final List<_PageSession> sessions = <_PageSession>[];
  PagedLocalSnapshot<int, int> current = const PagedLocalSnapshot<int, int>(
    revision: 'initial',
    items: <int>[],
  );
  var readCount = 0;

  void emit(PagedLocalSnapshot<int, int> snapshot) {
    current = snapshot;
    sessions.single.signal();
  }
}

final class _PageSourceDelegate
    implements ReactiveSource<PagedLocalSnapshot<int, int>, String> {
  _PageSource? owner;

  @override
  Future<
    Result<ReactiveSourceSession<PagedLocalSnapshot<int, int>, String>, String>
  >
  open() async {
    final session = _PageSession(owner!);
    owner!.sessions.add(session);
    return Ok<ReactiveSourceSession<PagedLocalSnapshot<int, int>, String>>(
      session,
    );
  }
}

final class _PageSession
    implements ReactiveSourceSession<PagedLocalSnapshot<int, int>, String> {
  _PageSession(this.source);

  final _PageSource source;
  final StreamController<void> signalsController =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get signals => signalsController.stream;

  void signal() => signalsController.add(null);

  @override
  Future<Result<PagedLocalSnapshot<int, int>, String>> read(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    source.readCount += 1;
    return Ok<PagedLocalSnapshot<int, int>>(source.current);
  }

  @override
  Future<void> close() => signalsController.close();
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not settle.');
}
