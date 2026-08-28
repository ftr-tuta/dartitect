import 'package:dartitect/dartitect.dart';

/// Pure field selector used by generated projections and test harnesses.
typedef DartitectProjectionSelector<Model, Projection> = Projection Function(
  Model model,
);

/// Named, typed description of one generated model field.
final class DartitectFieldDescriptor<Model, Value> {
  /// Creates a descriptor from a stable [name] and pure [select] function.
  const DartitectFieldDescriptor({required this.name, required this.select});

  /// Declared Dart field name.
  final String name;

  /// Reads the field without mutation or reflection.
  final Value Function(Model model) select;
}

/// Pure immutable-model lens generated from a primary constructor.
final class DartitectLens<Model, Value> {
  /// Creates a lens with a typed descriptor and reconstructing writer.
  const DartitectLens({required this.descriptor, required this.write});

  /// Field identity and reader.
  final DartitectFieldDescriptor<Model, Value> descriptor;

  /// Reconstructs a model with one replacement value.
  final Model Function(Model model, Value value) write;

  /// Reads the focused value.
  Value read(Model model) => descriptor.select(model);

  /// Reconstructs [model] after applying [update] to the focused value.
  Model update(Model model, Value Function(Value value) update) =>
      write(model, update(read(model)));
}

/// Stable payload-free category for a boundary mapping failure.
enum DartitectMappingFailureKind {
  /// A consumer-owned converter rejected its input.
  converterRejected,
}

/// Payload-free field location for a boundary mapping failure.
final class DartitectMappingPath extends ValueEquality {
  /// Creates a path between declared source and target fields.
  const DartitectMappingPath({
    required this.sourceField,
    required this.targetField,
  });

  /// Declared source-model field.
  final String sourceField;

  /// Declared target-boundary field.
  final String targetField;

  /// Stable machine representation.
  Map<String, String> toJson() => <String, String>{
    'sourceField': sourceField,
    'targetField': targetField,
  };

  @override
  Iterable<Object?> get equalityFields => <Object?>[sourceField, targetField];
}

/// Expected mapping failure without a domain payload.
final class DartitectMappingFailure extends ValueEquality implements Exception {
  /// Creates a typed failure at [path].
  const DartitectMappingFailure({required this.kind, required this.path});

  /// Typed failure category.
  final DartitectMappingFailureKind kind;

  /// Declared field boundary; no rejected value is retained.
  final DartitectMappingPath path;

  /// Creates a typed failed result with an empty stack trace.
  static Result<T, DartitectMappingFailure> result<T>(
    DartitectMappingFailureKind kind,
    DartitectMappingPath path,
  ) => Err<DartitectMappingFailure>(
    DartitectMappingFailure(kind: kind, path: path),
    StackTrace.empty,
  );

  /// Stable machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'path': path.toJson(),
  };

  @override
  Iterable<Object?> get equalityFields => <Object?>[kind, path];
}

/// Typed result constructors used by generated pure mappers.
abstract final class DartitectMappingResults {
  /// Lifts [value] while retaining the mapping failure type for composition.
  static Result<T, DartitectMappingFailure> success<T>(T value) => Ok<T>(value);
}

/// Pure one-way boundary mapper contract.
abstract interface class DartitectBoundaryMapper<Source, Target> {
  /// Maps one source without side effects or exceptions for expected failures.
  Result<Target, DartitectMappingFailure> toTarget(Source source);
}

/// Pure mapper whose reverse direction was independently validated.
abstract interface class DartitectBidirectionalBoundaryMapper<Source, Target>
    implements DartitectBoundaryMapper<Source, Target> {
  /// Maps one target back to the source model.
  Result<Source, DartitectMappingFailure> fromTarget(Target target);
}

/// Consumer-owned source-to-target converter hook.
typedef DartitectMapToHook<Source, Target> =
    Result<Target, DartitectMappingFailure> Function(
      Source source,
      DartitectMappingPath path,
    );

/// Consumer-owned target-to-source converter hook.
typedef DartitectMapFromHook<Target, Source> =
    Result<Source, DartitectMappingFailure> Function(
      Target target,
      DartitectMappingPath path,
    );
