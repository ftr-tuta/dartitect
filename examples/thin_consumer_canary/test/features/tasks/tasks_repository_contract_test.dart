import 'package:dartitect/dartitect.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/features/tasks/memory_tasks_repository.dart';

void main() {
  test('memory repository satisfies the public contract', () async {
    final repository = MemoryTasksRepository(const <Task>[
      Task(id: 'a', title: 'A'),
    ]);
    final result = await repository.load();
    expect(result, isA<Ok<List<Task>>>());
    expect((result as Ok<List<Task>>).value.single.title, 'A');
  });
}
