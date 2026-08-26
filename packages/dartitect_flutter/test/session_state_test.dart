import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session state is replayable and terminally owned', () {
    final controller = SessionStateController<_Session>(
      const SessionAnonymous<_Session>(),
    );
    final observed = <SessionState<_Session>>[];
    controller.addListener(() => observed.add(controller.value));
    final generation = Object();

    controller.transition(
      SessionActive<_Session>(
        generation: generation,
        value: const _Session('member'),
      ),
    );
    controller.transition(
      const SessionTransitioning<_Session>(SessionTransitionCause.forcedLogout),
    );
    controller.transition(const SessionForcedLogout<_Session>());
    controller.transition(const SessionSignedOut<_Session>());

    expect(observed, hasLength(4));
    expect(controller.value, isA<SessionSignedOut<_Session>>());
    controller.dispose();
    expect(
      () => controller.transition(const SessionAnonymous<_Session>()),
      throwsStateError,
    );
  });
}

final class _Session {
  const _Session(this.role);

  final String role;

  @override
  bool operator ==(Object other) => other is _Session && other.role == role;

  @override
  int get hashCode => role.hashCode;
}
