// GENERATED CODE - DO NOT EDIT BY HAND.
// Dartitect model renderer 1, semantic schema 4.

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

/// Generated typed descriptors and lenses for [User].
final class UserDartitectFields {
  /// Creates the generated field registry.
  const UserDartitectFields();

  /// Descriptor and immutable lens for `id`.
  DartitectLens<User, String> get id => DartitectLens<User, String>(
    descriptor: DartitectFieldDescriptor<User, String>(
      name: 'id',
      select: (model) => model.id,
    ),
    write: (model, value) => User(id: value, email: model.email),
  );

  /// Descriptor and immutable lens for `email`.
  DartitectLens<User, String?> get email => DartitectLens<User, String?>(
    descriptor: DartitectFieldDescriptor<User, String?>(
      name: 'email',
      select: (model) => model.email,
    ),
    write: (model, value) => User(id: model.id, email: value),
  );
}

/// Shared generated field registry for [User].
const userDartitectFields = UserDartitectFields();

/// Generated `summary` record projection for [User].
typedef UserSummaryDartitectProjection = ({String id});

/// Selects the generated `summary` projection.
UserSummaryDartitectProjection selectUserSummary(User model) => (id: model.id);

/// Generated pure boundary mapper from [User] to [UserDto].
final class UserToUserDtoDartitectMapper
    implements DartitectBidirectionalBoundaryMapper<User, UserDto> {
  /// Creates the generated mapper.
  const UserToUserDtoDartitectMapper();

  @override
  Result<UserDto, DartitectMappingFailure> toTarget(User source) =>
      DartitectMappingResults.success<String>(source.id).flatMap(
        (_idMapped) => DartitectMappingResults.success<String?>(source.email)
            .flatMap(
              (_emailMapped) => Ok<UserDto>(
                UserDto(identifier: _idMapped, email: _emailMapped),
              ),
            ),
      );

  @override
  Result<User, DartitectMappingFailure> fromTarget(UserDto target) =>
      DartitectMappingResults.success<String>(target.identifier).flatMap(
        (_idMapped) => DartitectMappingResults.success<String?>(target.email)
            .flatMap(
              (_emailMapped) =>
                  Ok<User>(User(id: _idMapped, email: _emailMapped)),
            ),
      );
}

/// Shared generated mapper from [User] to [UserDto].
const userToUserDtoDartitectMapper = UserToUserDtoDartitectMapper();
