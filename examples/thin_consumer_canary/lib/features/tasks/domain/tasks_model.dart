import 'package:dartitect/dartitect.dart';

/// Immutable domain value generated without product schema assumptions.
final class TasksModel({
  /// Stable consumer-owned model identifier.
  required final String id,
  Iterable<String> labels = const <String>[],
}) extends ValueEquality {
  /// Creates a model while defensively copying collection input.
  this : labels = immutableListCopy(labels);

  /// Immutable labels retained by the generated model.
  final List<String> labels;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, labels];
}
