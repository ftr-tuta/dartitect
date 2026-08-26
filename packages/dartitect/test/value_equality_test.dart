import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('deep equality preserves list order and ignores set/map order', () {
    final left = <Object?>[
      <int>[1, 2],
      <String>{'a', 'b'},
      <String, Object?>{
        'nested': <int>{3, 4},
        'record': (name: 'value', count: 2),
      },
    ];
    final right = <Object?>[
      <int>[1, 2],
      <String>{'b', 'a'},
      <String, Object?>{
        'record': (count: 2, name: 'value'),
        'nested': <int>{4, 3},
      },
    ];

    expect(ValueEquality.equals(left, right), isTrue);
    expect(ValueEquality.hash(left), ValueEquality.hash(right));
    expect(ValueEquality.equals(<int>[1, 2], <int>[2, 1]), isFalse);
  });

  test('value models and Result use structural equality', () {
    expect(const _Value(1, <String>['a']), const _Value(1, <String>['a']));
    expect(const Ok<int>(1), const Ok<int>(1));
    expect(const Ok<int>(1).hashCode, const Ok<int>(1).hashCode);
  });

  test('immutable copies do not retain mutable containers', () {
    final sourceList = <int>[1];
    final sourceSet = <int>{1};
    final sourceMap = <String, int>{'a': 1};
    final list = immutableListCopy(sourceList);
    final set = immutableSetCopy(sourceSet);
    final map = immutableMapCopy(sourceMap);

    sourceList.add(2);
    sourceSet.add(2);
    sourceMap['b'] = 2;

    expect(list, <int>[1]);
    expect(set, <int>{1});
    expect(map, <String, int>{'a': 1});
    expect(() => list.add(2), throwsUnsupportedError);
    expect(() => set.add(2), throwsUnsupportedError);
    expect(() => map['b'] = 2, throwsUnsupportedError);
  });

  test('cyclic collection graphs are rejected explicitly', () {
    final cyclic = <Object?>[];
    cyclic.add(cyclic);

    expect(
      () => ValueEquality.equals(cyclic, cyclic),
      throwsA(isA<CyclicValueException>()),
    );
    expect(
      () => ValueEquality.hash(cyclic),
      throwsA(isA<CyclicValueException>()),
    );
  });
}

final class _Value extends ValueEquality {
  const _Value(this.id, this.tags);

  final int id;
  final List<String> tags;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, tags];
}
