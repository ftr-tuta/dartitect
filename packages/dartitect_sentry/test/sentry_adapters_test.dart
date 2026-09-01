import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sentry/dartitect_sentry.dart';
import 'package:sentry/sentry.dart' hide SpanStatus;
import 'package:sentry/sentry.dart' as sentry show SpanStatus;
import 'package:test/test.dart';

void main() {
  test('1.0 log sink defensively redacts raw breadcrumbs and events', () async {
    final hub = _RecordingHub();
    final sink = SentryLogSink(hub: hub);

    await sink.emit(
      LogEvent(
        timestamp: DateTime.utc(2026),
        name: ObservabilityEventName('test.info'),
        level: LogLevel.info,
        message: 'person@example.com',
        context: ObservabilityContext(
          attributes: const <String, Object?>{'authorization': 'secret'},
        ),
      ),
    );
    await sink.emit(
      LogEvent(
        timestamp: DateTime.utc(2026),
        name: ObservabilityEventName('test.error'),
        level: LogLevel.error,
        message: 'token=secret',
        error: StateError('password=secret'),
        stackTrace: StackTrace.current,
      ),
    );

    expect(hub.breadcrumbs.single.message, '[REDACTED_EMAIL]');
    expect(hub.breadcrumbs.single.data!['authorization'], '[REDACTED]');
    expect(hub.events, hasLength(1));
    expect(hub.events.single.message!.formatted, isNot(contains('secret')));
    expect('${hub.events.single.throwable}', isNot(contains('secret')));
    expect(hub.closeCalls, 0);
  });

  test(
    '1.0 error reporter defensively redacts and preserves event semantics',
    () async {
      final hub = _RecordingHub();
      final reporter = SentryErrorReporter(hub: hub);

      await reporter.report(
        ErrorEvent(
          timestamp: DateTime.utc(2026),
          error: StateError('api_key=secret'),
          stackTrace: StackTrace.current,
          severity: ErrorSeverity.fatal,
          mechanism: ErrorMechanism.zone,
          handled: false,
          fingerprint: const <String>['person@example.com'],
        ),
      );
      await reporter.dispose();

      final event = hub.events.single;
      expect(event.level, SentryLevel.fatal);
      expect(event.tags!['dartitect.mechanism'], 'zone');
      expect(event.tags!['dartitect.handled'], 'false');
      expect(event.fingerprint, <String>['[REDACTED_EMAIL]']);
      expect(hub.closeCalls, 0);
    },
  );

  test('tracer continues explicit parent and finishes exactly once', () async {
    final hub = _RecordingHub();
    final tracer = SentryTracer(hub: hub);
    final parent = TraceContext(
      traceId: '0123456789abcdef0123456789abcdef',
      spanId: '0123456789abcdef',
      traceFlags: '01',
    );

    final span = tracer.startSpan(
      'load person@example.com',
      parent: parent,
      kind: SpanKind.client,
      attributes: const <String, Object?>{'token': 'secret'},
    );
    span.setAttribute('password', 'secret');
    span.addEvent(
      'done person@example.com',
      attributes: const <String, Object?>{'cookie': 'secret'},
    );
    await span.end(status: SpanStatus.ok);
    await span.end(status: SpanStatus.error);

    expect(hub.transactionContexts.single.traceId.toString(), parent.traceId);
    expect(
      hub.transactionContexts.single.parentSpanId.toString(),
      parent.spanId,
    );
    expect(hub.spans.single.data['token'], '[REDACTED]');
    expect(hub.spans.single.data['password'], '[REDACTED]');
    expect(hub.spans.single.finishCalls, 1);
    expect(span.context.traceId, parent.traceId);
    expect(hub.closeCalls, 0);
  });

  test(
    'prepared adapters preserve an approved value without redacting twice',
    () async {
      final hub = _RecordingHub();
      final runtime = ObservabilityRuntime.withPrivacy(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.diagnostic,
          destinationOverrides: <ObservabilityDestinationPrivacyOverrides>[
            ObservabilityDestinationPrivacyOverrides(
              name: 'sentry',
              kind: ObservabilityDestinationKind.remote,
              rules: ObservabilityPrivacyOverrides(
                allow: <ObservabilityDataClass>{
                  ObservabilityDataClass.errorMessage,
                  ObservabilityDataClass.email,
                },
              ),
            ),
          ],
          riskAcceptance: const ObservabilityRiskAcceptance.explicit(
            reason: 'Synthetic identity in an isolated adapter test.',
          ),
        ),
        destinations: <ObservabilityDestinationRegistration>[
          ObservabilityDestinationRegistration.remote(
            name: 'sentry',
            logSinks: <PreparedLogSinkRegistration>[
              PreparedLogSinkRegistration.borrowed(
                SentryLogSink.sanitizedInput(hub: hub),
              ),
            ],
            errorReporters: <ErrorReporterRegistration>[
              ErrorReporterRegistration.borrowed(
                SentryErrorReporter.sanitizedInput(hub: hub),
              ),
            ],
            tracers: <TracerRegistration>[
              TracerRegistration.borrowed(
                SentryTracer.sanitizedInput(hub: hub),
              ),
            ],
            samplingPolicy: FixedSamplingPolicy(logRate: 1, spanRate: 1),
          ),
        ],
      );

      runtime.logger.error(
        'synthetic@example.com',
        context: ObservabilityContext(
          attributes: <String, Object?>{
            'approved': ObservabilityClassifiedValue<Object?>(
              'synthetic@example.com',
              classes: <ObservabilityDataClass>{ObservabilityDataClass.email},
            ),
          },
        ),
      );
      runtime.reporter.report(
        ErrorEvent(
          timestamp: DateTime.utc(2026),
          error: StateError('raw error text must not be projected'),
          stackTrace: StackTrace.current,
          context: ObservabilityContext(
            attributes: <String, Object?>{
              'approved': ObservabilityClassifiedValue<Object?>(
                'synthetic@example.com',
                classes: <ObservabilityDataClass>{ObservabilityDataClass.email},
              ),
            },
          ),
        ),
      );
      final span = runtime.tracing.startSpan(
        'approved span',
        attributes: <String, Object?>{
          'status': ObservabilityClassifiedValue<Object?>(
            'ready',
            classes: <ObservabilityDataClass>{
              ObservabilityDataClass.safeStatus,
            },
          ),
        },
      );
      await span.end(status: SpanStatus.ok);
      await runtime.flushDetailed();

      expect(hub.events.first.message!.formatted, 'synthetic@example.com');
      expect(
        hub.events.first.contexts['dartitect'],
        containsPair('approved', 'synthetic@example.com'),
      );
      expect(hub.events.last.user, isNull);
      expect(hub.events.last.contexts['dartitect'], isNotNull);
      expect(hub.events.last.tags!.keys.toSet(), <String>{
        'dartitect.mechanism',
        'dartitect.handled',
      });
      expect(hub.spans.single.data, containsPair('status', 'ready'));
      expect(hub.closeCalls, 0);
      await runtime.disposeAsync();
      expect(hub.closeCalls, 0);
    },
  );
}

final class _RecordingHub implements Hub {
  final breadcrumbs = <Breadcrumb>[];
  final events = <SentryEvent>[];
  final transactionContexts = <SentryTransactionContext>[];
  final spans = <_RecordingSentrySpan>[];
  int closeCalls = 0;

  @override
  Future<void> addBreadcrumb(Breadcrumb crumb, {Hint? hint}) async {
    breadcrumbs.add(crumb);
  }

  @override
  Future<SentryId> captureEvent(
    SentryEvent event, {
    dynamic stackTrace,
    Hint? hint,
    ScopeCallback? withScope,
  }) async {
    events.add(event);
    return event.eventId;
  }

  @override
  ISentrySpan startTransactionWithContext(
    SentryTransactionContext transactionContext, {
    Map<String, dynamic>? customSamplingContext,
    DateTime? startTimestamp,
    bool? bindToScope,
    bool? waitForChildren,
    Duration? autoFinishAfter,
    bool? trimEnd,
    OnTransactionFinish? onFinish,
  }) {
    transactionContexts.add(transactionContext);
    final span = _RecordingSentrySpan(
      SentrySpanContext(
        traceId: transactionContext.traceId,
        spanId: transactionContext.spanId,
        parentSpanId: transactionContext.parentSpanId,
        operation: transactionContext.operation,
      ),
    );
    spans.add(span);
    return span;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingSentrySpan implements ISentrySpan {
  _RecordingSentrySpan(this.context);

  final Map<String, dynamic> data = <String, dynamic>{};
  int finishCalls = 0;

  @override
  final SentrySpanContext context;

  @override
  bool get finished => finishCalls > 0;

  @override
  dynamic throwable;

  @override
  void setData(String key, dynamic value) => data[key] = value;

  @override
  Future<void> finish({
    sentry.SpanStatus? status,
    DateTime? endTimestamp,
    Hint? hint,
  }) async {
    if (finished) return;
    finishCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
