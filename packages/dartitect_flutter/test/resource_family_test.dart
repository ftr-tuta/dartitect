import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'same key shares locally and active entries are never evicted',
    () async {
      var creations = 0;
      LiveResource<int, String> create(String key) {
        creations += 1;
        return LiveResource<int, String>(source: _ControlledSource<int>());
      }

      final family = ResourceFamily<String, int, String>(
        create: create,
        policy: FamilyCachePolicy<String, int>(
          maxIdleEntries: 0,
          maxIdleWeight: 0,
        ),
      );
      final first = family.acquire('same');
      final second = family.acquire('same');
      expect(first.resource, same(second.resource));
      expect(creations, 1);

      final otherFamily = ResourceFamily<String, int, String>(create: create);
      final foreign = otherFamily.acquire('same');
      expect(foreign.resource, isNot(same(first.resource)));
      expect(creations, 2);

      final observation = first.resource.observe();
      void listener() {}
      observation.addListener(listener);
      await observation.settled;
      await first.release();
      await second.release();
      expect(family.entryCount, 1, reason: 'the observer is still active');

      observation.removeListener(listener);
      await observation.settled;
      await family.settled;
      expect(family.entryCount, 0);
      expect(family.idleEntryCount, 0);
      expect(family.activeTimerCount, 0);
      await observation.close();

      await foreign.release();
      await otherFamily.dispose();
      await family.dispose();
    },
  );

  test('cost LRU weight oversized and TTL produce stable eviction', () async {
    final timers = _FakeTimerFactory();
    final weights = <String, int>{'a': 2, 'b': 2, 'c': 2, 'huge': 5};
    final costs = <String, int>{'a': 5, 'b': 0, 'c': 0, 'huge': 10};
    final family = ResourceFamily<String, int, String>(
      create: (_) =>
          LiveResource<int, String>(source: _ControlledSource<int>()),
      policy: FamilyCachePolicy<String, int>(
        idleTtl: const Duration(minutes: 10),
        maxIdleEntries: 2,
        maxIdleWeight: 4,
        weightOf: (key, _) => weights[key]!,
        recreationCostOf: (key) => costs[key]!,
      ),
      timerFactory: timers,
    );

    for (final key in <String>['a', 'b', 'c']) {
      await family.acquire(key).release();
    }
    expect(family.entryCount, 2);
    expect(family.idleWeight, 4);
    expect(family.peakIdleWeight, 6);
    expect(family.evictionTranscript, <String>['b']);

    await family.acquire('huge').release();
    expect(family.entryCount, 2, reason: 'oversized entry is never retained');
    expect(family.idleWeight, 4);
    expect(family.evictionTranscript, <String>['b', 'huge']);

    timers.advance(const Duration(minutes: 10));
    await family.settled;
    expect(family.entryCount, 0);
    expect(family.idleWeight, 0);
    expect(family.activeTimerCount, 0);
    expect(family.evictionTranscript, <String>['b', 'huge', 'c', 'a']);
    await family.dispose();
  });

  test(
    '1000-key churn stays bounded and leaves no entries or timers',
    () async {
      var creations = 0;
      final family = ResourceFamily<int, int, String>(
        create: (_) {
          creations += 1;
          return LiveResource<int, String>(source: _ControlledSource<int>());
        },
        policy: FamilyCachePolicy<int, int>(
          idleTtl: const Duration(hours: 1),
          maxIdleEntries: 32,
          maxIdleWeight: 32,
        ),
        timerFactory: _FakeTimerFactory(),
      );

      for (var key = 0; key < 1000; key += 1) {
        await family.acquire(key).release();
        expect(family.entryCount, lessThanOrEqualTo(32));
        expect(family.idleWeight, lessThanOrEqualTo(32));
      }

      expect(creations, 1000);
      expect(family.entryCount, 32);
      expect(family.idleEntryCount, 32);
      expect(family.evictionTranscript, hasLength(968));
      await family.dispose();
      expect(family.entryCount, 0);
      expect(family.idleEntryCount, 0);
      expect(family.idleWeight, 0);
      expect(family.activeTimerCount, 0);
    },
  );

  test('eviction transcript is identical across repeated runs', () async {
    Future<List<int>> run() async {
      final family = ResourceFamily<int, int, String>(
        create: (_) =>
            LiveResource<int, String>(source: _ControlledSource<int>()),
        policy: FamilyCachePolicy<int, int>(
          maxIdleEntries: 2,
          maxIdleWeight: 2,
          recreationCostOf: (key) => key.isEven ? 0 : 1,
        ),
        timerFactory: _FakeTimerFactory(),
      );
      for (final key in <int>[1, 2, 3, 4, 5, 6]) {
        await family.acquire(key).release();
      }
      final transcript = family.evictionTranscript;
      await family.dispose();
      return transcript;
    }

    final first = await run();
    final second = await run();
    final third = await run();
    expect(first, second);
    expect(second, third);
  });

  test('prewarm owns activation timer and family invalidation', () async {
    final timers = _FakeTimerFactory();
    final sources = <String, _ControlledSource<int>>{};
    final family = ResourceFamily<String, int, String>(
      create: (key) {
        final source = _ControlledSource<int>();
        sources[key] = source;
        return LiveResource<int, String>(source: source);
      },
      policy: FamilyCachePolicy<String, int>(
        maxIdleEntries: 0,
        maxIdleWeight: 0,
      ),
      timerFactory: timers,
    );

    await family.prewarm('field', const Duration(minutes: 2));
    final session = sources['field']!.sessions.single;
    await _waitFor(() => session.reads.length == 1);
    session.reads.single.complete(const Ok<int>(1));
    await _waitFor(() => family.entryCount == 1);
    expect(family.activeTimerCount, 1);

    expect(family.invalidate('field'), 1);
    await _waitFor(() => session.reads.length == 2);
    session.reads.last.complete(const Ok<int>(2));

    timers.advance(const Duration(minutes: 2));
    await family.settled;
    expect(family.entryCount, 0);
    expect(family.activeTimerCount, 0);
    await family.dispose();
  });

  test('reacquire during disposal gets a fresh generation', () async {
    final disposalStarted = Completer<void>();
    final allowDisposal = Completer<void>();
    var disposeCalls = 0;
    var creations = 0;
    final family = ResourceFamily<String, int, String>(
      create: (_) {
        creations += 1;
        return LiveResource<int, String>(source: _ControlledSource<int>());
      },
      policy: FamilyCachePolicy<String, int>(
        maxIdleEntries: 0,
        maxIdleWeight: 0,
      ),
      disposeResource: (resource) async {
        disposeCalls += 1;
        if (disposeCalls == 1) {
          disposalStarted.complete();
          await allowDisposal.future;
        }
        await resource.dispose();
      },
    );
    final oldLease = family.acquire('same');
    final oldResource = oldLease.resource;
    final eviction = oldLease.release();
    await disposalStarted.future;
    expect(family.entryCount, 0, reason: 'removed before async disposal');

    final newLease = family.acquire('same');
    expect(newLease.resource, isNot(same(oldResource)));
    expect(creations, 2);
    allowDisposal.complete();
    await eviction;
    await newLease.release();
    expect(family.entryCount, 0);
    expect(disposeCalls, 2);
    await family.dispose();
  });

  test('failed eviction stays removed and recovery recreates', () async {
    var disposals = 0;
    final family = ResourceFamily<String, int, String>(
      create: (_) =>
          LiveResource<int, String>(source: _ControlledSource<int>()),
      policy: FamilyCachePolicy<String, int>(
        maxIdleEntries: 0,
        maxIdleWeight: 0,
      ),
      disposeResource: (resource) async {
        disposals += 1;
        if (disposals == 1) throw StateError('dispose failed');
        await resource.dispose();
      },
    );

    await expectLater(
      family.acquire('recover').release(),
      throwsA(
        isA<AsyncLifecycleCleanupException>().having(
          (error) => error.failures,
          'failures',
          hasLength(1),
        ),
      ),
    );
    expect(family.entryCount, 0);
    final recreated = family.acquire('recover');
    await recreated.release();
    expect(family.entryCount, 0);
    expect(disposals, 2);
    await family.dispose();
  });
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
  final StreamController<void> _signals = StreamController<void>.broadcast();
  final List<Completer<Result<T, String>>> reads =
      <Completer<Result<T, String>>>[];

  @override
  Stream<void> get signals => _signals.stream;

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
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not settle.');
}
