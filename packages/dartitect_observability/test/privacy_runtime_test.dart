import 'dart:async';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:test/test.dart';

void main() {
  test(
    'lazy message builds once and queues prepared destination copies',
    () async {
      final local = <PreparedLogEvent>[];
      final remote = <PreparedLogEvent>[];
      var builds = 0;
      final runtime = ObservabilityRuntime.withPrivacy(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.diagnostic,
        ),
        destinations: <ObservabilityDestinationRegistration>[
          ObservabilityDestinationRegistration.local(
            logSinks: <PreparedLogSinkRegistration>[
              PreparedLogSinkRegistration.borrowed(
                CallbackPreparedLogSink(local.add),
              ),
            ],
            samplingPolicy: FixedSamplingPolicy(logRate: 1),
          ),
          ObservabilityDestinationRegistration.remote(
            name: 'remote',
            logSinks: <PreparedLogSinkRegistration>[
              PreparedLogSinkRegistration.borrowed(
                CallbackPreparedLogSink(remote.add),
              ),
            ],
            samplingPolicy: FixedSamplingPolicy(logRate: 1),
          ),
        ],
        clock: () => DateTime.utc(2026),
      );

      runtime.logger.event(
        ObservabilityLogEvent(
          name: ObservabilityEventName('account.login_failed'),
          level: LogLevel.error,
          message: () {
            builds += 1;
            return 'person@example.com token=top-secret';
          },
          context: ObservabilityContext(
            attributes: <String, Object?>{
              'attempt': 2,
              'body': ObservabilityClassifiedValue<Object?>(
                <String, Object?>{'password': 'top-secret'},
                classes: <ObservabilityDataClass>{
                  ObservabilityDataClass.httpBody,
                },
              ),
            },
          ),
        ),
      );
      final flush = await runtime.flushDetailed(const Duration(seconds: 1));

      expect(flush.completed, isTrue);
      expect(builds, 1);
      expect(local, hasLength(1));
      expect(remote, hasLength(1));
      expect(
        '${local.single.message}${local.single.context.attributes}',
        isNot(contains('top-secret')),
      );
      expect(
        '${remote.single.message}${remote.single.context.attributes}',
        isNot(contains('top-secret')),
      );
      expect(local.single.timestamp, DateTime.utc(2026));
      await runtime.disposeAsync();
    },
  );

  test(
    'slow remote queue neither blocks nor drops local prepared events',
    () async {
      final gate = Completer<void>();
      final local = <PreparedLogEvent>[];
      final remote = <PreparedLogEvent>[];
      final runtime = ObservabilityRuntime.withPrivacy(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.diagnostic,
        ),
        destinations: <ObservabilityDestinationRegistration>[
          ObservabilityDestinationRegistration.local(
            logSinks: <PreparedLogSinkRegistration>[
              PreparedLogSinkRegistration.borrowed(
                CallbackPreparedLogSink(local.add),
              ),
            ],
            samplingPolicy: FixedSamplingPolicy(logRate: 1),
            queueCapacity: 8,
          ),
          ObservabilityDestinationRegistration.remote(
            name: 'slow_remote',
            logSinks: <PreparedLogSinkRegistration>[
              PreparedLogSinkRegistration.borrowed(
                CallbackPreparedLogSink((event) async {
                  remote.add(event);
                  await gate.future;
                }),
              ),
            ],
            samplingPolicy: FixedSamplingPolicy(logRate: 1),
            queueCapacity: 1,
          ),
        ],
      );

      for (var index = 0; index < 4; index += 1) {
        runtime.logger.info('event $index');
      }
      await Future<void>.delayed(Duration.zero);

      expect(local, hasLength(4));
      expect(remote, hasLength(1));
      final beforeRelease = runtime.diagnostics;
      expect(beforeRelease.destinations['local']!.droppedEvents, 0);
      expect(beforeRelease.destinations['slow_remote']!.droppedEvents, 3);
      final timed = await runtime.flushDetailed(Duration.zero);
      expect(timed.destinations['local']!.completed, isTrue);
      expect(timed.destinations['slow_remote']!.timedOut, isTrue);

      gate.complete();
      expect(await runtime.flush(const Duration(seconds: 1)), isTrue);
      await runtime.disposeAsync();
    },
  );

  test(
    'registration rejects names, empty capabilities, and reused instances',
    () {
      expect(
        () => ObservabilityDestinationRegistration.remote(
          name: 'Invalid Name',
          logSinks: <PreparedLogSinkRegistration>[
            const PreparedLogSinkRegistration.borrowed(
              CallbackPreparedLogSink(_ignoreLog),
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ObservabilityDestinationRegistration.local(),
        throwsArgumentError,
      );

      const sink = CallbackPreparedLogSink(_ignoreLog);
      expect(
        () => ObservabilityRuntime.withPrivacy(
          privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
            profile: ObservabilityPrivacyProfile.strict,
          ),
          destinations: <ObservabilityDestinationRegistration>[
            ObservabilityDestinationRegistration.local(
              logSinks: const <PreparedLogSinkRegistration>[
                PreparedLogSinkRegistration.owned(sink),
              ],
            ),
            ObservabilityDestinationRegistration.remote(
              name: 'remote',
              logSinks: const <PreparedLogSinkRegistration>[
                PreparedLogSinkRegistration.borrowed(sink),
              ],
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('prepared errors and spans never retain raw objects', () async {
    final errors = <PreparedErrorEvent>[];
    final tracer = _RecordingPreparedTracer();
    final runtime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        ObservabilityDestinationRegistration.local(
          errorReporters: <ErrorReporterRegistration>[
            ErrorReporterRegistration.borrowed(
              CallbackPreparedErrorReporter(errors.add),
            ),
          ],
          tracers: <TracerRegistration>[TracerRegistration.borrowed(tracer)],
          samplingPolicy: FixedSamplingPolicy(logRate: 1, spanRate: 1),
        ),
      ],
    );
    final raw = _ExplosiveError();

    runtime.reporter.report(
      ErrorEvent(
        timestamp: DateTime.utc(2026),
        error: raw,
        stackTrace: _ExplosiveStackTrace(),
      ),
    );
    final span = runtime.tracing.startSpan(
      'load person@example.com',
      attributes: <String, Object?>{'token': 'top-secret'},
    );
    span.setAttribute('email', 'person@example.com');
    span.addEvent('token=top-secret');
    await span.end(error: raw, stackTrace: _ExplosiveStackTrace());
    await runtime.flush(const Duration(seconds: 1));

    expect(raw.toStringCalls, 0);
    expect('${errors.single.error}', contains('_ExplosiveError'));
    expect('${errors.single.stackTrace}', isNot(contains('private stack')));
    expect('${tracer.starts.single.attributes}', isNot(contains('top-secret')));
    expect('${tracer.span.attributes}', isNot(contains('person@example.com')));
    expect('${tracer.span.events}', isNot(contains('top-secret')));
    expect('${tracer.span.end?.error}', contains('_ExplosiveError'));
    await runtime.disposeAsync();
  });

  test(
    'runtime supplies one canonical trace context to every tracer',
    () async {
      final local = _RecordingPreparedTracer();
      final remote = _RecordingPreparedTracer();
      final runtime = ObservabilityRuntime.withPrivacyTraceIdGenerator(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.diagnostic,
        ),
        destinations: <ObservabilityDestinationRegistration>[
          ObservabilityDestinationRegistration.local(
            tracers: <TracerRegistration>[TracerRegistration.borrowed(local)],
            samplingPolicy: FixedSamplingPolicy(spanRate: 1),
          ),
          ObservabilityDestinationRegistration.remote(
            name: 'remote',
            tracers: <TracerRegistration>[TracerRegistration.borrowed(remote)],
            samplingPolicy: FixedSamplingPolicy(spanRate: 1),
          ),
        ],
        traceIdGenerator: _FixedTraceIds(),
      );

      final span = runtime.tracing.startSpan('canonical');

      expect(span.context.traceId, '11111111111111111111111111111111');
      expect(span.context.spanId, '2222222222222222');
      expect(local.starts.single.context.traceParent, span.context.traceParent);
      expect(
        remote.starts.single.context.traceParent,
        span.context.traceParent,
      );
      await span.end();
      await runtime.disposeAsync();
    },
  );

  test(
    'bounded shutdown retains an active destination for a later drain',
    () async {
      final gate = Completer<void>();
      var disposeCalls = 0;
      final runtime = ObservabilityRuntime.withPrivacy(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.diagnostic,
        ),
        destinations: <ObservabilityDestinationRegistration>[
          ObservabilityDestinationRegistration.local(
            logSinks: <PreparedLogSinkRegistration>[
              PreparedLogSinkRegistration.owned(
                CallbackPreparedLogSink(
                  (event) => gate.future,
                  onDispose: () => disposeCalls += 1,
                ),
              ),
            ],
            samplingPolicy: FixedSamplingPolicy(logRate: 1),
          ),
        ],
      );
      runtime.logger.info('admitted');
      await Future<void>.delayed(Duration.zero);

      final bounded = await runtime.disposeDetailed(
        const ObservabilityShutdownPolicy.bounded(Duration.zero),
      );

      expect(bounded.completed, isFalse);
      expect(bounded.timedOutDestinations, <String>{'local'});
      expect(bounded.disposedDestinations, isEmpty);
      expect(disposeCalls, 0);
      expect(runtime.isDisposed, isFalse);

      gate.complete();
      final drained = await runtime.disposeDetailed(
        const ObservabilityShutdownPolicy.drain(),
      );
      expect(drained.completed, isTrue);
      expect(drained.timedOutDestinations, isEmpty);
      expect(disposeCalls, 1);
      expect(runtime.isDisposed, isTrue);
      await runtime.disposeAsync();
      expect(disposeCalls, 1);
    },
  );
}

void _ignoreLog(PreparedLogEvent event) {}

final class _RecordingPreparedTracer extends PreparedTracer {
  final starts = <PreparedSpanStart>[];
  final span = _RecordingPreparedSpan();

  @override
  PreparedSpan startPreparedSpan(PreparedSpanStart start) {
    starts.add(start);
    return span;
  }
}

final class _RecordingPreparedSpan extends PreparedSpan {
  final attributes = <String, Object?>{};
  final events = <PreparedSpanEvent>[];
  PreparedSpanEnd? end;

  @override
  final TraceContext context = TraceContext(
    traceId: '0123456789abcdef0123456789abcdef',
    spanId: '0123456789abcdef',
    traceFlags: '01',
  );

  @override
  bool get isEnded => end != null;

  @override
  void addPreparedEvent(PreparedSpanEvent event) => events.add(event);

  @override
  void setPreparedAttribute(PreparedSpanAttribute attribute) =>
      attributes[attribute.key] = attribute.value;

  @override
  void endPrepared(PreparedSpanEnd end) => this.end = end;
}

final class _ExplosiveError {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('top-secret error');
  }
}

final class _ExplosiveStackTrace implements StackTrace {
  @override
  String toString() => throw StateError('private stack');
}

final class _FixedTraceIds implements TraceIdGenerator {
  @override
  String nextSpanId() => '2222222222222222';

  @override
  String nextTraceId() => '11111111111111111111111111111111';
}
