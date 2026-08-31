import 'package:thin_consumer_canary/features/tasks/presentation/tasks_view.dart';
import 'package:thin_consumer_canary/features/tasks/presentation/tasks_view_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/features/tasks/memory_tasks_repository.dart';

void main() {
  testWidgets('view renders ViewModel local data', (tester) async {
    final viewModel = TasksViewModel(MemoryTasksRepository());
    await viewModel.start();
    addTearDown(viewModel.disposeAsync);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TasksView(viewModel: viewModel),
      ),
    );
    await tester.pump();
    expect(find.text('First Task'), findsOneWidget);
  });
}
