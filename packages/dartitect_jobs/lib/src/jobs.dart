import 'dart:async';
import 'dart:collection';

import 'package:dartitect/dartitect.dart';

/// Current provider-neutral job envelope protocol version.
const int currentJobProtocolVersion = 1;

/// Transferable metadata and a consumer-validated job payload.
final class JobEnvelope<P> {
  /// Creates a versioned job request.
  JobEnvelope({
    this.protocolVersion = currentJobProtocolVersion,
    required this.jobId,
    required this.definition,
    required this.deadline,
    required this.payload,
  }) {
    if (protocolVersion <= 0) {
      throw ArgumentError.value(protocolVersion, 'protocolVersion');
    }
    if (jobId.trim().isEmpty) {
      throw ArgumentError.value(jobId, 'jobId', 'Must not be empty.');
    }
    if (definition.trim().isEmpty) {
      throw ArgumentError.value(definition, 'definition', 'Must not be empty.');
    }
    if (!deadline.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
  }

  /// Version negotiated before consumer work starts.
  final int protocolVersion;

  /// Consumer-safe identifier used for bounded deduplication.
  final String jobId;

  /// Registered definition key.
  final String definition;

  /// Absolute UTC execution deadline.
  final DateTime deadline;

  /// Consumer-owned transferable payload.
  final P payload;
}

/// Stable rejection before, or at an asynchronous admission boundary.
enum JobRejection {
  /// The envelope protocol is unsupported.
  unsupportedProtocol,

  /// No matching definition was registered.
  unknownDefinition,

  /// The consumer rejected the payload.
  invalidPayload,

  /// The deadline elapsed before execution.
  deadlineExceeded,

  /// The dispatcher is closing.
  notReady,

  /// The bounded concurrent execution capacity is full.
  atCapacity,

  /// A consumer-provided distributed lease could not be acquired.
  leaseUnavailable,
}

/// Immediate or terminal acknowledgement for a job ID.
sealed class JobAck<R, F extends Object> {
  const JobAck(this.jobId);

  /// Identifier copied from the envelope.
  final String jobId;
}

/// The request was admitted and a terminal acknowledgement will follow.
final class JobAccepted<R, F extends Object> extends JobAck<R, F> {
  /// Creates an admission acknowledgement.
  const JobAccepted(super.jobId);
}

/// The request was rejected without executing consumer work.
final class JobRejected<R, F extends Object> extends JobAck<R, F> {
  /// Creates a closed rejection.
  const JobRejected(super.jobId, this.reason);

  /// Stable rejection category.
  final JobRejection reason;
}

/// The handler completed successfully.
final class JobCompleted<R, F extends Object> extends JobAck<R, F> {
  /// Creates a successful terminal acknowledgement.
  const JobCompleted(super.jobId, this.result);

  /// Consumer-defined result.
  final R result;
}

/// The handler returned an expected typed failure.
final class JobFailed<R, F extends Object> extends JobAck<R, F> {
  /// Creates an expected-failure terminal acknowledgement.
  const JobFailed(super.jobId, this.failure, this.stackTrace);

  /// Consumer-defined expected failure.
  final F failure;

  /// Stack captured where the expected failure was produced.
  final StackTrace stackTrace;
}

/// Accepted request, terminal result, and cooperative cancellation handle.
final class JobReceipt<R, F extends Object> {
  /// Creates a receipt owned by the dispatcher.
  const JobReceipt({
    required this.ack,
    required this.terminal,
    required bool Function(Object? reason) cancel,
  }) : _cancel = cancel;

  /// Immediate admission acknowledgement.
  final JobAck<R, F> ack;

  /// Deduplicated terminal acknowledgement.
  final Future<JobAck<R, F>> terminal;

  final bool Function(Object? reason) _cancel;

  /// Requests cooperative cancellation if this receipt owns active work.
  bool cancel([Object? reason]) => _cancel(reason);
}

/// Execution context passed to a job handler.
final class JobExecutionContext<P> {
  /// Creates an execution context with an optional fencing token.
  const JobExecutionContext({required this.command, this.fencingToken});

  /// Cancellation, deadline, execution ID, and typed progress.
  final CommandExecutionContext<P> command;

  /// Consumer lease generation, when a lease port is configured.
  final int? fencingToken;
}

/// Isolate-local handler built inside one owned graph.
abstract interface class JobHandler<P, R, F extends Object, Q> {
  /// Executes one validated payload without hidden retry behavior.
  Future<Result<R, F>> execute(P payload, JobExecutionContext<Q> context);
}

/// One registered, typed job contract and graph factory.
final class JobDefinition<P, R, F extends Object, Q> {
  /// Creates a definition with consumer validation and graph construction.
  JobDefinition({
    required this.name,
    required this.createGraph,
    bool Function(P payload)? validatePayload,
  }) : validatePayload = validatePayload ?? ((_) => true) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
  }

  /// Stable definition key carried by the envelope.
  final String name;

  /// Pure, synchronous consumer payload validation.
  final bool Function(P payload) validatePayload;

  /// Creates a fresh owned graph for one accepted execution.
  final Future<OwnedGraph<JobHandler<P, R, F, Q>>> Function(P payload)
  createGraph;
}

/// Previously persisted terminal receipt used for cross-process deduplication.
abstract interface class JobReceiptStore<R, F extends Object> {
  /// Reads a terminal acknowledgement, or returns `null` when absent.
  Future<JobAck<R, F>?> read(String jobId);

  /// Persists a terminal acknowledgement after consumer work completes.
  Future<void> write(JobAck<R, F> terminal);
}

/// Acquired distributed execution lease carrying a fencing generation.
abstract interface class JobLease implements AsyncDisposable {
  /// Strictly positive generation supplied to fenced consumer writes.
  int get fencingToken;
}

/// Optional consumer-owned lease provider.
abstract interface class JobLeasePort {
  /// Acquires a lease through [deadline], or returns `null` if unavailable.
  Future<JobLease?> acquire(String jobId, DateTime deadline);
}

/// UTC time source used for deterministic admission and deadline tests.
abstract interface class JobClock {
  /// Current UTC time.
  DateTime now();
}

/// System UTC job clock.
final class SystemJobClock implements JobClock {
  /// Creates the system clock.
  const SystemJobClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Bounded dispatcher with deduplication and one owned graph per job.
final class JobDispatcher<P, R, F extends Object, Q>
    implements AsyncDisposable {
  /// Creates a dispatcher from uniquely named definitions.
  JobDispatcher({
    required Iterable<JobDefinition<P, R, F, Q>> definitions,
    this.maxConcurrent = 4,
    this.maxRememberedJobs = 128,
    JobClock clock = const SystemJobClock(),
    this.receiptStore,
    this.leasePort,
    ProgressReporter<Q> Function(JobEnvelope<P> envelope)? progressReporter,
    DartitectDiagnosticSubject? diagnostics,
  }) : _clock = clock,
       _diagnostics = diagnostics,
       _progressReporter =
           progressReporter ?? ((_) => const NoOpProgressReporter<Never>()),
       _definitions = <String, JobDefinition<P, R, F, Q>>{} {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.owner) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'JobDispatcher requires an owner diagnostic subject.',
      );
    }
    if (maxConcurrent <= 0 || maxRememberedJobs <= 0) {
      throw ArgumentError('Job dispatcher bounds must be positive.');
    }
    for (final definition in definitions) {
      if (_definitions.containsKey(definition.name)) {
        throw ArgumentError.value(
          definition.name,
          'definitions',
          'Definition names must be unique.',
        );
      }
      _definitions[definition.name] = definition;
    }
  }

  /// Maximum jobs executing concurrently.
  final int maxConcurrent;

  /// Maximum active plus retained deduplication entries.
  final int maxRememberedJobs;

  /// Optional durable deduplication store.
  final JobReceiptStore<R, F>? receiptStore;

  /// Optional consumer-owned lease provider.
  final JobLeasePort? leasePort;

  final JobClock _clock;
  final ProgressReporter<Q> Function(JobEnvelope<P>) _progressReporter;
  final DartitectDiagnosticSubject? _diagnostics;
  final Map<String, JobDefinition<P, R, F, Q>> _definitions;
  final Map<String, _JobEntry<R, F>> _jobs = <String, _JobEntry<R, F>>{};
  final ListQueue<String> _completedJobIds = ListQueue<String>();
  var _executionId = 0;
  var _activeCount = 0;
  var _closing = false;
  Future<void>? _disposal;

  /// Whether new jobs may be admitted.
  bool get isReady => !_closing;

  /// Number of consumer handlers currently executing.
  int get activeCount => _activeCount;

  /// Number of active and retained deduplication entries.
  int get rememberedCount => _jobs.length;

  /// Accepts, rejects, or joins one job without waiting for completion.
  JobReceipt<R, F> accept(
    JobEnvelope<P> envelope, {
    CancellationSignal? cancellation,
  }) {
    final rejection = _validate(envelope);
    if (rejection != null) return _rejected(envelope.jobId, rejection);
    final existing = _jobs[envelope.jobId];
    if (existing != null) {
      return JobReceipt<R, F>(
        ack: JobAccepted<R, F>(envelope.jobId),
        terminal: existing.terminal,
        cancel: (_) => false,
      );
    }
    _evictCompleted();
    if (_jobs.length >= maxRememberedJobs || _activeCount >= maxConcurrent) {
      return _rejected(envelope.jobId, JobRejection.atCapacity);
    }

    final source = CancellationSource();
    final externalRegistration = cancellation?.register(source.cancel);
    final executionId = ++_executionId;
    final entry = _JobEntry<R, F>(
      source,
      externalRegistration,
      _diagnostics?.child(
        DartitectDiagnosticSubjectKind.job,
        generation: executionId,
      ),
    );
    _jobs[envelope.jobId] = entry;
    _activeCount += 1;
    entry.diagnostics?.emit(
      DartitectDiagnosticPhase.started,
      generation: executionId,
    );
    entry.terminal = _execute(envelope, executionId, entry);
    unawaited(
      entry.terminal.then<void>(
        (_) => _markCompleted(envelope.jobId),
        onError: (_, _) => _markCompleted(envelope.jobId),
      ),
    );
    return JobReceipt<R, F>(
      ack: JobAccepted<R, F>(envelope.jobId),
      terminal: entry.terminal,
      cancel: (reason) {
        if (entry.isComplete || entry.source.signal.isCancelled) return false;
        entry.source.cancel(reason ?? 'Job receipt cancelled');
        return true;
      },
    );
  }

  /// Accepts a job and waits for its terminal acknowledgement.
  Future<JobAck<R, F>> handle(
    JobEnvelope<P> envelope, {
    CancellationSignal? cancellation,
  }) => accept(envelope, cancellation: cancellation).terminal;

  JobRejection? _validate(JobEnvelope<P> envelope) {
    if (_closing) return JobRejection.notReady;
    if (envelope.protocolVersion != currentJobProtocolVersion) {
      return JobRejection.unsupportedProtocol;
    }
    final definition = _definitions[envelope.definition];
    if (definition == null) return JobRejection.unknownDefinition;
    if (!_clock.now().toUtc().isBefore(envelope.deadline)) {
      return JobRejection.deadlineExceeded;
    }
    if (!definition.validatePayload(envelope.payload)) {
      return JobRejection.invalidPayload;
    }
    return null;
  }

  JobReceipt<R, F> _rejected(String jobId, JobRejection reason) {
    final ack = JobRejected<R, F>(jobId, reason);
    return JobReceipt<R, F>(
      ack: ack,
      terminal: Future<JobAck<R, F>>.value(ack),
      cancel: (_) => false,
    );
  }

  Future<JobAck<R, F>> _execute(
    JobEnvelope<P> envelope,
    int executionId,
    _JobEntry<R, F> entry,
  ) async {
    Timer? deadlineTimer;
    JobLease? lease;
    OwnedGraph<JobHandler<P, R, F, Q>>? graph;
    try {
      final stored = await receiptStore?.read(envelope.jobId);
      if (stored != null) {
        entry.diagnostics?.emit(
          DartitectDiagnosticPhase.succeeded,
          generation: executionId,
        );
        return stored;
      }
      entry.source.signal.throwIfCancelled();
      final remaining = envelope.deadline.difference(_clock.now().toUtc());
      if (remaining <= Duration.zero) {
        return JobRejected<R, F>(envelope.jobId, JobRejection.deadlineExceeded);
      }
      deadlineTimer = Timer(
        remaining,
        () => entry.source.cancel('Job deadline exceeded'),
      );
      final port = leasePort;
      if (port != null) {
        lease = await port.acquire(envelope.jobId, envelope.deadline);
        if (lease == null) {
          return JobRejected<R, F>(
            envelope.jobId,
            JobRejection.leaseUnavailable,
          );
        }
        if (lease.fencingToken <= 0) {
          throw StateError('Job lease fencingToken must be positive.');
        }
      }
      entry.source.signal.throwIfCancelled();
      final definition = _definitions[envelope.definition]!;
      graph = await definition.createGraph(envelope.payload);
      final command = CommandExecutionContext<Q>(
        executionId: executionId,
        cancellation: entry.source.signal,
        deadline: envelope.deadline,
        now: _clock.now,
        progress: SafeProgressReporter<Q>(
          reporter: _progressReporter(envelope),
        ),
      );
      final result = await graph.use(
        (handler) => handler.execute(
          envelope.payload,
          JobExecutionContext<Q>(
            command: command,
            fencingToken: lease?.fencingToken,
          ),
        ),
      );
      final terminal = switch (result) {
        Ok<dynamic>(:final value) => JobCompleted<R, F>(
          envelope.jobId,
          value as R,
        ),
        Err<Object>(:final failure, :final stackTrace) => JobFailed<R, F>(
          envelope.jobId,
          failure as F,
          stackTrace,
        ),
      };
      entry.diagnostics?.emit(
        terminal is JobCompleted<R, F>
            ? DartitectDiagnosticPhase.succeeded
            : DartitectDiagnosticPhase.failed,
        generation: executionId,
      );
      await receiptStore?.write(terminal);
      return terminal;
    } on CancellationException {
      entry.diagnostics?.emit(
        DartitectDiagnosticPhase.cancelled,
        generation: executionId,
      );
      rethrow;
    } catch (_) {
      entry.diagnostics?.emit(
        DartitectDiagnosticPhase.crashed,
        generation: executionId,
      );
      rethrow;
    } finally {
      deadlineTimer?.cancel();
      await graph?.disposeAsync();
      await lease?.disposeAsync();
      entry.externalRegistration?.dispose();
      entry.source.dispose();
      entry.isComplete = true;
      entry.diagnostics?.emit(
        DartitectDiagnosticPhase.disposed,
        generation: executionId,
      );
    }
  }

  void _markCompleted(String jobId) {
    _activeCount -= 1;
    _completedJobIds.add(jobId);
  }

  void _evictCompleted() {
    while (_jobs.length >= maxRememberedJobs && _completedJobIds.isNotEmpty) {
      _jobs.remove(_completedJobIds.removeFirst());
    }
  }

  /// Rejects admission, cancels active jobs, and drains every owned graph.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_closing) return;
    _closing = true;
    final entries = _jobs.values.toList(growable: false);
    for (final entry in entries) {
      if (!entry.isComplete) entry.source.cancel('JobDispatcher disposed');
    }
    await Future.wait<void>(
      entries.map(
        (entry) => entry.terminal.then<void>((_) {}, onError: (_, _) {}),
      ),
    );
    _jobs.clear();
    _completedJobIds.clear();
    _diagnostics?.emit(DartitectDiagnosticPhase.disposed);
  }
}

final class _JobEntry<R, F extends Object> {
  _JobEntry(this.source, this.externalRegistration, this.diagnostics);

  final CancellationSource source;
  final CancellationRegistration? externalRegistration;
  final DartitectDiagnosticSubject? diagnostics;
  late Future<JobAck<R, F>> terminal;
  var isComplete = false;
}
