import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('history bounds undo and drops redo after a new edit', () {
    final history = BoundedLocalHistory<int>(initialValue: 0, maxEntries: 3);

    history
      ..edit(1)
      ..edit(2)
      ..edit(3);
    expect(history.undoValues, <int>[1, 2]);
    expect(history.undo(), isTrue);
    expect(history.value, 2);
    expect(history.canRedo, isTrue);
    expect(history.edit(4), isTrue);
    expect(history.canRedo, isFalse);
    expect(history.undoValues, <int>[1, 2]);
  });

  test('weight bound trims oldest values and rejects oversized values', () {
    final history = BoundedLocalHistory<String>(
      initialValue: 'a',
      maxEntries: 10,
      maxWeight: 5,
      weightOf: (value) => value.length,
    );

    history
      ..edit('bb')
      ..edit('ccc');
    expect(history.undoValues, <String>['bb']);
    expect(history.retainedWeight, 5);
    expect(() => history.edit('123456'), throwsArgumentError);
  });

  test('retained weight is cached across reads and history navigation', () {
    var weightCalls = 0;
    final history = BoundedLocalHistory<String>(
      initialValue: 'a',
      weightOf: (value) {
        weightCalls += 1;
        return value.length;
      },
    )..edit('bb');

    expect(weightCalls, 2);
    expect(history.retainedWeight, 3);
    expect(history.retainedWeight, 3);
    history
      ..undo()
      ..redo();
    expect(history.retainedWeight, 3);
    expect(weightCalls, 2);
  });

  test('history rejects executable values and clears on disposal', () {
    expect(
      () => BoundedLocalHistory<Object>(initialValue: () {}),
      throwsArgumentError,
    );
    expect(
      () => BoundedLocalHistory<Object>(initialValue: Future<void>.value()),
      throwsArgumentError,
    );
    expect(
      () =>
          BoundedLocalHistory<Object>(initialValue: const Stream<void>.empty()),
      throwsArgumentError,
    );

    final history = BoundedLocalHistory<int>(initialValue: 1)..edit(2);
    history.dispose();
    expect(history.retainedEntryCount, 0);
    expect(() => history.value, throwsStateError);
  });
}
