import 'package:flutter_test/flutter_test.dart';
import 'package:thin_consumer_canary/src/dev/tasks_preview.dart';

void main() {
  testWidgets('dev-only task preview uses immutable synthetic values', (
    tester,
  ) async {
    await tester.pumpWidget(thinConsumerTasksPreview());

    expect(find.text('Synthetic preview task'), findsOneWidget);
    expect(find.text('Status: open'), findsOneWidget);
  });
}
