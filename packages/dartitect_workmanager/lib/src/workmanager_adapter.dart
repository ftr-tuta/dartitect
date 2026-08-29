import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// Version of the scalar Workmanager input envelope owned by Dartitect.
const int currentDartitectWorkmanagerEnvelopeVersion = 1;

/// Platforms covered by the stable Dartitect scheduling contract.
enum DartitectWorkmanagerPlatform {
  /// Android WorkManager.
  android,

  /// iOS background tasks.
  ios,

  /// macOS background tasks.
  macos,

  /// Browser service-worker scheduling.
  web,

  /// Linux systemd scheduling.
  linux,

  /// No upstream Workmanager implementation.
  windows,
}

/// Capability maturity reported independently from API stability.
enum DartitectWorkmanagerMaturity {
  /// Upstream platform implementation is production supported.
  stable,

  /// Dartitect contract is stable but upstream integration has limitations.
  preview,

  /// No implementation exists.
  unsupported,
}

/// Closed capability report for one platform.
final class DartitectWorkmanagerCapability {
  /// Creates a capability report.
  const DartitectWorkmanagerCapability({
    required this.platform,
    required this.maturity,
    required this.limitations,
  });

  /// Target platform.
  final DartitectWorkmanagerPlatform platform;

  /// Maturity of its current upstream implementation.
  final DartitectWorkmanagerMaturity maturity;

  /// Static, secret-free upstream limitations.
  final List<String> limitations;

  /// Whether the scheduler can be invoked.
  bool get supported => maturity != DartitectWorkmanagerMaturity.unsupported;

  /// Returns the closed report required by config-v1.
  static DartitectWorkmanagerCapability forPlatform(
    DartitectWorkmanagerPlatform platform,
  ) => switch (platform) {
    DartitectWorkmanagerPlatform.android ||
    DartitectWorkmanagerPlatform.ios ||
    DartitectWorkmanagerPlatform.macos => DartitectWorkmanagerCapability(
      platform: platform,
      maturity: DartitectWorkmanagerMaturity.stable,
      limitations: const <String>[],
    ),
    DartitectWorkmanagerPlatform.web => DartitectWorkmanagerCapability(
      platform: platform,
      maturity: DartitectWorkmanagerMaturity.preview,
      limitations: const <String>[
        'Execution depends on browser service-worker lifecycle and quotas.',
      ],
    ),
    DartitectWorkmanagerPlatform.linux => DartitectWorkmanagerCapability(
      platform: platform,
      maturity: DartitectWorkmanagerMaturity.preview,
      limitations: const <String>[
        'Execution depends on host systemd availability and configuration.',
      ],
    ),
    DartitectWorkmanagerPlatform.windows => DartitectWorkmanagerCapability(
      platform: platform,
      maturity: DartitectWorkmanagerMaturity.unsupported,
      limitations: const <String>[
        'Workmanager 0.10.9 does not provide a Windows implementation.',
      ],
    ),
  };

  /// Detects the Flutter target without constructing a plugin channel.
  static DartitectWorkmanagerPlatform currentPlatform() {
    if (kIsWeb) return DartitectWorkmanagerPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => DartitectWorkmanagerPlatform.android,
      TargetPlatform.iOS => DartitectWorkmanagerPlatform.ios,
      TargetPlatform.macOS => DartitectWorkmanagerPlatform.macos,
      TargetPlatform.linux => DartitectWorkmanagerPlatform.linux,
      TargetPlatform.windows => DartitectWorkmanagerPlatform.windows,
      TargetPlatform.fuchsia => DartitectWorkmanagerPlatform.linux,
    };
  }
}

/// Versioned, Workmanager-safe representation of a [JobEnvelope].
final class DartitectWorkmanagerEnvelope {
  /// Validates an envelope whose payload contains only Workmanager-safe data.
  DartitectWorkmanagerEnvelope({
    this.protocolVersion = currentDartitectWorkmanagerEnvelopeVersion,
    required this.jobId,
    required this.definition,
    required this.deadline,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload) {
    if (protocolVersion != currentDartitectWorkmanagerEnvelopeVersion) {
      throw ArgumentError.value(protocolVersion, 'protocolVersion');
    }
    if (jobId.trim().isEmpty || definition.trim().isEmpty) {
      throw ArgumentError('Job and definition identifiers must not be empty.');
    }
    if (!deadline.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
    if (!_isWorkmanagerValue(this.payload)) {
      throw ArgumentError.value(payload, 'payload', 'Contains unsafe values.');
    }
  }

  /// Decodes untrusted plugin input using a closed schema.
  factory DartitectWorkmanagerEnvelope.fromInputData(
    Map<String, dynamic>? input,
  ) {
    if (input == null ||
        input.keys.any(
          (key) => !const <String>{
            'dartitectVersion',
            'jobId',
            'definition',
            'deadlineMicrosUtc',
            'payload',
          }.contains(key),
        )) {
      throw const FormatException('Invalid Dartitect Workmanager envelope.');
    }
    final version = input['dartitectVersion'];
    final jobId = input['jobId'];
    final definition = input['definition'];
    final deadlineMicros = input['deadlineMicrosUtc'];
    final payload = input['payload'];
    if (version is! int ||
        jobId is! String ||
        definition is! String ||
        deadlineMicros is! int ||
        payload is! Map) {
      throw const FormatException('Invalid Dartitect Workmanager envelope.');
    }
    final normalizedPayload = <String, Object?>{};
    for (final entry in payload.entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid Workmanager payload key.');
      }
      normalizedPayload[entry.key as String] = entry.value;
    }
    try {
      return DartitectWorkmanagerEnvelope(
        protocolVersion: version,
        jobId: jobId,
        definition: definition,
        deadline: DateTime.fromMicrosecondsSinceEpoch(
          deadlineMicros,
          isUtc: true,
        ),
        payload: normalizedPayload,
      );
    } on ArgumentError {
      throw const FormatException('Invalid Dartitect Workmanager envelope.');
    }
  }

  /// Envelope protocol version.
  final int protocolVersion;

  /// Deduplication identifier.
  final String jobId;

  /// Registered [JobDefinition] name.
  final String definition;

  /// Absolute UTC execution deadline.
  final DateTime deadline;

  /// Consumer-owned scalar payload.
  final Map<String, Object?> payload;

  /// Encodes the closed envelope for Workmanager.
  Map<String, Object?> toInputData() => <String, Object?>{
    'dartitectVersion': protocolVersion,
    'jobId': jobId,
    'definition': definition,
    'deadlineMicrosUtc': deadline.microsecondsSinceEpoch,
    'payload': payload,
  };
}

bool _isWorkmanagerValue(Object? value) =>
    value == null ||
    value is bool ||
    value is int ||
    value is double ||
    value is String ||
    value is List<Object?> && value.every(_isWorkmanagerValue) ||
    value is Map<String, Object?> && value.values.every(_isWorkmanagerValue);

/// Closed outcome for plugin initialization and scheduling.
sealed class DartitectWorkmanagerOperationResult {
  const DartitectWorkmanagerOperationResult();
}

/// The plugin accepted the operation.
final class DartitectWorkmanagerOperationSucceeded
    extends DartitectWorkmanagerOperationResult {
  /// Creates a success result.
  const DartitectWorkmanagerOperationSucceeded();
}

/// The selected platform has no implementation.
final class DartitectWorkmanagerUnsupported
    extends DartitectWorkmanagerOperationResult {
  /// Creates a typed unsupported result.
  const DartitectWorkmanagerUnsupported(this.capability);

  /// Capability report explaining the unsupported result.
  final DartitectWorkmanagerCapability capability;
}

/// The plugin rejected or crashed during an operation.
final class DartitectWorkmanagerOperationFailed
    extends DartitectWorkmanagerOperationResult {
  /// Creates a failure preserving its original stack outside serialized state.
  const DartitectWorkmanagerOperationFailed(this.error, this.stackTrace);

  /// Original plugin error.
  final Object error;

  /// Original plugin stack.
  final StackTrace stackTrace;
}

/// Small plugin seam used for deterministic tests.
abstract interface class DartitectWorkmanagerPort {
  /// Initializes callback execution.
  Future<void> initialize(Function callbackDispatcher);

  /// Schedules a replacing one-off task.
  Future<void> schedule(
    String uniqueName,
    String taskName,
    Map<String, Object?> inputData,
  );

  /// Cancels pending work by unique name.
  Future<void> cancel(String uniqueName);
}

/// Default adapter around `workmanager ^0.10.9`.
final class PluginWorkmanagerPort implements DartitectWorkmanagerPort {
  /// Creates a port over the process-wide plugin singleton.
  PluginWorkmanagerPort({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  @override
  Future<void> initialize(Function callbackDispatcher) =>
      _workmanager.initialize(callbackDispatcher);

  @override
  Future<void> schedule(
    String uniqueName,
    String taskName,
    Map<String, Object?> inputData,
  ) => _workmanager.registerOneOffTask(
    uniqueName,
    taskName,
    inputData: Map<String, dynamic>.from(inputData),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );

  @override
  Future<void> cancel(String uniqueName) =>
      _workmanager.cancelByUniqueName(uniqueName);
}

/// Stable scheduling facade with a typed Windows result.
final class DartitectWorkmanagerScheduler {
  /// Creates a scheduler for an explicit or detected platform.
  DartitectWorkmanagerScheduler({
    DartitectWorkmanagerPort? port,
    DartitectWorkmanagerPlatform? platform,
  }) : _port = port ?? PluginWorkmanagerPort(),
       capability = DartitectWorkmanagerCapability.forPlatform(
         platform ?? DartitectWorkmanagerCapability.currentPlatform(),
       );

  final DartitectWorkmanagerPort _port;

  /// Current platform report.
  final DartitectWorkmanagerCapability capability;

  /// Initializes a top-level callback dispatcher.
  Future<DartitectWorkmanagerOperationResult> initialize(
    Function callbackDispatcher,
  ) => _run(() => _port.initialize(callbackDispatcher));

  /// Registers a versioned one-off envelope.
  Future<DartitectWorkmanagerOperationResult> schedule(
    DartitectWorkmanagerEnvelope envelope, {
    String? uniqueName,
  }) => _run(
    () => _port.schedule(
      uniqueName ?? envelope.jobId,
      envelope.definition,
      envelope.toInputData(),
    ),
  );

  /// Cancels pending work by its stable unique name.
  Future<DartitectWorkmanagerOperationResult> cancel(String uniqueName) =>
      _run(() => _port.cancel(uniqueName));

  Future<DartitectWorkmanagerOperationResult> _run(
    Future<void> Function() operation,
  ) async {
    if (!capability.supported) {
      return DartitectWorkmanagerUnsupported(capability);
    }
    try {
      await operation();
      return const DartitectWorkmanagerOperationSucceeded();
    } catch (error, stackTrace) {
      return DartitectWorkmanagerOperationFailed(error, stackTrace);
    }
  }
}

/// Sanitized callback receipt status.
enum DartitectWorkmanagerReceiptStatus {
  /// Handler completed.
  completed,

  /// Handler returned a typed failure or rejection.
  failed,

  /// Platform stopped or deadline cancelled execution.
  cancelled,

  /// Untrusted input could not be decoded.
  invalidEnvelope,

  /// Unexpected application crash.
  crashed,
}

/// Payload-free callback receipt.
final class DartitectWorkmanagerReceipt {
  /// Creates a versioned receipt.
  const DartitectWorkmanagerReceipt({
    required this.jobId,
    required this.status,
    required this.recordedAtUtc,
  });

  /// Safe job identifier.
  final String jobId;

  /// Closed execution status.
  final DartitectWorkmanagerReceiptStatus status;

  /// UTC completion time.
  final DateTime recordedAtUtc;
}

/// Consumer-owned durable receipt port.
abstract interface class DartitectWorkmanagerReceiptStore {
  /// Writes one sanitized callback receipt.
  Future<void> write(DartitectWorkmanagerReceipt receipt);
}

/// Fresh dispatcher graph factory invoked for every callback.
typedef DartitectWorkmanagerGraphFactory<P, R, F extends Object, Q> =
    Future<OwnedGraph<JobDispatcher<P, R, F, Q>>> Function();

/// Consumer payload decoder for a closed Workmanager payload map.
typedef DartitectWorkmanagerPayloadDecoder<P> = P Function(
  Map<String, Object?> payload,
);

/// Adapts Workmanager callbacks to a fresh, disposed [JobDispatcher] graph.
final class DartitectWorkmanagerCallback<P, R, F extends Object, Q> {
  /// Creates a callback adapter.
  DartitectWorkmanagerCallback({
    required this.createGraph,
    required this.decodePayload,
    this.receipts,
    DateTime Function()? now,
  }) : _now = now ?? _systemUtcNow;

  /// Fresh graph factory; never reused between callback executions.
  final DartitectWorkmanagerGraphFactory<P, R, F, Q> createGraph;

  /// Consumer-owned payload decoder.
  final DartitectWorkmanagerPayloadDecoder<P> decodePayload;

  /// Optional durable sanitized receipt store.
  final DartitectWorkmanagerReceiptStore? receipts;

  final DateTime Function() _now;
  final Map<String, CancellationSource> _active =
      <String, CancellationSource>{};

  /// Workmanager-compatible task callback.
  Future<bool> execute(String taskName, Map<String, dynamic>? inputData) async {
    DartitectWorkmanagerEnvelope envelope;
    try {
      envelope = DartitectWorkmanagerEnvelope.fromInputData(inputData);
    } on FormatException {
      await _record('', DartitectWorkmanagerReceiptStatus.invalidEnvelope);
      return false;
    }
    if (taskName != envelope.definition ||
        !_now().toUtc().isBefore(envelope.deadline)) {
      await _record(envelope.jobId, DartitectWorkmanagerReceiptStatus.failed);
      return false;
    }
    final source = CancellationSource();
    _active[taskName] = source;
    final timer = Timer(
      envelope.deadline.difference(_now().toUtc()),
      () => source.cancel('Dartitect Workmanager deadline exceeded'),
    );
    OwnedGraph<JobDispatcher<P, R, F, Q>>? graph;
    try {
      final payload = decodePayload(envelope.payload);
      graph = await createGraph();
      final terminal = await graph.root.handle(
        JobEnvelope<P>(
          jobId: envelope.jobId,
          definition: envelope.definition,
          deadline: envelope.deadline,
          payload: payload,
        ),
        cancellation: source.signal,
      );
      final success = terminal is JobCompleted<R, F>;
      await _record(
        envelope.jobId,
        success
            ? DartitectWorkmanagerReceiptStatus.completed
            : DartitectWorkmanagerReceiptStatus.failed,
      );
      return success;
    } on CancellationException {
      await _record(
        envelope.jobId,
        DartitectWorkmanagerReceiptStatus.cancelled,
      );
      return false;
    } catch (_) {
      await _record(envelope.jobId, DartitectWorkmanagerReceiptStatus.crashed);
      return false;
    } finally {
      timer.cancel();
      if (identical(_active[taskName], source)) _active.remove(taskName);
      await graph?.disposeAsync();
      source.dispose();
    }
  }

  /// Cooperatively cancels a running Android callback.
  Future<void> stopped(String taskName, StopReason _) async {
    _active[taskName]?.cancel('Workmanager stopped the task');
  }

  Future<void> _record(
    String jobId,
    DartitectWorkmanagerReceiptStatus status,
  ) async {
    await receipts?.write(
      DartitectWorkmanagerReceipt(
        jobId: jobId,
        status: status,
        recordedAtUtc: _now().toUtc(),
      ),
    );
  }
}

DateTime _systemUtcNow() => DateTime.now().toUtc();

/// Registers a callback adapter inside a consumer top-level dispatcher.
void runDartitectWorkmanagerDispatcher<P, R, F extends Object, Q>(
  DartitectWorkmanagerCallback<P, R, F, Q> callback,
) {
  Workmanager().executeTask(callback.execute, onTaskStopped: callback.stopped);
}
