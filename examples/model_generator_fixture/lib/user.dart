import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'user.dartitect.g.dart';

/// Consumer-owned boundary target proving mapper interoperability.
final class UserDto {
  /// Creates the fixture DTO.
  const UserDto({required this.identifier, required this.email});

  /// Boundary identifier with an explicit rename.
  final String identifier;

  /// Optional boundary address.
  final String? email;
}

/// Fixture proving checkout-time generated equality and copyWith behavior.
@DartitectValue()
@DartitectJson()
@DartitectProjection(name: 'summary', fields: <String>['id'])
@DartitectMapper(UserDto, bidirectional: true)
final class const User({
  /// Stable identifier.
  @DartitectField(targetName: 'identifier') required final String id,

  /// Optional address used to prove preserve/replace/clear.
  required final String? email,
}) extends ValueEquality with _$UserDartitect {
  /// Creates an immutable fixture user.
  this;
}
