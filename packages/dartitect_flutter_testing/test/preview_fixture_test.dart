import 'package:dartitect_flutter_testing/src/dev/preview_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preview fixture is synthetic and callback-only', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewTaskTile(
            data: const PreviewTaskViewData(
              title: 'Synthetic fixture',
              completed: false,
            ),
            onToggle: () => toggles++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(toggles, 1);
    expect(find.text('Synthetic fixture'), findsOneWidget);
  });
}
