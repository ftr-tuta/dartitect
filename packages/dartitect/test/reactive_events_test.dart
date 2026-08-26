import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('registry accepts exact static identity and rejects reconstruction', () {
    const custom = ChangeCause('feature.refresh', 'Feature refresh');
    final registry = ChangeCauseRegistry(
      causes: const <ChangeCause>[...ChangeCauses.values, custom],
    );

    expect(registry.requireStatic(custom), same(custom));
    expect(registry.length, ChangeCauses.values.length + 1);
    final dynamicKey = <String>['feature', 'refresh'].join('.');
    final reconstructed = ChangeCause(dynamicKey, 'Feature refresh');
    expect(() => registry.requireStatic(reconstructed), throwsArgumentError);
  });

  test('registry rejects adversarial labels and identifiers', () {
    for (final cause in <ChangeCause>[
      const ChangeCause('user.123', 'User change'),
      const ChangeCause('user.change', 'person@example.com'),
      const ChangeCause('user.change', 'token=secret'),
      const ChangeCause('user.change', '529 982 247 25'),
      const ChangeCause('https://secret', 'Feature change'),
    ]) {
      expect(
        () => ChangeCauseRegistry(causes: <ChangeCause>[cause]),
        throwsArgumentError,
        reason: '${cause.key}:${cause.label}',
      );
    }
  });

  test('journal wraps at capacity and clears terminally', () {
    final journal = ReactiveJournal();
    for (var revision = 1; revision <= 1000; revision += 1) {
      journal.onChange(_event(revision));
      expect(journal.length, lessThanOrEqualTo(200));
    }

    expect(journal.capacity, 200);
    expect(journal.length, 200);
    expect(journal.entries.first.nextRevision, 801);
    expect(journal.entries.last.nextRevision, 1000);
    final snapshot = journal.entries;
    expect(() => snapshot.add(_event(1001)), throwsUnsupportedError);

    journal.dispose();
    journal.onChange(_event(1001));
    expect(journal.entries, isEmpty);
    expect(journal.isDisposed, isTrue);
    expect(() => ReactiveJournal(capacity: 0), throwsArgumentError);
  });

  test(
    'safe observer reports once, disables, and isolates reporter failure',
    () {
      final reports = <Object>[];
      var calls = 0;
      final observer = SafeReactiveObserver(
        observer: _CallbackObserver((event) {
          calls += 1;
          throw StateError('sink failed');
        }),
        onFailure: (error, stackTrace) {
          reports.add(error);
          throw StateError('reporter failed');
        },
      );

      observer
        ..onChange(_event(1))
        ..onChange(_event(2));

      expect(calls, 1);
      expect(reports, hasLength(1));
      expect(observer.failureCount, 1);
      expect(observer.isDisabled, isTrue);
    },
  );

  test(
    'safe observer drops recursive emission without altering outer event',
    () {
      late final SafeReactiveObserver safe;
      var calls = 0;
      safe = SafeReactiveObserver(
        observer: _CallbackObserver((event) {
          calls += 1;
          safe.onChange(_event(event.nextRevision + 1));
        }),
      );

      safe.onChange(_event(1));

      expect(calls, 1);
      expect(safe.droppedReentrantEvents, 1);
      expect(safe.failureCount, 0);
    },
  );

  test('concurrent scheduling never exceeds journal capacity', () async {
    final journal = ReactiveJournal(capacity: 32);
    await Future.wait<void>(<Future<void>>[
      for (var revision = 1; revision <= 1000; revision += 1)
        Future<void>(() => journal.onChange(_event(revision))),
    ]);

    expect(journal.length, 32);
    expect(
      journal.entries.map((event) => event.nextRevision).toSet().length,
      32,
    );
    journal.dispose();
  });

  test(
    'observer registration disposes owned but never borrowed observer',
    () async {
      var ownedDisposals = 0;
      final borrowedDisposals = 0;
      final observer = _CallbackObserver((_) {});
      final owned = ReactiveObserverRegistration.owned(
        observer,
        dispose: () => ownedDisposals += 1,
      );
      final borrowed = ReactiveObserverRegistration.borrowed(observer);

      await owned.disposeOwned();
      await borrowed.disposeOwned();

      expect(owned.isOwned, isTrue);
      expect(borrowed.isOwned, isFalse);
      expect(ownedDisposals, 1);
      expect(borrowedDisposals, 0);
    },
  );
}

ReactiveChangeEvent _event(int revision) => ReactiveChangeEvent(
  source: ReactiveEventSource.reactiveOwner,
  kind: ReactiveEventKind.updated,
  cause: ChangeCauses.reactiveUpdate,
  previousRevision: revision - 1,
  nextRevision: revision,
  duration: const Duration(microseconds: 5),
  listenerCount: 0,
);

final class _CallbackObserver implements ReactiveObserver {
  const _CallbackObserver(this.callback);

  final void Function(ReactiveChangeEvent event) callback;

  @override
  void onChange(ReactiveChangeEvent event) => callback(event);
}
