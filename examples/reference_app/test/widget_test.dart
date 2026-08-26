import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_reference_app/app/app_runtime.dart';
import 'package:dartitect_reference_app/features/tasks/application/task_remote.dart';
import 'package:dartitect_reference_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('route renders, survives navigation, and forwards lifecycle', (
    tester,
  ) async {
    late AppRuntime runtime;
    await tester.pumpWidget(
      ReferenceApp(
        createRuntime: () async {
          runtime = await AppRuntime.create(forceMemory: true);
          return runtime;
        },
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('Dartitect Tasks').evaluate().isNotEmpty,
    );

    expect(find.text('Dartitect Tasks'), findsOneWidget);
    expect(find.text('Inspect explicit composition'), findsOneWidget);
    expect(find.text('Sync: synced'), findsWidgets);
    expect(tester.getSemantics(find.byType(MaterialApp)), isNotNull);

    await tester.tap(find.byTooltip('Open diagnostics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Runtime diagnostics'), findsOneWidget);
    expect(find.text('Store: memory'), findsOneWidget);

    runtime.tasks.remote.mode = ReferenceRemoteMode.offline;
    var toggleCompleted = false;
    final toggle = runtime.tasks
        .toggle(1)
        .whenComplete(() => toggleCompleted = true);
    await _pumpUntil(tester, () => toggleCompleted);
    await toggle;
    await tester.pump();
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sync: pending'), findsOneWidget);

    for (final state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(runtime.tasks.diagnostics.lifecycleTransitions, 2);
    expect(runtime.tasks.diagnostics.foreground, isTrue);

    await _pumpUntil(tester, () => !runtime.tasks.paged.isBusy, attempts: 100);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(find.text('Dartitect Tasks'), findsNothing);
  });

  testWidgets('forced logout removes nested routes before session drain', (
    tester,
  ) async {
    late AppRuntime runtime;
    await tester.pumpWidget(
      ReferenceApp(
        autoDrainForcedLogout: false,
        createRuntime: () async {
          runtime = await AppRuntime.create(forceMemory: true);
          return runtime;
        },
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('Dartitect Tasks').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Open diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Runtime diagnostics'), findsOneWidget);

    runtime.requestForcedLogout(expired: true);
    await tester.pump();
    expect(find.text('Runtime diagnostics'), findsNothing);
    expect(find.text('Session signed out'), findsOneWidget);
    expect(
      runtime.sessionState.value,
      isA<SessionForcedLogout<ReferenceSessionDescription>>(),
    );
    final drain = runtime.completeForcedLogout();
    await _pumpUntil(
      tester,
      () =>
          runtime.sessionState.value
              is SessionSignedOut<ReferenceSessionDescription>,
      attempts: 120,
      diagnostics: () =>
          'session=${runtime.sessionState.value.runtimeType}, '
          'sessionPhase=${runtime.tasks.diagnostics.disposePhase.name}, '
          'pagedPhase=${runtime.tasks.paged.disposePhase.name}, '
          'sourcePhase=${runtime.tasks.local.sourceLifecyclePhase.name}',
    );
    await drain;
    await tester.pump();
    expect(
      runtime.sessionState.value,
      isA<SessionSignedOut<ReferenceSessionDescription>>(),
    );
    expect(runtime.tasks.diagnostics.disposed, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 40,
  String Function()? diagnostics,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail(
    'Widget condition did not become true after $attempts pumps. '
    '${diagnostics?.call() ?? ''}',
  );
}
