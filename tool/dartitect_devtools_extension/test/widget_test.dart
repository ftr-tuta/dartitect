import 'package:flutter_test/flutter_test.dart';

import 'package:dartitect_devtools_extension_web/main.dart';

void main() {
  testWidgets('inspector surface exposes no mutation actions', (tester) async {
    await tester.pumpWidget(const DartitectReadOnlyInspector());
    expect(find.text('Dartitect diagnostics'), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
    expect(find.textContaining('Cancel'), findsNothing);
    expect(find.textContaining('Clear'), findsNothing);
  });
}
