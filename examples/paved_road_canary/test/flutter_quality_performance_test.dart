library;

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paved_road_canary/composition/canary_factories.dart';
import 'package:paved_road_canary/main.dart';

part 'support/flutter_quality_probe.dart';

void main() {
  testWidgets('records payload-free structural and informative evidence', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = CanaryRepository();
    final viewModel = CanaryViewModel(repository);
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

    Widget workload(Size size) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: _RebuildProbe(
          onBuild: probe.recordRebuild,
          child: CanaryScreen(viewModel: viewModel),
        ),
      ),
    );
    await tester.pumpWidget(workload(const Size(360, 700)));
    await tester.pumpAndSettle();
    probe.markUsefulState();

    expect(find.text('value 0'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.tap(find.text('Increment local state'));
    await tester.pumpAndSettle();
    probe.recordQueueDepth(viewModel.incrementCommand.laneQueuedCount);
    expect(find.text('value 1'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpWidget(workload(const Size(1000, 700)));
    await tester.pumpAndSettle();
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    final statePreserved =
        rail.selectedIndex == 1 && find.text('value 1').evaluate().length == 1;
    probe.recordStatePreserved(statePreserved);
    expect(statePreserved, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    ownerDisposed = true;
    await viewModel.disposeAsync();
    viewModelDisposed = true;
    probe.recordDisposal();
    await repository.disposeAsync();
    repositoryDisposed = true;
    probe.recordDisposal();
    probe.recordResourceCensus(
      subscriptions: viewModel.forwardedListenerCount,
      watchers: 0,
      timers: 0,
      workers: 0,
    );

    final evidence = probe.finish();
    expect(evidence.firstFrameMicros, isNotNull);
    expect(evidence.usefulStateMicros, isNotNull);
    expect(evidence.rebuilds, greaterThan(0));
    expect(evidence.disposals, 2);
    expect(evidence.structuralFailures, isEmpty);
    expect(
      evidence.toJson()['informative'],
      containsPair('rssDeltaBytes', isA<int>()),
    );
  });
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
