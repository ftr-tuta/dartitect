import 'dart:ui';

import 'package:dartitect_reference_app/app/app_runtime.dart';
import 'package:dartitect_reference_app/app/reference_app.dart';
import 'package:dartitect_reference_app/composition/application_module.wiring.dartitect.g.dart';
import 'package:dartitect_reference_app/composition/reference_factories.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_first_task_session.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/memory_offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/reference_task_remote.dart';
import 'package:dartitect_reference_app/features/tasks/presentation/tasks_page.dart';
import 'package:dartitect_reference_app/features/tasks/presentation/tasks_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '10k local-first resize, keyboard, mouse, touch, and reconnect journey',
    (tester) async {
      final repository = await LocalFirstTaskRepository.create(
        store: MemoryOfflineTaskStore(),
        remote: ReferenceTaskRemote(),
      );
      final viewModel = TasksViewModel(repository);
      addTearDown(() async {
        await viewModel.disposeAsync();
        await repository.disposeAsync();
      });
      late StateSetter resize;
      var width = 500.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                resize = setState;
                return SizedBox(
                  width: width,
                  height: 700,
                  child: TasksPage(viewModel: viewModel),
                );
              },
            ),
          ),
        ),
      );
      viewModel.start();
      await _pumpUntil(
        tester,
        () => find.text('Inspect explicit composition').evaluate().isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey<String>('compact-layout')),
        findsOneWidget,
      );
      expect(repository.paged.collection.length.value, lessThan(100));

      await tester.tap(find.byTooltip('Select Inspect explicit composition'));
      await tester.pump();
      expect(find.text('Mark complete'), findsOneWidget);

      await tester.tap(find.text('Airplane mode'));
      await tester.pumpAndSettle();
      expect(viewModel.isOffline, isTrue);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final toggle = find.text('Mark complete');
      await mouse.moveTo(tester.getCenter(toggle));
      await mouse.down(tester.getCenter(toggle));
      await mouse.up();
      await _pumpUntil(
        tester,
        () => find.text('Mark incomplete').evaluate().isNotEmpty,
      );
      expect((await repository.store.findTask(1))?.completed, isTrue);

      final search = find.byKey(const ValueKey<String>('tasks-search'));
      await tester.tap(search);
      await tester.enterText(search, 'Field task 09999');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _pumpUntil(
        tester,
        () => find.text('Field task 09999').evaluate().isNotEmpty,
      );
      expect(viewModel.query, 'Field task 09999');
      expect(viewModel.tasks.collection.keys.value, <int>[9999]);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      resize(() => width = 1100);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('expanded-layout')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(search).controller!.text,
        'Field task 09999',
      );

      await tester.tap(find.text('Airplane mode'));
      await tester.pumpAndSettle();
      expect(viewModel.isOffline, isFalse);
      expect(repository.remote.diagnostics.appliedDeliveries, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('forced logout removes routes before repository drain', (
    tester,
  ) async {
    final runtime = await AppRuntime.create(forceMemory: true);
    addTearDown(runtime.disposeAsync);
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

    runtime.requestForcedLogout(expired: true);
    await tester.pump();
    expect(find.text('Dartitect Tasks'), findsNothing);
    expect(find.text('Session signed out'), findsOneWidget);
    await runtime.completeForcedLogout();
    await tester.pump();
    expect(runtime.tasks.diagnostics.disposed, isTrue);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 100,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail('Integration condition did not become true.');
}
