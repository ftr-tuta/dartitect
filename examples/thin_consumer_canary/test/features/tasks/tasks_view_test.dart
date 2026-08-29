import 'package:thin_consumer_canary/features/tasks/presentation/tasks_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page owns its ViewModel and renders local data', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TasksPage(),
      ),
    );
    await tester.pump();
    expect(find.text('First Tasks'), findsOneWidget);
  });
}
