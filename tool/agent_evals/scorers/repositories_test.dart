import 'dart:io';

import 'package:dartitect_flutter_quality_eval_fixture/local_first_task_repository.dart';
import 'package:dartitect_flutter_quality_eval_fixture/repository_contract.dart';
import 'package:dartitect_flutter_quality_eval_fixture/repository_stores.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in <String, TaskStore Function()>{
    'memory': MemoryTaskStore.new,
    'drift': DriftTaskStore.new,
    'objectbox': ObjectBoxTaskStore.new,
  }.entries) {
    test('${entry.key} implements the same local-first contract', () async {
      final store = entry.value();
      final repository = LocalFirstTaskRepository(store, _OfflineRemote());
      const task = Task(1, 'Synthetic task');

      await repository.add(task);

      expect(repository.store, same(store));
      expect(store.tasks, <Task>[task]);
      expect(store.outbox, <Task>[task]);
    });
  }

  test('composition selects exactly one store without dual-write hooks', () {
    final source = File('lib/local_first_task_repository.dart')
        .readAsStringSync();
    expect(source, isNot(contains('List<TaskStore>')));
    expect(source, isNot(contains('mirrors')));
    expect(source, isNot(contains('migrate')));
  });
}

final class _OfflineRemote implements TaskRemoteService {
  @override
  Future<bool> send(Task task) async => false;
}
