import 'package:dartitect_openapi_contract_fixture/contracts/tasks.contracts.dartitect.g.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generated DTO codecs, fixtures, routes, and status mappings are usable',
    () {
      final task = TaskDto.fromJson(<String, Object?>{
        'id': 'task-1',
        'title': 'Generated contract',
        'version': 3,
        'status': 'open',
      });

      expect(task.id, 'task-1');
      expect(task.status, StatusDto.open);
      expect(task.toJson()['version'], 3);
      expect(taskOpenApiFixture, containsPair('id', 'fixture'));
      expect(getTaskRoute(id: 'a/b'), '/tasks/a%2Fb');
      expect(
        taskContractCanaryEndpoints
            .singleWhere((endpoint) => endpoint.operationId == 'getTask')
            .responseTypes,
        <int, String>{200: 'TaskDto', 404: 'ApiErrorDto'},
      );
    },
  );
}
