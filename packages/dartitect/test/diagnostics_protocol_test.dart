import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('versioned protocol is exact, payload-free, and round-trips', () async {
    final buffer = DartitectDiagnosticBuffer(capacity: 4);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      idGenerator: _Ids(),
      detail: DartitectDiagnosticDetail.topology,
    );
    final owner = emitter.subject(DartitectDiagnosticSubjectKind.owner);
    final node = emitter.subject(
      DartitectDiagnosticSubjectKind.node,
      parent: owner,
      generation: 2,
      revision: 3,
    );
    node.emit(
      DartitectDiagnosticPhase.linked,
      related: owner,
      generation: 2,
      revision: 4,
    );

    final encoded = jsonEncode(buffer.events.last.toJson());
    expect(encoded, isNot(contains('customer')));
    expect(encoded, isNot(contains('error')));
    expect(buffer.events.last.toJson().keys, <String>[
      'schemaVersion',
      'sequence',
      'subjectKind',
      'phase',
      'subjectId',
      'relatedSubjectId',
      'generation',
      'revision',
    ]);
    final decoded = DartitectDiagnosticEvent.fromJson(
      jsonDecode(encoded) as Map<String, Object?>,
    );
    expect(decoded.toJson(), buffer.events.last.toJson());
    expect(decoded.subjectId.toString(), 'DartitectDiagnosticId(<opaque>)');
    await emitter.dispose();
    buffer.dispose();
  });

  test('all protocol subjects reconstruct from opaque lifecycle facts', () {
    final buffer = DartitectDiagnosticBuffer(capacity: 64);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      idGenerator: _Ids(),
      detail: DartitectDiagnosticDetail.topology,
    );
    final root = emitter.subject(DartitectDiagnosticSubjectKind.owner);
    for (final kind in DartitectDiagnosticSubjectKind.values) {
      final subject = kind == DartitectDiagnosticSubjectKind.owner
          ? root
          : emitter.subject(kind, parent: root);
      subject.emit(DartitectDiagnosticPhase.started);
      subject.emit(DartitectDiagnosticPhase.disposed);
    }

    expect(
      buffer.events.map((event) => event.subjectKind).toSet(),
      DartitectDiagnosticSubjectKind.values.toSet(),
    );
    expect(
      buffer.events
          .map((event) => event.toJson().keys)
          .every(
            (keys) => keys.toSet().containsAll(<String>{
              'schemaVersion',
              'subjectKind',
              'phase',
            }),
          ),
      isTrue,
    );
  });

  test('buffer is bounded and clears all retained events on dispose', () {
    final buffer = DartitectDiagnosticBuffer(capacity: 2);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      idGenerator: _Ids(),
      detail: DartitectDiagnosticDetail.topology,
    );
    final subject = emitter.subject(DartitectDiagnosticSubjectKind.resource);
    subject
      ..emit(DartitectDiagnosticPhase.started)
      ..emit(DartitectDiagnosticPhase.updated);

    expect(buffer.length, 2);
    expect(buffer.events.first.phase, DartitectDiagnosticPhase.started);
    buffer.dispose();
    expect(buffer.events, isEmpty);
    expect(buffer.length, 0);
    subject.emit(DartitectDiagnosticPhase.disposed);
    expect(buffer.events, isEmpty);
  });

  test('reporter failure is isolated once and disables destination', () {
    var reports = 0;
    var failures = 0;
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(
        _Reporter((_) {
          reports += 1;
          throw StateError('destination unavailable');
        }),
      ),
      idGenerator: _Ids(),
      detail: DartitectDiagnosticDetail.topology,
      onReporterFailure: (_, _) => failures += 1,
    );

    final subject = emitter.subject(DartitectDiagnosticSubjectKind.command);
    subject.emit(DartitectDiagnosticPhase.failed);

    expect(reports, 1);
    expect(failures, 1);
    expect(emitter.reporterDisabled, isTrue);
  });

  test(
    'off mode allocates no identifier and changes no caller control flow',
    () {
      final ids = _Ids();
      final emitter = DartitectDiagnosticsEmitter(
        reporter: const DartitectDiagnosticReporterRegistration.borrowed(
          NoOpDartitectDiagnosticReporter(),
        ),
        idGenerator: ids,
        detail: DartitectDiagnosticDetail.off,
      );

      var businessResult = 0;
      final subject = emitter.subject(DartitectDiagnosticSubjectKind.effect);
      businessResult += 7;
      subject.emit(DartitectDiagnosticPhase.succeeded);

      expect(subject.isDisabled, isTrue);
      expect(ids.calls, 0);
      expect(emitter.emittedCount, 0);
      expect(businessResult, 7);
    },
  );

  test('decoder rejects payload fields and unsupported versions', () {
    final valid = <String, Object?>{
      'schemaVersion': 1,
      'sequence': 1,
      'subjectKind': 'owner',
      'phase': 'created',
      'subjectId': '00000000-0000-4000-8000-000000000001',
      'relatedSubjectId': null,
      'generation': 0,
      'revision': 0,
    };
    expect(
      () => DartitectDiagnosticEvent.fromJson(<String, Object?>{
        ...valid,
        'domainPayload': 'secret',
      }),
      throwsFormatException,
    );
    expect(
      () => DartitectDiagnosticEvent.fromJson(<String, Object?>{
        ...valid,
        'schemaVersion': 2,
      }),
      throwsFormatException,
    );
  });
}

final class _Ids implements IdGenerator {
  var calls = 0;

  @override
  String nextId() {
    calls += 1;
    return '00000000-0000-4000-8000-${calls.toString().padLeft(12, '0')}';
  }
}

final class _Reporter implements DartitectDiagnosticReporter {
  const _Reporter(this.callback);

  final void Function(DartitectDiagnosticEvent event) callback;

  @override
  void report(DartitectDiagnosticEvent event) => callback(event);
}
