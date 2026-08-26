import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed invalidation is monotonic across hot warm and cold', () async {
    final owner = ReactiveOwner();
    final group = owner.invalidationGroup<String>();

    final hotSource = _ControlledSource<int>();
    final hot = LiveResource<int, String>(
      source: hotSource,
      policy: const ActivationPolicy.alwaysHot(),
    );
    group.bind('hot', hot);
    await hot.start();
    var hotSession = hotSource.sessions.single;
    await _waitFor(() => hotSession.reads.length == 1);
    hotSession.reads.single.complete(const Ok<int>(0));
    await _waitFor(() => hot.state.lastData == 0);

    expect(group.invalidate('hot'), 1);
    await _waitFor(() => hotSession.reads.length == 2);
    expect(hot.isStale, isTrue);
    expect(hot.invalidationRevision, 1);
    group.invalidate('hot');
    expect(group.revision, 2);
    expect(hot.invalidationRevision, 2);
    hotSession.reads[1].complete(const Ok<int>(1));
    await _waitFor(() => hotSession.reads.length == 3);
    expect(
      hot.isStale,
      isTrue,
      reason: 'the newer invalidation is still dirty',
    );
    hotSession.reads[2].complete(const Ok<int>(2));
    await _waitFor(() => hot.state.lastData == 2);
    expect(hot.isStale, isFalse);
    expect(hot.observedInvalidationRevision, 2);

    final warmSource = _ControlledSource<int>();
    final warm = LiveResource<int, String>(
      source: warmSource,
      policy: ActivationPolicy.keepWarm(const Duration(minutes: 5)),
    );
    group.bind('warm', warm);
    final warmObservation = warm.observe();
    void listener() {}
    warmObservation.addListener(listener);
    await warmObservation.settled;
    hotSession = warmSource.sessions.single;
    await _waitFor(() => hotSession.reads.length == 1);
    hotSession.reads.single.complete(const Ok<int>(10));
    await _waitFor(() => warm.state.lastData == 10);
    warmObservation.removeListener(listener);
    await warmObservation.settled;
    expect(warm.temperature, ResourceTemperature.warm);

    expect(group.invalidateWhere((key) => key == 'warm'), 3);
    expect(warm.isStale, isTrue);
    expect(
      warmSource.sessions,
      hasLength(1),
      reason: 'warm does no source work',
    );
    warmObservation.addListener(listener);
    await warmObservation.settled;
    final reactivated = warmSource.sessions.last;
    await _waitFor(() => reactivated.reads.length == 1);
    reactivated.reads.single.complete(const Ok<int>(11));
    await _waitFor(() => warm.state.lastData == 11);
    expect(warm.isStale, isFalse);

    final coldSource = _ControlledSource<int>();
    final cold = LiveResource<int, String>(source: coldSource);
    group.bind('cold', cold);
    expect(group.invalidate('cold'), 4);
    expect(coldSource.sessions, isEmpty);
    expect(cold.invalidationRevision, 0);
    expect(cold.isStale, isFalse);

    warmObservation.removeListener(listener);
    await warmObservation.settled;
    await warmObservation.close();
    await owner.dispose();
    expect(group.isDisposed, isTrue);
    expect(group.bindingCount, 0);
    await Future.wait(<Future<void>>[
      hot.dispose(),
      warm.dispose(),
      cold.dispose(),
    ]);
  });

  test('observed refresh completes after matching publication flush', () async {
    final source = _ControlledSource<ObservedValue<String, int>>();
    final resource = LiveResource<ObservedValue<String, int>, String>(
      source: source,
      policy: const ActivationPolicy.alwaysHot(),
    );
    await resource.start();
    final session = source.sessions.single;
    await _waitFor(() => session.reads.length == 1);
    session.reads.single.complete(
      const Ok<ObservedValue<String, int>>(ObservedValue('zero', 0)),
    );
    await _waitFor(() => resource.state.lastData?.revision == 0);

    final receipts = <int>[1, 2, 3, 4, 5];
    final commit = LocalCommitRefresh<int, String>(() async {
      return Ok<LocalCommitReceipt<int>>(
        LocalCommitReceipt<int>(receipts.removeAt(0)),
      );
    });
    final timers = _FakeTimerFactory();
    final refresh = ObservedLocalRefresh<String, int, String>(
      commit: commit,
      resource: resource,
      timeout: const Duration(seconds: 30),
      mapTimeout: (receipt) => 'timeout:${receipt.revision}',
      timerFactory: timers,
    );
    final group = InvalidationGroup<String>();
    group.bind('items', resource);
    final timeline = <String>[];
    final ui = resource.observe();
    void uiListener() {
      final data = ui.state.lastData;
      if (ui.state is ResourceReady<ObservedValue<String, int>, String> &&
          data != null) {
        timeline.add('ui:${data.revision}');
      }
    }

    ui.addListener(uiListener);
    await ui.settled;
    final first = refresh.execute();
    unawaited(first.then((_) => timeline.add('refresh:1')));
    await _waitFor(() => refresh.waiterCount == 1);
    expect(timeline, isEmpty);
    group.invalidate('items');
    await _waitFor(() => session.reads.length == 2);
    session.reads[1].complete(
      const Ok<ObservedValue<String, int>>(ObservedValue('one', 1)),
    );
    final firstResult = await first;
    expect((firstResult as Ok<ObservedValue<String, int>>).value.revision, 1);
    await Future<void>.delayed(Duration.zero);
    expect(timeline, <String>['ui:1', 'refresh:1']);
    expect(refresh.waiterCount, 0);
    expect(refresh.activeTimerCount, 0);

    final timedOut = refresh.execute();
    await _waitFor(() => refresh.waiterCount == 1);
    timers.advance(const Duration(seconds: 30));
    final timeoutResult = await timedOut;
    expect((timeoutResult as Err<String>).failure, 'timeout:2');
    expect(resource.state.lastData?.revision, 1);
    expect(refresh.waiterCount, 0);
    expect(refresh.activeTimerCount, 0);

    final third = refresh.execute();
    final fourth = refresh.execute();
    await _waitFor(() => refresh.waiterCount == 2);
    group
      ..invalidate('items')
      ..invalidate('items');
    await _waitFor(() => session.reads.length == 3);
    session.reads[2].complete(
      const Ok<ObservedValue<String, int>>(ObservedValue('three', 3)),
    );
    expect((await third as Ok<ObservedValue<String, int>>).value.revision, 3);
    await _waitFor(() => session.reads.length == 4);
    session.reads[3].complete(
      const Ok<ObservedValue<String, int>>(ObservedValue('four', 4)),
    );
    expect((await fourth as Ok<ObservedValue<String, int>>).value.revision, 4);
    expect(refresh.waiterCount, 0);

    final cancelled = refresh.execute();
    await _waitFor(() => refresh.waiterCount == 1);
    final cancellationExpectation = expectLater(
      cancelled,
      throwsA(isA<CancellationException>()),
    );
    await refresh.dispose();
    await cancellationExpectation;
    expect(refresh.waiterCount, 0);
    expect(refresh.activeTimerCount, 0);

    ui.removeListener(uiListener);
    await ui.settled;
    await ui.close();
    group.dispose();
    await resource.dispose();
  });

  test(
    'remote and local refresh types preserve distinct completion values',
    () async {
      final remote = RemoteRefresh<int, String>(() async => const Ok<int>(7));
      final local = LocalCommitRefresh<int, String>(
        () async => const Ok<LocalCommitReceipt<int>>(LocalCommitReceipt(9)),
      );

      expect((await remote.execute() as Ok<int>).value, 7);
      expect(
        (await local.execute() as Ok<LocalCommitReceipt<int>>).value.revision,
        9,
      );
      final invalidResource = LiveResource<ObservedValue<int, int>, String>(
        source: _ControlledSource<ObservedValue<int, int>>(),
      );
      expect(
        () => ObservedLocalRefresh<int, int, String>(
          commit: local,
          resource: invalidResource,
          timeout: Duration.zero,
          mapTimeout: (_) => 'timeout',
        ),
        throwsArgumentError,
      );
      await invalidResource.dispose();

      final failureResource = LiveResource<ObservedValue<int, int>, String>(
        source: _ControlledSource<ObservedValue<int, int>>(),
      );
      final failed = ObservedLocalRefresh<int, int, String>(
        commit: LocalCommitRefresh<int, String>(
          () async => Err<String>('offline', StackTrace.current),
        ),
        resource: failureResource,
        timeout: const Duration(seconds: 1),
        mapTimeout: (_) => 'timeout',
      );
      expect((await failed.execute() as Err<String>).failure, 'offline');
      expect(failed.waiterCount, 0);
      expect(failed.activeTimerCount, 0);
      await failed.dispose();
      await failureResource.dispose();
    },
  );
}

final class _ControlledSource<T> implements ReactiveSource<T, String> {
  final List<_ControlledSession<T>> sessions = <_ControlledSession<T>>[];

  @override
  Future<Result<ReactiveSourceSession<T, String>, String>> open() async {
    final session = _ControlledSession<T>();
    sessions.add(session);
    return Ok<ReactiveSourceSession<T, String>>(session);
  }
}

final class _ControlledSession<T> implements ReactiveSourceSession<T, String> {
  final StreamController<void> _signals = StreamController<void>.broadcast(
    sync: true,
  );
  final List<Completer<Result<T, String>>> reads =
      <Completer<Result<T, String>>>[];

  @override
  Stream<void> get signals => _signals.stream;

  void signal() => _signals.add(null);

  @override
  Future<Result<T, String>> read(CancellationSignal signal) {
    final completer = Completer<Result<T, String>>();
    reads.add(completer);
    final registration = signal.register((reason) {
      if (!completer.isCompleted) {
        completer.completeError(CancellationException(reason));
      }
    });
    return completer.future.whenComplete(registration.dispose);
  }

  @override
  Future<void> close() => _signals.close();
}

final class _FakeTimerFactory implements ReactiveTimerFactory {
  final List<_FakeTimer> _timers = <_FakeTimer>[];
  Duration _elapsed = Duration.zero;

  @override
  ReactiveTimerHandle schedule(Duration duration, void Function() callback) {
    final timer = _FakeTimer(_elapsed + duration, callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    _elapsed += duration;
    for (final timer
        in _timers
            .where((timer) => timer.isActive && timer.deadline <= _elapsed)
            .toList(growable: false)) {
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
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not settle.');
}
