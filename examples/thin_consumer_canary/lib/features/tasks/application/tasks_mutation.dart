import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/tasks_repository.dart';

final class const TasksMutation({
  /// Consumer-owned aggregate identifier.
  required final String aggregateId,
}) extends ValueEquality {
  /// Completes the primary constructor without adding runtime behavior.
  this;

  @override
  Iterable<Object?> get equalityFields => <Object?>[aggregateId];
}

typedef TasksMutationLane =
    MutationLane<String, TasksMutation, void, TasksFailure>;
