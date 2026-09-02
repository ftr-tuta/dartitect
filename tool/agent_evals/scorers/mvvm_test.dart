import 'dart:io';

import 'package:dartitect_flutter_quality_eval_fixture/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ViewModel owns loading and view receives presentation state', (
    tester,
  ) async {
    final repository = _FakeTaskRepository();
    final viewModel = TasksViewModel(repository);
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(MaterialApp(home: TasksPage(viewModel: viewModel)));
    await tester.pump();
    expect(find.text('Synthetic task'), findsOneWidget);
    expect(repository.loads, 1);

    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('class TasksViewModel extends ChangeNotifier'));
    expect(source, contains('class TasksView extends StatelessWidget'));
    expect(source, isNot(contains('setState(() => tasks')));
    expect(source, isNot(contains('TaskRemoteService remote')));
  });
}

final class _FakeTaskRepository implements TaskRepository {
  var loads = 0;

  @override
  Future<List<Task>> load() async {
    loads += 1;
    return const <Task>[Task('Synthetic task')];
  }
}
