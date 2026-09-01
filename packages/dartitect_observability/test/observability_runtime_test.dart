import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:test/test.dart';

void main() {
  test('strict redaction covers secrets, identifiers, depth, and size', () {
    const redactor = Redactor(
      limits: RedactionLimits(
        maxDepth: 2,
        maxCollectionLength: 2,
        maxStringLength: 60,
        maxAttributes: 2,
      ),
    );
    final attributes = redactor.sanitizeAttributes(<String, Object?>{
      'authorization': 'Bearer top-secret',
      'contact': 'a.person@example.com 529.982.247-25',
      'ignored': 'value',
    });

    expect(attributes['authorization'], '[REDACTED]');
    expect(attributes['contact'], contains('[REDACTED_EMAIL]'));
    expect(attributes['contact'], contains('[REDACTED_CPF]'));
    expect(attributes['_truncated_attributes'], 1);
    expect(
      redactor.sanitize(<String, Object?>{
        'safe': <String, Object?>{
          'nested': <String, Object?>{'tooDeep': true},
        },
      }),
      containsPair('safe', containsPair('nested', '[MAX_DEPTH]')),
    );
    final sanitizedText = const Redactor().sanitize(
      'https://example.invalid/users/42?token=secret '
      '550e8400-e29b-41d4-a716-446655440000 '
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature',
    );
    expect('$sanitizedText', isNot(contains('secret')));
    expect('$sanitizedText', contains('[REDACTED_UUID]'));
    expect('$sanitizedText', contains('[REDACTED_JWT]'));
    expect('$sanitizedText', contains('[REDACTED_QUERY]'));
    final deep = redactor.sanitize(<String, Object?>{
      'headers': <String, Object?>{'cookie': 'session'},
      'payload': <String, Object?>{'password': 'value'},
      'query': <String, Object?>{'token': 'value'},
    });
    expect('$deep', isNot(contains('session')));
    expect('$deep', isNot(contains('value')));
    expect(
      redactor.sanitize('x' * 100),
      allOf(hasLength(greaterThan(60)), contains('[TRUNCATED]')),
    );
    expect(
      '${const Redactor().sanitizeStackTrace(StackTrace.fromString('#0 file:///home/person/private.dart:1:2'))}',
      isNot(contains('/home/person')),
    );
  });

  test(
    'bounded non-blocking queue counts overflow and drains in order',
    () async {
      final events = <LogEvent>[];
      final runtime = ObservabilityRuntime(
        logSinks: <LogSinkRegistration>[
          LogSinkRegistration.borrowed(CallbackLogSink(events.add)),
        ],
        queueCapacity: 2,
      );

      for (var index = 0; index < 5; index += 1) {
        runtime.logger.info('event $index');
      }

      expect(await runtime.flush(const Duration(seconds: 1)), isTrue);
      expect(events.map((event) => event.message), <String>[
        'event 0',
        'event 1',
      ]);
      expect(runtime.diagnostics.droppedEvents, 3);
      await runtime.disposeAsync();
    },
  );

  test(
    'error and fatal logs are never sampled and sink failures isolate',
    () async {
      final levels = <LogLevel>[];
      final runtime = ObservabilityRuntime(
        logSinks: <LogSinkRegistration>[
          LogSinkRegistration.borrowed(
            CallbackLogSink((_) => throw StateError('sink unavailable')),
          ),
          LogSinkRegistration.borrowed(
            CallbackLogSink((event) => levels.add(event.level)),
          ),
        ],
        samplingPolicy: FixedSamplingPolicy(logRate: 0),
      );

      runtime.logger
        ..info('sampled out')
        ..error('kept')
        ..fatal('also kept');
      await runtime.flush(const Duration(seconds: 1));

      expect(levels, <LogLevel>[LogLevel.error, LogLevel.fatal]);
      expect(runtime.diagnostics.sampledOutEvents, 1);
      expect(runtime.diagnostics.sinkFailures, 2);
      await runtime.disposeAsync();
    },
  );

  test(
    'reporting sanitizes before destination and ownership is explicit',
    () async {
      final reports = <ErrorEvent>[];
      var reporterDisposeCalls = 0;
      var ownedSinkDisposeCalls = 0;
      var borrowedSinkDisposeCalls = 0;
      final reporter = CallbackErrorReporter(
        reports.add,
        onDispose: () => reporterDisposeCalls += 1,
      );
      final runtime = ObservabilityRuntime(
        logSinks: <LogSinkRegistration>[
          LogSinkRegistration.owned(
            CallbackLogSink(
              (_) {},
              onDispose: () => ownedSinkDisposeCalls += 1,
            ),
          ),
          LogSinkRegistration.borrowed(
            CallbackLogSink(
              (_) {},
              onDispose: () => borrowedSinkDisposeCalls += 1,
            ),
          ),
        ],
        errorReporter: reporter,
        ownsErrorReporter: true,
      );

      runtime.reporter.report(
        ErrorEvent(
          timestamp: DateTime.utc(2026),
          error: StateError('token=secret'),
          stackTrace: StackTrace.current,
          fingerprint: const <String>['person@example.com'],
          context: ObservabilityContext(
            attributes: const <String, Object?>{'password': 'secret'},
          ),
        ),
      );
      await runtime.disposeAsync();

      expect(reports, hasLength(1));
      expect('${reports.single.error}', isNot(contains('secret')));
      expect(reports.single.fingerprint.single, '[REDACTED_EMAIL]');
      expect(reports.single.context.attributes['password'], isNull);
      expect(runtime.diagnostics.deniedContextAttributes, 1);
      expect(reporterDisposeCalls, 1);
      expect(ownedSinkDisposeCalls, 1);
      expect(borrowedSinkDisposeCalls, 0);
    },
  );

  test('W3C propagation validates headers and never injects baggage', () {
    const propagator = W3CTracePropagator();
    final context = TraceContext(
      traceId: '0123456789abcdef0123456789abcdef',
      spanId: '0123456789abcdef',
      traceFlags: '01',
      traceState: 'vendor=value',
    );
    final headers = <String, String>{'baggage': 'must-remain-consumer-owned'};
    propagator.inject(headers, context);

    expect(headers['traceparent'], context.traceParent);
    expect(headers['tracestate'], 'vendor=value');
    expect(headers['baggage'], 'must-remain-consumer-owned');
    expect(propagator.extract(headers)?.traceId, context.traceId);
    expect(
      propagator.extract(<String, String>{
        'traceparent': '00-${'0' * 32}-${'0' * 16}-01',
      }),
      isNull,
    );
    expect(
      propagator.extract(<String, String>{
        'traceparent': context.traceParent,
        'tracestate': 'duplicate=one,duplicate=two',
      })?.traceState,
      isNull,
    );
    final discardHeaders = <String, String>{};
    const W3CTracePropagator.withTraceStatePolicy(
      TraceStatePropagationPolicy.discard,
    ).inject(discardHeaders, context);
    expect(discardHeaders, isNot(contains('tracestate')));
    expect(discardHeaders, isNot(contains('baggage')));
  });

  test('configured spans are sanitized and end exactly once', () async {
    final tracer = _RecordingTracer();
    final runtime = ObservabilityRuntime(
      logSinks: const <LogSinkRegistration>[],
      tracer: tracer,
      samplingPolicy: FixedSamplingPolicy(spanRate: 1),
    );
    final span = runtime.tracing.startSpan(
      'load person@example.com',
      kind: SpanKind.client,
      attributes: const <String, Object?>{'token': 'secret'},
    );

    await span.end(status: SpanStatus.ok);
    await span.end(status: SpanStatus.error);

    expect(tracer.names.single, 'load [REDACTED_EMAIL]');
    expect(tracer.attributes.single['token'], '[REDACTED]');
    expect(tracer.spans.single.endCalls, 1);
    await runtime.disposeAsync();
  });

  test('flush timeout and reporter failure stay in diagnostics', () async {
    final gate = Completer<void>();
    final runtime = ObservabilityRuntime(
      logSinks: <LogSinkRegistration>[
        LogSinkRegistration.borrowed(CallbackLogSink((_) => gate.future)),
      ],
      errorReporter: CallbackErrorReporter((_) => throw StateError('offline')),
    );
    runtime.logger.info('blocked');
    runtime.reporter.report(
      ErrorEvent(
        timestamp: DateTime.utc(2026),
        error: StateError('failure'),
        stackTrace: StackTrace.current,
      ),
    );

    expect(await runtime.flush(Duration.zero), isFalse);
    expect(runtime.diagnostics.flushTimeouts, 1);
    gate.complete();
    expect(await runtime.flush(const Duration(seconds: 1)), isTrue);
    expect(runtime.diagnostics.reporterFailures, 1);
    await runtime.disposeAsync();
  });

  test('reactive adapter emits only static allowlisted facts', () async {
    final logs = <LogEvent>[];
    final runtime = ObservabilityRuntime(
      logSinks: <LogSinkRegistration>[
        LogSinkRegistration.borrowed(CallbackLogSink(logs.add)),
      ],
      allowedContextKeys: const <String>{
        'reactive.source',
        'reactive.kind',
        'reactive.cause_key',
        'reactive.cause_label',
        'reactive.previous_revision',
        'reactive.next_revision',
        'reactive.duration_us',
        'reactive.listener_count',
      },
    );
    final adapter = ReactiveObserverLoggerAdapter(logger: runtime.logger);

    adapter.onChange(
      ReactiveChangeEvent(
        source: ReactiveEventSource.mutationCommand,
        kind: ReactiveEventKind.updated,
        cause: ChangeCauses.mutationExecute,
        previousRevision: 7,
        nextRevision: 8,
        duration: const Duration(microseconds: 25),
        listenerCount: 3,
      ),
    );
    expect(await runtime.flush(const Duration(seconds: 1)), isTrue);

    expect(logs, hasLength(1));
    final event = logs.single;
    expect(event.message, 'reactive.change');
    expect(event.level, LogLevel.debug);
    expect(event.context.attributes, <String, Object?>{
      'reactive.source': 'mutationCommand',
      'reactive.kind': 'updated',
      'reactive.cause_key': 'mutation.execute',
      'reactive.cause_label': 'Mutation execute',
      'reactive.previous_revision': 7,
      'reactive.next_revision': 8,
      'reactive.duration_us': 25,
      'reactive.listener_count': 3,
    });
    final serialized = '${event.message}${event.context.attributes}';
    for (final adversarial in <String>[
      'person@example.com',
      'token=secret',
      '529.982.247-25',
      '550e8400-e29b-41d4-a716-446655440000',
    ]) {
      expect(serialized, isNot(contains(adversarial)));
    }
    await runtime.disposeAsync();
  });

  test(
    'named events build lazily and route through per-sink filters',
    () async {
      final accepted = <LogEvent>[];
      final rejected = <LogEvent>[];
      var messageBuilds = 0;
      final runtime = ObservabilityRuntime(
        logSinks: <LogSinkRegistration>[
          LogSinkRegistration.borrowed(
            CallbackLogSink(accepted.add),
            filter: CallbackLogSinkFilter(
              (event) => event.name.value == 'catalog.loaded',
            ),
          ),
          LogSinkRegistration.borrowed(
            CallbackLogSink(rejected.add),
            filter: const CallbackLogSinkFilter(_rejectEveryEvent),
          ),
        ],
        samplingPolicy: FixedSamplingPolicy(logRate: 0),
      );

      runtime.logger.event(
        ObservabilityLogEvent(
          name: ObservabilityEventName('catalog.sampled_out'),
          level: LogLevel.info,
          message: () {
            messageBuilds += 1;
            return 'must stay lazy';
          },
        ),
      );
      runtime.logger.event(
        ObservabilityLogEvent(
          name: ObservabilityEventName('catalog.loaded'),
          level: LogLevel.error,
          message: () {
            messageBuilds += 1;
            return 'Catalog loaded.';
          },
        ),
      );
      await runtime.flush(const Duration(seconds: 1));

      expect(messageBuilds, 1);
      expect(accepted.single.name.value, 'catalog.loaded');
      expect(rejected, isEmpty);
      expect(runtime.diagnostics.sampledOutEvents, 1);
      await runtime.disposeAsync();
    },
  );

  test('architecture bridge ends completed and abandoned spans once', () async {
    final tracer = _RecordingTracer();
    final bridge = ArchitectureObserverBridge(
      logger: const _NoOpLogger(),
      tracer: tracer,
    );
    bridge
      ..onEvent(
        const ArchitectureEvent(
          ArchitectureEventKind.commandStarted,
          source: 'command',
          label: 'load',
        ),
      )
      ..onEvent(
        const ArchitectureEvent(
          ArchitectureEventKind.commandSucceeded,
          source: 'command',
          label: 'load',
        ),
      )
      ..onEvent(
        const ArchitectureEvent(
          ArchitectureEventKind.commandStarted,
          source: 'command',
          label: 'abandoned',
        ),
      );

    await bridge.disposeAsync();

    expect(tracer.spans, hasLength(2));
    expect(tracer.spans[0].status, SpanStatus.ok);
    expect(tracer.spans[1].status, SpanStatus.cancelled);
    expect(tracer.spans.map((span) => span.endCalls), everyElement(1));
  });
}

bool _rejectEveryEvent(LogEvent _) => false;

final class _NoOpLogger extends DartitectLogger {
  const _NoOpLogger();

  @override
  void log(
    LogLevel level,
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

final class _RecordingTracer extends Tracer {
  final names = <String>[];
  final attributes = <Map<String, Object?>>[];
  final spans = <_RecordingSpan>[];

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    names.add(name);
    this.attributes.add(attributes);
    final span = _RecordingSpan(
      TraceContext(
        traceId: parent?.traceId ?? '0123456789abcdef0123456789abcdef',
        spanId: 'fedcba9876543210',
        traceFlags: '01',
      ),
    );
    spans.add(span);
    return span;
  }
}

final class _RecordingSpan extends Span {
  _RecordingSpan(this.context);

  @override
  final TraceContext context;

  int endCalls = 0;
  SpanStatus? status;

  @override
  bool get isEnded => endCalls > 0;

  @override
  void addEvent(String name, {Map<String, Object?> attributes = const {}}) {}

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (isEnded) return;
    endCalls += 1;
    this.status = status;
  }
}
