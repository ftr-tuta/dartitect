// GENERATED CODE - DO NOT EDIT BY HAND.
// Dartitect model generator 1.0.0-rc.2, input schema 1.

part of 'user.dart';

mixin _$UserDartitect on ValueEquality {
  String get id;
  String? get email;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, email];

  User copyWith({String? id, String? email, bool clearEmail = false}) {
    if (clearEmail && email != null) {
      throw ArgumentError('email and clearEmail cannot be used together.');
    }
    return User(
      id: id ?? this.id,
      email: clearEmail ? null : email ?? this.email,
    );
  }
}
