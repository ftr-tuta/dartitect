// GENERATED CODE - DO NOT EDIT BY HAND.
// Dartitect model generator 1.0.0-rc.3, input schema 3.

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

/// Generated JSON codec for [User].
final class UserDartitectJsonCodec extends DartitectJsonCodec<User> {
  /// Creates the generated codec.
  const UserDartitectJsonCodec();

  @override
  Result<User, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) =>
      DartitectJsonObjectSupport.decodeObject(
        input,
        path,
        allowedKeys: const <String>{'id', 'email'},
        requiredKeys: const <String>{'id', 'email'},
        rejectUnknownKeys: true,
      ).flatMap(
        (object) =>
            (DartitectJsonCodecs.string.decodeValue(
              object['id'],
              path.key('id'),
            )).flatMap(
              (_idJson) =>
                  (DartitectJsonCodecs.nullable(
                    DartitectJsonCodecs.string,
                  ).decodeValue(object['email'], path.key('email'))).flatMap(
                    (_emailJson) =>
                        Ok<User>(User(id: _idJson, email: _emailJson)),
                  ),
            ),
      );

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    User value,
    DartitectJsonPath path,
  ) => DartitectJsonCodecs.string
      .encodeValue(value.id, path.key('id'))
      .flatMap(
        (_idJson) => DartitectJsonCodecs.nullable(DartitectJsonCodecs.string)
            .encodeValue(value.email, path.key('email'))
            .flatMap(
              (_emailJson) => Ok<Object?>(<String, Object?>{
                'id': _idJson,
                'email': _emailJson,
              }),
            ),
      );
}

/// Shared generated JSON codec for [User].
const userDartitectJsonCodec = UserDartitectJsonCodec();
