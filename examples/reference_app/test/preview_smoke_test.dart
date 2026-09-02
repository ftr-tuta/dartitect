import 'package:dartitect_reference_app/src/dev/tasks_previews.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('task preview uses only synthetic values and pure callbacks', (
    tester,
  ) async {
    await tester.pumpWidget(referenceTasksPreview());

    expect(find.text('Synthetic local-first task'), findsWidgets);
    expect(find.text('Mark complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
