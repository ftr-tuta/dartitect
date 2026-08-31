import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_ui.dart';
import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paved_road_canary/composition/application_module.wiring.dartitect.g.dart';
import 'package:paved_road_canary/main.dart';

void main() {
  testDartitectUiMatrix(
    'paved-road UI quality canary',
    buildRoot: (scenario) => MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: scenario.brightness),
      home: ApplicationHost<ApplicationGraph>.create(
        create: ApplicationModule.create,
        loading: (context) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        failure: (context, failure, retry) => Scaffold(
          body: Center(
            child: TextButton(onPressed: retry, child: const Text('Retry')),
          ),
        ),
        ready: (context, graph) => CanaryApp(graph: graph),
      ),
    ),
    exercise: (tester, scenario) async {
      await tester.pumpAndSettle();
      expect(find.text('value 0'), findsOneWidget);
      final window = scenario.windowClass();
      if (window.width == DartitectSizeClass.compact) {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      } else {
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      }
      await tester.tap(find.text('Increment local state'));
      await tester.pumpAndSettle();
      expect(find.text('value 1'), findsOneWidget);
    },
  );

  testWidgets('official button is keyboard reachable and actionable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: ApplicationHost<ApplicationGraph>.create(
          create: ApplicationModule.create,
          loading: (context) => const SizedBox.shrink(),
          failure: (context, failure, retry) =>
              TextButton(onPressed: retry, child: const Text('Retry')),
          ready: (context, graph) => CanaryApp(graph: graph),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var attempt = 0; attempt < 10 && !_filledButtonHasFocus(); attempt++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(_filledButtonHasFocus(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('value 1'), findsOneWidget);
  });
}

bool _filledButtonHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget is FilledButton) found = true;
    return !found;
  });
  return found;
}
