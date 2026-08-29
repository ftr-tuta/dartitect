import 'package:dartitect/dartitect.dart';
import 'package:thin_consumer_canary/features/tasks/infrastructure/memory_tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('memory repository satisfies the public contract', () async {
    final repository = MemoryTasksRepository(const <String>['A']);
    final result = await repository.load();
    expect(result, isA<Ok<List<String>>>());
    expect((result as Ok<List<String>>).value, <String>['A']);
  });
}
