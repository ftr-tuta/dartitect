import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  group('1.0 lifecycle contract matrix', () {
    const lifetimes = <String>[
      'application',
      'session',
      'feature',
      'route',
      'operation',
      'isolate',
    ];

    for (final lifetime in lifetimes) {
      test('$lifetime is an independently disposable graph', () async {
        final resource = _TrackedResource();
        final graph = await ResourceTransaction.create<String>((transaction) {
          transaction.own(
            resource,
            (value) => value.close(),
            label: '$lifetime-resource',
          );
          return lifetime;
        }, label: '$lifetime-contract');

        expect(await graph.use((root) => root), lifetime);
        await graph.disposeAsync();

        expect(resource.closeCalls, 1);
        expect(graph.activeOperationCount, 0);
        expect(graph.isDisposed, isTrue);
        await expectLater(graph.use((_) {}), throwsStateError);
      });
    }

    test('nested lifetimes dispose child scopes before parents', () async {
      final releases = <String>[];
      final application = ResourceOwner(label: 'application');
      application.own(
        'application',
        releases.add,
        label: 'application-resource',
      );

      var parent = application;
      for (final lifetime in const <String>[
        'session',
        'feature',
        'route',
        'operation',
      ]) {
        final child = ResourceOwner(label: lifetime);
        parent.own(
          child,
          (owner) => owner.disposeAsync(),
          label: '$lifetime-owner',
        );
        child.own(lifetime, releases.add, label: '$lifetime-resource');
        parent = child;
      }

      await application.disposeAsync();

      expect(releases, const <String>[
        'operation',
        'route',
        'feature',
        'session',
        'application',
      ]);
    });

    test(
      'commit transfers owned resources and excludes borrowed values',
      () async {
        final owned = _TrackedResource();
        final borrowed = _TrackedResource();
        final transaction = ResourceTransaction(label: 'transfer-contract');
        transaction
          ..own(owned, (value) => value.close(), label: 'owned')
          ..borrow(borrowed);

        final graph = transaction.commit('root');

        expect(transaction.isTerminal, isTrue);
        expect(() => transaction.borrow(Object()), throwsStateError);
        expect(() => transaction.commit('second'), throwsStateError);
        await graph.disposeAsync();
        expect(owned.closeCalls, 1);
        expect(borrowed.closeCalls, 0);
      },
    );

    test('runtime slot assumes ownership of a complete graph', () async {
      final resource = _TrackedResource();
      final graph = await ResourceTransaction.create<String>((transaction) {
        transaction.own(
          resource,
          (value) => value.close(),
          label: 'slot-resource',
        );
        return 'root';
      });
      final slot = OwnedRuntimeSlot<String>();

      await slot.replaceGraph(() => graph);
      await slot.disposeAsync();
      await graph.disposeAsync();

      expect(resource.closeCalls, 1);
      expect(graph.isDisposed, isTrue);
    });

    test(
      'durability controls data cleanup independently from handles',
      () async {
        final durability = _DurabilityFixture();
        final graph = await ResourceTransaction.create<void>((transaction) {
          transaction
            ..own(
              durability.ephemeralHandle,
              (handle) => handle.close(),
              label: 'ephemeral-handle',
            )
            ..own(
              durability.temporaryData,
              (data) => data.remove(),
              label: 'temporary-data',
            )
            ..own(
              durability.persistedHandle,
              (handle) => handle.close(),
              label: 'persisted-handle',
            );
        });

        await graph.disposeAsync();

        expect(durability.ephemeralHandle.isOpen, isFalse);
        expect(durability.temporaryData.exists, isFalse);
        expect(durability.persistedHandle.isOpen, isFalse);
        expect(durability.persistedDataExists, isTrue);
      },
    );
  });
}

final class _TrackedResource {
  int closeCalls = 0;

  void close() => closeCalls += 1;
}

final class _DurabilityFixture {
  final ephemeralHandle = _Handle();
  final temporaryData = _TemporaryData();
  final persistedHandle = _Handle();
  final bool persistedDataExists = true;
}

final class _Handle {
  bool isOpen = true;

  void close() => isOpen = false;
}

final class _TemporaryData {
  bool exists = true;

  void remove() => exists = false;
}
