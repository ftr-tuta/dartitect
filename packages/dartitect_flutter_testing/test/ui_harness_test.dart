import 'package:dartitect_flutter/dartitect_flutter_ui.dart';
import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('standard matrix is paired, bounded, and spans all size classes', () {
    final scenarios = DartitectUiMatrix.standard.scenarios;

    expect(scenarios, hasLength(5));
    expect(scenarios.map((scenario) => scenario.size), const <Size>[
      Size(360, 640),
      Size(430, 932),
      Size(768, 1024),
      Size(1024, 768),
      Size(1440, 900),
    ]);
    expect(
      scenarios.map((scenario) => scenario.windowClass().width).toSet(),
      DartitectSizeClass.values.toSet(),
    );
    expect(
      scenarios.map((scenario) => scenario.textScaleFactor).toSet(),
      <double>{1, 2},
    );
    expect(
      scenarios.map((scenario) => scenario.textDirection).toSet(),
      TextDirection.values.toSet(),
    );
    expect(
      scenarios.map((scenario) => scenario.brightness).toSet(),
      Brightness.values.toSet(),
    );
  });

  testWidgets('harness restores platform and view even when the root fails', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    final scenario = DartitectUiMatrix.standard.scenarios.first;

    await expectLater(
      () =>
          const DartitectUiHarness(
            accessibilityPolicy: DartitectAccessibilityPolicy(
              requireLabels: false,
              requireTextContrast: false,
              requireMinimumTapTargets: false,
            ),
          ).run(
            tester,
            scenario: scenario,
            buildRoot: (_) => Builder(
              builder: (_) => throw StateError('consumer root failed'),
            ),
          ),
      throwsA(isA<TestFailure>()),
    );

    expect(debugDefaultTargetPlatformOverride, originalPlatform);
    expect(tester.view.physicalSize, isNot(scenario.size));
  });

  testDartitectUiMatrix(
    'official Material control passes the standard accessibility matrix',
    buildRoot: (scenario) => MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: scenario.brightness),
      home: Scaffold(
        body: Center(
          child: FilledButton(onPressed: () {}, child: const Text('Continue')),
        ),
      ),
    ),
  );
}
