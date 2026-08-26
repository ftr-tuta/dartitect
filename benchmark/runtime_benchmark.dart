import 'dart:async';
import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';
import 'package:dartitect_objectbox/dartitect_objectbox.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart';

Future<void> main() async {
  const iterations = 2000;
  final results = <String, double>{};

  final redactor = const Redactor();
  results['redaction_us_per_operation'] = _measureSync(iterations, () {
    redactor.sanitize(<String, Object?>{
      'authorization': 'Bearer secret',
      'nested': <String, Object?>{'email': 'person@example.com'},
    });
  });

  final sampledOut = ObservabilityRuntime(
    logSinks: const <LogSinkRegistration>[],
    samplingPolicy: FixedSamplingPolicy(logRate: 0),
  );
  results['sampled_out_log_us_per_operation'] = _measureSync(iterations, () {
    sampledOut.logger.info('no-op event');
  });
  await sampledOut.disposeAsync();

  var delivered = 0;
  final queued = ObservabilityRuntime(
    queueCapacity: iterations,
    logSinks: <LogSinkRegistration>[
      LogSinkRegistration.borrowed(
        CallbackLogSink((_) {
          delivered += 1;
        }),
      ),
    ],
  );
  results['queued_log_us_per_operation'] = await _measureAsync(
    iterations,
    () async {
      queued.logger.info('queued event');
    },
    after: () async {
      final flushed = await queued.flush(const Duration(seconds: 5));
      if (!flushed) throw StateError('Log benchmark flush timed out.');
    },
  );
  const warmupOperations = 20;
  if (delivered != iterations + warmupOperations) {
    throw StateError(
      'Expected ${iterations + warmupOperations} delivered logs, '
      'got $delivered.',
    );
  }
  await queued.disposeAsync();

  final tracer = NoOpTracer();
  results['noop_span_us_per_operation'] = await _measureAsync(
    iterations,
    () async {
      final span = tracer.startSpan('benchmark');
      await span.end(status: SpanStatus.ok);
    },
  );

  final dio = Dio()..httpClientAdapter = _ImmediateAdapter();
  final dioInstrumentation = DioInstrumentation.attach(
    dio,
    tracer: tracer,
    routeTemplate: (_) => RouteTemplate('/resource'),
    propagator: const W3CTracePropagator(),
  );
  results['dio_instrumented_request_us_per_operation'] = await _measureAsync(
    250,
    () async {
      await dio.get<void>('https://example.invalid/resource?secret=value');
    },
  );
  if (dioInstrumentation.activeRequestCount != 0) {
    throw StateError('Dio instrumentation retained active requests.');
  }
  dioInstrumentation.dispose();
  dio.close(force: true);

  final objectBox = ObjectBoxInstrumentation(tracer: tracer);
  results['objectbox_boundary_us_per_operation'] = await _measureAsync(
    iterations,
    () async {
      await objectBox.traceOpen(() => 1);
      await objectBox.traceClose(() {});
    },
  );

  final worker = await IsolateWorker.spawn<int, int, StateError>(
    handler: _benchmarkWorker,
  );
  results['isolate_worker_roundtrip_us_per_operation'] = await _measureAsync(
    100,
    () async {
      final result = await worker.execute(1);
      if (result != const Ok<int>(2)) {
        throw StateError('Isolate benchmark returned an invalid result.');
      }
    },
  );
  await worker.safeStop();
  if (!worker.isDisposed || worker.activeRequestCount != 0) {
    throw StateError('Isolate benchmark retained supervisor resources.');
  }

  // Machine-readable output is intentionally easy to archive and compare.
  // ignore: avoid_print
  print(const JsonEncoder.withIndent('  ').convert(results));
}

Future<Result<int, StateError>> _benchmarkWorker(
  int value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value * 2);
}

double _measureSync(int iterations, void Function() operation) {
  for (var index = 0; index < 100; index += 1) {
    operation();
  }
  final watch = Stopwatch()..start();
  for (var index = 0; index < iterations; index += 1) {
    operation();
  }
  watch.stop();
  return watch.elapsedMicroseconds / iterations;
}

Future<double> _measureAsync(
  int iterations,
  FutureOr<void> Function() operation, {
  FutureOr<void> Function()? after,
}) async {
  for (var index = 0; index < 20; index += 1) {
    await operation();
  }
  await after?.call();
  final watch = Stopwatch()..start();
  for (var index = 0; index < iterations; index += 1) {
    await operation();
  }
  await after?.call();
  watch.stop();
  return watch.elapsedMicroseconds / iterations;
}

final class _ImmediateAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', 204);

  @override
  void close({bool force = false}) {}
}
