import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'late dependency generation never publishes over the newest read',
    () async {
      final dependency = ValueNotifier<int>(0);
      final reads = <_Read>[];
      final readyValues = <int>[];
      final resource = DerivedAsyncResource<int, String>(
        dependencies: <Listenable>[dependency],
        policy: const ActivationPolicy.alwaysHot(),
        load: (context) {
          final read = _Read(context);
          reads.add(read);
          return read.result.future;
        },
      );
      void listener() {
        if (resource.state case ResourceReady<int, String>(:final data)) {
          readyValues.add(data);
        }
      }

      resource.addListener(listener);
      await resource.start();
      await _waitFor(() => reads.length == 1);
      dependency.value = 1;
      expect(reads.single.context.cancellation.isCancelled, isTrue);

      // The loader deliberately ignores cancellation. Its old value must still
      // be rejected before the newest generation is admitted.
      reads[0].result.complete(const Ok<int>(10));
      await _waitFor(() => reads.length == 2);
      expect(reads[1].context.dependencyGeneration, 1);
      expect(readyValues, isNot(contains(10)));
      reads[1].result.complete(const Ok<int>(20));
      await _waitFor(() => resource.state.lastData == 20);

      expect(readyValues, <int>[20]);
      expect(resource.dependencyRevision, 1);
      resource.removeListener(listener);
      await resource.dispose();
      dependency.dispose();
    },
  );

  test('dependencies exist only for an observed hot lifecycle', () async {
    final dependency = _CountingListenable();
    final resource = DerivedAsyncResource<int, String>(
      dependencies: <Listenable>[dependency],
      load: (_) async => const Ok<int>(1),
    );
    final observation = resource.observe();
    void listener() {}

    expect(dependency.listenerCount, 0);
    observation.addListener(listener);
    await observation.settled;
    await _waitFor(() => resource.state.lastData == 1);
    expect(dependency.listenerCount, 1);

    observation.removeListener(listener);
    await observation.settled;
    expect(dependency.listenerCount, 0);
    await observation.close();
    await resource.dispose();
  });

  test(
    'stale policy, deduplication, expected failure, and crash are explicit',
    () async {
      final dependency = ValueNotifier<int>(0);
      final reads = <_Read>[];
      final reporter = _CrashReporter();
      final resource = DerivedAsyncResource<int, String>(
        dependencies: <Listenable>[dependency],
        policy: const ActivationPolicy.alwaysHot(),
        stalePolicy: LiveResourceStalePolicy.staleWhileRevalidate,
        reporter: reporter,
        load: (context) {
          final read = _Read(context);
          reads.add(read);
          return read.result.future;
        },
      );
      await resource.start();
      await _waitFor(() => reads.length == 1);
      reads[0].result.complete(const Ok<int>(5));
      await _waitFor(() => resource.state is ResourceReady<int, String>);
      final firstReady = resource.state;

      dependency.value = 1;
      await _waitFor(() => reads.length == 2);
      expect(resource.state, same(firstReady));
      expect(resource.isStale, isTrue);
      reads[1].result.complete(const Ok<int>(5));
      await _waitFor(() => !resource.isStale);
      expect(resource.state, same(firstReady));

      dependency.value = 2;
      await _waitFor(() => reads.length == 3);
      reads[2].result.complete(Err<String>('offline', StackTrace.current));
      await _waitFor(() => resource.state is ResourceFailed<int, String>);
      expect(resource.state.lastData, 5);

      dependency.value = 3;
      await _waitFor(() => reads.length == 4);
      reads[3].result.completeError(StateError('derived crash'));
      await _waitFor(() => resource.state is ResourceCrashed<int, String>);
      expect(resource.state.lastData, 5);
      expect(reporter.errors, 1);

      await resource.dispose();
      dependency.dispose();
    },
  );

  test('family retains derived resources under its explicit key and eviction policy', () async {
    final dependency = ValueNotifier<int>(1);
    final family = ResourceFamily<String, int, String>(
      create: (_) => DerivedAsyncResource<int, String>(
        dependencies: <Listenable>[dependency],
        load: (_) async => Ok<int>(dependency.value),
      ).liveResource,
      policy: FamilyCachePolicy<String, int>(
        maxIdleEntries: 0,
        maxIdleWeight: 0,
      ),
    );

    final first = family.acquire('account');
    final second = family.acquire('account');
    expect(first.resource, same(second.resource));
    await first.release();
    expect(family.entryCount, 1);
    await second.release();
    expect(family.entryCount, 0);
    expect(family.evictionTranscript, <String>['account']);
    await family.dispose();
    dependency.dispose();
  });

  test('invalid dependency declarations fail before subscriptions', () {
    final dependency = _CountingListenable();
    expect(
      () => DerivedAsyncResource<int, String>(
        dependencies: const <Listenable>[],
        load: (_) async => const Ok<int>(1),
      ),
      throwsArgumentError,
    );
    expect(
      () => DerivedAsyncResource<int, String>(
        dependencies: <Listenable>[dependency, dependency],
        load: (_) async => const Ok<int>(1),
      ),
      throwsArgumentError,
    );
    expect(dependency.listenerCount, 0);
  });

  test(
    'optional diagnostics expose lifecycle but never failure payload',
    () async {
      final dependency = ValueNotifier<int>(0);
      final buffer = DartitectDiagnosticBuffer(capacity: 16);
      final emitter = DartitectDiagnosticsEmitter(
        reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
        idGenerator: _Ids(),
        detail: DartitectDiagnosticDetail.topology,
      );
      final diagnosticSubject = emitter.subject(
        DartitectDiagnosticSubjectKind.resource,
      );
      final reads = <_Read>[];
      final resource = DerivedAsyncResource<int, String>(
        dependencies: <Listenable>[dependency],
        policy: const ActivationPolicy.alwaysHot(),
        diagnostics: diagnosticSubject,
        load: (context) {
          final read = _Read(context);
          reads.add(read);
          return read.result.future;
        },
      );
      await resource.start();
      await _waitFor(() => reads.length == 1);
      reads[0].result.complete(
        Err<String>('customer-secret-failure', StackTrace.current),
      );
      await _waitFor(() => resource.state is ResourceFailed<int, String>);
      await resource.dispose();

      expect(
        buffer.events.map((event) => event.phase),
        containsAll(<DartitectDiagnosticPhase>[
          DartitectDiagnosticPhase.waiting,
          DartitectDiagnosticPhase.failed,
          DartitectDiagnosticPhase.disposed,
        ]),
      );
      expect(
        buffer.events.map((event) => event.toJson().toString()).join(),
        isNot(contains('customer-secret-failure')),
      );
      await emitter.dispose();
      buffer.dispose();
      dependency.dispose();
    },
  );
}

final class _Read {
  _Read(this.context);

  final DerivedAsyncRead context;
  final Completer<Result<int, String>> result =
      Completer<Result<int, String>>();
}

final class _CountingListenable implements Listenable {
  final List<VoidCallback> _listeners = <VoidCallback>[];

  int get listenerCount => _listeners.length;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

final class _CrashReporter implements LiveResourceCrashReporter {
  var errors = 0;

  @override
  void report(Object error, StackTrace stackTrace) => errors += 1;
}

final class _Ids implements IdGenerator {
  var next = 0;

  @override
  String nextId() {
    next += 1;
    return '00000000-0000-4000-8000-${next.toString().padLeft(12, '0')}';
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var index = 0; index < 100; index += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached.');
}
