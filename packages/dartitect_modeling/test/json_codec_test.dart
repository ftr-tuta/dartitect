import 'dart:convert';

import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:test/test.dart';

void main() {
  test('object codec round-trips and rejects unknown keys by default', () {
    const codec = _UserCodec();
    const user = _User('u-1', null);

    final encoded = _success<Object?>(codec.encode(user));
    final decoded = _success<_User>(codec.decode(encoded));
    final failure = _failure(
      codec.decode(<String, Object?>{
        'id': 'u-1',
        'email': null,
        'authorization_token': 'must-not-leak',
      }),
    );

    expect(decoded, user);
    expect(encoded, <String, Object?>{'id': 'u-1', 'email': null});
    expect(failure.kind, DartitectJsonFailureKind.unknownKey);
    expect(failure.path, DartitectJsonPath.root.key('authorization_token'));
    expect(jsonEncode(failure.toJson()), isNot(contains('must-not-leak')));
  });

  test('scalar codecs use portable mathematical number semantics', () {
    expect(_success<int>(DartitectJsonCodecs.integer.decode(1)), 1);
    expect(_success<int>(DartitectJsonCodecs.integer.decode(1.0)), 1);
    expect(
      _failure(DartitectJsonCodecs.integer.decode(1.5)).kind,
      DartitectJsonFailureKind.expectedInteger,
    );
    expect(_success<double>(DartitectJsonCodecs.doubleValue.decode(1.0)), 1.0);
    expect(_success<double>(DartitectJsonCodecs.doubleValue.decode(1)), 1.0);
    expect(
      _failure(DartitectJsonCodecs.number.decode(double.nan)).kind,
      DartitectJsonFailureKind.nonFiniteNumber,
    );
  });

  test('immutable collection codecs retain structure without mutable APIs', () {
    final listCodec = DartitectJsonCodecs.immutableList(
      DartitectJsonCodecs.integer,
    );
    final setCodec = DartitectJsonCodecs.immutableSet(
      DartitectJsonCodecs.string,
    );
    final mapCodec = DartitectJsonCodecs.immutableMap(
      DartitectJsonCodecs.boolean,
    );

    final list = _success<ImmutableValueList<int>>(
      listCodec.decode(<Object?>[1, 2]),
    );
    final map = _success<ImmutableValueMap<String, bool>>(
      mapCodec.decode(<String, Object?>{'enabled': true}),
    );

    expect(list, ImmutableValueList<int>(<int>[1, 2]));
    expect(map['enabled'], isTrue);
    expect(
      _failure(setCodec.decode(<Object?>['same', 'same'])).kind,
      DartitectJsonFailureKind.duplicateSetItem,
    );
  });

  test('untrusted defaults enforce depth collection and total-node bounds', () {
    const limits = DartitectJsonLimits.untrusted();
    expect(limits.maxDepth, 64);
    expect(limits.maxCollectionItems, 10000);
    expect(limits.maxTotalNodes, 100000);

    Object? deep = 'leaf';
    for (var index = 0; index < 65; index += 1) {
      deep = <Object?>[deep];
    }
    final oversized = List<Object?>.filled(10001, null);
    final tooManyNodes = <Object?>[
      for (var group = 0; group < 11; group += 1)
        List<Object?>.filled(10000, null),
    ];

    expect(
      _failure(DartitectJsonCodecs.jsonValue.decode(deep)).kind,
      DartitectJsonFailureKind.depthLimitExceeded,
    );
    expect(
      _failure(DartitectJsonCodecs.jsonValue.decode(oversized)).kind,
      DartitectJsonFailureKind.collectionLimitExceeded,
    );
    expect(
      _failure(DartitectJsonCodecs.jsonValue.decode(tooManyNodes)).kind,
      DartitectJsonFailureKind.nodeLimitExceeded,
    );
  });

  test('custom and trusted choices are explicit while cycles stay invalid', () {
    const custom = DartitectJsonLimits.custom(
      maxDepth: 1,
      maxCollectionItems: 2,
      maxTotalNodes: 3,
    );
    const trusted = DartitectJsonLimits.trusted();
    final oversized = List<Object?>.filled(10001, null);
    final cyclic = <Object?>[];
    cyclic.add(cyclic);

    expect(
      _failure(
        DartitectJsonCodecs.jsonValue.decode(<Object?>[
          <Object?>[<Object?>[]],
        ], limits: custom),
      ).kind,
      DartitectJsonFailureKind.depthLimitExceeded,
    );
    expect(
      _success<Object?>(
        DartitectJsonCodecs.jsonValue.decode(oversized, limits: trusted),
      ),
      same(oversized),
    );
    expect(
      _failure(DartitectJsonCodecs.jsonValue.decode(cyclic, limits: trusted))
          .kind,
      DartitectJsonFailureKind.cyclicValue,
    );
  });

  test('consumer hook codec remains explicit and path-aware', () {
    final codec = DartitectHookJsonCodec<_Identifier>(
      decode: _decodeIdentifier,
      encode: _encodeIdentifier,
    );

    expect(
      _success<_Identifier>(codec.decode('id-1')),
      const _Identifier('id-1'),
    );
    expect(
      _failure(codec.decode(1)).kind,
      DartitectJsonFailureKind.customCodec,
    );
  });
}

final class _User extends ValueEquality {
  const _User(this.id, this.email);

  final String id;
  final String? email;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, email];
}

final class _UserCodec extends DartitectJsonCodec<_User> {
  const _UserCodec();

  @override
  Result<_User, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) =>
      DartitectJsonObjectSupport.decodeObject(
        input,
        path,
        allowedKeys: const <String>{'id', 'email'},
        requiredKeys: const <String>{'id', 'email'},
      ).flatMap(
        (object) => DartitectJsonCodecs.string
            .decodeValue(object['id'], path.key('id'))
            .flatMap(
              (id) =>
                  DartitectJsonCodecs.nullable(DartitectJsonCodecs.string)
                      .decodeValue(object['email'], path.key('email'))
                      .map((email) => _User(id, email)),
            ),
      );

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    _User value,
    DartitectJsonPath path,
  ) => DartitectJsonCodecs.string
      .encodeValue(value.id, path.key('id'))
      .flatMap(
        (id) => DartitectJsonCodecs.nullable(DartitectJsonCodecs.string)
            .encodeValue(value.email, path.key('email'))
            .map<Object?>(
              (email) => <String, Object?>{'id': id, 'email': email},
            ),
      );
}

final class _Identifier extends ValueEquality {
  const _Identifier(this.value);

  final String value;

  @override
  Iterable<Object?> get equalityFields => <Object?>[value];
}

Result<_Identifier, DartitectJsonFailure> _decodeIdentifier(
  Object? input,
  DartitectJsonPath path,
) => input is String
    ? Ok<_Identifier>(_Identifier(input))
    : DartitectJsonFailure.result<_Identifier>(
        DartitectJsonFailureKind.customCodec,
        path,
      );

Result<Object?, DartitectJsonFailure> _encodeIdentifier(
  _Identifier value,
  DartitectJsonPath path,
) => Ok<Object?>(value.value);

T _success<T>(Result<T, DartitectJsonFailure> result) => switch (result) {
  Ok<dynamic>(:final value) => value as T,
  Err<Object>(:final failure) => throw TestFailure('Expected Ok, got $failure'),
};

DartitectJsonFailure _failure<T>(Result<T, DartitectJsonFailure> result) =>
    switch (result) {
      Ok<dynamic>() => throw TestFailure('Expected Err, got Ok'),
      Err<Object>(:final failure) => failure as DartitectJsonFailure,
    };
