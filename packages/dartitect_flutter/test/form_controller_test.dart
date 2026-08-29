import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter_forms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tracks original/current, touched, history, drafts, and submit',
    () async {
      final drafts = _Drafts();
      final submitted = <String>[];
      final controller = DartitectFormController<String, _Failure>(
        original: 'one',
        equals: (left, right) => left == right,
        syncValidator: (value) => value.isEmpty
            ? Err<_Failure>(const _Failure('required'), StackTrace.current)
            : const Ok<void>(null),
        submitter: (value, cancellation) async {
          cancellation.throwIfCancelled();
          submitted.add(value);
          return const Ok<void>(null);
        },
        drafts: drafts,
        draftVersion: 2,
      );

      controller.update('two');
      expect(controller.snapshot.dirty, isTrue);
      expect(controller.snapshot.touched, isTrue);
      expect(controller.undo(), isTrue);
      expect(controller.snapshot.current, 'one');
      expect(controller.redo(), isTrue);
      expect(await controller.saveDraft(), isA<Ok<void>>());

      controller.reset();
      expect((await controller.restoreDraft() as Ok<bool>).value, isTrue);
      expect(controller.snapshot.current, 'two');
      expect(await controller.submit(), isA<Ok<void>>());
      expect(submitted, <String>['two']);
      expect(controller.snapshot.dirty, isFalse);
      expect(drafts.value, isNull);
      await controller.disposeAsync();
    },
  );

  test(
    'async validation is restart-latest and disposal cancels work',
    () async {
      final validations = <Completer<Result<void, _Failure>>>[];
      final controller = DartitectFormController<String, _Failure>(
        original: 'one',
        equals: (left, right) => left == right,
        asyncValidator: (value, cancellation) {
          final completer = Completer<Result<void, _Failure>>();
          validations.add(completer);
          cancellation.register((reason) {
            if (!completer.isCompleted) {
              completer.completeError(CancellationException(reason));
            }
          });
          return completer.future;
        },
        submitter: (_, _) async => const Ok<void>(null),
      );

      final first = controller.validate();
      final firstFailure = expectLater(
        first,
        throwsA(isA<CancellationException>()),
      );
      controller.update('two');
      final second = controller.validate();
      validations.last.complete(const Ok<void>(null));
      await firstFailure;
      expect(await second, isA<Ok<void>>());
      expect(controller.snapshot.phase, DartitectFormPhase.idle);
      await controller.disposeAsync();
    },
  );
}

final class _Failure {
  const _Failure(this.message);

  final String message;
}

final class _Drafts implements DartitectFormDraftStore<String, _Failure> {
  DartitectFormDraft<String>? value;

  @override
  Future<Result<void, _Failure>> clear(CancellationSignal cancellation) async {
    value = null;
    return const Ok<void>(null);
  }

  @override
  Future<Result<DartitectFormDraft<String>?, _Failure>> load(
    CancellationSignal cancellation,
  ) async => Ok<DartitectFormDraft<String>?>(value);

  @override
  Future<Result<void, _Failure>> save(
    DartitectFormDraft<String> draft,
    CancellationSignal cancellation,
  ) async {
    value = draft;
    return const Ok<void>(null);
  }
}
