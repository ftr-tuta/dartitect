import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'values are direct ValueListenables with configurable equality',
    () async {
      final owner = ReactiveOwner();
      final value = owner.value<List<int>>(const <int>[
        1,
      ], equality: (previous, next) => previous.length == next.length);
      final ValueListenable<List<int>> listenable = value;
      var notifications = 0;
      listenable.addListener(() => notifications += 1);

      owner.update<void>((write) => write.set(value, const <int>[9]));
      expect(value.value, const <int>[1]);
      expect(notifications, 0);
      expect(owner.revision, 0);

      owner.update<void>((write) => write.set(value, const <int>[9, 10]));
      expect(value.value, const <int>[9, 10]);
      expect(notifications, 1);
      await owner.dispose();
    },
  );

  test('outer and nested updates publish one stable diamond cycle', () async {
    final owner = ReactiveOwner();
    final left = owner.value(1);
    final right = owner.value(2);
    var sumComputes = 0;
    var labelComputes = 0;
    final sum = owner.computed<int>(
      const ReactiveKey<int>(
        'sum',
        namespace: 'test.diamond',
        definitionRevision: 1,
        definitionFingerprint: 'sum-v1',
      ),
      <ReactiveNode<Object?>>[left, right],
      (read) {
        sumComputes += 1;
        return read.read(left) + read.read(right);
      },
    );
    final label = owner.computed<String>(
      const ReactiveKey<String>(
        'label',
        namespace: 'test.diamond',
        definitionRevision: 1,
        definitionFingerprint: 'label-v1',
      ),
      <ReactiveNode<Object?>>[sum],
      (read) {
        labelComputes += 1;
        return 'sum:${read.read(sum)}';
      },
    );
    final notifications = <String>[];
    left.addListener(() => notifications.add('left:${left.value}'));
    sum.addListener(() => notifications.add('sum:${sum.value}'));
    label.addListener(() => notifications.add(label.value));

    owner.update<void>((write) {
      write.set(left, 3);
      owner.update<void>((nested) {
        nested.set(right, 4);
        nested.set(left, 5);
      });
    });

    expect(sum.value, 9);
    expect(label.value, 'sum:9');
    expect(sumComputes, 2);
    expect(labelComputes, 2);
    expect(notifications, <String>['left:5', 'sum:9', 'sum:9']);
    expect(owner.revision, 1);
    expect(left.revision, 1);
    expect(sum.revision, 1);
    await owner.dispose();
  });

  test(
    'compute crash rolls back and emits a payload-free crash event',
    () async {
      final reporter = _Reporter();
      final journal = ReactiveJournal(capacity: 4);
      final clock = _SequenceClock(<int>[100, 125, 200, 225]);
      final owner = ReactiveOwner(
        reporter: reporter,
        observer: ReactiveObserverRegistration.borrowed(journal),
        monotonicMicroseconds: clock.now,
      );
      final input = owner.value(1);
      final stable = owner.computed<int>(
        const ReactiveKey<int>(
          'stable',
          namespace: 'test.rollback',
          definitionRevision: 1,
          definitionFingerprint: 'stable-v1',
        ),
        <ReactiveNode<Object?>>[input],
        (read) {
          final value = read.read(input);
          if (value == 2) throw StateError('compute failed');
          return value * 10;
        },
      );
      var notifications = 0;
      input.addListener(() => notifications += 1);
      stable.addListener(() => notifications += 1);

      expect(
        () => owner.update<void>((write) => write.set(input, 2)),
        throwsA(isA<StateError>()),
      );

      expect(input.value, 1);
      expect(stable.value, 10);
      expect(owner.revision, 0);
      expect(notifications, 0);
      expect(reporter.errors, hasLength(1));
      expect(journal.entries, hasLength(1));
      expect(journal.entries.single.kind, ReactiveEventKind.crashed);
      expect(journal.entries.single.previousRevision, 0);
      expect(journal.entries.single.nextRevision, 0);
      expect(journal.entries.single.duration, const Duration(microseconds: 25));

      owner.update<void>((write) => write.set(input, 3));
      expect(stable.value, 30);
      expect(owner.revision, 1);
      expect(journal.entries, hasLength(2));
      expect(journal.entries.last.kind, ReactiveEventKind.updated);
      expect(journal.entries.last.previousRevision, 0);
      expect(journal.entries.last.nextRevision, 1);
      await owner.dispose();
    },
  );

  test('listener reentrancy is deferred to a second logical cycle', () {
    final owner = ReactiveOwner();
    final value = owner.value(0);
    final observed = <int>[];
    value.addListener(() {
      observed.add(value.value);
      if (value.value == 1) {
        owner.update<void>((write) => write.set(value, 2));
      }
    });

    owner.update<void>((write) => write.set(value, 1));

    expect(observed, <int>[1, 2]);
    expect(value.value, 2);
    expect(owner.revision, 2);
  });

  test('write from compute is rejected without publishing a partial graph', () {
    final owner = ReactiveOwner();
    final input = owner.value(1);
    final sideEffect = owner.value(0);
    var attemptedWrite = false;
    final derived = owner.computed<int>(
      const ReactiveKey<int>(
        'write-during-compute',
        namespace: 'test.phases',
        definitionRevision: 1,
        definitionFingerprint: 'write-during-compute-v1',
      ),
      <ReactiveNode<Object?>>[input, sideEffect],
      (read) {
        expect(owner.phase, ReactiveOwnerPhase.compute);
        final current = read.read(input);
        if (current == 2 && !attemptedWrite) {
          attemptedWrite = true;
          owner.update<void>((write) => write.set(sideEffect, 99));
        }
        return current + read.read(sideEffect);
      },
    );
    final notifications = <int>[];
    derived.addListener(() => notifications.add(derived.value));

    expect(
      () => owner.update<void>((write) => write.set(input, 2)),
      throwsStateError,
    );

    expect(input.value, 1);
    expect(sideEffect.value, 0);
    expect(derived.value, 1);
    expect(owner.revision, 0);
    expect(notifications, isEmpty);

    owner.update<void>((write) {
      expect(owner.phase, ReactiveOwnerPhase.write);
      write.set(input, 3);
    });
    expect(derived.value, 3);
    expect(owner.revision, 1);
    expect(owner.phase, ReactiveOwnerPhase.idle);
  });

  test('listener failure is reported without changing mutation outcome', () {
    final reporter = _Reporter();
    final owner = ReactiveOwner(reporter: reporter);
    final value = owner.value(0);
    var healthyListenerCalls = 0;
    value
      ..addListener(() => throw StateError('listener failed'))
      ..addListener(() {
        expect(owner.phase, ReactiveOwnerPhase.notify);
        healthyListenerCalls += 1;
      });

    final outcome = owner.update<String>((write) {
      write.set(value, 1);
      return 'committed';
    });

    expect(outcome, 'committed');
    expect(value.value, 1);
    expect(value.revision, 1);
    expect(owner.revision, 1);
    expect(healthyListenerCalls, 1);
    expect(reporter.errors, hasLength(1));
    expect(reporter.errors.single, isA<StateError>());
    expect(owner.phase, ReactiveOwnerPhase.idle);
  });

  test('reporter failure after listener failure is isolated', () {
    final owner = ReactiveOwner(reporter: const _ThrowingReporter());
    final value = owner.value(0)
      ..addListener(() => throw StateError('listener failed'));

    expect(
      owner.update<String>((write) {
        write.set(value, 1);
        return 'committed';
      }),
      'committed',
    );
    expect(value.value, 1);
    expect(owner.revision, 1);
  });

  test('custom equality cannot write during snapshot computation', () {
    final reporter = _Reporter();
    final owner = ReactiveOwner(reporter: reporter);
    late final ReactiveValue<int> sideEffect;
    var attemptedWrite = false;
    final value = owner.value<int>(
      0,
      equality: (previous, next) {
        expect(owner.phase, ReactiveOwnerPhase.compute);
        if (next == 1 && !attemptedWrite) {
          attemptedWrite = true;
          owner.update<void>((write) => write.set(sideEffect, 99));
        }
        return previous == next;
      },
    );
    sideEffect = owner.value(0);

    expect(
      () => owner.update<void>((write) => write.set(value, 1)),
      throwsStateError,
    );
    expect(value.value, 0);
    expect(sideEffect.value, 0);
    expect(owner.revision, 0);
    expect(reporter.errors, hasLength(1));
    expect(owner.phase, ReactiveOwnerPhase.idle);
  });

  test(
    'dispose during notify is terminal and leaves no residual graph',
    () async {
      final owner = ReactiveOwner();
      final value = owner.value(0);
      value.addListener(owner.dispose);

      owner.update<void>((write) => write.set(value, 1));
      await owner.dispose();

      expect(owner.phase, ReactiveOwnerPhase.disposed);
      expect(owner.diagnostics.nodeCount, 0);
      expect(owner.diagnostics.listenerCount, 0);
      expect(owner.diagnostics.pendingWriteCount, 0);
      expect(() => value.value, throwsStateError);
    },
  );

  test('dispose during write is rejected and the transaction rolls back', () {
    final owner = ReactiveOwner();
    final value = owner.value(0);

    expect(
      () => owner.update<void>((write) {
        write.set(value, 1);
        unawaited(owner.dispose());
      }),
      throwsStateError,
    );

    expect(value.value, 0);
    expect(owner.revision, 0);
    expect(owner.phase, ReactiveOwnerPhase.idle);
    expect(owner.isDisposed, isFalse);
  });

  test('compatible key reuse refreshes the computed definition closure', () {
    final owner = ReactiveOwner();
    final input = owner.value(1);
    const key = ReactiveKey<int>(
      'reassembled-definition',
      namespace: 'test.reassembly',
      definitionRevision: 1,
      definitionFingerprint: 'multiply-v1',
    );

    int Function(ReactiveRead) definition(int factor) =>
        (read) => read.read(input) * factor;

    final computed = owner.computed<int>(key, <ReactiveNode<Object?>>[
      input,
    ], definition(2));
    final rebound = owner.computed<int>(key, <ReactiveNode<Object?>>[
      input,
    ], definition(3));
    expect(rebound, same(computed));

    owner.update<void>((write) => write.set(input, 2));

    expect(computed.value, 6);
    expect(owner.revision, 1);
  });

  test('typed keys share only compatible nodes and dependencies', () async {
    final owner = ReactiveOwner();
    final otherOwner = ReactiveOwner();
    const valueKey = ReactiveKey<int>(
      'value',
      namespace: 'test.keys',
      definitionRevision: 1,
      definitionFingerprint: 'value-v1',
    );
    const computedKey = ReactiveKey<int>(
      'computed',
      namespace: 'test.keys',
      definitionRevision: 1,
      definitionFingerprint: 'computed-v1',
    );
    final value = owner.value(1, key: valueKey);
    expect(owner.value(999, key: valueKey), same(value));
    expect(otherOwner.value(7, key: valueKey), isNot(same(value)));
    const otherNamespace = ReactiveKey<int>(
      'value',
      namespace: 'test.other-keys',
      definitionRevision: 1,
      definitionFingerprint: 'value-v1',
    );
    expect(owner.value(2, key: otherNamespace), isNot(same(value)));
    const incompatibleValueKey = ReactiveKey<int>(
      'value',
      namespace: 'test.keys',
      definitionRevision: 2,
      definitionFingerprint: 'value-v2',
    );
    expect(
      () => owner.value(2, key: incompatibleValueKey),
      throwsA(
        isA<ReactiveKeyConflictException>()
            .having((error) => error.key, 'key', valueKey.identity)
            .having(
              (error) => error.existingDefinition,
              'existing definition',
              valueKey.definition,
            )
            .having(
              (error) => error.incomingDefinition,
              'incoming definition',
              incompatibleValueKey.definition,
            ),
      ),
    );
    final computed = owner.computed<int>(computedKey, <ReactiveNode<Object?>>[
      value,
    ], (read) => read.read(value) + 1);
    expect(
      owner.computed<int>(computedKey, <ReactiveNode<Object?>>[
        value,
      ], (read) => -1),
      same(computed),
    );
    final other = owner.value(0);
    expect(
      () => owner.computed<int>(computedKey, <ReactiveNode<Object?>>[
        other,
      ], (read) => read.read(other)),
      throwsA(isA<ReactiveKeyConflictException>()),
    );
    await Future.wait(<Future<void>>[owner.dispose(), otherOwner.dispose()]);
  });

  test(
    'attempted definition cycle is rejected without changing the graph',
    () async {
      final owner = ReactiveOwner();
      final source = owner.value(1);
      const firstKey = ReactiveKey<int>(
        'first',
        namespace: 'test.cycles',
        definitionRevision: 1,
        definitionFingerprint: 'first-v1',
      );
      const secondKey = ReactiveKey<int>(
        'second',
        namespace: 'test.cycles',
        definitionRevision: 1,
        definitionFingerprint: 'second-v1',
      );
      final first = owner.computed<int>(firstKey, <ReactiveNode<Object?>>[
        source,
      ], (read) => read.read(source) + 1);
      final second = owner.computed<int>(secondKey, <ReactiveNode<Object?>>[
        first,
      ], (read) => read.read(first) + 1);

      expect(
        () => owner.computed<int>(firstKey, <ReactiveNode<Object?>>[
          second,
        ], (read) => read.read(second) + 1),
        throwsA(isA<ReactiveKeyConflictException>()),
      );

      owner.update<void>((write) => write.set(source, 2));
      expect(first.value, 3);
      expect(second.value, 4);
      expect(owner.revision, 1);
      await owner.dispose();
    },
  );

  test(
    'foreign reads fail and dispose leaves no retained graph state',
    () async {
      final owner = ReactiveOwner();
      final foreignOwner = ReactiveOwner();
      final local = owner.value(1);
      final foreign = foreignOwner.value(2);
      expect(
        () => owner.computed<int>(
          const ReactiveKey<int>(
            'foreign',
            namespace: 'test.ownership',
            definitionRevision: 1,
            definitionFingerprint: 'foreign-v1',
          ),
          <ReactiveNode<Object?>>[foreign],
          (read) => read.read(foreign),
        ),
        throwsArgumentError,
      );
      final computed = owner.computed<int>(
        const ReactiveKey<int>(
          'local',
          namespace: 'test.ownership',
          definitionRevision: 1,
          definitionFingerprint: 'local-v1',
        ),
        <ReactiveNode<Object?>>[local],
        (read) => read.read(local),
      );
      computed.addListener(() {});
      expect(owner.diagnostics.nodeCount, 2);
      expect(owner.diagnostics.edgeCount, 1);
      expect(owner.diagnostics.listenerCount, 1);

      await Future.wait(<Future<void>>[owner.dispose(), owner.dispose()]);

      expect(owner.diagnostics.nodeCount, 0);
      expect(owner.diagnostics.edgeCount, 0);
      expect(owner.diagnostics.listenerCount, 0);
      expect(owner.diagnostics.pendingWriteCount, 0);
      expect(owner.isDisposed, isTrue);
      expect(() => local.value, throwsStateError);
      await foreignOwner.dispose();
    },
  );

  test('emits one static causal event with revisions and duration', () async {
    const cause = ChangeCause('feature.edit', 'Feature edit');
    final journal = ReactiveJournal(capacity: 4);
    final clock = _SequenceClock(<int>[100, 125]);
    final owner = ReactiveOwner(
      observer: ReactiveObserverRegistration.owned(
        journal,
        dispose: journal.dispose,
      ),
      causeRegistry: ChangeCauseRegistry(
        causes: const <ChangeCause>[...ChangeCauses.values, cause],
      ),
      monotonicMicroseconds: clock.now,
    );
    final value = owner.value(0)..addListener(() {});

    owner.update<void>((write) => write.set(value, 1), cause: cause);

    expect(journal.entries, hasLength(1));
    final event = journal.entries.single;
    expect(event.source, ReactiveEventSource.reactiveOwner);
    expect(event.kind, ReactiveEventKind.updated);
    expect(event.cause, same(cause));
    expect(event.previousRevision, 0);
    expect(event.nextRevision, 1);
    expect(event.duration, const Duration(microseconds: 25));
    expect(event.listenerCount, 1);

    await owner.dispose();
    expect(journal.isDisposed, isTrue);
  });

  test(
    'dynamic cause and failing observer never alter graph behavior',
    () async {
      final reporter = _Reporter();
      var observerCalls = 0;
      final owner = ReactiveOwner(
        reporter: reporter,
        observer: ReactiveObserverRegistration.borrowed(
          _ReactiveObserver((event) {
            observerCalls += 1;
            throw StateError('observer unavailable');
          }),
        ),
      );
      final value = owner.value(0);
      final dynamicCause = ChangeCause(
        <String>['reactive', 'update'].join('.'),
        'Reactive update',
      );

      expect(
        () => owner.update<void>(
          (write) => write.set(value, 99),
          cause: dynamicCause,
        ),
        throwsArgumentError,
      );
      expect(value.value, 0);
      owner.update<void>((write) => write.set(value, 1));
      owner.update<void>((write) => write.set(value, 2));

      expect(value.value, 2);
      expect(owner.revision, 2);
      expect(observerCalls, 1);
      expect(owner.observerFailureCount, 1);
      expect(reporter.errors, hasLength(1));
      await owner.dispose();
    },
  );
}

final class _Reporter implements ReactiveComputeReporter {
  final List<Object> errors = <Object>[];

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}

final class _ThrowingReporter implements ReactiveComputeReporter {
  const _ThrowingReporter();

  @override
  void report(Object error, StackTrace stackTrace) {
    throw StateError('reporter failed');
  }
}

final class _SequenceClock {
  _SequenceClock(this.values);

  final List<int> values;
  var _index = 0;

  int now() => values[_index++];
}

final class _ReactiveObserver implements ReactiveObserver {
  const _ReactiveObserver(this.callback);

  final void Function(ReactiveChangeEvent event) callback;

  @override
  void onChange(ReactiveChangeEvent event) => callback(event);
}
