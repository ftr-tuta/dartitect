import 'package:thin_consumer_canary/features/tasks/presentation/tasks_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/features/tasks/memory_tasks_repository.dart';

void main() {
  testWidgets('page owns its ViewModel and renders local data', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TasksPage(repository: MemoryTasksRepository()),
      ),
    );
    await tester.pump();
    expect(find.text('First Task'), findsOneWidget);
  });
}
