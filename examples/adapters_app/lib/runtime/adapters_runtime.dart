// This file is the consumer composition boundary for optional provider SDKs.
// ignore_for_file: dartitect_vendor_observability_import

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_media/dartitect_media.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:dartitect_sentry/dartitect_sentry.dart';
import 'package:dio/dio.dart';
import 'package:sentry/sentry.dart';

import '../features/catalog/catalog_view_model.dart';
import '../infrastructure/dio_catalog_remote.dart';
import 'objectbox_capability_stub.dart'
    if (dart.library.io) 'objectbox_capability_native.dart';

/// Consumer-owned composition root for optional provider adapters.
final class AdaptersRuntime implements AsyncDisposable {
  AdaptersRuntime._(
    this.http,
    this.instrumentation,
    this.observability,
    this.catalog,
    this.gallery,
    this.trackingAuthorization,
    this._hub,
  );

  /// Creates adapters without performing network or database I/O.
  factory AdaptersRuntime.create() {
    // The example exercises a real consumer-owned Hub without network I/O.
    // Sentry requires a syntactically valid DSN even when transport is fake.
    final hub = Hub(
      SentryOptions()
        ..dsn = 'https://public@example.invalid/1'
        ..transport = _DiscardingSentryTransport(),
    );
    final tracer = SentryTracer(hub: hub);
    final observability = ObservabilityRuntime(
      logSinks: <LogSinkRegistration>[
        const LogSinkRegistration.owned(DeveloperLogSink()),
        LogSinkRegistration.borrowed(SentryLogSink(hub: hub)),
      ],
      errorReporter: SentryErrorReporter(hub: hub),
      tracer: tracer,
      samplingPolicy: FixedSamplingPolicy(spanRate: 1),
    );
    final http = DioOwner.create(
      options: BaseOptions(baseUrl: 'https://example.invalid'),
      interceptors: <Interceptor>[
        DartitectHeadersInterceptor(
          authorization: (_) => null,
          tenant: (_) => null,
        ),
      ],
      configure: (dio) => dio.httpClientAdapter = _CatalogFixtureAdapter(),
    );
    final instrumentation = DioInstrumentation.attach(
      http.dio,
      tracer: observability.tracing,
      routeTemplate: (options) =>
          options.extra['routeTemplate'] as RouteTemplate?,
      propagator: const W3CTracePropagator(),
    );
    observability.logger.info('Adapter runtime created.');
    final catalog = CatalogViewModel(
      DioCatalogRemote(http.dio),
      reporter: _CatalogCrashReporter(observability.reporter),
    );
    unawaited(_startCatalog(catalog));
    return AdaptersRuntime._(
      http,
      instrumentation,
      observability,
      catalog,
      MethodChannelGalleryMediaService(),
      MethodChannelTrackingAuthorizationService(),
      hub,
    );
  }

  /// Owned Dio client lifecycle.
  final DioOwner http;

  /// Borrowed-client tracing attachment removed during disposal.
  final DioInstrumentation instrumentation;

  /// Owned local observability pipeline.
  final ObservabilityRuntime observability;

  /// Remote-read/paged workload owned by this composition.
  final CatalogViewModel catalog;

  /// Inert until the consumer explicitly reads/requests/saves media.
  final GalleryMediaService gallery;

  /// Inert ATT boundary; composition never requests authorization implicitly.
  final TrackingAuthorizationService trackingAuthorization;
  final Hub _hub;

  /// Platform-specific statement of ObjectBox availability.
  String get databaseCapability => objectBoxCapability;

  /// Flutter crash bridge kept at the application composition root.
  FlutterCrashReporter get flutterCrashReporter =>
      CallbackFlutterCrashReporter((error, stackTrace, mechanism) async {
        await observability.reporter.report(
          ErrorEvent(
            timestamp: DateTime.now().toUtc(),
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
            fingerprint: <String>['flutter', mechanism.name],
          ),
        );
      });

  @override
  Future<void> disposeAsync() async {
    await catalog.disposeAsync();
    instrumentation.dispose();
    http.dispose();
    await observability.disposeAsync();
    await _hub.close();
  }
}

Future<void> _startCatalog(CatalogViewModel catalog) async {
  try {
    await catalog.start();
  } catch (_) {
    // PagedResourceCrashReporter already captured the original error/stack.
    return;
  }
}

final class _CatalogCrashReporter implements PagedResourceCrashReporter {
  const _CatalogCrashReporter(this._reporter);

  final ErrorReporter _reporter;

  @override
  void report(Object error, StackTrace stackTrace) {
    final result = _reporter.report(
      ErrorEvent(
        timestamp: DateTime.now().toUtc(),
        error: error,
        stackTrace: stackTrace,
        mechanism: ErrorMechanism.command,
        handled: true,
        fingerprint: const <String>['catalog', 'page'],
      ),
    );
    if (result is Future<void>) {
      unawaited(result.catchError((Object _, StackTrace __) => null));
    }
  }
}

final class _CatalogFixtureAdapter implements HttpClientAdapter {
  var _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) throw StateError('Catalog adapter is closed.');
    final offset = int.tryParse('${options.queryParameters['offset']}') ?? 0;
    final query = '${options.queryParameters['query'] ?? ''}'.toLowerCase();
    final rows = <Map<String, Object?>>[
      for (var index = offset; index < offset + 25 && index < 75; index += 1)
        if ('Catalog item $index'.toLowerCase().contains(query))
          <String, Object?>{
            'id': index,
            'title': 'Catalog item $index',
            'version': 1,
          },
    ];
    return ResponseBody.fromString(
      jsonEncode(rows),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) => _closed = true;
}

final class _DiscardingSentryTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => null;
}
