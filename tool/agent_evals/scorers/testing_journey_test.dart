import 'package:dartitect_flutter_quality_eval_fixture/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('responsive keyboard journey retains state without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const CounterJourneyApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Increment counter'), findsOneWidget);

    await tester.tap(find.byTooltip('Increment counter'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(tester.getSemantics(find.byType(CounterJourneyApp)), isNotNull);
  });
}
