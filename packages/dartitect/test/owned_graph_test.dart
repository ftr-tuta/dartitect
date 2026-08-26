import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('transaction rolls back owned resources in LIFO order', () async {
    final timeline = <String>[];

    await expectLater(
      ResourceTransaction.create<void>((transaction) {
        transaction
          ..own(1, (_) => timeline.add('first'), label: 'first')
          ..borrow(Object())
          ..own(2, (_) => timeline.add('second'), label: 'second');
        throw StateError('create failed');
      }),
      throwsA(isA<StateError>()),
    );

    expect(timeline, <String>['second', 'first']);
  });

  test('committed graph drains admitted work before LIFO teardown', () async {
    final timeline = <String>[];
    final gate = Completer<void>();
    final graph = await ResourceTransaction.create<String>((transaction) {
      transaction.own('provider', (_) => timeline.add('provider'));
      transaction.own('dependent', (_) => timeline.add('dependent'));
      return 'root';
    });

    final work = graph.use((root) async {
      timeline.add('$root-start');
      await gate.future;
      timeline.add('$root-end');
    });
    final disposal = graph.disposeAsync();
    await Future<void>.delayed(Duration.zero);
    expect(graph.isAccepting, isFalse);
    expect(timeline, <String>['root-start']);
    gate.complete();
    await Future.wait<void>(<Future<void>>[work, disposal]);

    expect(timeline, <String>[
      'root-start',
      'root-end',
      'dependent',
      'provider',
    ]);
    expect(graph.activeOperationCount, 0);
  });

  test(
    'slot keeps old graph after failed create and swaps atomically',
    () async {
      final slot = OwnedRuntimeSlot<String>();
      await slot.replace((_) => 'one');

      await expectLater(
        slot.replace((_) => throw StateError('broken')),
        throwsA(isA<StateError>()),
      );
      expect(await slot.use((root) => root), 'one');

      await slot.replace((_) => 'two');
      expect(slot.generation, 2);
      expect(await slot.use((root) => root), 'two');
      await slot.disposeAsync();
    },
  );

  test('resource snapshot has value semantics without owning a source', () {
    final observedAt = DateTime.utc(2026, 8, 24);
    final first = ResourceSnapshot<List<int>, String>(
      value: const <int>[1],
      metadata: 'local',
      revision: 7,
      observedAt: observedAt,
      isStale: false,
    );
    final equal = ResourceSnapshot<List<int>, String>(
      value: first.value,
      metadata: 'local',
      revision: 7,
      observedAt: observedAt,
      isStale: false,
    );

    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
  });
}
