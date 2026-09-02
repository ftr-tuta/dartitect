import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_reference_app/app/app_runtime.dart';
import 'package:dartitect_reference_app/app/reference_app.dart';
import 'package:dartitect_reference_app/composition/application_module.wiring.dartitect.g.dart';
import 'package:dartitect_reference_app/composition/reference_factories.dart';
import 'package:dartitect_reference_app/features/tasks/application/task_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('route renders, survives navigation, and forwards lifecycle', (
    tester,
  ) async {
    late AppRuntime runtime;
    await tester.runAsync(() async {
      runtime = await AppRuntime.create(forceMemory: true);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(runtime.disposeAsync());
    });
    await tester.pumpWidget(
      ReferenceApp(
        graph: ApplicationGraph(
          referenceRuntime: runtime,
          referenceTransport: const ReferenceTransport(),
        ),
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
    expect((await runtime.tasks.store.findTask(1))!.syncState.name, 'pending');
    await tester.pump();
    await tester.pageBack();
    await tester.pump();
    expect(find.textContaining('Sync:'), findsWidgets);

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
    await tester.runAsync(() async {
      runtime = await AppRuntime.create(forceMemory: true);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(runtime.disposeAsync());
    });
    await tester.pumpWidget(
      ReferenceApp(
        autoDrainForcedLogout: false,
        graph: ApplicationGraph(
          referenceRuntime: runtime,
          referenceTransport: const ReferenceTransport(),
        ),
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
    await tester.runAsync(runtime.completeForcedLogout);
    await tester.pump();
    expect(
      runtime.sessionState.value,
      isA<SessionSignedOut<ReferenceSessionDescription>>(),
    );
    expect(runtime.tasks.diagnostics.disposed, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'responsive branches preserve query, selection, scroll, and focus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late AppRuntime runtime;
      await tester.runAsync(() async {
        runtime = await AppRuntime.create(forceMemory: true);
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        unawaited(runtime.disposeAsync());
      });
      await tester.pumpWidget(
        ReferenceApp(
          graph: ApplicationGraph(
            referenceRuntime: runtime,
            referenceTransport: const ReferenceTransport(),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Inspect explicit composition').evaluate().isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey<String>('compact-layout')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Select Inspect explicit composition'));
      await tester.pump();
      final listFinder = find.byKey(const PageStorageKey<String>('tasks-list'));
      final scroll = tester.widget<ListView>(listFinder).controller!;
      scroll.jumpTo(240);
      await tester.pump();
      final retainedOffset = scroll.offset;
      await tester.tap(find.byKey(const ValueKey<String>('tasks-search')));
      await tester.enterText(
        find.byKey(const ValueKey<String>('tasks-search')),
        'retained query',
      );
      final search = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('tasks-search')),
      );
      expect(search.focusNode!.hasFocus, isTrue);

      await tester.binding.setSurfaceSize(const Size(800, 900));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('medium-layout')),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('expanded-layout')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('tasks-search')),
            )
            .controller!
            .text,
        'retained query',
      );
      expect(search.focusNode!.hasFocus, isTrue);
      expect(scroll.offset, retainedOffset);
      expect(find.text('Mark complete'), findsOneWidget);
      await _pumpUntil(
        tester,
        () => !runtime.tasks.paged.isBusy,
        attempts: 100,
      );
    },
  );
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
