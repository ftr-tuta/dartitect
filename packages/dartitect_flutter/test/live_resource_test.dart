import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'latestWhileBusy turns a 100-signal burst into exactly two reads',
    () async {
      final source = _FakeSource();
      final resource = LiveResource<int, String>(source: source);
      final observation = resource.observe();
      void listener() {}
      observation.addListener(listener);
      await observation.settled;
      final session = source.sessions.single;
      await _waitFor(() => session.reads.length == 1);

      for (var index = 0; index < 100; index += 1) {
        session.signal();
      }
      session.reads[0].complete(const Ok<int>(1));
      await _waitFor(() => session.reads.length == 2);
      session.reads[1].complete(const Ok<int>(2));
      await _waitFor(() => _isReadyWith(resource.state, 2));

      expect(resource.readCount, 2);
      expect(resource.activeOperationCount, 0);
      observation.removeListener(listener);
      await observation.settled;
      expect(session.transcript, <String>[
        'subscription.cancel',
        'session.close',
      ]);
      expect(resource.temperature, ResourceTemperature.cold);
      await observation.close();
      await resource.dispose();
    },
  );

  test('everyEmission preserves every signal in FIFO order', () async {
    final source = _FakeSource();
    final resource = LiveResource<int, String>(
      source: source,
      backpressure: SourceBackpressure.everyEmission,
    );
    final observation = resource.observe();
    void listener() {}
    observation.addListener(listener);
    await observation.settled;
    final session = source.sessions.single;
    await _waitFor(() => session.reads.length == 1);
    session
      ..signal()
      ..signal()
      ..signal();

    for (var index = 0; index < 4; index += 1) {
      await _waitFor(() => session.reads.length == index + 1);
      session.reads[index].complete(Ok<int>(index));
    }
    await _waitFor(() => resource.activeOperationCount == 0);
    expect(resource.readCount, 4);
    observation.removeListener(listener);
    await observation.settled;
    await observation.close();
    await resource.dispose();
  });

  test('microtask and frame policies coalesce their boundaries', () async {
    final microtaskSource = _FakeSource();
    final microtask = LiveResource<int, String>(
      source: microtaskSource,
      backpressure: SourceBackpressure.coalesceMicrotask,
    );
    final microtaskObservation = microtask.observe();
    void listener() {}
    microtaskObservation.addListener(listener);
    await microtaskObservation.settled;
    final microtaskSession = microtaskSource.sessions.single;
    await _waitFor(() => microtaskSession.reads.length == 1);
    microtaskSession.reads.single.complete(const Ok<int>(1));
    await _waitFor(() => microtask.activeOperationCount == 0);
    for (var index = 0; index < 100; index += 1) {
      microtaskSession.signal();
    }
    await _waitFor(() => microtaskSession.reads.length == 2);
    microtaskSession.reads.last.complete(const Ok<int>(2));
    await _waitFor(() => microtask.activeOperationCount == 0);
    expect(microtask.readCount, 2);
    microtaskObservation.removeListener(listener);
    await microtaskObservation.settled;
    await microtaskObservation.close();
    await microtask.dispose();

    final frames = _FakeFrameScheduler();
    final frameSource = _FakeSource();
    final frame = LiveResource<int, String>(
      source: frameSource,
      backpressure: SourceBackpressure.coalesceFrame,
      frameScheduler: frames,
    );
    final frameObservation = frame.observe();
    frameObservation.addListener(listener);
    await frameObservation.settled;
    expect(frames.pendingCount, 1);
    frames.flush();
    final frameSession = frameSource.sessions.single;
    await _waitFor(() => frameSession.reads.length == 1);
    frameSession.reads.single.complete(const Ok<int>(1));
    await _waitFor(() => frame.activeOperationCount == 0);
    for (var index = 0; index < 100; index += 1) {
      frameSession.signal();
    }
    expect(frames.pendingCount, 1);
    frames.flush();
    await _waitFor(() => frameSession.reads.length == 2);
    frameSession.reads.last.complete(const Ok<int>(2));
    await _waitFor(() => frame.activeOperationCount == 0);
    expect(frame.readCount, 2);
    frameObservation.removeListener(listener);
    await frameObservation.settled;
    await frameObservation.close();
    await frame.dispose();
  });

  test('typed failure retains data and crash suspends until retry', () async {
    final source = _FakeSource();
    final reporter = _Reporter();
    final resource = LiveResource<int, String>(
      source: source,
      policy: ActivationPolicy.keepWarm(const Duration(minutes: 1)),
      reporter: reporter,
    );
    final observation = resource.observe();
    void listener() {}
    observation.addListener(listener);
    await observation.settled;
    var session = source.sessions.single;
    await _waitFor(() => session.reads.length == 1);
    session.reads.single.complete(const Ok<int>(10));
    await _waitFor(() => _isReadyWith(resource.state, 10));

    session.signal();
    await _waitFor(() => session.reads.length == 2);
    session.reads.last.complete(Err<String>('offline', StackTrace.current));
    await _waitFor(() => resource.state is ResourceFailed<int, String>);
    expect(resource.state.lastData, 10);
    expect(resource.temperature, ResourceTemperature.hot);

    session.signal();
    await _waitFor(() => session.reads.length == 3);
    session.reads.last.completeError(StateError('query crashed'));
    await _waitFor(() => resource.temperature == ResourceTemperature.warm);
    expect(resource.state, isA<ResourceCrashed<int, String>>());
    expect(resource.state.lastData, 10);
    expect(reporter.errors, hasLength(1));
    expect(session.transcript, <String>[
      'subscription.cancel',
      'session.close',
    ]);

    await resource.retry();
    expect(source.sessions, hasLength(2));
    session = source.sessions.last;
    await _waitFor(() => session.reads.length == 1);
    session.reads.single.complete(const Ok<int>(20));
    await _waitFor(() => _isReadyWith(resource.state, 20));
    observation.removeListener(listener);
    await observation.settled;
    await observation.close();
    await resource.dispose();
    expect(resource.activeOperationCount, 0);
  });

  test('keepWarm closes the source, retains data, then expires cold', () async {
    final timers = _FakeTimerFactory();
    final source = _FakeSource();
    final resource = LiveResource<int, String>(
      source: source,
      policy: ActivationPolicy.keepWarm(const Duration(minutes: 5)),
      timerFactory: timers,
    );
    final observation = resource.observe();
    void listener() {}
    observation.addListener(listener);
    await observation.settled;
    final session = source.sessions.single;
    await _waitFor(() => session.reads.length == 1);
    session.reads.single.complete(const Ok<int>(7));
    await _waitFor(() => _isReadyWith(resource.state, 7));

    observation.removeListener(listener);
    await observation.settled;
    expect(resource.temperature, ResourceTemperature.warm);
    expect(resource.state.lastData, 7);
    expect(session.transcript, <String>[
      'subscription.cancel',
      'session.close',
    ]);

    timers.advance(const Duration(minutes: 5));
    await resource.settled;
    expect(resource.temperature, ResourceTemperature.cold);
    expect(resource.state.hasData, isFalse);
    expect(timers.activeCount, 0);
    await observation.close();
    await resource.dispose();
  });

  test(
    'multiple unexpected source errors report once per generation',
    () async {
      final source = _FakeSource();
      final reporter = _Reporter();
      final resource = LiveResource<int, String>(
        source: source,
        policy: ActivationPolicy.keepWarm(const Duration(minutes: 1)),
        reporter: reporter,
      );
      final observation = resource.observe();
      void listener() {}
      observation.addListener(listener);
      await observation.settled;
      final session = source.sessions.single;
      await _waitFor(() => session.reads.length == 1);
      session.reads.single.complete(const Ok<int>(1));
      await _waitFor(() => _isReadyWith(resource.state, 1));

      session
        ..crash(StateError('first'))
        ..crash(StateError('duplicate'));
      await _waitFor(() => resource.temperature == ResourceTemperature.warm);
      expect(reporter.errors, hasLength(1));
      expect(resource.state, isA<ResourceCrashed<int, String>>());

      observation.removeListener(listener);
      await observation.settled;
      await observation.close();
      await resource.dispose();
    },
  );

  test('dispose cancels a blocked read and rejects late publication', () async {
    final source = _FakeSource(ignoreCancellation: true);
    final resource = LiveResource<int, String>(
      source: source,
      policy: const ActivationPolicy.alwaysHot(),
    );
    await resource.start();
    final session = source.sessions.single;
    await _waitFor(() => session.reads.length == 1);

    final firstDispose = resource.dispose();
    final secondDispose = resource.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(resource.activeOperationCount, 1);
    session.reads.single.complete(const Ok<int>(99));
    await Future.wait(<Future<void>>[firstDispose, secondDispose]);

    expect(resource.isDisposed, isTrue);
    expect(resource.activeOperationCount, 0);
    expect(session.transcript, <String>[
      'subscription.cancel',
      'session.close',
    ]);
    expect(resource.state, isA<ResourceWaiting<int, String>>());
  });
}

final class _FakeSource implements ReactiveSource<int, String> {
  _FakeSource({this.ignoreCancellation = false});

  final bool ignoreCancellation;
  final List<_FakeSession> sessions = <_FakeSession>[];

  @override
  Future<Result<ReactiveSourceSession<int, String>, String>> open() async {
    final session = _FakeSession(ignoreCancellation: ignoreCancellation);
    sessions.add(session);
    return Ok<ReactiveSourceSession<int, String>>(session);
  }
}

final class _FakeSession implements ReactiveSourceSession<int, String> {
  _FakeSession({required this.ignoreCancellation}) {
    _signals = StreamController<void>.broadcast(
      sync: true,
      onCancel: () => transcript.add('subscription.cancel'),
    );
  }

  late final StreamController<void> _signals;
  final bool ignoreCancellation;
  final List<Completer<Result<int, String>>> reads =
      <Completer<Result<int, String>>>[];
  final List<String> transcript = <String>[];
  var _closed = false;

  @override
  Stream<void> get signals => _signals.stream;

  void signal() => _signals.add(null);

  void crash(Object error) => _signals.addError(error, StackTrace.current);

  @override
  Future<Result<int, String>> read(CancellationSignal signal) {
    final completer = Completer<Result<int, String>>();
    reads.add(completer);
    if (ignoreCancellation) return completer.future;
    final registration = signal.register((reason) {
      if (!completer.isCompleted) {
        completer.completeError(CancellationException(reason));
      }
    });
    return completer.future.whenComplete(registration.dispose);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    transcript.add('session.close');
    await _signals.close();
  }
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
    for (final timer in _timers.where(
      (timer) => timer.isActive && timer.deadline <= _elapsed,
    )) {
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

final class _FakeFrameScheduler implements SourceFrameScheduler {
  final List<void Function()> _callbacks = <void Function()>[];

  int get pendingCount => _callbacks.length;

  @override
  void schedule(void Function() callback) => _callbacks.add(callback);

  void flush() {
    final callbacks = List<void Function()>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

final class _Reporter implements LiveResourceCrashReporter {
  final List<Object> errors = <Object>[];

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not settle.');
}

bool _isReadyWith(ResourceDataState<int, String> state, int value) =>
    switch (state) {
      ResourceReady<int, String>(data: final data) => data == value,
      _ => false,
    };
