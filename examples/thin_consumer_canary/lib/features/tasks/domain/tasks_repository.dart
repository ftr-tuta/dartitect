import 'package:dartitect/dartitect.dart';

/// Expected failure at the Tasks repository boundary.
final class TasksFailure implements Exception {
  const TasksFailure(this.code);

  final String code;
}

/// Pure-Dart Tasks repository contract.
abstract interface class TasksRepository {
  Future<Result<List<String>, TasksFailure>> load();
}
