import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  group('ResourceOwner', () {
    test('releases mixed resources once in LIFO order', () async {
      final releases = <String>[];
      final owner = ResourceOwner();
      owner
        ..own('first', (value) => releases.add(value), label: 'first')
        ..own('second', (value) async {
          await Future<void>.value();
          releases.add(value);
        }, label: 'second');

      final firstDisposal = owner.disposeAsync();
      final secondDisposal = owner.disposeAsync();
      expect(secondDisposal, same(firstDisposal));
      await firstDisposal;
      await owner.disposeAsync();

      expect(releases, <String>['second', 'first']);
      expect(owner.isDisposed, isTrue);
      expect(owner.isDisposing, isFalse);
    });

    test('closes registration immediately when shutdown starts', () async {
      final release = Completer<void>();
      final owner = ResourceOwner()
        ..own('resource', (_) => release.future, label: 'resource');

      final disposal = owner.disposeAsync();
      expect(owner.isDisposing, isTrue);
      expect(() => owner.own('late', (_) {}, label: 'late'), throwsStateError);
      release.complete();
      await disposal;
    });

    test('reentrant disposal from a release callback shares one run', () async {
      final owner = ResourceOwner();
      Future<void>? nestedDisposal;
      var calls = 0;
      owner.own('resource', (_) {
        calls += 1;
        nestedDisposal = owner.disposeAsync();
      });

      final disposal = owner.disposeAsync();
      await disposal;

      expect(nestedDisposal, same(disposal));
      expect(calls, 1);
    });

    test('attempts every cleanup and aggregates failures', () async {
      final calls = <String>[];
      final firstError = StateError('first failure');
      final owner = ResourceOwner()
        ..own('first', (_) {
          calls.add('first');
          throw firstError;
        }, label: 'first')
        ..own('second', (_) {
          calls.add('second');
          throw ArgumentError('second failure');
        }, label: 'second');

      try {
        await owner.disposeAsync();
        fail('Expected ResourceCleanupException.');
      } on ResourceCleanupException catch (error) {
        expect(calls, <String>['second', 'first']);
        expect(error.failures, hasLength(2));
        expect(error.first.resourceLabel, 'second');
        expect(error.failures.last.error, same(firstError));
        expect(
          error.failures.every(
            (failure) => failure.stackTrace != StackTrace.empty,
          ),
          isTrue,
        );
      }
      expect(owner.isDisposed, isTrue);
    });

    test('supports rollback after a partial acquisition failure', () async {
      final releases = <String>[];
      final owner = ResourceOwner();

      await expectLater(() async {
        try {
          owner.own('opened', releases.add, label: 'opened');
          throw StateError('second acquisition failed');
        } finally {
          await owner.disposeAsync();
        }
      }, throwsStateError);

      expect(releases, <String>['opened']);
    });

    test(
      'emits events without allowing observer failure to break cleanup',
      () async {
        final observer = _ThrowingObserver();
        final owner = ResourceOwner(observer: observer)..own('value', (_) {});

        await owner.disposeAsync();

        expect(owner.isDisposed, isTrue);
        expect(observer.calls, greaterThan(0));
      },
    );
  });
}

final class _ThrowingObserver implements ArchitectureObserver {
  int calls = 0;

  @override
  void onEvent(ArchitectureEvent event) {
    calls += 1;
    throw StateError('observer failure');
  }
}
