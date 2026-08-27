import 'dart:async';

import '../id_generator.dart';
import '../lifecycle/contracts.dart';

/// Marks a Dartitect API that remains experimental during the candidate line.
///
/// Experimental APIs may change before the stable release and require an ADR,
/// a real consumer use, and an explicit discard contract before stabilization.
final class ExperimentalDartitectApi {
  /// Creates the marker used by experimental Dartitect declarations.
  const ExperimentalDartitectApi();
}

/// Shared marker for APIs that have not completed the stabilization gate.
const experimentalDartitectApi = ExperimentalDartitectApi();

/// Current wire schema emitted by [DartitectDiagnosticsEmitter].
@experimentalDartitectApi
const int dartitectDiagnosticsProtocolVersion = 1;

/// Fixed subject categories supported by diagnostics protocol version 1.
@experimentalDartitectApi
enum DartitectDiagnosticSubjectKind {
  /// An owned reactive or lifecycle composition root.
  owner,

  /// A node inside an owned reactive graph.
  node,

  /// A command or mutation execution boundary.
  command,

  /// A live, paged, collection, or derived resource.
  resource,

  /// A keyed resource family.
  family,

  /// A one-shot effect boundary.
  effect,

  /// A synchronization run.
  sync,

  /// An isolate worker or isolate-owned execution boundary.
  isolate,
}

/// Fixed lifecycle facts supported by diagnostics protocol version 1.
@experimentalDartitectApi
enum DartitectDiagnosticPhase {
  /// A subject entered the diagnostic topology.
  created,

  /// A subject was linked to another opaque subject.
  linked,

  /// Work began.
  started,

  /// Work is waiting for an asynchronous result.
  waiting,

  /// Stable state changed without exposing its value.
  updated,

  /// Work completed successfully.
  succeeded,

  /// Work completed with an expected typed failure.
  failed,

  /// Work crashed unexpectedly.
  crashed,

  /// Work ended through cooperative cancellation.
  cancelled,

  /// An idle family entry was evicted.
  evicted,

  /// A subject was terminally disposed.
  disposed,
}

/// Runtime diagnostic detail without event sampling.
@experimentalDartitectApi
enum DartitectDiagnosticDetail {
  /// Allocates no subject identifiers and emits no events.
  off,

  /// Emits lifecycle terminals and failures, omitting topology and churn.
  lifecycle,

  /// Emits the complete protocol needed to reconstruct local topology.
  topology,
}

/// Opaque process-local identifier allocated only by a diagnostics emitter.
@experimentalDartitectApi
final class DartitectDiagnosticId {
  DartitectDiagnosticId._(this.value) {
    if (!_pattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'diagnosticId',
        'Must be an opaque UUID-shaped identifier.',
      );
    }
  }

  /// Opaque value used only to correlate protocol events.
  final String value;

  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  @override
  bool operator ==(Object other) =>
      other is DartitectDiagnosticId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DartitectDiagnosticId(<opaque>)';
}

/// Versioned, payload-free fact emitted by the diagnostic runtime.
@experimentalDartitectApi
final class DartitectDiagnosticEvent {
  DartitectDiagnosticEvent._({
    required this.sequence,
    required this.subjectKind,
    required this.phase,
    required this.subjectId,
    required this.relatedSubjectId,
    required this.generation,
    required this.revision,
  }) {
    if (sequence <= 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must be positive.');
    }
    if (generation < 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'Must not be negative.',
      );
    }
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'Must not be negative.');
    }
    if (phase == DartitectDiagnosticPhase.linked && relatedSubjectId == null) {
      throw ArgumentError(
        'A linked diagnostic event requires a related subject.',
      );
    }
  }

  /// Monotonic sequence owned by one emitter.
  final int sequence;

  /// Fixed category of the subject.
  final DartitectDiagnosticSubjectKind subjectKind;

  /// Fixed lifecycle fact.
  final DartitectDiagnosticPhase phase;

  /// Process-local correlation identifier; never a domain identifier.
  final DartitectDiagnosticId subjectId;

  /// Optional process-local parent or edge target.
  final DartitectDiagnosticId? relatedSubjectId;

  /// Non-negative runtime generation, or zero when not applicable.
  final int generation;

  /// Non-negative runtime revision, or zero when not applicable.
  final int revision;

  /// Encodes the exact protocol-version-1 schema.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': dartitectDiagnosticsProtocolVersion,
    'sequence': sequence,
    'subjectKind': subjectKind.name,
    'phase': phase.name,
    'subjectId': subjectId.value,
    'relatedSubjectId': relatedSubjectId?.value,
    'generation': generation,
    'revision': revision,
  };

  /// Decodes only the exact protocol-version-1 schema and allowlisted values.
  // Kept beside [toJson] so the wire contract remains reviewable as one unit.
  // ignore: sort_constructors_first
  factory DartitectDiagnosticEvent.fromJson(Map<String, Object?> json) {
    const keys = <String>{
      'schemaVersion',
      'sequence',
      'subjectKind',
      'phase',
      'subjectId',
      'relatedSubjectId',
      'generation',
      'revision',
    };
    if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
      throw const FormatException(
        'Diagnostic event must use the exact version-1 field set.',
      );
    }
    if (json['schemaVersion'] != dartitectDiagnosticsProtocolVersion) {
      throw const FormatException('Unsupported diagnostic schema version.');
    }
    final sequence = json['sequence'];
    final kindName = json['subjectKind'];
    final phaseName = json['phase'];
    final subjectId = json['subjectId'];
    final relatedId = json['relatedSubjectId'];
    final generation = json['generation'];
    final revision = json['revision'];
    if (sequence is! int ||
        kindName is! String ||
        phaseName is! String ||
        subjectId is! String ||
        relatedId is! String? ||
        generation is! int ||
        revision is! int) {
      throw const FormatException('Diagnostic event field type is invalid.');
    }
    final kind = _enumByName(DartitectDiagnosticSubjectKind.values, kindName);
    final phase = _enumByName(DartitectDiagnosticPhase.values, phaseName);
    try {
      return DartitectDiagnosticEvent._(
        sequence: sequence,
        subjectKind: kind,
        phase: phase,
        subjectId: DartitectDiagnosticId._(subjectId),
        relatedSubjectId: relatedId == null
            ? null
            : DartitectDiagnosticId._(relatedId),
        generation: generation,
        revision: revision,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid diagnostic event value.', error);
    }
  }
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown diagnostic enum value: $name');
}

/// Synchronous destination for allowlisted diagnostic events.
@experimentalDartitectApi
abstract interface class DartitectDiagnosticReporter {
  /// Receives one immutable, payload-free event.
  void report(DartitectDiagnosticEvent event);
}

/// Reporter that deliberately ignores every event.
@experimentalDartitectApi
final class NoOpDartitectDiagnosticReporter
    implements DartitectDiagnosticReporter {
  /// Creates a no-op reporter.
  const NoOpDartitectDiagnosticReporter();

  @override
  void report(DartitectDiagnosticEvent event) {}
}

/// Explicit borrowed or owned diagnostic destination.
@experimentalDartitectApi
final class DartitectDiagnosticReporterRegistration {
  /// Borrows [reporter] and never disposes it.
  const DartitectDiagnosticReporterRegistration.borrowed(this.reporter)
    : _dispose = null;

  /// Owns [reporter] through an explicit asynchronous teardown callback.
  const DartitectDiagnosticReporterRegistration.owned(
    this.reporter, {
    required FutureOr<void> Function() dispose,
  }) : _dispose = dispose;

  /// Injected reporter.
  final DartitectDiagnosticReporter reporter;

  final FutureOr<void> Function()? _dispose;

  /// Whether this registration owns destination teardown.
  bool get isOwned => _dispose != null;

  Future<void> _disposeOwned() async => _dispose?.call();
}

/// Failure-isolating, reentrancy-safe wrapper around an injected reporter.
@experimentalDartitectApi
final class SafeDartitectDiagnosticReporter
    implements DartitectDiagnosticReporter {
  /// Wraps [reporter] and reports only its first failure when disabled.
  SafeDartitectDiagnosticReporter({
    required DartitectDiagnosticReporter reporter,
    void Function(Object error, StackTrace stackTrace)? onFailure,
    this.disableAfterFailure = true,
  }) : _reporter = reporter,
       _onFailure = onFailure;

  final DartitectDiagnosticReporter _reporter;
  final void Function(Object error, StackTrace stackTrace)? _onFailure;
  var _emitting = false;
  var _disabled = false;
  var _failureCount = 0;
  var _droppedReentrantEvents = 0;

  /// Whether a reporter failure disabled this wrapper.
  bool get isDisabled => _disabled;

  /// Number of destination failures observed.
  int get failureCount => _failureCount;

  /// Recursive reports dropped to prevent diagnostic loops.
  int get droppedReentrantEvents => _droppedReentrantEvents;

  /// Whether the first destination failure disables later delivery.
  final bool disableAfterFailure;

  @override
  void report(DartitectDiagnosticEvent event) {
    if (_disabled) return;
    if (_emitting) {
      _droppedReentrantEvents += 1;
      return;
    }
    _emitting = true;
    try {
      _reporter.report(event);
    } catch (error, stackTrace) {
      _failureCount += 1;
      if (disableAfterFailure) _disabled = true;
      final onFailure = _onFailure;
      if (onFailure != null) {
        try {
          onFailure(error, stackTrace);
        } on Object {
          return;
        }
      }
    } finally {
      _emitting = false;
    }
  }
}

/// Bounded in-memory diagnostic ring that clears all references on disposal.
@experimentalDartitectApi
final class DartitectDiagnosticBuffer
    implements DartitectDiagnosticReporter, Disposable {
  /// Creates a buffer with a positive fixed [capacity].
  DartitectDiagnosticBuffer({int capacity = 200})
    : capacity = _positiveCapacity(capacity),
      _entries = List<DartitectDiagnosticEvent?>.filled(
        _positiveCapacity(capacity),
        null,
      );

  /// Maximum retained event count.
  final int capacity;

  final List<DartitectDiagnosticEvent?> _entries;
  var _start = 0;
  var _length = 0;
  var _disposed = false;

  /// Retained events from oldest to newest.
  List<DartitectDiagnosticEvent> get events {
    if (_disposed) return const <DartitectDiagnosticEvent>[];
    return List<DartitectDiagnosticEvent>.unmodifiable(
      List<DartitectDiagnosticEvent>.generate(
        _length,
        (index) => _entries[(_start + index) % capacity]!,
      ),
    );
  }

  /// Current retained event count.
  int get length => _disposed ? 0 : _length;

  /// Whether terminal disposal has cleared the buffer.
  bool get isDisposed => _disposed;

  @override
  void report(DartitectDiagnosticEvent event) {
    if (_disposed) return;
    if (_length < capacity) {
      _entries[(_start + _length) % capacity] = event;
      _length += 1;
      return;
    }
    _entries[_start] = event;
    _start = (_start + 1) % capacity;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (var index = 0; index < _entries.length; index += 1) {
      _entries[index] = null;
    }
    _start = 0;
    _length = 0;
  }

  static int _positiveCapacity(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'capacity', 'Must be positive.');
    }
    return value;
  }
}

/// Process-local protocol emitter with injected identifiers and destination.
@experimentalDartitectApi
final class DartitectDiagnosticsEmitter implements AsyncDisposable {
  /// Creates an emitter. Reporter failure never escapes [emit] or [subject].
  DartitectDiagnosticsEmitter({
    required DartitectDiagnosticReporterRegistration reporter,
    IdGenerator? idGenerator,
    this.detail = DartitectDiagnosticDetail.lifecycle,
    void Function(Object error, StackTrace stackTrace)? onReporterFailure,
  }) : _registration = reporter,
       _idGenerator = idGenerator ?? SecureUuidV4Generator(),
       _safeReporter = SafeDartitectDiagnosticReporter(
         reporter: reporter.reporter,
         onFailure: onReporterFailure,
       );

  final DartitectDiagnosticReporterRegistration _registration;
  final IdGenerator _idGenerator;
  final SafeDartitectDiagnosticReporter _safeReporter;
  var _sequence = 0;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Configured diagnostic detail. It never changes runtime semantics.
  final DartitectDiagnosticDetail detail;

  /// Number of events admitted by this emitter.
  int get emittedCount => _sequence;

  /// Whether the destination was disabled after a failure.
  bool get reporterDisabled => _safeReporter.isDisabled;

  /// Whether owned destination teardown has begun.
  bool get isDisposed => _disposed;

  /// Allocates an opaque subject and emits its creation when enabled.
  DartitectDiagnosticSubject subject(
    DartitectDiagnosticSubjectKind kind, {
    DartitectDiagnosticSubject? parent,
    int generation = 0,
    int revision = 0,
  }) {
    if (_disposed || detail == DartitectDiagnosticDetail.off) {
      return DartitectDiagnosticSubject._disabled(kind);
    }
    final id = DartitectDiagnosticId._(_idGenerator.nextId());
    final subject = DartitectDiagnosticSubject._(this, kind, id);
    emit(
      subject,
      DartitectDiagnosticPhase.created,
      related: parent,
      generation: generation,
      revision: revision,
    );
    return subject;
  }

  /// Emits one allowlisted fact for an emitter-owned subject.
  void emit(
    DartitectDiagnosticSubject subject,
    DartitectDiagnosticPhase phase, {
    DartitectDiagnosticSubject? related,
    int generation = 0,
    int revision = 0,
  }) {
    if (_disposed || !_accepts(phase)) return;
    if (!identical(subject._emitter, this) || subject._id == null) {
      throw ArgumentError.value(
        subject,
        'subject',
        'Must be an enabled subject owned by this emitter.',
      );
    }
    if (related != null &&
        (!identical(related._emitter, this) || related._id == null)) {
      throw ArgumentError.value(
        related,
        'related',
        'Must be an enabled subject owned by this emitter.',
      );
    }
    _sequence += 1;
    _safeReporter.report(
      DartitectDiagnosticEvent._(
        sequence: _sequence,
        subjectKind: subject.kind,
        phase: phase,
        subjectId: subject._id,
        relatedSubjectId: related?._id,
        generation: generation,
        revision: revision,
      ),
    );
  }

  bool _accepts(DartitectDiagnosticPhase phase) {
    switch (detail) {
      case DartitectDiagnosticDetail.off:
        return false;
      case DartitectDiagnosticDetail.lifecycle:
        return switch (phase) {
          DartitectDiagnosticPhase.linked ||
          DartitectDiagnosticPhase.waiting ||
          DartitectDiagnosticPhase.updated => false,
          _ => true,
        };
      case DartitectDiagnosticDetail.topology:
        return true;
    }
  }

  /// Disposes only an explicitly owned destination.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _registration._disposeOwned();
  }

  @override
  Future<void> disposeAsync() => dispose();
}

/// Opaque handle used to emit facts without accepting domain payloads.
@experimentalDartitectApi
final class DartitectDiagnosticSubject {
  DartitectDiagnosticSubject._(this._emitter, this.kind, this._id);

  DartitectDiagnosticSubject._disabled(this.kind) : _emitter = null, _id = null;

  final DartitectDiagnosticsEmitter? _emitter;
  final DartitectDiagnosticId? _id;

  /// Fixed subject category.
  final DartitectDiagnosticSubjectKind kind;

  /// Opaque identifier, or `null` when diagnostics are off.
  DartitectDiagnosticId? get id => _id;

  /// Whether this subject emits no diagnostics.
  bool get isDisabled => _id == null;

  /// Emits an allowlisted fact through the owning emitter.
  void emit(
    DartitectDiagnosticPhase phase, {
    DartitectDiagnosticSubject? related,
    int generation = 0,
    int revision = 0,
  }) {
    _emitter?.emit(
      this,
      phase,
      related: related,
      generation: generation,
      revision: revision,
    );
  }
}
