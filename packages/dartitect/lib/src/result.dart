import 'value_equality.dart';

/// A successful value or an expected, typed failure.
///
/// Unexpected exceptions are deliberately outside this type. Preserve them as
/// exceptions so programming defects and broken invariants are not converted
/// into ordinary control flow.
sealed class Result<T, F extends Object> extends ValueEquality {
  const Result();
}

/// Small functional operations for a statically typed [Result].
extension ResultOperations<T, F extends Object> on Result<T, F> {
  /// Transforms a successful value while preserving a failure unchanged.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok<dynamic>(:final value) => Ok<R>(transform(value as T)),
    Err<Object>(:final failure, :final stackTrace) => Err<F>(
      failure as F,
      stackTrace,
    ),
  };

  /// Transforms an expected failure while preserving a success unchanged.
  Result<T, G> mapFailure<G extends Object>(G Function(F failure) transform) =>
      switch (this) {
        Ok<dynamic>(:final value) => Ok<T>(value as T),
        Err<Object>(:final failure, :final stackTrace) => Err<G>(
          transform(failure as F),
          stackTrace,
        ),
      };

  /// Chains another typed operation without nesting [Result] values.
  Result<R, F> flatMap<R>(Result<R, F> Function(T value) transform) =>
      switch (this) {
        Ok<dynamic>(:final value) => transform(value as T),
        Err<Object>(:final failure, :final stackTrace) => Err<F>(
          failure as F,
          stackTrace,
        ),
      };

  /// Reduces both variants to one value using exhaustive callbacks.
  R fold<R>(
    R Function(T value) onSuccess,
    R Function(F failure, StackTrace stackTrace) onFailure,
  ) => switch (this) {
    Ok<dynamic>(:final value) => onSuccess(value as T),
    Err<Object>(:final failure, :final stackTrace) => onFailure(
      failure as F,
      stackTrace,
    ),
  };
}

/// A successful [Result] containing [value].
final class Ok<T> extends Result<T, Never> {
  /// Creates a successful result.
  const Ok(this.value);

  /// Successful value.
  final T value;

  @override
  Iterable<Object?> get equalityFields => <Object?>[value];
}

/// A failed [Result] preserving a typed [failure] and its [stackTrace].
final class Err<F extends Object> extends Result<Never, F> {
  /// Creates an expected failure.
  const Err(this.failure, this.stackTrace);

  /// Expected failure value.
  final F failure;

  /// Stack trace captured at the failure boundary.
  final StackTrace stackTrace;

  @override
  Iterable<Object?> get equalityFields => <Object?>[failure, stackTrace];
}
