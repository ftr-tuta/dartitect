import 'package:dartitect_flutter_quality_eval_fixture/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses constraints and virtualizes the 10k collection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const CatalogApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(LayoutBuilder), findsWidgets);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(Card).evaluate().length, lessThan(100));

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Item 0'), findsOneWidget);
  });
}
