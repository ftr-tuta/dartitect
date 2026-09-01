import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Flutter crash composition sanitizes before its prepared destination',
    () async {
      final events = <PreparedErrorEvent>[];
      final runtime = ObservabilityRuntime.withPrivacy(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.diagnostic,
        ),
        destinations: <ObservabilityDestinationRegistration>[
          ObservabilityDestinationRegistration.local(
            errorReporters: <ErrorReporterRegistration>[
              ErrorReporterRegistration.borrowed(
                CallbackPreparedErrorReporter(events.add),
              ),
            ],
          ),
        ],
      );
      final reporter = CallbackFlutterCrashReporter((
        error,
        stackTrace,
        mechanism,
      ) async {
        await runtime.reporter.report(
          ErrorEvent(
            timestamp: DateTime.utc(2026),
            error: error,
            stackTrace: stackTrace,
            mechanism: switch (mechanism) {
              FlutterCrashMechanism.flutterFramework =>
                ErrorMechanism.flutterFramework,
              FlutterCrashMechanism.platformDispatcher =>
                ErrorMechanism.platformDispatcher,
              FlutterCrashMechanism.zone => ErrorMechanism.zone,
            },
            handled: false,
          ),
        );
      });
      final raw = _ExplosiveFlutterError();

      await reporter.report(
        raw,
        _ExplosiveStackTrace(),
        FlutterCrashMechanism.zone,
      );
      await runtime.flushDetailed();

      expect(raw.toStringCalls, 0);
      expect(events, hasLength(1));
      expect('${events.single.error}', contains('_ExplosiveFlutterError'));
      expect('${events.single.stackTrace}', isNot(contains('private stack')));
      await runtime.disposeAsync();
    },
  );
}

final class _ExplosiveFlutterError {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('private Flutter error');
  }
}

final class _ExplosiveStackTrace implements StackTrace {
  @override
  String toString() => throw StateError('private stack');
}
