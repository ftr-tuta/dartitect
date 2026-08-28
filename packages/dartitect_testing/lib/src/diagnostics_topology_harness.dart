import 'package:dartitect/dartitect.dart';

/// Payload-free reconstructed state for one diagnostic subject.
@experimentalDartitectApi
final class DiagnosticTopologyNode {
  DiagnosticTopologyNode._({
    required this.id,
    required this.kind,
    required this.phase,
    required this.generation,
    required this.revision,
  });

  /// Opaque process-local protocol identifier.
  final DartitectDiagnosticId id;

  /// Fixed protocol category.
  final DartitectDiagnosticSubjectKind kind;

  /// Most recently observed fixed lifecycle fact.
  DartitectDiagnosticPhase phase;

  /// Most recently observed generation.
  int generation;

  /// Most recently observed revision.
  int revision;

  final Set<DartitectDiagnosticId> _related = <DartitectDiagnosticId>{};

  /// Opaque subjects related by parent or link events.
  Set<DartitectDiagnosticId> get related => Set.unmodifiable(_related);

  /// Whether the lifecycle ended terminally.
  bool get isTerminal =>
      phase == DartitectDiagnosticPhase.disposed ||
      phase == DartitectDiagnosticPhase.evicted;
}

/// Deterministic protocol harness that reconstructs topology and lifecycle.
///
/// It accepts only [DartitectDiagnosticEvent], whose type has no domain
/// payload, error text, stack, key, query, identity, or arbitrary metadata.
@experimentalDartitectApi
final class DiagnosticsTopologyHarness {
  final Map<DartitectDiagnosticId, DiagnosticTopologyNode> _nodes =
      <DartitectDiagnosticId, DiagnosticTopologyNode>{};
  var _lastSequence = 0;
  var _lastMonotonicMicroseconds = 0;

  /// Latest admitted event sequence.
  int get lastSequence => _lastSequence;

  /// Immutable reconstructed nodes indexed only by opaque protocol IDs.
  Map<DartitectDiagnosticId, DiagnosticTopologyNode> get nodes =>
      Map.unmodifiable(_nodes);

  /// Number of subjects not terminally disposed or evicted.
  int get liveCount => _nodes.values.where((node) => !node.isTerminal).length;

  /// Number of reconstructed subjects in one fixed category.
  int count(DartitectDiagnosticSubjectKind kind) =>
      _nodes.values.where((node) => node.kind == kind).length;

  /// Admits one event and validates its local topology ordering.
  void ingest(DartitectDiagnosticEvent event) {
    if (event.sequence <= _lastSequence) {
      throw StateError('Diagnostic event sequence is not strictly monotonic.');
    }
    if (event.monotonicMicroseconds < _lastMonotonicMicroseconds) {
      throw StateError('Diagnostic event time moved backwards.');
    }
    _lastSequence = event.sequence;
    _lastMonotonicMicroseconds = event.monotonicMicroseconds;
    final existing = _nodes[event.subjectId];
    if (event.phase == DartitectDiagnosticPhase.created) {
      if (existing != null) {
        throw StateError('Diagnostic subject was created more than once.');
      }
      final node = DiagnosticTopologyNode._(
        id: event.subjectId,
        kind: event.subjectKind,
        phase: event.phase,
        generation: event.generation,
        revision: event.revision,
      );
      _nodes[event.subjectId] = node;
      _recordRelation(node, event.relatedSubjectId);
      return;
    }
    if (existing == null) {
      throw StateError('Diagnostic event references an unknown subject.');
    }
    if (existing.kind != event.subjectKind) {
      throw StateError('Diagnostic subject kind changed within one lifecycle.');
    }
    if (existing.isTerminal) {
      throw StateError('Diagnostic event followed a terminal lifecycle fact.');
    }
    if (event.generation < existing.generation ||
        (event.generation == existing.generation &&
            event.revision < existing.revision)) {
      throw StateError('Diagnostic generation or revision moved backwards.');
    }
    existing
      ..phase = event.phase
      ..generation = event.generation
      ..revision = event.revision;
    _recordRelation(existing, event.relatedSubjectId);
  }

  /// Admits a complete local transcript in order.
  void ingestAll(Iterable<DartitectDiagnosticEvent> events) {
    for (final event in events) {
      ingest(event);
    }
  }

  void _recordRelation(
    DiagnosticTopologyNode node,
    DartitectDiagnosticId? related,
  ) {
    if (related == null) return;
    if (!_nodes.containsKey(related)) {
      throw StateError('Diagnostic relation references an unknown subject.');
    }
    node._related.add(related);
  }
}
