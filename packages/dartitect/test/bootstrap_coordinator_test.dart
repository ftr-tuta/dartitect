import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test(
    'named stages commit one graph and publish monotonic progress',
    () async {
      final progress = BoundedProgressReporter<BootstrapProgress>();
      final releases = <String>[];
      final coordinator = BootstrapCoordinator<String>(
        stages: <BootstrapStage>[
          BootstrapStage(
            name: 'database',
            run: (transaction, context) {
              transaction.own('db', releases.add);
            },
          ),
          BootstrapStage(name: 'settings', run: (_, _) {}),
        ],
        buildRoot: (_, _) => 'application',
        progress: progress,
      );

      final attempt = await coordinator.run() as BootstrapSucceeded<String>;
      expect(attempt.graph.root, 'application');
      expect(attempt.report.completedStages, <String>['database', 'settings']);
      expect(progress.events.map((event) => event.sequence), <int>[1, 2, 3, 4]);
      await attempt.graph.disposeAsync();
      expect(releases, <String>['db']);
      await coordinator.disposeAsync();
    },
  );

  test('failure rolls resources back and returns original stack', () async {
    final releases = <String>[];
    final coordinator = BootstrapCoordinator<String>(
      stages: <BootstrapStage>[
        BootstrapStage(
          name: 'database',
          run: (transaction, _) {
            transaction.own('db', releases.add);
          },
        ),
        BootstrapStage(
          name: 'config',
          run: (_, _) => throw StateError('failed'),
        ),
      ],
      buildRoot: (_, _) => 'never',
    );

    final attempt = await coordinator.run() as BootstrapFailed<String>;
    expect(attempt.kind, BootstrapFailureKind.construction);
    expect(attempt.report.failedStage, 'config');
    expect(attempt.error, isA<StateError>());
    expect(attempt.stackTrace, isNot(StackTrace.empty));
    expect(releases, <String>['db']);
    await coordinator.disposeAsync();
  });

  test('disposal cancels and drains an active attempt', () async {
    final entered = Completer<void>();
    final coordinator = BootstrapCoordinator<String>(
      stages: <BootstrapStage>[
        BootstrapStage(
          name: 'wait',
          run: (_, context) async {
            entered.complete();
            await context.cancellation.whenCancelled;
            context.cancellation.throwIfCancelled();
          },
        ),
      ],
      buildRoot: (_, _) => 'never',
    );
    final attempt = coordinator.run();
    await entered.future;
    await coordinator.disposeAsync();
    expect(
      (await attempt as BootstrapFailed<String>).kind,
      BootstrapFailureKind.cancelled,
    );
  });
}
