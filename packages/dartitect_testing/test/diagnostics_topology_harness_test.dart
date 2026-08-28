import 'package:dartitect/dartitect.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test('reconstructs every v2 category without application payload', () async {
    final buffer = DartitectDiagnosticBuffer(capacity: 64);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      idGenerator: _diagnosticIds(),
      detail: DartitectDiagnosticDetail.topology,
    );
    final owner = emitter.subject(DartitectDiagnosticSubjectKind.owner);
    final subjects = <DartitectDiagnosticSubject>[owner];
    for (final kind in DartitectDiagnosticSubjectKind.values.skip(1)) {
      subjects.add(emitter.subject(kind, parent: owner));
    }
    for (final subject in subjects) {
      subject
        ..emit(DartitectDiagnosticPhase.started, generation: 1)
        ..emit(DartitectDiagnosticPhase.updated, generation: 1, revision: 1)
        ..emit(DartitectDiagnosticPhase.disposed, generation: 1, revision: 1);
    }

    final harness = DiagnosticsTopologyHarness()..ingestAll(buffer.events);
    expect(
      harness.nodes,
      hasLength(DartitectDiagnosticSubjectKind.values.length),
    );
    expect(harness.liveCount, 0);
    for (final kind in DartitectDiagnosticSubjectKind.values) {
      expect(harness.count(kind), 1);
    }
    expect(
      harness.nodes.values
          .where((node) => node.kind != DartitectDiagnosticSubjectKind.owner)
          .every((node) => node.related.contains(owner.id)),
      isTrue,
    );
    await emitter.dispose();
    buffer.dispose();
  });

  test('rejects out-of-order, unknown, and post-terminal facts', () {
    final buffer = DartitectDiagnosticBuffer(capacity: 8);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      idGenerator: _diagnosticIds(),
      detail: DartitectDiagnosticDetail.topology,
    );
    final subject = emitter.subject(DartitectDiagnosticSubjectKind.resource);
    subject.emit(DartitectDiagnosticPhase.disposed);
    subject.emit(DartitectDiagnosticPhase.updated);

    final harness = DiagnosticsTopologyHarness();
    harness.ingest(buffer.events[0]);
    harness.ingest(buffer.events[1]);
    expect(() => harness.ingest(buffer.events[2]), throwsStateError);
    expect(() => harness.ingest(buffer.events[1]), throwsStateError);
  });
}

DeterministicIdGenerator _diagnosticIds() => DeterministicIdGenerator.sequence(
  List<String>.generate(
    32,
    (index) =>
        '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
  ),
);
