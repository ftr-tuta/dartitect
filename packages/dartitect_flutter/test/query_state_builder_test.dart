import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter_queries.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'query builder renders every state and resumes at current state',
    (tester) async {
      final port = _Port();
      final controller = DartitectQueryController<String, int, String>(
        initialQuery: 'all',
        port: port,
        identity: (item) => item,
      );
      var enabled = true;

      Widget tree() => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: enabled,
          child: DartitectQueryStateBuilder<String, int, String>(
            controller: controller,
            initial: (_, _) => const Text('initial'),
            loading: (_, state) => Text('loading:${state.staleItems.join()}'),
            empty: (_, _) => const Text('empty'),
            content: (_, state) => Text('content:${state.items.join()}'),
            failure: (_, state) => Text('failure:${state.failure}'),
          ),
        ),
      );

      await tester.pumpWidget(tree());
      expect(find.text('initial'), findsOneWidget);
      final first = controller.refresh();
      await tester.pump();
      expect(find.text('loading:'), findsOneWidget);
      port.complete(DartitectQueryPage<int>(items: <int>[], nextCursor: null));
      await first;
      await tester.pump();
      expect(find.text('empty'), findsOneWidget);

      final second = controller.refresh();
      await tester.pump();
      port.complete(
        DartitectQueryPage<int>(items: <int>[1, 2], nextCursor: null),
      );
      await second;
      await tester.pump();
      expect(find.text('content:12'), findsOneWidget);

      enabled = false;
      await tester.pumpWidget(tree());
      final third = controller.refresh();
      await tester.pump();
      port.fail('offline');
      await third;
      await tester.pump();
      expect(find.text('content:12'), findsOneWidget);
      enabled = true;
      await tester.pumpWidget(tree());
      expect(find.text('failure:offline'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.state, isA<DartitectQueryFailure<int, String>>());
      await controller.disposeAsync();
    },
  );
}

final class _Port implements DartitectQueryPort<String, int, String> {
  Completer<Result<DartitectQueryPage<int>, String>>? _pending;

  @override
  bool get localAuthority => false;

  @override
  Future<Result<DartitectQueryPage<int>, String>> fetch(
    String query, {
    required String? cursor,
    required CancellationSignal cancellation,
  }) {
    _pending = Completer<Result<DartitectQueryPage<int>, String>>();
    return _pending!.future;
  }

  void complete(DartitectQueryPage<int> page) {
    _pending!.complete(Ok<DartitectQueryPage<int>>(page));
  }

  void fail(String failure) {
    _pending!.complete(Err<String>(failure, StackTrace.current));
  }

  @override
  Stream<List<int>> watchLocal(String query) => const Stream.empty();
}
