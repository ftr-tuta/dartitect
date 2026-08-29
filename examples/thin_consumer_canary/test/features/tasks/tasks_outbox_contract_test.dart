import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/features/tasks/fake_tasks_outbox_store.dart';

void main() {
  test('fake persists the exact idempotency key', () async {
    final store = FakeTasksOutboxStore();
    final cancellation = CancellationSource();
    final operation = OutboxOperation<String, TasksMutation>(
      idempotencyKey: 'fixture-1',
      key: 'fixture',
      argument: const TasksMutation(aggregateId: 'fixture'),
    );
    expect(
      await store.applyLocalAndEnqueue(operation, cancellation.signal),
      const Ok<void>(null),
    );
    expect(store.rows, contains('fixture-1'));
    cancellation.dispose();
  });
}
