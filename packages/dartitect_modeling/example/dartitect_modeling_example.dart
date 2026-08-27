import 'package:dartitect_modeling/dartitect_modeling.dart';

/// An immutable consumer model with value semantics as its only capability.
@DartitectValue()
final class const Profile({required final String id, final String? displayName})
    extends ValueEquality {
  /// Completes the primary constructor without adding runtime behavior.
  this;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, displayName];
}

void main() {
  const first = Profile(id: 'profile-1', displayName: 'Ada');
  const second = Profile(id: 'profile-1', displayName: 'Ada');

  assert(first == second);
}
