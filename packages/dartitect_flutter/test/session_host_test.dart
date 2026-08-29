import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replacement publishes only after typed route success', () async {
    final controller = SessionRuntimeController<String, _Session>();
    final disposals = <String>[];
    await controller.signIn(const _Session('one'), (transaction) {
      transaction.own('one', disposals.add);
      return 'one';
    });
    final replacing = controller.replace(const _Session('two'), (transaction) {
      transaction.own('two', disposals.add);
      return 'two';
    });
    await _waitForRequest(controller);

    final request = controller.pendingRouteRemovalRequest!;
    expect(request.transitionId, greaterThan(0));
    expect(request.cancellation.isCancelled, isFalse);
    expect(disposals, isEmpty);
    expect(
      controller.completeRouteRemoval(
        request.transitionId + 1,
        const SessionRouteRemovalSucceeded(),
      ),
      isFalse,
    );
    expect(
      controller.completeRouteRemoval(
        request.transitionId,
        const SessionRouteRemovalSucceeded(),
      ),
      isTrue,
    );

    expect(await replacing, 2);
    expect(disposals, <String>['one']);
    expect(controller.current, 'two');
    await controller.disposeAsync();
    expect(disposals, <String>['one', 'two']);
  });

  test(
    'typed route failure discards new graph and preserves old graph',
    () async {
      final controller = SessionRuntimeController<String, _Session>();
      final disposals = <String>[];
      await controller.signIn(const _Session('one'), (transaction) {
        transaction.own('one', disposals.add);
        return 'one';
      });
      final replacing = controller.replace(const _Session('two'), (
        transaction,
      ) {
        transaction.own('two', disposals.add);
        return 'two';
      });
      await _waitForRequest(controller);
      final request = controller.pendingRouteRemovalRequest!;
      final error = StateError('router rejected');
      final stack = StackTrace.current;
      controller.completeRouteRemoval(
        request.transitionId,
        SessionRouteRemovalFailed(error: error, stackTrace: stack),
      );

      await expectLater(
        replacing,
        throwsA(
          isA<SessionTransitionException>().having(
            (exception) => exception.failure.error,
            'original error',
            same(error),
          ),
        ),
      );
      expect(disposals, <String>['two']);
      expect(controller.current, 'one');
      expect(controller.state, isA<SessionTransitionFailed<_Session>>());
      expect(
        (controller.state as SessionTransitionFailed<_Session>).kind,
        SessionTransitionFailureKind.routeRemoval,
      );
      expect(controller.abortFailedTransition(), isTrue);
      expect(controller.state, isA<SessionActive<_Session>>());
      await controller.disposeAsync();
      expect(disposals, <String>['two', 'one']);
    },
  );

  test(
    'timeout releases queue, discards prepared graph, and permits retry',
    () async {
      final controller = SessionRuntimeController<String, _Session>(
        routeRemovalTimeout: const Duration(milliseconds: 20),
      );
      final disposals = <String>[];
      await controller.signIn(const _Session('one'), (transaction) {
        transaction.own('one', disposals.add);
        return 'one';
      });
      final replacing = controller.replace(const _Session('two'), (
        transaction,
      ) {
        transaction.own('two', disposals.add);
        return 'two';
      });
      await _waitForRequest(controller);
      final timedOutRequest = controller.pendingRouteRemovalRequest!;

      await expectLater(replacing, throwsA(isA<SessionTransitionException>()));
      expect(timedOutRequest.cancellation.isCancelled, isTrue);
      expect(disposals, <String>['two']);
      expect(controller.current, 'one');
      expect(
        controller.failedTransition?.kind,
        SessionTransitionFailureKind.deadlineExceeded,
      );

      final retry = controller.retryFailedTransition();
      await _waitForRequest(controller);
      final retryRequest = controller.pendingRouteRemovalRequest!;
      controller.completeRouteRemoval(
        retryRequest.transitionId,
        const SessionRouteRemovalSucceeded(),
      );
      await retry;
      expect(controller.current, 'two');
      await controller.disposeAsync();
    },
  );

  test(
    'dispose while waiting cancels route work and drains both graphs',
    () async {
      final controller = SessionRuntimeController<String, _Session>();
      final disposals = <String>[];
      await controller.signIn(const _Session('one'), (transaction) {
        transaction.own('one', disposals.add);
        return 'one';
      });
      final replacing = controller.replace(const _Session('two'), (
        transaction,
      ) {
        transaction.own('two', disposals.add);
        return 'two';
      });
      await _waitForRequest(controller);
      final request = controller.pendingRouteRemovalRequest!;
      final replacementFailure = expectLater(
        replacing,
        throwsA(isA<SessionTransitionException>()),
      );

      await controller.disposeAsync();
      await replacementFailure;
      expect(request.cancellation.isCancelled, isTrue);
      expect(disposals, containsAll(<String>['two', 'one']));
    },
  );

  test(
    'failed sign-out and force logout preserve graph and allow later work',
    () async {
      final controller = SessionRuntimeController<String, _Session>();
      await controller.signIn(const _Session('one'), (_) => 'one');

      final signOut = controller.signOut();
      await _waitForRequest(controller);
      var request = controller.pendingRouteRemovalRequest!;
      controller.completeRouteRemoval(
        request.transitionId,
        SessionRouteRemovalFailed(
          error: StateError('blocked'),
          stackTrace: StackTrace.current,
        ),
      );
      await expectLater(signOut, throwsA(isA<SessionTransitionException>()));
      expect(controller.current, 'one');

      final forced = controller.forceLogout(expired: true);
      await _waitForRequest(controller);
      request = controller.pendingRouteRemovalRequest!;
      controller.completeRouteRemoval(
        request.transitionId,
        const SessionRouteRemovalSucceeded(),
      );
      await forced;
      expect(controller.state, isA<SessionSignedOut<_Session>>());
      await controller.disposeAsync();
    },
  );

  test(
    'concurrent replacements serialize and each receives a new request',
    () async {
      final controller = SessionRuntimeController<String, _Session>();
      await controller.signIn(const _Session('one'), (_) => 'one');
      final second = controller.replace(const _Session('two'), (_) => 'two');
      final third = controller.replace(const _Session('three'), (_) => 'three');

      await _waitForRequest(controller);
      var request = controller.pendingRouteRemovalRequest!;
      controller.completeRouteRemoval(
        request.transitionId,
        const SessionRouteRemovalSucceeded(),
      );
      await second;
      await _waitForRequest(controller);
      request = controller.pendingRouteRemovalRequest!;
      controller.completeRouteRemoval(
        request.transitionId,
        const SessionRouteRemovalSucceeded(),
      );
      await third;
      expect(controller.current, 'three');
      await controller.disposeAsync();
    },
  );

  testWidgets(
    'host converts callback throw to typed failure with original stack',
    (tester) async {
      final controller = SessionRuntimeController<String, _Session>();
      final callbackError = StateError('route callback crashed');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SessionHost<String, _Session>.value(
            value: controller,
            removeRoutes: (_) async => throw callbackError,
            anonymous: (_) => const Text('anonymous'),
            transitioning: (_, state) => Text(state.runtimeType.toString()),
            active: (_, runtime, _) => Text(runtime),
          ),
        ),
      );
      await controller.signIn(const _Session('one'), (_) => 'one');
      await tester.pump();
      final logout = controller.forceLogout();
      final logoutFailure = expectLater(
        logout,
        throwsA(
          isA<SessionTransitionException>().having(
            (exception) => exception.failure.error,
            'original error',
            same(callbackError),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await logoutFailure;
      expect(controller.current, 'one');
      expect(controller.state, isA<SessionTransitionFailed<_Session>>());
      await tester.pumpWidget(const SizedBox());
      await controller.disposeAsync();
    },
  );
}

Future<void> _waitForRequest(
  SessionRuntimeController<String, _Session> controller,
) async {
  while (controller.pendingRouteRemovalRequest == null) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Session {
  const _Session(this.name);

  final String name;
}
