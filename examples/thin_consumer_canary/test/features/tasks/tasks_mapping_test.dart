import 'package:thin_consumer_canary/features/tasks/infrastructure/tasks_mapper.dart';
import 'package:thin_consumer_canary/features/tasks/infrastructure/tasks_remote_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps infrastructure DTO into immutable domain value', () {
    final value = mapTasksRemoteDto(
      const TasksRemoteDto(
        id: '1',
        title: 'A',
        version: 3,
        status: 'completed',
      ),
    );
    expect(value.id, '1');
    expect(value.title, 'A');
    expect(value.version, 3);
    expect(value.status.name, 'completed');
  });
}
