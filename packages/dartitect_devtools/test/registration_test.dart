import 'dart:convert';
import 'dart:developer';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_devtools/dartitect_devtools.dart';
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
}

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
    final response = await handlers[method]!(method, parameters);
    expect(response.isError(), isFalse);
    return jsonDecode(response.result!) as Map<String, Object?>;
  }
}
