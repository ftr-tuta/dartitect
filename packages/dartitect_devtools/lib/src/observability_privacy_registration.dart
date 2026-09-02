import 'dart:convert';
import 'dart:developer';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_observability/dartitect_observability.dart';

import 'registration.dart';

/// Separate read-only RPC for payload-free observability privacy diagnostics.
const String dartitectObservabilityPrivacyExtension =
    'ext.dartitect.observabilityPrivacy';

/// Exact allowlist for the separate observability privacy protocol.
///
/// This is deliberately not part of [dartitectReadOnlyServiceExtensions],
/// whose three entries remain the closed diagnostics-v2 protocol.
const List<String> dartitectObservabilityPrivacyServiceExtensions = <String>[
  dartitectObservabilityPrivacyExtension,
];

/// Explicit development-only registration for privacy policy diagnostics.
///
/// The registration borrows [runtime]. Its handler reads only immutable
/// policy configuration and payload-free counter snapshots; it cannot inspect
/// prepared events or destination queues.
final class DartitectObservabilityPrivacyRegistration implements Disposable {
  DartitectObservabilityPrivacyRegistration._({
    required DestinationAwareObservabilityRuntime? runtime,
    required bool registered,
  }) : _runtime = runtime,
       _registered = registered;

  /// Registers the separate read-only handler when explicitly [enabled].
  factory DartitectObservabilityPrivacyRegistration.register({
    required bool enabled,
    required DestinationAwareObservabilityRuntime runtime,
    DartitectServiceExtensionRegistrar registrar =
        const VmDartitectServiceExtensionRegistrar(),
  }) {
    const productMode = bool.fromEnvironment('dart.vm.product');
    final registration = DartitectObservabilityPrivacyRegistration._(
      runtime: runtime,
      registered: enabled && !productMode,
    );
    if (registration._registered) {
      registrar.register(
        dartitectObservabilityPrivacyExtension,
        registration._snapshot,
      );
    }
    return registration;
  }

  DestinationAwareObservabilityRuntime? _runtime;
  final bool _registered;
  var _disposed = false;

  /// Whether the handler was installed in this isolate.
  bool get isRegistered => _registered;

  /// Whether this registration released its borrowed runtime reference.
  bool get isDisposed => _disposed;

  Future<ServiceExtensionResponse> _snapshot(
    String method,
    Map<String, String> parameters,
  ) async {
    if (parameters.isNotEmpty) return _invalidParameters();
    final runtime = _runtime;
    if (_disposed || runtime == null) return _result(_inactiveSnapshot());
    final diagnostics = runtime.diagnostics;
    return _result(<String, Object?>{
      'schemaVersion': observabilityPrivacyPolicySchemaVersion,
      'readOnly': true,
      'isolateScoped': true,
      'active': true,
      'profile': runtime.privacyPolicy.profile.name,
      'maskingMode': runtime.privacyPolicy.masking.mode.name,
      'messageBuilderFailures': diagnostics.messageBuilderFailures,
      'destinations': <Map<String, Object?>>[
        for (final registration in runtime.destinations)
          _destinationSnapshot(
            runtime,
            registration,
            diagnostics.destinations[registration.name]!,
          ),
      ],
    });
  }

  static Map<String, Object?> _destinationSnapshot(
    DestinationAwareObservabilityRuntime runtime,
    ObservabilityDestinationRegistration registration,
    ObservabilityDestinationDiagnosticsSnapshot diagnostics,
  ) {
    final sanitization = diagnostics.sanitization;
    final actions = runtime.privacyPolicy.effectiveActions(
      destination: registration.kind,
      destinationName: registration.name,
    );
    return <String, Object?>{
      'name': registration.name,
      'kind': registration.kind.name,
      'capabilities':
          registration.capabilities
              .map((capability) => capability.name)
              .toList(growable: false)
            ..sort(),
      'actionCounts': <String, int>{
        'allow': sanitization.allowedValues,
        'mask': sanitization.maskedValues,
        'deny': sanitization.deniedValues,
      },
      'queue': <String, int>{
        'depth': diagnostics.queueDepth,
        'maxDepth': diagnostics.maxQueueDepth,
        'enqueued': diagnostics.enqueuedEvents,
        'dispatched': diagnostics.dispatchedEvents,
        'overflow': diagnostics.droppedEvents,
        'sampledOut': diagnostics.sampledOutEvents,
      },
      'failures': <String, int>{
        'filter': diagnostics.filterFailures,
        'sampling': diagnostics.samplingFailures,
        'sink': diagnostics.sinkFailures,
        'reporter': diagnostics.reporterFailures,
        'tracer': diagnostics.tracerFailures,
        'flushTimeout': diagnostics.flushTimeouts,
      },
      'sanitization': <String, int>{
        'visitedNodes': sanitization.visitedNodes,
        'textCodePoints': sanitization.textCodePoints,
        'stackFrames': sanitization.stackFrames,
        'classificationWork': sanitization.classificationWork,
        'unknownObjects': sanitization.unknownObjects,
        'cycles': sanitization.cycles,
        'truncatedNodes': sanitization.truncatedNodes,
        'truncatedText': sanitization.truncatedText,
        'truncatedCollections': sanitization.truncatedCollections,
        'truncatedFrames': sanitization.truncatedFrames,
        'truncatedClassification': sanitization.truncatedClassification,
        'classifierFailures': sanitization.classifierFailures,
        'projectorFailures': sanitization.projectorFailures,
      },
      'effectiveActions': <String, String>{
        for (final entry in actions.entries) entry.key: entry.value.name,
      },
    };
  }

  static Map<String, Object?> _inactiveSnapshot() => <String, Object?>{
    'schemaVersion': observabilityPrivacyPolicySchemaVersion,
    'readOnly': true,
    'isolateScoped': true,
    'active': false,
    'profile': null,
    'maskingMode': null,
    'messageBuilderFailures': 0,
    'destinations': const <Object?>[],
  };

  static ServiceExtensionResponse _result(Map<String, Object?> value) =>
      ServiceExtensionResponse.result(jsonEncode(value));

  static ServiceExtensionResponse _invalidParameters() =>
      ServiceExtensionResponse.error(
        ServiceExtensionResponse.invalidParams,
        jsonEncode(<String, Object?>{'reason': 'invalidParameters'}),
      );

  /// Releases the borrowed runtime reference without mutating the runtime.
  ///
  /// Registered VM handlers remain inert because `dart:developer` has no
  /// unregister API.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runtime = null;
  }
}
