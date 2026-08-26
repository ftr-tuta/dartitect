import 'dart:async';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_objectbox/dartitect_objectbox.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';

void main() {
  test('owned closes Store after observations', () async {
    final order = <String>[];
    final store = _FakeStore(order);
    final owner = await ObjectBoxStoreOwner.create(
      openStore: (_) => store,
      configure: (value, observations) {
        observations.own('watcher', (_) => order.add('watcher'));
      },
    );

    await owner.disposeAsync();
    await owner.disposeAsync();

    expect(order, <String>['watcher', 'store']);
    expect(store.closeCalls, 1);
    expect(() => owner.store, throwsStateError);
  });

  test('borrowed drains observations without closing Store', () async {
    final order = <String>[];
    final store = _FakeStore(order);
    final owner = ObjectBoxStoreOwner.value(store);
    owner.observations.own('watcher', (_) => order.add('watcher'));

    await owner.disposeAsync();

    expect(order, <String>['watcher']);
    expect(store.closeCalls, 0);
  });

  test(
    'observation owner cancels subscription and timer in LIFO order',
    () async {
      final controller = StreamController<int>();
      final timer = Timer(const Duration(days: 1), () {});
      final owner = ObjectBoxObservationOwner()
        ..ownSubscription(controller.stream.listen((_) {}))
        ..ownTimer(timer);

      await owner.disposeAsync();

      expect(timer.isActive, isFalse);
      expect(owner.isDisposed, isTrue);
      await controller.close();
    },
  );

  test('temporary open failure removes only its created directory', () async {
    String? openedPath;

    await expectLater(
      ObjectBoxStoreOwner.temporary(
        openStore: (path) {
          openedPath = path;
          throw StateError('open failed');
        },
      ),
      throwsStateError,
    );

    expect(openedPath, isNotNull);
    expect(await Directory(openedPath!).exists(), isFalse);
  });

  test(
    'checkpoint adapter uses borrowed Store transaction boundaries',
    () async {
      final values = <String, int>{};
      final store = _TransactionalFakeStore(<String>[]);
      final checkpoints = ObjectBoxSyncCheckpointStore<String, int>(
        store: store,
        readCheckpoint: (_, key) => values[key],
        writeCheckpoint: (_, key, value, fencingToken) => values[key] = value,
        removeCheckpoint: (_, key) => values.remove(key),
      );
      final cancellation = CancellationSource();

      await checkpoints.write('catalog', 7, cancellation.signal);
      expect(await checkpoints.read('catalog', cancellation.signal), 7);
      await checkpoints.remove('catalog', cancellation.signal);

      expect(values, isEmpty);
      expect(store.transactionModes, <TxMode>[
        TxMode.write,
        TxMode.read,
        TxMode.write,
      ]);
      expect(
        store.closeCalls,
        0,
        reason: 'The checkpoint adapter borrows Store.',
      );
      cancellation.dispose();
    },
  );

  test('Store watch source merges watches and keeps Store borrowed', () async {
    final store = _TransactionalFakeStore(<String>[]);
    final first = StreamController<void>.broadcast();
    final second = StreamController<void>.broadcast();
    var reads = 0;
    final source = ObjectBoxStoreWatchSource<int, _Failure>(
      store: store,
      watches: <ObjectBoxStoreWatch>[(_) => first.stream, (_) => second.stream],
      pull: (_, cancellation) async {
        cancellation.throwIfCancelled();
        return Ok<int>(++reads);
      },
    );
    final opened = await source.open();
    final session = (opened as Ok<ReactiveSourceSession<int, _Failure>>).value;
    var signals = 0;
    final subscription = session.signals.listen((_) => signals += 1);
    final cancellation = CancellationSource();

    expect(await session.read(cancellation.signal), const Ok<int>(1));
    first.add(null);
    second.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(signals, 2);

    await session.close();
    await subscription.cancel();
    await first.close();
    await second.close();
    cancellation.dispose();
    expect(store.closeCalls, 0);
  });

  test('journal appends and reads in borrowed Store transactions', () async {
    final store = _TransactionalFakeStore(<String>[]);
    final entries = <SyncJournalEntry<String>>[];
    final journal = ObjectBoxSyncRunJournal<String>(
      store: store,
      appendEntry: (_, entry) => entries.add(entry),
      readIncompleteAttempts: (_) => <IncompleteSyncAttempt<String>>[
        IncompleteSyncAttempt<String>(
          attemptId: 'attempt-1',
          startedAt: DateTime.utc(2026),
          completedDatasetKeys: const <String>['catalog'],
        ),
      ],
    );

    await journal.append(
      SyncJournalEntry<String>(
        attemptId: 'attempt-2',
        sequence: 1,
        timestamp: DateTime.utc(2026),
        fact: SyncJournalFact.attemptStarted,
      ),
    );
    final incomplete = await journal.loadIncompleteAttempts();

    expect(entries, hasLength(1));
    expect(incomplete.single.attemptId, 'attempt-1');
    expect(store.transactionModes, <TxMode>[TxMode.write, TxMode.read]);
    expect(store.closeCalls, 0);
  });
}

final class _Failure implements Exception {
  const _Failure();
}

base class _FakeStore implements Store {
  _FakeStore(this.order);

  final List<String> order;
  int closeCalls = 0;
  var _closed = false;

  @override
  void close() {
    closeCalls += 1;
    _closed = true;
    order.add('store');
  }

  @override
  bool isClosed() => _closed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TransactionalFakeStore extends _FakeStore {
  _TransactionalFakeStore(super.order);

  final List<TxMode> transactionModes = <TxMode>[];

  @override
  T runInTransaction<T>(TxMode mode, T Function() fn) {
    transactionModes.add(mode);
    return fn();
  }
}
