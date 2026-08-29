import 'package:thin_consumer_canary/features/tasks/infrastructure/tasks_mapper.dart';
import 'package:thin_consumer_canary/features/tasks/infrastructure/tasks_remote_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps infrastructure DTO into immutable domain value', () {
    final value = mapTasksRemoteDto(const TasksRemoteDto(id: '1', label: 'A'));
    expect(value.id, '1');
    expect(value.labels, <String>['A']);
  });
}
