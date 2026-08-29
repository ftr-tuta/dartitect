import 'package:test/test.dart';

import 'api_snapshot.dart';

void main() {
  test('semantic diff classifies additions, deprecations, and breaks', () {
    final before = _snapshot(<Map<String, Object?>>[
      _symbol('Stable'),
      _symbol('Old'),
      _symbol('Removed'),
    ]);
    final after = _snapshot(<Map<String, Object?>>[
      _symbol('Stable'),
      _symbol('Old', deprecated: true),
      _symbol('Added'),
    ]);

    final differences = classifyApiDiff(before, after);

    expect(
      differences.map((difference) => difference.kind),
      containsAll(<ApiCompatibilityKind>[
        ApiCompatibilityKind.additive,
        ApiCompatibilityKind.deprecated,
        ApiCompatibilityKind.breaking,
      ]),
    );
    expect(maximumApiChange(differences), ApiCompatibilityKind.breaking);
  });

  test('version validation follows semantic compatibility impact', () {
    expect(
      validatesApiVersion(
        '1.0.0-rc.8',
        '1.0.0-rc.8',
        ApiCompatibilityKind.breaking,
      ),
      isTrue,
    );
    expect(
      validatesApiVersion(
        '1.0.0-rc.9',
        '1.0.0-rc.10',
        ApiCompatibilityKind.breaking,
      ),
      isTrue,
    );
    expect(
      validatesApiVersion('1.2.3', '1.3.0', ApiCompatibilityKind.additive),
      isTrue,
    );
    expect(
      validatesApiVersion('1.2.3', '1.3.0', ApiCompatibilityKind.breaking),
      isFalse,
    );
    expect(
      validatesApiVersion('1.2.3', '1.2.4', ApiCompatibilityKind.deprecated),
      isTrue,
    );
    expect(
      validatesApiVersion('1.2.3', '1.2.4', ApiCompatibilityKind.additive),
      isFalse,
    );
  });
}

Map<String, Object?> _snapshot(List<Map<String, Object?>> symbols) =>
    <String, Object?>{
      'schemaVersion': 2,
      'sdkVersion': '1.0.0',
      'entrypoints': <String, Object?>{
        'package/lib/package.dart': <String, Object?>{
          'defaultAudience': 'application-facing',
          'symbols': symbols,
        },
      },
    };

Map<String, Object?> _symbol(
  String name, {
  bool deprecated = false,
}) => <String, Object?>{
  'name': name,
  'kind': 'class',
  'audience': 'application-facing',
  'declaration': 'class $name',
  'deprecated': deprecated,
  'annotations': deprecated ? <String>['@Deprecated("use next")'] : <String>[],
  'modifiers': deprecated ? <String>['deprecated'] : <String>[],
  'typeParameters': const <Object?>[],
  'supertype': 'Object',
  'mixins': const <Object?>[],
  'interfaces': const <Object?>[],
  'members': const <Object?>[],
};
