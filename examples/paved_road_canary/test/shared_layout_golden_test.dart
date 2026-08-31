import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paved_road_canary/presentation/ui_quality_shell.dart';

void main() {
  const layouts = <String, Size>{
    'compact': Size(360, 640),
    'medium': Size(768, 1024),
    'expanded': Size(1440, 900),
  };

  for (final entry in layouts.entries) {
    testWidgets('shared ${entry.key} layout golden', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = entry.value;
      addTearDown(() {
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const CanaryUiShell(
            body: Center(child: Text('Shared responsive layout')),
          ),
        ),
      );

      await expectLater(
        find.byType(CanaryUiShell),
        matchesGoldenFile('goldens/shared_${entry.key}.png'),
      );
    }, tags: const <String>['golden']);
  }
}
