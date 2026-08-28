import 'dart:convert';
import 'dart:developer';

import 'package:dartitect/dartitect.dart';

/// Per-isolate capabilities RPC.
const String dartitectCapabilitiesExtension = 'ext.dartitect.capabilities';

/// Per-isolate bounded snapshot RPC.
const String dartitectSnapshotExtension = 'ext.dartitect.snapshot';

/// Per-isolate bounded event-delta RPC.
const String dartitectEventsExtension = 'ext.dartitect.events';

/// Exact read-only service extension allowlist.
const List<String> dartitectReadOnlyServiceExtensions = <String>[
  dartitectCapabilitiesExtension,
  dartitectSnapshotExtension,
  dartitectEventsExtension,
];

/// Registers isolate-local service extension handlers.
abstract interface class DartitectServiceExtensionRegistrar {
  /// Registers [handler] under one `ext.dartitect.*` [method].
  void register(String method, ServiceExtensionHandler handler);
}

/// VM-backed registrar that delegates to `dart:developer`.
final class VmDartitectServiceExtensionRegistrar
    implements DartitectServiceExtensionRegistrar {
  /// Creates the system registrar.
  const VmDartitectServiceExtensionRegistrar();

  @override
  void register(String method, ServiceExtensionHandler handler) =>
      registerExtension(method, handler);
}

/// Explicit development-only registration for one isolate.
///
/// The bridge exposes no mutation RPC. When enabled it assumes ownership of
/// [buffer] and clears every retained event on [dispose]. Product builds never
/// register, even if [enabled] is accidentally true.
final class DartitectDevToolsRegistration implements Disposable {
  DartitectDevToolsRegistration._({
    required DartitectDiagnosticBuffer buffer,
    required DartitectDiagnosticDetail detail,
    required bool registered,
  }) : _buffer = buffer,
       _detail = detail,
       _registered = registered;

  /// Registers the three read-only handlers when explicitly [enabled].
  factory DartitectDevToolsRegistration.register({
    required bool enabled,
    required DartitectDiagnosticBuffer buffer,
    required DartitectDiagnosticDetail detail,
    DartitectServiceExtensionRegistrar registrar =
        const VmDartitectServiceExtensionRegistrar(),
  }) {
    const productMode = bool.fromEnvironment('dart.vm.product');
    final registration = DartitectDevToolsRegistration._(
      buffer: buffer,
      detail: detail,
      registered: enabled && !productMode,
    );
    if (registration._registered) registration._register(registrar);
    return registration;
  }

  final DartitectDiagnosticBuffer _buffer;
  final DartitectDiagnosticDetail _detail;
  final bool _registered;
  var _disposed = false;

  /// Whether handlers were installed in this isolate.
  bool get isRegistered => _registered;

  /// Whether disposal cleared the owned event buffer.
  bool get isDisposed => _disposed;

  void _register(DartitectServiceExtensionRegistrar registrar) {
    registrar
      ..register(dartitectCapabilitiesExtension, _capabilities)
      ..register(dartitectSnapshotExtension, _snapshot)
      ..register(dartitectEventsExtension, _events);
  }

  Future<ServiceExtensionResponse> _capabilities(
    String method,
    Map<String, String> parameters,
  ) async {
    if (parameters.isNotEmpty) return _invalidParameters();
    return _result(<String, Object?>{
      'schemaVersion': dartitectDiagnosticsProtocolVersion,
      'diagnosticsProtocolVersion': dartitectDiagnosticsProtocolVersion,
      'readOnly': true,
      'isolateScoped': true,
      'detail': _detail.name,
      'bufferCapacity': _buffer.capacity,
      'methods': dartitectReadOnlyServiceExtensions,
    });
  }

  Future<ServiceExtensionResponse> _snapshot(
    String method,
    Map<String, String> parameters,
  ) async {
    if (parameters.isNotEmpty) return _invalidParameters();
    return _eventResult(_buffer.events);
  }

  Future<ServiceExtensionResponse> _events(
    String method,
    Map<String, String> parameters,
  ) async {
    if (parameters.keys.any((key) => key != 'afterSequence')) {
      return _invalidParameters();
    }
    final rawAfter = parameters['afterSequence'];
    final after = rawAfter == null ? 0 : int.tryParse(rawAfter);
    if (after == null || after < 0) return _invalidParameters();
    return _eventResult(
      _buffer.events.where((event) => event.sequence > after),
    );
  }

  ServiceExtensionResponse _eventResult(
    Iterable<DartitectDiagnosticEvent> events,
  ) {
    final snapshot = events.toList(growable: false);
    return _result(<String, Object?>{
      'schemaVersion': dartitectDiagnosticsProtocolVersion,
      'capacity': _buffer.capacity,
      'retainedCount': snapshot.length,
      'events': snapshot.map((event) => event.toJson()).toList(growable: false),
    });
  }

  static ServiceExtensionResponse _result(Map<String, Object?> value) =>
      ServiceExtensionResponse.result(jsonEncode(value));

  static ServiceExtensionResponse _invalidParameters() =>
      ServiceExtensionResponse.error(
        ServiceExtensionResponse.invalidParams,
        jsonEncode(<String, Object?>{'reason': 'invalidParameters'}),
      );

  /// Clears all retained events. Registered VM handlers remain inert and read
  /// an empty disposed buffer because `dart:developer` has no unregister API.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_registered) _buffer.dispose();
  }
}
