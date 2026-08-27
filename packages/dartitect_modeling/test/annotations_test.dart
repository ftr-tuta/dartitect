import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:test/test.dart';

void main() {
  test('modeling capabilities remain independently configurable', () {
    const value = DartitectValue();
    const json = DartitectJson();
    const projection = DartitectProjection(name: 'summary');
    const mapper = DartitectMapper(_Target, bidirectional: true);
    const field = DartitectField(
      jsonName: 'display_name',
      mapToWith: '_toTargetName',
    );

    expect(value, isA<DartitectValue>());
    expect(json.unknownKeys, DartitectUnknownKeys.reject);
    expect(json.trusted, isFalse);
    expect(projection.name, 'summary');
    expect(mapper.target, _Target);
    expect(mapper.bidirectional, isTrue);
    expect(field.jsonName, 'display_name');
    expect(field.mapToWith, '_toTargetName');
  });

  test('reexports the minimal core value surface', () {
    const result = Ok<int>(1);
    expect(result, isA<Result<int, Never>>());
    expect(result.equalityFields, <Object?>[1]);
  });
}

final class _Target {}
