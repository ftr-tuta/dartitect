import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('application host loads, retries, publishes, and tears down', (
    tester,
  ) async {
    var attempts = 0;
    var disposed = 0;
    final coordinator = BootstrapCoordinator<String>(
      stages: <BootstrapStage>[
        BootstrapStage(
          name: 'boot',
          run: (_, _) {
            attempts += 1;
            if (attempts == 1) throw StateError('first attempt');
          },
        ),
      ],
      buildRoot: (transaction, _) {
        transaction.own('runtime', (_) => disposed += 1);
        return 'runtime';
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ApplicationHost<String>.value(
          value: coordinator,
          loading: (_) => const Text('loading'),
          failure: (_, _, retry) =>
              GestureDetector(onTap: retry, child: const Text('retry')),
          ready: (_, runtime) => Text(runtime),
        ),
      ),
    );
    expect(find.text('loading'), findsOneWidget);
    await tester.pump();
    expect(find.text('retry'), findsOneWidget);
    await tester.tap(find.text('retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('runtime'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(disposed, 1);
    await coordinator.disposeAsync();
  });
}
