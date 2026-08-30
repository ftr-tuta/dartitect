// ignore_for_file: close_sinks

import 'dart:async';

import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:test/test.dart';

void main() {
  test(
    'coalesces active triggers into at most one prioritized follow-up',
    () async {
      final sources = _Sources<String>();
      addTearDown(sources.close);
      final batches = <SyncTriggerBatch<String>>[];
      final completions = <Completer<SyncTriggerRunDisposition>>[];
      final crashes = <Object>[];
      final coordinator = SyncTriggerCoordinator<String>(
        sources: sources.value,
        run: (batch, _) {
          batches.add(batch);
          final completion = Completer<SyncTriggerRunDisposition>();
          completions.add(completion);
          return completion.future;
        },
        reportCrash: (error, _) => crashes.add(error),
      )..start();
      addTearDown(coordinator.disposeAsync);

      sources.manual.add(
        SyncTriggerIntent<String>.work(const <String>{'tasks'}),
      );
      await _eventually(() => batches.length == 1);
      sources.lifecycle.add(
        SyncTriggerIntent<String>.work(const <String>{'notes'}),
      );
      sources.scheduler.add(
        SyncTriggerIntent<String>.work(const <String>{'catalog'}),
      );
      sources.push.add(
        SyncTriggerIntent<String>.work(const <String>{'orders', 'notes'}),
      );

      expect(coordinator.snapshot.phase, SyncTriggerPhase.running);
      expect(coordinator.snapshot.pendingDatasets, <String>{
        'notes',
        'catalog',
        'orders',
      });
      expect(coordinator.snapshot.cause, SyncTriggerCause.push);
      completions.first.complete(SyncTriggerRunDisposition.completed);

      await _eventually(() => batches.length == 2);
      expect(batches[1].datasets, <String>{'notes', 'catalog', 'orders'});
      expect(batches[1].cause, SyncTriggerCause.push);
      expect(batches[1].generation, 0);
      expect(batches, hasLength(2));

      completions[1].complete(SyncTriggerRunDisposition.completed);
      await _eventually(
        () => coordinator.snapshot.phase == SyncTriggerPhase.idle,
      );
      expect(crashes, isEmpty);
    },
  );

  test('offline and backoff require explicit external release', () async {
    final sources = _Sources<String>();
    addTearDown(sources.close);
    final batches = <SyncTriggerBatch<String>>[];
    final dispositions = <SyncTriggerRunDisposition>[
      SyncTriggerRunDisposition.backoff,
      SyncTriggerRunDisposition.completed,
    ];
    final coordinator = SyncTriggerCoordinator<String>(
      sources: sources.value,
      run: (batch, _) async {
        batches.add(batch);
        return dispositions.removeAt(0);
      },
      reportCrash: (error, stackTrace) => fail('$error\n$stackTrace'),
    )..start();
    addTearDown(coordinator.disposeAsync);

    sources.connectivity.add(
      SyncTriggerIntent<String>.connectivity(online: false),
    );
    sources.manual.add(SyncTriggerIntent<String>.work(const <String>{'tasks'}));
    await _pump();
    expect(coordinator.snapshot.phase, SyncTriggerPhase.offline);
    expect(batches, isEmpty);

    sources.connectivity.add(
      SyncTriggerIntent<String>.connectivity(online: true),
    );
    await _eventually(
      () => coordinator.snapshot.phase == SyncTriggerPhase.backoff,
    );
    expect(batches, hasLength(1));

    sources.manual.add(SyncTriggerIntent<String>.work(const <String>{'notes'}));
    await _pump();
    expect(batches, hasLength(1));
    expect(coordinator.snapshot.pendingDatasets, <String>{'notes'});

    coordinator.resumeBackoff();
    await _eventually(() => batches.length == 2);
    expect(batches[1].datasets, <String>{'notes'});
    await _eventually(
      () => coordinator.snapshot.phase == SyncTriggerPhase.idle,
    );
  });

  test('session generations fence active work and stale completion', () async {
    final sources = _Sources<String>();
    addTearDown(sources.close);
    final batches = <SyncTriggerBatch<String>>[];
    final cancellationReasons = <Object?>[];
    final coordinator = SyncTriggerCoordinator<String>(
      sources: sources.value,
      run: (batch, cancellation) async {
        batches.add(batch);
        if (batch.generation == 1) {
          cancellationReasons.add(await cancellation.whenCancelled);
        }
        return SyncTriggerRunDisposition.completed;
      },
      reportCrash: (error, stackTrace) => fail('$error\n$stackTrace'),
    )..start();
    addTearDown(coordinator.disposeAsync);

    sources.session.add(
      SyncTriggerIntent<String>.session(
        generation: 1,
        datasets: const <String>{'tasks'},
      ),
    );
    await _eventually(() => batches.length == 1);
    sources.session.add(SyncTriggerIntent<String>.session(generation: 2));

    await _eventually(() => cancellationReasons.isNotEmpty);
    expect(
      cancellationReasons.single,
      SyncTriggerCancellationReason.sessionChanged,
    );
    expect(coordinator.snapshot.generation, 2);
    expect(coordinator.snapshot.phase, SyncTriggerPhase.idle);

    sources.manual.add(SyncTriggerIntent<String>.work(const <String>{'notes'}));
    await _eventually(() => batches.length == 2);
    expect(batches.last.generation, 2);
  });

  test(
    'deadline cancels cooperatively and disposal removes every listener',
    () async {
      final sources = _Sources<String>();
      final reasons = <Object?>[];
      final coordinator = SyncTriggerCoordinator<String>(
        sources: sources.value,
        run: (batch, cancellation) async {
          reasons.add(await cancellation.whenCancelled);
          return SyncTriggerRunDisposition.completed;
        },
        reportCrash: (error, stackTrace) => fail('$error\n$stackTrace'),
      )..start();

      sources.scheduler.add(
        SyncTriggerIntent<String>.work(const <String>{
          'tasks',
        }, deadline: DateTime.now().add(const Duration(milliseconds: 20))),
      );
      await _eventually(() => reasons.isNotEmpty);
      expect(reasons.single, SyncTriggerCancellationReason.deadlineExceeded);
      await _eventually(
        () => coordinator.snapshot.phase == SyncTriggerPhase.idle,
      );

      await coordinator.disposeAsync();
      expect(sources.hasListeners, isFalse);
      await coordinator.disposeAsync();
      await sources.close();
    },
  );

  test('intent invariants and source authority are active', () async {
    expect(
      () => SyncTriggerIntent<String>.work(const <String>{}),
      throwsArgumentError,
    );
    expect(
      () => SyncTriggerIntent<String>.session(generation: -1),
      throwsArgumentError,
    );

    final sources = _Sources<String>();
    addTearDown(sources.close);
    final crashes = <Object>[];
    final coordinator = SyncTriggerCoordinator<String>(
      sources: sources.value,
      run: (batch, cancellation) async => SyncTriggerRunDisposition.completed,
      reportCrash: (error, _) => crashes.add(error),
    )..start();
    addTearDown(coordinator.disposeAsync);

    sources.manual.add(SyncTriggerIntent<String>.connectivity(online: false));
    await _eventually(() => crashes.isNotEmpty);
    expect(crashes.single, isA<StateError>());
    expect(coordinator.snapshot.phase, SyncTriggerPhase.blocked);
  });
}

final class _Sources<K> {
  final manual = StreamController<SyncTriggerIntent<K>>.broadcast(sync: true);
  final lifecycle = StreamController<SyncTriggerIntent<K>>.broadcast(
    sync: true,
  );
  final connectivity = StreamController<SyncTriggerIntent<K>>.broadcast(
    sync: true,
  );
  final scheduler = StreamController<SyncTriggerIntent<K>>.broadcast(
    sync: true,
  );
  final push = StreamController<SyncTriggerIntent<K>>.broadcast(sync: true);
  final session = StreamController<SyncTriggerIntent<K>>.broadcast(sync: true);

  SyncTriggerSources<K> get value => SyncTriggerSources<K>(
    manual: manual.stream,
    lifecycle: lifecycle.stream,
    connectivity: connectivity.stream,
    scheduler: scheduler.stream,
    push: push.stream,
    session: session.stream,
  );

  bool get hasListeners => <StreamController<SyncTriggerIntent<K>>>[
    manual,
    lifecycle,
    connectivity,
    scheduler,
    push,
    session,
  ].any((controller) => controller.hasListener);

  Future<void> close() async {
    for (final controller in <StreamController<SyncTriggerIntent<K>>>[
      manual,
      lifecycle,
      connectivity,
      scheduler,
      push,
      session,
    ]) {
      if (!controller.isClosed) await controller.close();
    }
  }
}

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (condition()) return;
    await _pump();
  }
  fail('Condition did not become true.');
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 1));
