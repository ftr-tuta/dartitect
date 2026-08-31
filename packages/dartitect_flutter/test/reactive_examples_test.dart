@TestOn('vm')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reactive_example_web.dart'
    if (dart.library.io) 'reactive_example_vm.dart';

void main() {
  testWidgets('headless offline-first example renders and tears down', (
    tester,
  ) async {
    await tester.pumpWidget(const HeadlessOfflineFirstTasksExample());
    await _pumpUntilFound(tester, find.text('Inspect field'));
    expect(find.text('Sync inventory'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Example did not render expected local data.');
}
