import 'package:dartitect/dartitect.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/features/tasks/memory_tasks_repository.dart';

void main() {
  test('memory repository satisfies the public contract', () async {
    final repository = MemoryTasksRepository(const <String>['A']);
    final result = await repository.load();
    expect(result, isA<Ok<List<String>>>());
    expect((result as Ok<List<String>>).value, <String>['A']);
  });
}
