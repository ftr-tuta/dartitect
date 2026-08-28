import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'profile.dartitect.g.dart';

@DartitectValue()
final class const Profile({
  required final String id,
  required final String? label,
}) extends ValueEquality with _$ProfileDartitect {
  /// Creates a minimal canary profile.
  this;
}
