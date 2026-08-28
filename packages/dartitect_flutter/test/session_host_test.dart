import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'controller keeps old runtime until route removal is confirmed',
    () async {
      final controller = SessionRuntimeController<String, _Session>();
      final disposals = <String>[];
      await controller.signIn(const _Session('one'), (transaction) {
        transaction.own('one', disposals.add);
        return 'one';
      });
      final replacing = controller.replace(const _Session('two'), (
        transaction,
      ) {
        transaction.own('two', disposals.add);
        return 'two';
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<SessionTransitioning<_Session>>());
      expect(disposals, isEmpty);
      final removalId = controller.pendingRouteRemovalId!;
      expect(controller.confirmRoutesRemoved(removalId + 1), isFalse);
      expect(controller.confirmRoutesRemoved(removalId), isTrue);
      expect(await replacing, 2);
      expect(disposals, <String>['one']);
      expect(controller.current, 'two');
      await controller.disposeAsync();
      expect(disposals, <String>['one', 'two']);
    },
  );

  testWidgets('session host confirms removal only after router callback', (
    tester,
  ) async {
    final controller = SessionRuntimeController<String, _Session>();
    final routesRemoved = Completer<void>();
    var disposed = false;

    Widget host() => Directionality(
      textDirection: TextDirection.ltr,
      child: SessionHost<String, _Session>.value(
        value: controller,
        removeRoutes: (_) => routesRemoved.future,
        anonymous: (_) => const Text('anonymous'),
        transitioning: (_, _) => const Text('transition'),
        active: (_, runtime, _) => Text(runtime),
      ),
    );

    await tester.pumpWidget(host());
    await controller.signIn(const _Session('one'), (transaction) {
      transaction.own('one', (_) => disposed = true);
      return 'one';
    });
    await tester.pump();
    expect(find.text('one'), findsOneWidget);
    final logout = controller.forceLogout(expired: true);
    while (controller.pendingRouteRemovalId == null) {
      await tester.pump();
    }
    await tester.pump();
    expect(find.text('transition'), findsOneWidget);
    expect(disposed, isFalse);
    routesRemoved.complete();
    await logout;
    await tester.pump();
    expect(disposed, isTrue);
    expect(find.text('anonymous'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await controller.disposeAsync();
  });
}

final class _Session {
  const _Session(this.name);

  final String name;
}
