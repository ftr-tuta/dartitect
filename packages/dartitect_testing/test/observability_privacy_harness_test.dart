import 'dart:async';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test('all profiles pass local, remote, named, and precedence matrices', () {
    for (final profile in ObservabilityPrivacyProfile.values) {
      final policy = ObservabilityPrivacyPolicy.fromProfile(
        profile: profile,
        destinationOverrides: <ObservabilityDestinationPrivacyOverrides>[
          ObservabilityDestinationPrivacyOverrides(
            name: 'support',
            kind: ObservabilityDestinationKind.remote,
            rules: ObservabilityPrivacyOverrides(
              allow: <ObservabilityDataClass>{ObservabilityDataClass.runId},
            ),
          ),
        ],
      );
      final harness = ObservabilityPrivacyPolicyHarness(policy);
      final emailActions = switch (profile) {
        ObservabilityPrivacyProfile.strict => <ObservabilityPrivacyAction>[
          ObservabilityPrivacyAction.deny,
          ObservabilityPrivacyAction.deny,
        ],
        ObservabilityPrivacyProfile.balanced => <ObservabilityPrivacyAction>[
          ObservabilityPrivacyAction.mask,
          ObservabilityPrivacyAction.deny,
        ],
        ObservabilityPrivacyProfile.diagnostic => <ObservabilityPrivacyAction>[
          ObservabilityPrivacyAction.mask,
          ObservabilityPrivacyAction.mask,
        ],
      };

      harness.verify(<ObservabilityPrivacyExpectation>[
        ObservabilityPrivacyExpectation(
          destination: ObservabilityDestinationKind.local,
          classes: <ObservabilityDataClass>{ObservabilityDataClass.safeCount},
          action: ObservabilityPrivacyAction.allow,
        ),
        ObservabilityPrivacyExpectation(
          destination: ObservabilityDestinationKind.remote,
          classes: <ObservabilityDataClass>{ObservabilityDataClass.safeCount},
          action: ObservabilityPrivacyAction.allow,
        ),
        ObservabilityPrivacyExpectation(
          destination: ObservabilityDestinationKind.local,
          classes: <ObservabilityDataClass>{ObservabilityDataClass.email},
          action: emailActions[0],
        ),
        ObservabilityPrivacyExpectation(
          destination: ObservabilityDestinationKind.remote,
          classes: <ObservabilityDataClass>{ObservabilityDataClass.email},
          action: emailActions[1],
        ),
        ObservabilityPrivacyExpectation(
          destination: ObservabilityDestinationKind.remote,
          destinationName: 'support',
          classes: <ObservabilityDataClass>{ObservabilityDataClass.runId},
          action: ObservabilityPrivacyAction.allow,
          source: ObservabilityPrivacyDecisionSource.namedDestinationOverride,
        ),
      ]);
      for (final destination in ObservabilityDestinationKind.values) {
        harness.verifyRestrictivePrecedence(
          destination: destination,
          denied: ObservabilityDataClass.secret,
          masked: ObservabilityDataClass.runId,
          allowed: ObservabilityDataClass.safeCount,
        );
      }
    }
  });

  test('prepared destination proves raw-data absence and ownership', () async {
    final local = RecordingObservabilityDestination(
      name: 'local',
      kind: ObservabilityDestinationKind.local,
    );
    final remote = RecordingObservabilityDestination(
      name: 'remote',
      kind: ObservabilityDestinationKind.remote,
    );
    final runtime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        local.registration(owned: true),
        remote.registration(),
      ],
    );
    final rawError = _ExplosiveError();

    runtime.logger.event(
      ObservabilityLogEvent(
        name: ObservabilityEventName('privacy.harness'),
        level: LogLevel.error,
        message: () => 'private-message-sentinel',
        error: rawError,
        stackTrace: _ExplosiveStackTrace(),
        context: ObservabilityContext(
          attributes: <String, Object?>{
            'email': ObservabilityClassifiedValue<Object?>(
              'private-email-sentinel@example.test',
              classes: <ObservabilityDataClass>{ObservabilityDataClass.email},
            ),
            'token': ObservabilityClassifiedValue<Object?>(
              'private-token-sentinel',
              classes: <ObservabilityDataClass>{ObservabilityDataClass.token},
            ),
          },
        ),
      ),
    );
    runtime.reporter.report(
      ErrorEvent(
        timestamp: DateTime.utc(2026),
        error: rawError,
        stackTrace: _ExplosiveStackTrace(),
      ),
    );
    final span = runtime.tracing.startSpan(
      'private-span-sentinel',
      attributes: <String, Object?>{
        'email': ObservabilityClassifiedValue<Object?>(
          'private-span-email@example.test',
          classes: <ObservabilityDataClass>{ObservabilityDataClass.email},
        ),
      },
    );
    await span.end(error: rawError, stackTrace: _ExplosiveStackTrace());
    expect((await runtime.flushDetailed()).completed, isTrue);

    expect(rawError.toStringCalls, 0);
    for (final destination in <RecordingObservabilityDestination>[
      local,
      remote,
    ]) {
      expectNoSensitiveObservabilityData(
        destination,
        sentinels: const <String>[
          'private-message-sentinel',
          'private-email-sentinel',
          'private-token-sentinel',
          'private-span-sentinel',
          'private-span-email',
          'private stack',
        ],
      );
    }

    await runtime.disposeAsync();
    expect(local.disposeCalls, 3);
    expect(remote.disposeCalls, 0);
  });

  test('slow and failing remote destinations remain isolated', () async {
    final gate = Completer<void>();
    final local = RecordingObservabilityDestination(
      name: 'local',
      kind: ObservabilityDestinationKind.local,
    );
    final slow = RecordingObservabilityDestination(
      name: 'slow_remote',
      kind: ObservabilityDestinationKind.remote,
      logGate: gate.future,
    );
    final runtime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        local.registration(includeErrors: false, includeTraces: false),
        slow.registration(
          includeErrors: false,
          includeTraces: false,
          queueCapacity: 1,
        ),
      ],
    );

    for (var index = 0; index < 4; index += 1) {
      runtime.logger.info('static event');
    }
    await Future<void>.delayed(Duration.zero);
    expect(local.logs, hasLength(4));
    expect(slow.logs, hasLength(1));
    expect(runtime.diagnostics.destinations['local']!.droppedEvents, 0);
    expect(runtime.diagnostics.destinations['slow_remote']!.droppedEvents, 3);
    final timed = await runtime.flushDetailed(Duration.zero);
    expect(timed.destinations['local']!.completed, isTrue);
    expect(timed.destinations['slow_remote']!.timedOut, isTrue);
    gate.complete();
    expect(await runtime.flush(const Duration(seconds: 1)), isTrue);
    await runtime.disposeAsync();

    final healthy = RecordingObservabilityDestination(
      name: 'healthy',
      kind: ObservabilityDestinationKind.local,
    );
    final failing = RecordingObservabilityDestination(
      name: 'failing_remote',
      kind: ObservabilityDestinationKind.remote,
      failLogs: true,
    );
    final failureRuntime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.strict,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        healthy.registration(includeErrors: false, includeTraces: false),
        failing.registration(includeErrors: false, includeTraces: false),
      ],
    );
    failureRuntime.logger.info('static event');
    await failureRuntime.flushDetailed();
    expect(healthy.logs, hasLength(1));
    expect(failing.logs, hasLength(1));
    expect(
      failureRuntime.diagnostics.destinations['failing_remote']!.sinkFailures,
      1,
    );
    await failureRuntime.disposeAsync();
  });

  test('concurrent producers preserve every accepted local event', () async {
    final destination = RecordingObservabilityDestination(
      name: 'concurrent',
      kind: ObservabilityDestinationKind.local,
    );
    final runtime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.strict,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        destination.registration(
          includeErrors: false,
          includeTraces: false,
          queueCapacity: 64,
        ),
      ],
    );

    await Future.wait(<Future<void>>[
      for (var index = 0; index < 64; index += 1)
        Future<void>(() => runtime.logger.info('static concurrent event')),
    ]);
    expect((await runtime.flushDetailed()).completed, isTrue);
    expect(destination.logs, hasLength(64));
    expect(runtime.diagnostics.destinations['concurrent']!.droppedEvents, 0);
    await runtime.disposeAsync();
  });

  test('registrations expose duplicate and conflicting ownership', () async {
    final probe = RecordingObservabilityDestination(
      name: 'local',
      kind: ObservabilityDestinationKind.local,
    );
    expect(
      () => ObservabilityRuntime.withPrivacy(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.strict,
        ),
        destinations: <ObservabilityDestinationRegistration>[
          probe.registration(includeErrors: false, includeTraces: false),
          ObservabilityDestinationRegistration.remote(
            name: 'remote',
            logSinks: <PreparedLogSinkRegistration>[
              PreparedLogSinkRegistration.owned(probe.logSink),
            ],
          ),
        ],
      ),
      throwsArgumentError,
    );

    final borrowed = RecordingObservabilityDestination(
      name: 'borrowed',
      kind: ObservabilityDestinationKind.local,
    );
    final runtime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.strict,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        borrowed.registration(),
      ],
    );
    await runtime.disposeAsync();
    expect(borrowed.disposeCalls, 0);
  });

  test('deterministic generated inputs stay inside structural budgets', () {
    const limits = ObservabilitySanitizationLimits(
      maxDepth: 3,
      maxCollectionLength: 3,
      maxStringCodePoints: 128,
      maxNodes: 16,
      maxTotalTextCodePoints: 32,
      maxStackFrames: 2,
      maxClassificationWork: 20,
    );
    final harness = ObservabilitySanitizationBudgetHarness(
      ObservabilitySanitizer(
        policy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.diagnostic,
        ),
        limits: limits,
      ),
    );
    final generator = _DeterministicInputs(140013);

    for (var index = 0; index < 200; index += 1) {
      final prepared = harness.prepareAndVerify(
        generator.nextValue(0),
        destination: index.isEven
            ? ObservabilityDestinationKind.local
            : ObservabilityDestinationKind.remote,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.httpBody},
      );
      expect(prepared.diagnostics.visitedNodes, lessThanOrEqualTo(16));
      expect(prepared.diagnostics.textCodePoints, lessThanOrEqualTo(32));
      expect(prepared.diagnostics.classificationWork, lessThanOrEqualTo(20));
    }
    final stack = harness.sanitizer.prepareStackTrace(
      const ObservabilityStackTraceProjection('#0 one\n#1 two\n#2 three'),
      destination: ObservabilityDestinationKind.local,
    );
    harness.verify(stack);
    expect(stack.diagnostics.stackFrames, 2);
    expect(stack.diagnostics.truncatedFrames, 1);
  });

  test('raw-data assertion never stringifies unsupported evidence', () {
    final explosive = _ExplosiveEvidence();
    expect(
      () => expectNoSensitiveObservabilityData(
        explosive,
        sentinels: const <String>['secret'],
      ),
      throwsStateError,
    );
    expect(explosive.toStringCalls, 0);
    expect(
      () => expectNoSensitiveObservabilityData(
        const <String, Object?>{'value': 'prefix-secret-suffix'},
        sentinels: const <String>['secret'],
      ),
      throwsStateError,
    );
  });
}

final class _DeterministicInputs {
  _DeterministicInputs(this._state);

  int _state;

  int _nextInt(int max) {
    _state = (1664525 * _state + 1013904223) & 0x7fffffff;
    return _state % max;
  }

  Object? nextValue(int depth) {
    if (depth > 5) return 'leaf-${_nextInt(100000)}-person@example.test';
    return switch (_nextInt(6)) {
      0 => null,
      1 => _nextInt(100000),
      2 => 'value-${_nextInt(100000)}-token=private',
      3 => <Object?>[
        for (var index = 0; index < 5; index += 1) nextValue(depth + 1),
      ],
      _ => <String, Object?>{
        for (var index = 0; index < 5; index += 1)
          'key_${_nextInt(1000)}': nextValue(depth + 1),
      },
    };
  }
}

final class _ExplosiveError {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('private raw error');
  }
}

final class _ExplosiveStackTrace implements StackTrace {
  @override
  String toString() => throw StateError('private stack');
}

final class _ExplosiveEvidence {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('secret');
  }
}
