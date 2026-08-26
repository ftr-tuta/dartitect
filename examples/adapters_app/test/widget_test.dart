import 'package:dartitect_adapters_app/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows optional adapter boundary', (tester) async {
    await tester.pumpWidget(const AdaptersApp());
    expect(find.text('Optional adapters'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Catalog item 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
