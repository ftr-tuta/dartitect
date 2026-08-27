import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'user.dartitect.g.dart';

/// Fixture proving checkout-time generated equality and copyWith behavior.
@DartitectValue()
final class const User({
  /// Stable identifier.
  required final String id,

  /// Optional address used to prove preserve/replace/clear.
  required final String? email,
}) extends ValueEquality with _$UserDartitect {
  /// Creates an immutable fixture user.
  this;
}
