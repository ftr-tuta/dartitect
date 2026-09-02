import 'repository_contract.dart';

final class LocalFirstTaskRepository implements TaskRepository {
  LocalFirstTaskRepository(this.store, this.remote, {this.mirrors = const []});

  @override
  final TaskStore store;
  final TaskRemoteService remote;
  final List<TaskStore> mirrors;

  @override
  Future<void> add(Task task) async {
    await store.save(task);
    for (final mirror in mirrors) {
      await mirror.save(task);
    }
    if (!await remote.send(task)) {
      await store.enqueue(task);
      for (final mirror in mirrors) {
        await mirror.enqueue(task);
      }
    }
  }
}
