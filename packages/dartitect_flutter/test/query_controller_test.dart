import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter_queries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'debounce, pagination, selection, bulk, and restoration compose',
    () async {
      final port = _RemotePort();
      final restoration = _Restoration()..value = 'restored';
      final controller = DartitectQueryController<String, int, _Failure>(
        initialQuery: 'initial',
        port: port,
        identity: (item) => item,
        restoration: restoration,
        debounce: Duration.zero,
      );

      await controller.start();
      expect(controller.query, 'restored');
      expect(
        (controller.state as DartitectQueryContent<int, _Failure>).items,
        <int>[1, 2],
      );
      controller.toggleSelection(1);
      await controller.loadNext();
      expect(
        (controller.state as DartitectQueryContent<int, _Failure>).items,
        <int>[1, 2, 3],
      );
      expect(controller.selection, <Object>{1});
      final selected = <int>[];
      await controller.runBulk((items, cancellation) async {
        selected.addAll(items);
        return const Ok<void>(null);
      });
      expect(selected, <int>[1]);

      controller.setQuery('next');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(restoration.value, 'next');
      await controller.disposeAsync();
    },
  );

  test('local stream remains the publication authority', () async {
    final local = StreamController<List<int>>();
    addTearDown(local.close);
    final port = _LocalPort(local);
    final controller = DartitectQueryController<String, int, _Failure>(
      initialQuery: 'all',
      port: port,
      identity: (item) => item,
    );
    final started = controller.start(restore: false);
    await Future<void>.delayed(Duration.zero);
    port.local.add(<int>[7, 8]);
    await started;
    final content = controller.state as DartitectQueryContent<int, _Failure>;
    expect(content.items, <int>[7, 8]);
    expect(content.stale, isFalse);
    await controller.disposeAsync();
  });
}

final class _Failure {
  const _Failure();
}

final class _RemotePort implements DartitectQueryPort<String, int, _Failure> {
  @override
  bool get localAuthority => false;

  @override
  Future<Result<DartitectQueryPage<int>, _Failure>> fetch(
    String query, {
    required String? cursor,
    required CancellationSignal cancellation,
  }) async => Ok<DartitectQueryPage<int>>(
    cursor == null
        ? DartitectQueryPage<int>(items: <int>[1, 2], nextCursor: 'next')
        : DartitectQueryPage<int>(items: <int>[3], nextCursor: null),
  );

  @override
  Stream<List<int>> watchLocal(String query) => const Stream<List<int>>.empty();
}

final class _LocalPort implements DartitectQueryPort<String, int, _Failure> {
  _LocalPort(this.local);

  final StreamController<List<int>> local;

  @override
  bool get localAuthority => true;

  @override
  Future<Result<DartitectQueryPage<int>, _Failure>> fetch(
    String query, {
    required String? cursor,
    required CancellationSignal cancellation,
  }) async => Ok<DartitectQueryPage<int>>(
    DartitectQueryPage<int>(items: <int>[999], nextCursor: null),
  );

  @override
  Stream<List<int>> watchLocal(String query) => local.stream;
}

final class _Restoration implements DartitectQueryRestorationStore<String> {
  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String query) async => value = query;
}
