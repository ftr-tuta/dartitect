import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paved_road_canary/composition/canary_factories.dart';
import 'package:paved_road_canary/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resize, touch, mouse, keyboard, and command journey', (
    tester,
  ) async {
    late StateSetter resize;
    var windowSize = const Size(500, 700);
    final repository = CanaryRepository();
    final viewModel = CanaryViewModel(repository);
    addTearDown(() async {
      await viewModel.disposeAsync();
      await repository.disposeAsync();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            resize = setState;
            return MediaQuery(
              data: MediaQueryData(size: windowSize),
              child: CanaryScreen(viewModel: viewModel),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Increment local state')));
    await mouse.down(tester.getCenter(find.text('Increment local state')));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('value 1'), findsOneWidget);

    for (var attempt = 0; attempt < 10 && !_buttonHasFocus(); attempt += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(_buttonHasFocus(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('value 2'), findsOneWidget);

    resize(() => windowSize = const Size(1000, 700));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    expect(find.text('value 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

bool _buttonHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget is FilledButton) found = true;
    return !found;
  });
  return found;
}
