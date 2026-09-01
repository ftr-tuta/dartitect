import 'package:dartitect_flutter/src/reactive/listener_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'removal skips a pending listener and addition waits for next dispatch',
    () {
      final registry = ListenerRegistry();
      final calls = <String>[];
      late void Function() second;
      void lateListener() => calls.add('late');
      void first() {
        calls.add('first');
        registry
          ..remove(second)
          ..add(lateListener);
      }

      second = () => calls.add('second');
      registry
        ..add(first)
        ..add(second)
        ..notifySafely();

      expect(calls, <String>['first']);
      registry.notifySafely();
      expect(calls, <String>['first', 'first', 'late']);
    },
  );

  test('nested dispatch is stable and listener failures are isolated', () {
    final registry = ListenerRegistry();
    final calls = <String>[];
    final failures = <Object>[];
    var nested = false;
    void first() {
      calls.add('first');
      if (!nested) {
        nested = true;
        registry.notifySafely(onFailure: (error, _) => failures.add(error));
      }
    }

    registry
      ..add(first)
      ..add(() => throw StateError('listener failed'))
      ..add(() => calls.add('last'))
      ..notifySafely(onFailure: (error, _) => failures.add(error));

    expect(calls, <String>['first', 'first', 'last', 'last']);
    expect(failures, hasLength(2));
  });

  test('duplicate registrations are removed one at a time by identity', () {
    final registry = ListenerRegistry();
    var calls = 0;
    void listener() => calls += 1;

    registry
      ..add(listener)
      ..add(listener);
    expect(registry.length, 2);
    expect(registry.remove(listener), isTrue);
    registry.notifySafely();

    expect(calls, 1);
    expect(registry.length, 1);
  });
}
