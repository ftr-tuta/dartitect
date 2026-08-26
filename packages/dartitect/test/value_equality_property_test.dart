import 'dart:math';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

const _seed = 11001;
const _cases = 1000;

void main() {
  test(
    'deep equality laws and hashes hold for deterministic acyclic values',
    () {
      final random = Random(_seed);
      for (var index = 0; index < _cases; index += 1) {
        final original = _value(random, 0);
        final equivalentA = _equivalentCopy(original, random);
        final equivalentB = _equivalentCopy(equivalentA, random);

        expect(
          ValueEquality.equals(original, original),
          isTrue,
          reason: 'reflexivity failed at seed=$_seed case=$index',
        );
        expect(
          ValueEquality.equals(original, equivalentA),
          isTrue,
          reason: 'equivalence failed at seed=$_seed case=$index',
        );
        expect(
          ValueEquality.equals(equivalentA, original),
          isTrue,
          reason: 'symmetry failed at seed=$_seed case=$index',
        );
        expect(
          ValueEquality.equals(equivalentA, equivalentB),
          isTrue,
          reason: 'transitivity premise failed at seed=$_seed case=$index',
        );
        expect(
          ValueEquality.equals(original, equivalentB),
          isTrue,
          reason: 'transitivity failed at seed=$_seed case=$index',
        );
        expect(
          ValueEquality.hash(original),
          ValueEquality.hash(equivalentA),
          reason: 'equal hash failed at seed=$_seed case=$index',
        );
      }
    },
  );

  test('collection kind and list order remain semantically significant', () {
    for (var index = 0; index < _cases; index += 1) {
      final left = <Object?>[index, index + 1, 'case-$index'];
      final reversed = left.reversed.toList();
      expect(ValueEquality.equals(left, reversed), isFalse);
      expect(ValueEquality.equals(left, left.toSet()), isFalse);
      expect(ValueEquality.equals(left, <int, Object?>{0: left}), isFalse);
    }
  });
}

Object? _value(Random random, int depth) {
  if (depth >= 4 || random.nextInt(4) == 0) return _leaf(random);
  switch (random.nextInt(3)) {
    case 0:
      return <Object?>[
        for (var index = 0; index < random.nextInt(5); index += 1)
          _value(random, depth + 1),
      ];
    case 1:
      return <Object?>{
        for (var index = 0; index < random.nextInt(5); index += 1)
          _value(random, depth + 1),
      };
    default:
      return <String, Object?>{
        for (var index = 0; index < random.nextInt(5); index += 1)
          'k$index': _value(random, depth + 1),
      };
  }
}

Object? _leaf(Random random) => switch (random.nextInt(5)) {
  0 => null,
  1 => random.nextBool(),
  2 => random.nextInt(1000) - 500,
  3 => 'value-${random.nextInt(100)}',
  _ => (random.nextInt(10), flag: random.nextBool()),
};

Object? _equivalentCopy(Object? value, Random random) {
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _equivalentCopy(item, random)];
  }
  if (value is Set<Object?>) {
    final values = <Object?>[
      for (final item in value) _equivalentCopy(item, random),
    ]..shuffle(random);
    return values.toSet();
  }
  if (value is Map<Object?, Object?>) {
    final entries = value.entries.toList()..shuffle(random);
    return <Object?, Object?>{
      for (final entry in entries)
        _equivalentCopy(entry.key, random): _equivalentCopy(
          entry.value,
          random,
        ),
    };
  }
  return value;
}
