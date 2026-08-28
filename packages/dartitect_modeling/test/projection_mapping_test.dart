import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:test/test.dart';

void main() {
  test('descriptor and lens read update and reconstruct immutable values', () {
    final lens = DartitectLens<_Profile, String>(
      descriptor: const DartitectFieldDescriptor<_Profile, String>(
        name: 'name',
        select: _readName,
      ),
      write: _writeName,
    );
    const original = _Profile('Ada');

    expect(lens.descriptor.name, 'name');
    expect(lens.read(original), 'Ada');
    expect(
      lens.update(original, (value) => value.toUpperCase()),
      const _Profile('ADA'),
    );
    expect(original, const _Profile('Ada'));
  });

  test('mapping failures retain only typed declared-field evidence', () {
    const path = DartitectMappingPath(
      sourceField: 'identifier',
      targetField: 'id',
    );
    const failure = DartitectMappingFailure(
      kind: DartitectMappingFailureKind.converterRejected,
      path: path,
    );

    expect(failure.toJson(), <String, Object?>{
      'kind': 'converterRejected',
      'path': <String, String>{
        'sourceField': 'identifier',
        'targetField': 'id',
      },
    });
  });

  test('mapping success retains the expected failure channel', () {
    final result = DartitectMappingResults.success<String>('mapped');

    expect(result, isA<Result<String, DartitectMappingFailure>>());
    expect(result, const Ok<String>('mapped'));
  });
}

final class _Profile extends ValueEquality {
  const _Profile(this.name);

  final String name;

  @override
  Iterable<Object?> get equalityFields => <Object?>[name];
}

String _readName(_Profile profile) => profile.name;

_Profile _writeName(_Profile profile, String name) => _Profile(name);
