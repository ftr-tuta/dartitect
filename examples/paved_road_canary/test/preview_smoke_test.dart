import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paved_road_canary/src/dev/ui_quality_previews.dart';

void main() {
  testWidgets('preview is synthetic and covers exhaustive command states', (
    tester,
  ) async {
    await tester.pumpWidget(pavedRoadQualityPreview());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Command idle'), findsOneWidget);
    expect(find.text('Command running'), findsOneWidget);
    expect(find.text('Command success'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Unexpected crash'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Expected failure'), findsOneWidget);
    expect(find.text('Command cancelled'), findsOneWidget);
    expect(find.text('Unexpected crash'), findsOneWidget);
  });
}
