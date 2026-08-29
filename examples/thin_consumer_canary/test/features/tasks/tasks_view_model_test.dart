import 'package:dartitect/dartitect.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';
import 'package:thin_consumer_canary/features/tasks/presentation/tasks_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads through the injected repository contract', () async {
    final repository = _Repository();
    final viewModel = TasksViewModel(repository);
    await viewModel.start();
    expect(viewModel.items, <String>['Injected Tasks']);
    expect(repository.calls, 1);
    await viewModel.disposeAsync();
  });
}

final class _Repository implements TasksRepository {
  var calls = 0;

  @override
  Future<Result<List<String>, TasksFailure>> load() async {
    calls += 1;
    return const Ok<List<String>>(<String>['Injected Tasks']);
  }
}
