library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_first_task_session.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/domain/task_repository.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/memory_offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/reference_task_remote.dart';
import 'package:dartitect_reference_app/features/tasks/presentation/tasks_page.dart';
import 'package:dartitect_reference_app/features/tasks/presentation/tasks_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

part 'support/flutter_quality_probe.dart';

void main() {
  testWidgets(
    'records virtualized workload, resize, cancellation, and cleanup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = await LocalFirstTaskRepository.create(
        store: MemoryOfflineTaskStore(),
        remote: ReferenceTaskRemote(),
      );
      final viewModel = TasksViewModel(repository);
      final probe = _FlutterQualityProbe()..attach(tester.binding);
      var ownerDisposed = false;
      var viewModelDisposed = false;
      var repositoryDisposed = false;
      void detectLatePublication() {
        if (ownerDisposed) probe.recordLatePublication();
      }

      viewModel.addListener(detectLatePublication);
      addTearDown(() async {
        probe.detach();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        ownerDisposed = true;
        if (!viewModelDisposed) await viewModel.disposeAsync();
        if (!repositoryDisposed) await repository.disposeAsync();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: _RebuildProbe(
            onBuild: probe.recordRebuild,
            child: TasksPage(viewModel: viewModel),
          ),
        ),
      );
      viewModel.start();
      await _pumpUntil(
        tester,
        () => find.text('Inspect explicit composition').evaluate().isNotEmpty,
      );
      probe.markUsefulState();

      final rowsBeforeScroll = find.byType(TaskRow).evaluate().length;
      probe.recordMaterializedRows(rows: rowsBeforeScroll, totalRows: 10000);
      expect(rowsBeforeScroll, lessThan(100));
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
      final searchFinder = find.byKey(const ValueKey<String>('tasks-search'));
      await tester.tap(searchFinder);
      await tester.enterText(searchFinder, 'retained query');
      final search = tester.widget<TextField>(searchFinder);
      expect(search.focusNode!.hasFocus, isTrue);

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pump();
      final statePreserved =
          find
                  .byKey(const ValueKey<String>('expanded-layout'))
                  .evaluate()
                  .length ==
              1 &&
          tester.widget<TextField>(searchFinder).controller!.text ==
              'retained query' &&
          search.focusNode!.hasFocus &&
          scroll.offset == retainedOffset &&
          find.text('Mark complete').evaluate().length == 1;
      probe.recordStatePreserved(statePreserved);
      expect(statePreserved, isTrue);

      final stale = viewModel.searchCommand.execute('slow');
      final current = viewModel.searchCommand.execute('Field task 09999');
      probe.recordQueueDepth(viewModel.searchCommand.laneQueuedCount);
      Object? staleResult;
      Object? currentResult;
      unawaited(stale.then<void>((value) => staleResult = value));
      unawaited(current.then<void>((value) => currentResult = value));
      await _pumpUntil(
        tester,
        () => staleResult != null && currentResult != null,
      );
      expect(
        staleResult,
        isA<
          CommandExecutionCancelled<PageWriteReceipt<TaskCursor>, TaskFailure>
        >(),
      );
      probe.recordCancellation();
      expect(
        currentResult,
        isA<
          CommandExecutionSucceeded<PageWriteReceipt<TaskCursor>, TaskFailure>
        >(),
      );
      await _pumpUntil(
        tester,
        () => find.text('Field task 09999').evaluate().isNotEmpty,
      );
      probe.markFirstSearchResult();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      ownerDisposed = true;
      await viewModel.disposeAsync();
      viewModelDisposed = true;
      probe.recordDisposal();
      await repository.disposeAsync();
      repositoryDisposed = true;
      probe.recordDisposal();
      final diagnostics = repository.diagnosticsSnapshot();
      probe.recordResourceCensus(
        subscriptions: viewModel.forwardedListenerCount,
        watchers: diagnostics.activeWatchers + diagnostics.activeQueries,
        timers:
            viewModel.tasks.activeTimerCount +
            viewModel.tasks.observationWaiterCount,
        workers: diagnostics.activeWorkers,
      );

      final evidence = probe.finish();
      expect(evidence.firstFrameMicros, isNotNull);
      expect(evidence.usefulStateMicros, isNotNull);
      expect(evidence.firstSearchResultMicros, isNotNull);
      expect(evidence.materializedRows, lessThan(100));
      expect(evidence.cancellations, 1);
      expect(evidence.disposals, 2);
      expect(evidence.structuralFailures, isEmpty);
    },
  );
}

final class _RebuildProbe extends StatelessWidget {
  const _RebuildProbe({required this.onBuild, required this.child});

  final VoidCallback onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return child;
  }
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
  fail('Widget condition did not become true after $attempts pumps.');
}
