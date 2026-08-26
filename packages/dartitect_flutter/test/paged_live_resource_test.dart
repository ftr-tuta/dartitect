import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'refresh joins, deduplicates, and advances after local observation',
    () async {
      final source = _LocalSource();
      final remote = Completer<Result<PageBatch<int, _Item>, _Failure>>();
      final write = Completer<Result<PageWriteReceipt<int>, _Failure>>();
      final writes = <PageWrite<int, _Item>>[];
      var requestCalls = 0;
      final resource = _createPaged(
        source,
        requestPage: (request, signal) {
          requestCalls += 1;
          return remote.future;
        },
        writePage: (value, signal) {
          writes.add(value);
          return write.future;
        },
      );
      final timeline = <PageTimelineEvent<int>>[];
      final timelineSubscription = resource.timeline.listen(timeline.add);
      await _waitFor(() => source.sessionCount == 1 && source.readCount >= 1);
      await _waitFor(() => resource.collection.revision == 0);

      final first = resource.refresh();
      final joined = resource.refresh();
      expect(requestCalls, 1);
      remote.complete(
        const Ok<PageBatch<int, _Item>>(
          PageBatch<int, _Item>(
            items: <_Item>[_Item(1, 'old'), _Item(1, 'new'), _Item(2, 'two')],
            nextCursor: 1,
          ),
        ),
      );
      await _waitFor(() => writes.length == 1);
      expect(writes.single.duplicateCount, 1);
      expect(writes.single.items, const <_Item>[
        _Item(1, 'new'),
        _Item(2, 'two'),
      ]);
      expect(resource.collection.length.value, 0);
      expect(resource.nextCursor, isNull);

      source.emit(
        const PagedLocalSnapshot<int, _Item>(
          revision: 'r1',
          items: <_Item>[_Item(1, 'new'), _Item(2, 'two')],
        ),
      );
      write.complete(
        const Ok<PageWriteReceipt<int>>(
          PageWriteReceipt<int>(localRevision: 'r1', nextCursor: 1),
        ),
      );
      final outcomes = await Future.wait(
        <Future<CommandOutcome<PageWriteReceipt<int>, _Failure>>>[
          first,
          joined,
        ],
      );

      expect(outcomes.every((value) => value is CommandSucceeded), isTrue);
      expect(identical(outcomes.first, outcomes.last), isTrue);
      expect(resource.collection.keys.value, <int>[1, 2]);
      expect(resource.collection.item(1).value, const _Item(1, 'new'));
      expect(resource.nextCursor, 1);
      expect(resource.lastFailure, isNull);
      expect(timeline.map((event) => event.phase), <PageTimelinePhase>[
        PageTimelinePhase.requestStarted,
        PageTimelinePhase.responseReceived,
        PageTimelinePhase.localWriteCommitted,
        PageTimelinePhase.localObserved,
        PageTimelinePhase.completed,
      ]);

      await timelineSubscription.cancel();
      await resource.dispose();
      await source.resource.dispose();
    },
  );

  test(
    'load more drops reentrancy and never publishes remote data directly',
    () async {
      final source = _LocalSource();
      final loadRemote = Completer<Result<PageBatch<int, _Item>, _Failure>>();
      var loadRequests = 0;
      var revision = 0;
      var localItems = <_Item>[];
      final resource = _createPaged(
        source,
        requestPage: (request, signal) async {
          if (request.operation == PageOperation.loadMore) {
            loadRequests += 1;
            return loadRemote.future;
          }
          return const Ok<PageBatch<int, _Item>>(
            PageBatch<int, _Item>(
              items: <_Item>[_Item(1, 'one')],
              nextCursor: 1,
            ),
          );
        },
        writePage: (write, signal) async {
          revision += 1;
          localItems = write.reset
              ? List<_Item>.of(write.items)
              : <_Item>[...localItems, ...write.items];
          final receipt = PageWriteReceipt<int>(
            localRevision: 'r$revision',
            nextCursor: write.nextCursor,
          );
          source.emit(
            PagedLocalSnapshot<int, _Item>(
              revision: receipt.localRevision,
              items: List<_Item>.unmodifiable(localItems),
            ),
          );
          return Ok<PageWriteReceipt<int>>(receipt);
        },
      );
      await _waitFor(() => source.readCount >= 1);
      expect(
        await resource.refresh(),
        isA<CommandSucceeded<PageWriteReceipt<int>, _Failure>>(),
      );
      expect(resource.nextCursor, 1);

      final first = resource.loadMore();
      final dropped = await resource.loadMore();
      expect(dropped, isA<CommandDropped<PageWriteReceipt<int>, _Failure>>());
      expect(loadRequests, 1);
      loadRemote.complete(
        const Ok<PageBatch<int, _Item>>(
          PageBatch<int, _Item>(
            items: <_Item>[_Item(2, 'two')],
            nextCursor: null,
          ),
        ),
      );
      await _waitFor(() => revision == 2);
      expect(
        await first,
        isA<CommandSucceeded<PageWriteReceipt<int>, _Failure>>(),
      );
      expect(resource.collection.keys.value, <int>[1, 2]);
      expect(resource.nextCursor, isNull);
      expect(
        await resource.loadMore(),
        isA<CommandDropped<PageWriteReceipt<int>, _Failure>>(),
      );
      expect(loadRequests, 1);

      await resource.dispose();
      await source.resource.dispose();
    },
  );

  test(
    'search restart-latest cancels stale generation before local write',
    () async {
      final source = _LocalSource();
      final requests = <PageRequest<int>>[];
      final signals = <CancellationSignal>[];
      final remotes = <Completer<Result<PageBatch<int, _Item>, _Failure>>>[];
      final writes = <PageWrite<int, _Item>>[];
      var revision = 0;
      final resource = _createPaged(
        source,
        requestPage: (request, signal) {
          requests.add(request);
          signals.add(signal);
          final completer =
              Completer<Result<PageBatch<int, _Item>, _Failure>>();
          remotes.add(completer);
          return completer.future;
        },
        writePage: (write, signal) async {
          writes.add(write);
          revision += 1;
          final receipt = PageWriteReceipt<int>(
            localRevision: 'search-$revision',
            nextCursor: write.nextCursor,
          );
          source.emit(
            PagedLocalSnapshot<int, _Item>(
              revision: receipt.localRevision,
              items: write.items,
            ),
          );
          return Ok<PageWriteReceipt<int>>(receipt);
        },
      );
      await _waitFor(() => source.readCount >= 1);

      final stale = resource.search(10);
      final latest = resource.search(20);
      expect(requests.map((request) => request.cursor), <int>[10, 20]);
      expect(signals.first.isCancelled, isTrue);
      expect(
        await stale,
        isA<CommandCancelled<PageWriteReceipt<int>, _Failure>>(),
      );
      remotes.first.complete(
        const Ok<PageBatch<int, _Item>>(
          PageBatch<int, _Item>(
            items: <_Item>[_Item(10, 'stale')],
            nextCursor: 11,
          ),
        ),
      );
      remotes.last.complete(
        const Ok<PageBatch<int, _Item>>(
          PageBatch<int, _Item>(
            items: <_Item>[_Item(20, 'latest')],
            nextCursor: 21,
          ),
        ),
      );
      expect(
        await latest,
        isA<CommandSucceeded<PageWriteReceipt<int>, _Failure>>(),
      );

      expect(writes, hasLength(1));
      expect(writes.single.items.single, const _Item(20, 'latest'));
      expect(resource.collection.keys.value, <int>[20]);
      expect(resource.initialCursor, 20);
      expect(resource.nextCursor, 21);
      expect(resource.lastFailure, isNull);

      await resource.dispose();
      await source.resource.dispose();
    },
  );

  test(
    'failure and observation timeout preserve local data and cursor',
    () async {
      final source = _LocalSource();
      final timers = _FakeTimerFactory();
      var loadAttempt = 0;
      var revision = 0;
      final resource = _createPaged(
        source,
        timers: timers,
        requestPage: (request, signal) async {
          if (request.operation == PageOperation.refresh) {
            return const Ok<PageBatch<int, _Item>>(
              PageBatch<int, _Item>(
                items: <_Item>[_Item(1, 'one')],
                nextCursor: 1,
              ),
            );
          }
          loadAttempt += 1;
          if (loadAttempt == 1) {
            return Err<_Failure>(const _Failure('offline'), StackTrace.current);
          }
          return const Ok<PageBatch<int, _Item>>(
            PageBatch<int, _Item>(
              items: <_Item>[_Item(2, 'two')],
              nextCursor: 2,
            ),
          );
        },
        writePage: (write, signal) async {
          revision += 1;
          final receipt = PageWriteReceipt<int>(
            localRevision: 'r$revision',
            nextCursor: write.nextCursor,
          );
          if (revision == 1) {
            source.emit(
              PagedLocalSnapshot<int, _Item>(
                revision: receipt.localRevision,
                items: write.items,
              ),
            );
          }
          return Ok<PageWriteReceipt<int>>(receipt);
        },
      );
      await _waitFor(() => source.readCount >= 1);
      expect(
        await resource.refresh(),
        isA<CommandSucceeded<PageWriteReceipt<int>, _Failure>>(),
      );
      expect(resource.collection.keys.value, <int>[1]);
      expect(resource.nextCursor, 1);

      final failed = await resource.loadMore();
      expect(failed, isA<CommandFailed<PageWriteReceipt<int>, _Failure>>());
      expect(resource.lastFailure, const _Failure('offline'));
      expect(resource.collection.keys.value, <int>[1]);
      expect(resource.nextCursor, 1);

      final timedOut = resource.loadMore();
      await _waitFor(() => resource.observationWaiterCount == 1);
      timers.advance(const Duration(seconds: 1));
      expect(
        await timedOut,
        isA<CommandFailed<PageWriteReceipt<int>, _Failure>>(),
      );
      expect(resource.lastFailure, const _Failure('timeout'));
      expect(resource.collection.keys.value, <int>[1]);
      expect(resource.nextCursor, 1);
      expect(resource.observationWaiterCount, 0);
      expect(resource.activeTimerCount, 0);

      await resource.dispose();
      expect(timers.activeCount, 0);
      await source.resource.dispose();
    },
  );

  test(
    'duplicate local keys abort atomically and teardown leaves no nodes',
    () async {
      final source = _LocalSource();
      final reports = <Object>[];
      final resource = _createPaged(
        source,
        reporter: _CrashReporter(reports.add),
        requestPage: (request, signal) async => const Ok<PageBatch<int, _Item>>(
          PageBatch<int, _Item>(items: <_Item>[], nextCursor: null),
        ),
        writePage: (write, signal) async => const Ok<PageWriteReceipt<int>>(
          PageWriteReceipt<int>(localRevision: 'unused', nextCursor: null),
        ),
      );
      await _waitFor(() => source.readCount >= 1);
      source.emit(
        const PagedLocalSnapshot<int, _Item>(
          revision: 'good',
          items: <_Item>[_Item(1, 'stable')],
        ),
      );
      await _waitFor(() => resource.collection.length.value == 1);
      final revision = resource.collection.revision;

      source.emit(
        const PagedLocalSnapshot<int, _Item>(
          revision: 'bad',
          items: <_Item>[_Item(1, 'first'), _Item(1, 'duplicate')],
        ),
      );
      await _waitFor(() => resource.crash != null);

      expect(resource.crash, isA<DuplicateCollectionKeyException<int>>());
      expect(reports, hasLength(1));
      expect(resource.collection.revision, revision);
      expect(resource.collection.keys.value, <int>[1]);
      expect(resource.collection.item(1).value, const _Item(1, 'stable'));
      await resource.dispose();
      expect(resource.collection.nodeCount, 0);
      expect(resource.collection.activeTimerCount, 0);
      expect(source.resource.observerCount, 0);
      await source.resource.dispose();
    },
  );
}

PagedLiveResource<int, int, _Item, _Failure> _createPaged(
  _LocalSource source, {
  required Future<Result<PageBatch<int, _Item>, _Failure>> Function(
    PageRequest<int> request,
    CancellationSignal signal,
  )
  requestPage,
  required Future<Result<PageWriteReceipt<int>, _Failure>> Function(
    PageWrite<int, _Item> write,
    CancellationSignal signal,
  )
  writePage,
  _FakeTimerFactory? timers,
  PagedResourceCrashReporter reporter = const NoOpPagedResourceCrashReporter(),
}) => PagedLiveResource<int, int, _Item, _Failure>(
  local: source.resource,
  initialCursor: 0,
  requestPage: requestPage,
  writePage: writePage,
  keyOf: (item) => item.id,
  observationTimeout: const Duration(seconds: 1),
  mapObservationTimeout: (_) => const _Failure('timeout'),
  timerFactory: timers ?? _FakeTimerFactory(),
  tombstoneRetention: Duration.zero,
  reporter: reporter,
);

final class _Item {
  const _Item(this.id, this.label);

  final int id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is _Item && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

final class _Failure implements Exception {
  const _Failure(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is _Failure && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

final class _CrashReporter implements PagedResourceCrashReporter {
  const _CrashReporter(this.callback);

  final void Function(Object error) callback;

  @override
  void report(Object error, StackTrace stackTrace) => callback(error);
}

final class _LocalSource
    implements ReactiveSource<PagedLocalSnapshot<int, _Item>, _Failure> {
  factory _LocalSource() {
    final delegate = _LocalSourceDelegate();
    final source = _LocalSource._(delegate);
    delegate._owner = source;
    return source;
  }

  _LocalSource._(this.resourceSource)
    : resource = LiveResource<PagedLocalSnapshot<int, _Item>, _Failure>(
        source: resourceSource,
      );

  final LiveResource<PagedLocalSnapshot<int, _Item>, _Failure> resource;
  final _LocalSourceDelegate resourceSource;
  PagedLocalSnapshot<int, _Item> current = const PagedLocalSnapshot<int, _Item>(
    revision: 'initial',
    items: <_Item>[],
  );
  final List<_LocalSession> _sessions = <_LocalSession>[];
  var readCount = 0;

  int get sessionCount => _sessions.length;

  void emit(PagedLocalSnapshot<int, _Item> snapshot) {
    current = snapshot;
    _sessions.last.signal();
  }

  @override
  Future<
    Result<
      ReactiveSourceSession<PagedLocalSnapshot<int, _Item>, _Failure>,
      _Failure
    >
  >
  open() async {
    final session = _LocalSession(this);
    _sessions.add(session);
    return Ok<ReactiveSourceSession<PagedLocalSnapshot<int, _Item>, _Failure>>(
      session,
    );
  }
}

final class _LocalSourceDelegate
    implements ReactiveSource<PagedLocalSnapshot<int, _Item>, _Failure> {
  _LocalSource? _owner;

  @override
  Future<
    Result<
      ReactiveSourceSession<PagedLocalSnapshot<int, _Item>, _Failure>,
      _Failure
    >
  >
  open() => _owner!.open();
}

final class _LocalSession
    implements ReactiveSourceSession<PagedLocalSnapshot<int, _Item>, _Failure> {
  _LocalSession(this.source);

  final _LocalSource source;
  final StreamController<void> _signals = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get signals => _signals.stream;

  void signal() => _signals.add(null);

  @override
  Future<Result<PagedLocalSnapshot<int, _Item>, _Failure>> read(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    source.readCount += 1;
    return Ok<PagedLocalSnapshot<int, _Item>>(source.current);
  }

  @override
  Future<void> close() => _signals.close();
}

final class _FakeTimerFactory implements ReactiveTimerFactory {
  final List<_FakeTimer> _timers = <_FakeTimer>[];
  Duration _elapsed = Duration.zero;

  int get activeCount => _timers.where((timer) => timer.isActive).length;

  @override
  ReactiveTimerHandle schedule(Duration duration, void Function() callback) {
    final timer = _FakeTimer(_elapsed + duration, callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    _elapsed += duration;
    final due = _timers
        .where((timer) => timer.isActive && timer.deadline <= _elapsed)
        .toList(growable: false);
    for (final timer in due) {
      timer.fire();
    }
  }
}

final class _FakeTimer implements ReactiveTimerHandle {
  _FakeTimer(this.deadline, this._callback);

  final Duration deadline;
  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not settle.');
}
