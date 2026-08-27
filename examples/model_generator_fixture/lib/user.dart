import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'user.dartitect.g.dart';

/// Fixture proving checkout-time generated equality and copyWith behavior.
@DartitectValue()
final class User extends ValueEquality with _$UserDartitect {
  /// Creates an immutable fixture user.
  const User({required this.id, required this.email});

  /// Stable identifier.
  final String id;

  /// Optional address used to prove preserve/replace/clear.
  final String? email;
}
