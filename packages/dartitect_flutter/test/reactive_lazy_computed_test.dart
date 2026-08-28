import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'first read evaluates and unobserved dependency changes only dirty',
    () async {
      final owner = ReactiveOwner();
      final input = owner.value(1);
      var computes = 0;
      final lazy = owner.lazyComputed<int>(
        label: 'test.lazy.double',
        dependencies: () => <ValueListenable<Object?>>[input],
        compute: (read) {
          computes += 1;
          return read.read(input) * 2;
        },
      );

      expect(computes, 0);
      expect(lazy.hasValue, isFalse);
      expect(lazy.value, 2);
      expect(computes, 1);
      expect(input.listenerCount, 1);

      owner.update<void>((write) => write.set(input, 2));
      expect(lazy.isDirty, isTrue);
      expect(computes, 1);
      expect(lazy.value, 4);
      expect(computes, 2);

      await owner.dispose();
      expect(owner.diagnostics.nodeCount, 0);
      expect(owner.diagnostics.edgeCount, 0);
      expect(input.listenerCount, 0);
      expect(() => lazy.value, throwsStateError);
    },
  );

  test(
    'observed lazy recomputes after atomic commit and honors equality',
    () async {
      final owner = ReactiveOwner();
      final left = owner.value(1);
      final right = owner.value(2);
      var notifications = 0;
      final lazy = owner.lazyComputed<int>(
        label: 'test.lazy.sum-parity',
        dependencies: () => <ValueListenable<Object?>>[left, right],
        compute: (read) => (read.read<int>(left) + read.read<int>(right)) % 2,
      )..addListener(() => notifications += 1);

      owner.update<void>((write) {
        write
          ..set(left, 3)
          ..set(right, 4);
      });
      expect(lazy.value, 1);
      expect(notifications, 0);

      owner.update<void>((write) => write.set(right, 5));
      expect(lazy.value, 0);
      expect(notifications, 1);
      await owner.dispose();
    },
  );

  test(
    'failed observed recompute retains last value and remains dirty',
    () async {
      final reporter = _Reporter();
      final owner = ReactiveOwner(reporter: reporter);
      final input = owner.value(1);
      var notifications = 0;
      final lazy = owner.lazyComputed<int>(
        label: 'test.lazy.failure',
        dependencies: () => <ValueListenable<Object?>>[input],
        compute: (read) {
          final value = read.read(input);
          if (value == 2) throw StateError('expected test crash');
          return value * 10;
        },
      )..addListener(() => notifications += 1);

      expect(lazy.value, 10);
      owner.update<void>((write) => write.set(input, 2));
      expect(lazy.hasValue, isTrue);
      expect(lazy.isDirty, isTrue);
      expect(notifications, 0);
      expect(reporter.errors, hasLength(1));
      expect(() => lazy.value, throwsStateError);

      owner.update<void>((write) => write.set(input, 3));
      expect(lazy.value, 30);
      expect(lazy.isDirty, isFalse);
      expect(notifications, 1);
      await owner.dispose();
    },
  );

  test(
    'explicit cyclic lazy dependencies fail without implicit tracking',
    () async {
      final owner = ReactiveOwner();
      late final ReactiveLazyComputed<int> first;
      late final ReactiveLazyComputed<int> second;
      first = owner.lazyComputed<int>(
        label: 'test.lazy.first',
        dependencies: () => <ValueListenable<Object?>>[second],
        compute: (read) => read.read(second) + 1,
      );
      second = owner.lazyComputed<int>(
        label: 'test.lazy.second',
        dependencies: () => <ValueListenable<Object?>>[first],
        compute: (read) => read.read(first) + 1,
      );

      expect(() => first.value, throwsA(isA<ReactiveCycleException>()));
      await owner.dispose();
      expect(owner.diagnostics.nodeCount, 0);
    },
  );

  test('hot reload rebind preserves value and refreshes closures', () async {
    final owner = ReactiveOwner();
    final input = owner.value(2);
    var factor = 2;
    int compute(ReactiveLazyRead read) => read.read(input) * factor;
    final lazy = owner.lazyComputed<int>(
      label: 'test.lazy.rebind',
      dependencies: () => <ValueListenable<Object?>>[input],
      compute: compute,
    );
    expect(lazy.value, 4);

    factor = 3;
    lazy.rebind(
      dependencies: () => <ValueListenable<Object?>>[input],
      compute: compute,
    );
    expect(lazy.isDirty, isTrue);
    expect(lazy.value, 6);
    await owner.dispose();
  });
}

final class _Reporter implements ReactiveComputeReporter {
  final List<Object> errors = <Object>[];

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}
