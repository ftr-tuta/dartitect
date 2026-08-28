import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:test/test.dart';

void main() {
  test('list copies its source and retains ordered structural value', () {
    final source = <Object?>[
      1,
      <String>['nested'],
    ];
    final value = ImmutableValueList<Object?>(source);
    final equal = ImmutableValueList<Object?>(<Object?>[
      1,
      <String>['nested'],
    ]);

    source.add(2);

    expect(value, equal);
    expect(value.hashCode, equal.hashCode);
    expect(value.length, 2);
    expect(value[0], 1);
    expect(value, isNot(ImmutableValueList<Object?>(<Object?>[2, 1])));
    expect(value, isNot(isA<List<Object?>>()));
  });

  test('set and map ignore iteration order in equality and hashing', () {
    final set = ImmutableValueSet<int>(<int>[1, 2, 3]);
    final reorderedSet = ImmutableValueSet<int>(<int>[3, 1, 2]);
    final source = <String, Object?>{
      'id': 1,
      'roles': <String>{'reader', 'writer'},
    };
    final map = ImmutableValueMap<String, Object?>(source);
    final reorderedMap = ImmutableValueMap<String, Object?>(<String, Object?>{
      'roles': <String>{'writer', 'reader'},
      'id': 1,
    });

    source['later'] = true;

    expect(set, reorderedSet);
    expect(set.hashCode, reorderedSet.hashCode);
    expect(map, reorderedMap);
    expect(map.hashCode, reorderedMap.hashCode);
    expect(map.containsKey('later'), isFalse);
    expect(map, isNot(isA<Map<String, Object?>>()));

    final nestedSet = ImmutableValueSet<Object?>(<Object?>[
      <int>[1, 2],
      <int>[1, 2],
    ]);
    expect(nestedSet.length, 1);
    expect(nestedSet.contains(<int>[1, 2]), isTrue);

    final structuralMap = ImmutableValueMap<Object?, String>(<Object?, String>{
      <int>[1, 2]: 'first',
      <int>[1, 2]: 'last',
    });
    expect(structuralMap.length, 1);
    expect(structuralMap.containsKey(<int>[1, 2]), isTrue);
    expect(structuralMap[<int>[1, 2]], 'last');
  });

  test('constructors reject cycles before retaining a collection graph', () {
    final cyclicList = <Object?>[];
    cyclicList.add(cyclicList);
    final cyclicMap = <String, Object?>{};
    cyclicMap['self'] = cyclicMap;

    expect(
      () => ImmutableValueList<Object?>(cyclicList),
      throwsA(isA<CyclicValueException>()),
    );
    expect(
      () => ImmutableValueMap<String, Object?>(cyclicMap),
      throwsA(isA<CyclicValueException>()),
    );
  });
}
