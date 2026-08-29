import 'package:dartitect/dartitect.dart';

/// Status of the real vertical canary Task.
enum TaskStatus { open, completed }

/// Consumer-owned `Task(id, title, version, status)` domain value.
final class const Task({
  /// Stable task identifier.
  required final String id,

  /// User-visible title.
  required final String title,

  /// Monotonic semantic version.
  final int version = 1,

  /// Current domain status.
  final TaskStatus status = TaskStatus.open,
}) extends ValueEquality {
  /// Completes the primary constructor.
  this;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, title, version, status];
}
