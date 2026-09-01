import 'dart:convert';
import 'dart:developer';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_devtools/dartitect_devtools.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:test/test.dart';

void main() {
  test('registers only read-only payload-free isolate RPCs', () async {
    final buffer = DartitectDiagnosticBuffer(capacity: 4);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      detail: DartitectDiagnosticDetail.topology,
    );
    final subject = emitter.subject(DartitectDiagnosticSubjectKind.job)
      ..emit(DartitectDiagnosticPhase.started, generation: 1);
    final registrar = _Registrar();
    final registration = DartitectDevToolsRegistration.register(
      enabled: true,
      buffer: buffer,
      detail: DartitectDiagnosticDetail.topology,
      registrar: registrar,
    );

    expect(registration.isRegistered, isTrue);
    expect(registrar.handlers.keys, dartitectReadOnlyServiceExtensions);
    expect(
      registrar.handlers.keys.join(','),
      isNot(anyOf(contains('retry'), contains('cancel'), contains('clear'))),
    );
    final capabilities = await registrar.invoke(dartitectCapabilitiesExtension);
    expect(capabilities['readOnly'], isTrue);
    expect(capabilities['isolateScoped'], isTrue);
    final snapshot = await registrar.invoke(dartitectSnapshotExtension);
    expect(snapshot['retainedCount'], 2);
    expect(jsonEncode(snapshot), isNot(contains('customer')));
    final delta = await registrar.invoke(
      dartitectEventsExtension,
      <String, String>{'afterSequence': '1'},
    );
    expect(delta['retainedCount'], 1);

    registration.dispose();
    expect(buffer.events, isEmpty);
    expect(registration.isDisposed, isTrue);
    final afterDispose = await registrar.invoke(dartitectSnapshotExtension);
    expect(afterDispose['retainedCount'], 0);
    subject.emit(DartitectDiagnosticPhase.disposed);
    expect(buffer.events, isEmpty);
    await emitter.dispose();
  });

  test('disabled registration installs nothing and does not own buffer', () {
    final buffer = DartitectDiagnosticBuffer(capacity: 1);
    final registrar = _Registrar();
    final registration = DartitectDevToolsRegistration.register(
      enabled: false,
      buffer: buffer,
      detail: DartitectDiagnosticDetail.off,
      registrar: registrar,
    );

    expect(registration.isRegistered, isFalse);
    expect(registrar.handlers, isEmpty);
    registration.dispose();
    expect(buffer.isDisposed, isFalse);
    buffer.dispose();
  });

  test(
    'privacy RPC is separate, read-only, and contains no observed values',
    () async {
      const secret = 'privacy-sentinel-raw-value';
      final businessClass = ObservabilityDataClass.custom(
        'business.customer.contract_number',
      );
      final runtime = ObservabilityRuntime.withPrivacy(
        privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
          profile: ObservabilityPrivacyProfile.balanced,
          localOverrides: ObservabilityPrivacyOverrides(
            mask: <ObservabilityDataClass>{businessClass},
          ),
        ),
        destinations: <ObservabilityDestinationRegistration>[
          ObservabilityDestinationRegistration.local(
            name: 'developer_console',
            logSinks: <PreparedLogSinkRegistration>[
              const PreparedLogSinkRegistration.borrowed(
                CallbackPreparedLogSink(_ignorePreparedLog),
              ),
            ],
            samplingPolicy: FixedSamplingPolicy(logRate: 1),
          ),
        ],
      );
      runtime.logger.event(
        ObservabilityLogEvent(
          name: ObservabilityEventName('privacy.probe'),
          level: LogLevel.info,
          message: () => 'authorization=$secret',
          context: ObservabilityContext(
            attributes: <String, Object?>{
              'contract': ObservabilityClassifiedValue<String>(
                secret,
                classes: <ObservabilityDataClass>{businessClass},
              ),
              'password': secret,
            },
          ),
        ),
      );
      expect(
        await runtime.flushDetailed(const Duration(seconds: 1)),
        isA<ObservabilityFlushResult>(),
      );

      final registrar = _Registrar();
      final registration = DartitectObservabilityPrivacyRegistration.register(
        enabled: true,
        runtime: runtime,
        registrar: registrar,
      );

      expect(dartitectReadOnlyServiceExtensions, <String>[
        dartitectCapabilitiesExtension,
        dartitectSnapshotExtension,
        dartitectEventsExtension,
      ]);
      expect(
        dartitectReadOnlyServiceExtensions,
        isNot(contains(dartitectObservabilityPrivacyExtension)),
      );
      expect(
        registrar.handlers.keys,
        dartitectObservabilityPrivacyServiceExtensions,
      );
      final snapshot = await registrar.invoke(
        dartitectObservabilityPrivacyExtension,
      );
      final encoded = jsonEncode(snapshot);
      expect(
        snapshot['schemaVersion'],
        observabilityPrivacyPolicySchemaVersion,
      );
      expect(snapshot['readOnly'], isTrue);
      expect(snapshot['active'], isTrue);
      expect(snapshot['profile'], 'balanced');
      expect(snapshot['maskingMode'], 'full');
      expect(encoded, isNot(contains(secret)));
      expect(encoded, isNot(contains('authorization=')));
      final destinations = snapshot['destinations']! as List<Object?>;
      final local = destinations.single! as Map<String, Object?>;
      expect(local['name'], 'developer_console');
      expect(local['kind'], 'local');
      final actions = local['effectiveActions']! as Map<String, Object?>;
      expect(actions['credential.token'], 'deny');
      expect(actions[businessClass.wireName], 'mask');
      final counts = local['actionCounts']! as Map<String, Object?>;
      expect(
        (counts['deny']! as int) + (counts['mask']! as int),
        greaterThan(0),
      );

      final invalid = await registrar.response(
        dartitectObservabilityPrivacyExtension,
        <String, String>{'sample': 'forbidden'},
      );
      expect(invalid.isError(), isTrue);
      final beforeDispose = runtime.diagnostics;
      registration.dispose();
      expect(registration.isDisposed, isTrue);
      final inactive = await registrar.invoke(
        dartitectObservabilityPrivacyExtension,
      );
      expect(inactive['active'], isFalse);
      expect(inactive['destinations'], isEmpty);
      expect(
        runtime.diagnostics.destinations['developer_console']!.enqueuedEvents,
        beforeDispose.destinations['developer_console']!.enqueuedEvents,
      );
      await runtime.disposeAsync();
    },
  );
}

void _ignorePreparedLog(PreparedLogEvent event) {}

final class _Registrar implements DartitectServiceExtensionRegistrar {
  final Map<String, ServiceExtensionHandler> handlers =
      <String, ServiceExtensionHandler>{};

  @override
  void register(String method, ServiceExtensionHandler handler) {
    if (handlers.containsKey(method)) throw StateError('duplicate method');
    handlers[method] = handler;
  }

  Future<Map<String, Object?>> invoke(
    String method, [
    Map<String, String> parameters = const <String, String>{},
  ]) async {
    final response = await this.response(method, parameters);
    expect(response.isError(), isFalse);
    return jsonDecode(response.result!) as Map<String, Object?>;
  }

  Future<ServiceExtensionResponse> response(
    String method, [
    Map<String, String> parameters = const <String, String>{},
  ]) => handlers[method]!(method, parameters);
}
