import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual hot warm cold transitions preserve and discard data', () async {
    var activations = 0;
    var deactivations = 0;
    var discards = 0;
    final resource = ResourceLifecycle<int, String>(
      policy: const ActivationPolicy.manual(),
      onActivate: (generation) async {
        activations += 1;
      },
      onDeactivate: () async {
        deactivations += 1;
      },
      onDiscardSnapshot: () => discards += 1,
    );
    final lease = resource.acquireLease();

    await resource.activate();
    expect(resource.temperature, ResourceTemperature.hot);
    expect(
      resource.publish(
        const ResourceReady<int, String>(7),
        generation: resource.generation,
      ),
      isTrue,
    );
    await resource.deactivate();
    expect(resource.temperature, ResourceTemperature.warm);
    expect(resource.state, isA<ResourceReady<int, String>>());

    await resource.activate();
    expect(resource.temperature, ResourceTemperature.hot);
    await resource.deactivate(retainSnapshot: false);
    expect(resource.temperature, ResourceTemperature.cold);
    expect(resource.state, isA<ResourceWaiting<int, String>>());
    expect(activations, 2);
    expect(deactivations, 2);
    expect(discards, 1);

    await lease.release();
    await lease.release();
    expect(resource.leaseCount, 0);
    await resource.dispose();
  });

  test(
    'alwaysHot and whileObserved cover their terminal transitions',
    () async {
      var alwaysDeactivations = 0;
      final always = ResourceLifecycle<int, String>(
        policy: const ActivationPolicy.alwaysHot(),
        onActivate: (generation) async {},
        onDeactivate: () async {
          alwaysDeactivations += 1;
        },
      );
      await always.start();
      expect(always.temperature, ResourceTemperature.hot);
      await always.dispose();
      expect(always.temperature, ResourceTemperature.cold);
      expect(alwaysDeactivations, 1);

      var observedDeactivations = 0;
      final observed = ResourceLifecycle<int, String>(
        policy: const ActivationPolicy.whileObserved(),
        onActivate: (generation) async {},
        onDeactivate: () async {
          observedDeactivations += 1;
        },
      );
      final observation = observed.observe();
      void listener() {}
      observation.addListener(listener);
      await observation.settled;
      expect(observed.temperature, ResourceTemperature.hot);
      observation.removeListener(listener);
      await observation.settled;
      expect(observed.temperature, ResourceTemperature.cold);
      expect(observedDeactivations, 1);
      await observation.close();
      await observed.dispose();
      expect(
        () => ActivationPolicy.keepWarm(Duration.zero),
        throwsArgumentError,
      );
    },
  );

  test('lease retains automatic activation and release settles cold', () async {
    var activations = 0;
    var deactivations = 0;
    final resource = ResourceLifecycle<int, String>(
      policy: const ActivationPolicy.whileObserved(),
      onActivate: (generation) async {
        activations += 1;
      },
      onDeactivate: () async {
        deactivations += 1;
      },
    );

    final lease = resource.acquireLease();
    await resource.settled;
    expect(resource.temperature, ResourceTemperature.hot);
    expect(resource.leaseCount, 1);
    expect(activations, 1);

    await lease.release();
    expect(lease.isReleased, isTrue);
    expect(resource.temperature, ResourceTemperature.cold);
    expect(resource.leaseCount, 0);
    expect(deactivations, 1);
    await resource.dispose();
  });

  test('owner disposal terminally releases outstanding leases', () async {
    final resource = ResourceLifecycle<int, String>(
      policy: const ActivationPolicy.whileObserved(),
      onActivate: (generation) async {},
      onDeactivate: () async {},
    );
    final lease = resource.acquireLease();
    await resource.settled;

    await resource.dispose();

    expect(lease.isReleased, isTrue);
    expect(resource.leaseCount, 0);
    await lease.release();
  });

  test('keepWarm cancels upstream and handles reacquire around TTL', () async {
    final timers = _FakeTimerFactory();
    late ResourceLifecycle<int, String> resource;
    var activations = 0;
    var deactivations = 0;
    resource = ResourceLifecycle<int, String>(
      policy: ActivationPolicy.keepWarm(const Duration(minutes: 5)),
      timerFactory: timers,
      onActivate: (generation) async {
        activations += 1;
        resource.publish(
          ResourceReady<int, String>(activations),
          generation: generation,
        );
      },
      onDeactivate: () async {
        deactivations += 1;
      },
    );
    final observation = resource.observe();
    void listener() {}

    observation.addListener(listener);
    await observation.settled;
    expect(resource.temperature, ResourceTemperature.hot);
    expect(resource.observerCount, 1);
    expect(activations, 1);

    observation.removeListener(listener);
    await observation.settled;
    expect(resource.temperature, ResourceTemperature.warm);
    expect(resource.state.hasData, isTrue);
    expect(deactivations, 1);
    expect(timers.activeCount, 1);

    timers.advance(const Duration(minutes: 4));
    await resource.settled;
    expect(resource.temperature, ResourceTemperature.warm);
    final lease = resource.acquireLease();
    await observation.settled;
    expect(resource.temperature, ResourceTemperature.hot);
    expect(timers.activeCount, 0);
    expect(activations, 2);

    await lease.release();
    expect(resource.temperature, ResourceTemperature.warm);
    expect(timers.activeCount, 1);
    timers.advance(const Duration(minutes: 5));
    await resource.settled;
    expect(resource.temperature, ResourceTemperature.cold);
    expect(resource.state.hasData, isFalse);
    expect(deactivations, 2);
    await observation.close();
    await resource.dispose();
    expect(timers.activeCount, 0);
  });

  testWidgets('TickerMode pauses and resumes an observation', (tester) async {
    late ResourceLifecycle<int, String> resource;
    var activations = 0;
    var deactivations = 0;
    resource = ResourceLifecycle<int, String>(
      policy: ActivationPolicy.keepWarm(const Duration(minutes: 1)),
      onActivate: (generation) async {
        activations += 1;
        resource.publish(
          ResourceReady<int, String>(activations),
          generation: generation,
        );
      },
      onDeactivate: () async {
        deactivations += 1;
      },
    );
    final observation = resource.observe(tickerEnabled: false);

    await tester.pumpWidget(
      TickerMode(enabled: true, child: _ObservationHost(observation)),
    );
    await observation.settled;
    expect(observation.isActive, isTrue);
    expect(resource.temperature, ResourceTemperature.hot);

    await tester.pumpWidget(
      TickerMode(enabled: false, child: _ObservationHost(observation)),
    );
    await observation.settled;
    expect(observation.isActive, isFalse);
    expect(resource.temperature, ResourceTemperature.warm);
    expect(deactivations, 1);

    await tester.pumpWidget(
      TickerMode(enabled: true, child: _ObservationHost(observation)),
    );
    await observation.settled;
    expect(resource.temperature, ResourceTemperature.hot);
    expect(activations, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await observation.settled;
    expect(resource.observerCount, 0);
    await resource.dispose();
  });

  test('barrier closes admission, cancels once, and drains', () async {
    final barrier = AsyncLifecycleBarrier();
    final operation = Completer<int>();
    var cancellations = 0;
    final result = barrier.run<int>(
      () => operation.future,
      cancel: () {
        cancellations += 1;
        operation.complete(42);
      },
    );
    final firstClose = barrier.close();
    final secondClose = barrier.close();

    expect(barrier.isOpen, isFalse);
    await expectLater(
      barrier.run<void>(() async {}),
      throwsA(isA<StateError>()),
    );
    expect(await result, 42);
    await Future.wait(<Future<void>>[firstClose, secondClose]);
    expect(cancellations, 1);
    expect(barrier.activeOperationCount, 0);
    expect(barrier.isClosed, isTrue);
  });

  test('barrier aggregates cancellation failure after draining', () async {
    final barrier = AsyncLifecycleBarrier();
    final operation = Completer<void>();
    final work = barrier.run<void>(
      () => operation.future,
      cancel: () {
        operation.complete();
        throw StateError('cancel failed');
      },
    );

    await expectLater(
      barrier.close(),
      throwsA(
        isA<AsyncLifecycleCleanupException>().having(
          (error) => error.failures,
          'failures',
          hasLength(1),
        ),
      ),
    );
    await work;
    expect(barrier.activeOperationCount, 0);
    expect(barrier.isClosed, isTrue);
  });

  test('dispose blocks stale publication before draining work', () async {
    final barrier = AsyncLifecycleBarrier();
    final operation = Completer<void>();
    final resource = ResourceLifecycle<int, String>(
      policy: const ActivationPolicy.manual(),
      barrier: barrier,
      onActivate: (generation) async {},
      onDeactivate: () async {},
    );
    await resource.activate();
    final generation = resource.generation;
    final work = barrier.run<void>(
      () => operation.future,
      cancel: operation.complete,
    );

    final firstDispose = resource.dispose();
    final secondDispose = resource.dispose();
    expect(
      resource.publish(
        const ResourceReady<int, String>(1),
        generation: generation,
      ),
      isFalse,
    );
    await Future.wait(<Future<void>>[work, firstDispose, secondDispose]);
    expect(resource.temperature, ResourceTemperature.cold);
    expect(resource.observerCount, 0);
    expect(barrier.activeOperationCount, 0);
  });

  test('failure states preserve nullable last-known data explicitly', () {
    const failed = ResourceFailed<int?, String>(
      'offline',
      lastData: null,
      hasData: true,
    );
    final crashed = ResourceCrashed<int?, String>(
      StateError('boom'),
      StackTrace.current,
      lastData: null,
      hasData: true,
    );
    expect(failed.hasData, isTrue);
    expect(failed.lastData, isNull);
    expect(crashed.hasData, isTrue);
    expect(crashed.lastData, isNull);
  });
}

final class _ObservationHost extends StatefulWidget {
  const _ObservationHost(this.observation);

  final ReactiveObservation<int, String> observation;

  @override
  State<_ObservationHost> createState() => _ObservationHostState();
}

final class _ObservationHostState extends State<_ObservationHost> {
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.observation.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(
      widget.observation.setTickerEnabled(TickerMode.valuesOf(context).enabled),
    );
  }

  @override
  void dispose() {
    widget.observation.removeListener(_changed);
    unawaited(widget.observation.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    '${widget.observation.temperature}:${widget.observation.state.hasData}',
    textDirection: TextDirection.ltr,
  );
}

final class _FakeTimerFactory implements ReactiveTimerFactory {
  final List<_FakeTimer> _timers = <_FakeTimer>[];
  Duration _elapsed = Duration.zero;

  int get activeCount => _timers.where((timer) => timer.isActive).length;

  @override
  ReactiveTimerHandle schedule(Duration duration, VoidCallback callback) {
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
  final VoidCallback _callback;
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
