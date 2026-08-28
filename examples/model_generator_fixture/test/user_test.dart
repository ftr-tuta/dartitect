import 'package:dartitect_model_generator_fixture/user.dart';
import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:test/test.dart';

void main() {
  test('generated equality and nullable copyWith semantics are complete', () {
    const original = User(id: '1', email: 'old@example.test');
    expect(original, const User(id: '1', email: 'old@example.test'));
    expect(original.copyWith(), original);
    expect(
      original.copyWith(email: 'new@example.test'),
      const User(id: '1', email: 'new@example.test'),
    );
    expect(
      original.copyWith(clearEmail: true),
      const User(id: '1', email: null),
    );
    expect(
      () => original.copyWith(email: 'new@example.test', clearEmail: true),
      throwsArgumentError,
    );
  });

  test('generated JSON codec round-trips and rejects unknown keys', () {
    final decoded = userDartitectJsonCodec.decode(<String, Object?>{
      'id': '1',
      'email': null,
    });
    final unknown = userDartitectJsonCodec.decode(<String, Object?>{
      'id': '1',
      'email': null,
      'extra': true,
    });

    expect(decoded, const Ok<User>(User(id: '1', email: null)));
    expect(
      unknown,
      isA<Err<DartitectJsonFailure>>().having(
        (result) => result.failure.kind,
        'kind',
        DartitectJsonFailureKind.unknownKey,
      ),
    );
  });
}
