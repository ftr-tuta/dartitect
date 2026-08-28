// The one intentionally empty catch preserves an already captured original
// crash when the best-effort crash-journal write is the secondary failure.
// ignore_for_file: dartitect_empty_catch

import 'dart:async';

import 'package:dartitect/dartitect.dart';

import 'dependency_graph.dart';
import 'journal.dart';
import 'models.dart';
import 'ports.dart';

/// Provider-neutral coordinator for one consumer-supplied dataset DAG.
final class SyncEngine<K, C, F extends Object> implements AsyncDisposable {
  /// Creates an engine for a validated dependency graph.
  SyncEngine({
    required Iterable<SyncDataset<K, C, F>> datasets,
    required this.graph,
    required this.checkpoints,
    this.leases,
    this.journal,
    this.cleanup,
    SyncClock clock = const SystemSyncClock(),
    IdGenerator? ids,
    SyncObserver<K> observer = const NoOpSyncObserver(),
    this.leaseTtl = const Duration(minutes: 5),
    this.maxRecentProgressEvents = 256,
    DartitectDiagnosticSubject? diagnostics,
  }) : _clock = clock,
       _ids = ids ?? SecureUuidV4Generator(),
       _observer = observer,
       _diagnostics = diagnostics,
       _datasets = <K, SyncDataset<K, C, F>>{
         for (final dataset in datasets) dataset.key: dataset,
       } {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.owner) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'SyncEngine requires an owner diagnostic subject.',
      );
    }
    if (leaseTtl <= Duration.zero) {
      throw ArgumentError.value(leaseTtl, 'leaseTtl', 'must be positive');
    }
    if (maxRecentProgressEvents <= 0) {
      throw ArgumentError.value(
        maxRecentProgressEvents,
        'maxRecentProgressEvents',
        'must be positive',
      );
    }
    if (_datasets.length != graph.keys.length ||
        !_datasets.keys.toSet().containsAll(graph.keys)) {
      throw ArgumentError('Dataset keys must exactly match the graph keys.');
    }
  }

  /// Consumer-supplied dependency graph.
  final SyncDependencyGraph<K> graph;

  /// Borrowed checkpoint persistence port.
  final SyncCheckpointStore<K, C> checkpoints;

  /// Optional borrowed mutual-exclusion port.
  final SyncLeaseStore? leases;

  /// Optional borrowed durable payload-free journal.
  final SyncRunJournal<K>? journal;

  /// Optional borrowed consumer cleanup invoked after lease release.
  final SyncRunCleanup? cleanup;

  /// Lease duration; policy for scheduling/retry remains consumer-owned.
  final Duration leaseTtl;

  /// Bound for the diagnostic recent-event ring.
  final int maxRecentProgressEvents;

  final Map<K, SyncDataset<K, C, F>> _datasets;
  final SyncClock _clock;
  final IdGenerator _ids;
  final SyncObserver<K> _observer;
  final DartitectDiagnosticSubject? _diagnostics;
  final Set<SyncRun<K, C, F>> _runs = <SyncRun<K, C, F>>{};
  Future<void>? _disposal;
  var _closing = false;
  var _diagnosticGeneration = 0;

  /// Active runs owned by this engine.
  int get activeRunCount => _runs.length;

  /// Starts a single-use run for an immutable plan.
  SyncRun<K, C, F> start({Iterable<K>? eligible, DateTime? deadline}) {
    if (_closing) throw StateError('SyncEngine is shutting down.');
    if (deadline != null && !deadline.isUtc) deadline = deadline.toUtc();
    final id = _ids.nextId();
    if (id.trim().isEmpty)
      throw StateError('SyncIdGenerator returned empty ID.');
    final run = SyncRun<K, C, F>._(
      runId: id,
      plan: graph.plan(eligible: eligible),
      deadline: deadline,
      maxRecentProgressEvents: maxRecentProgressEvents,
      diagnostics: _diagnostics?.child(
        DartitectDiagnosticSubjectKind.sync,
        generation: ++_diagnosticGeneration,
      ),
      diagnosticGeneration: _diagnosticGeneration,
    );
    _runs.add(run);
    unawaited(_execute(run));
    return run;
  }

  /// Starts replacement attempts for every interrupted journal summary.
  ///
  /// Already confirmed datasets are omitted; checkpoint authority still comes
  /// from [checkpoints], never from journal payload.
  Future<List<SyncRun<K, C, F>>> resumeIncomplete({DateTime? deadline}) async {
    if (_closing) throw StateError('SyncEngine is shutting down.');
    final durableJournal = journal;
    if (durableJournal == null) return <SyncRun<K, C, F>>[];
    final incomplete = await durableJournal.loadIncompleteAttempts();
    final runs = <SyncRun<K, C, F>>[];
    for (final attempt in incomplete) {
      final completed = attempt.completedDatasetKeys.toSet();
      final eligible = graph.keys.where((key) => !completed.contains(key));
      if (eligible.isNotEmpty) {
        runs.add(start(eligible: eligible, deadline: deadline));
      }
    }
    return List<SyncRun<K, C, F>>.unmodifiable(runs);
  }

  Future<void> _execute(SyncRun<K, C, F> run) async {
    final reports = <SyncDatasetReport<K, C, F>>[];
    final byKey = <K, SyncDatasetReport<K, C, F>>{};
    SyncLease? lease;
    SyncAuthority? authority;
    final startedAt = _clock.now();
    var journalReceipt = journal == null
        ? const SyncBoundaryReceipt.notRequired()
        : const SyncBoundaryReceipt.succeeded();
    var leaseReleaseReceipt = const SyncBoundaryReceipt.notRequired();
    var cleanupReceipt = const SyncBoundaryReceipt.succeeded();
    Object? terminalError;
    StackTrace? terminalStackTrace;
    K? activeKey;
    var activeApplication = const SyncBoundaryReceipt.notAttempted();
    var activeCheckpoint = const SyncBoundaryReceipt.notAttempted();
    var journalSequence = 0;
    Future<void> record(
      SyncJournalFact fact, {
      K? key,
      bool hasKey = false,
    }) async {
      final durableJournal = journal;
      if (durableJournal == null) return;
      journalSequence += 1;
      try {
        await durableJournal.append(
          SyncJournalEntry<K>(
            attemptId: run.runId,
            sequence: journalSequence,
            timestamp: _clock.now(),
            fact: fact,
            datasetKey: key,
            hasDatasetKey: hasKey,
          ),
        );
      } catch (error, stackTrace) {
        journalReceipt = SyncBoundaryReceipt.failed(error, stackTrace);
        rethrow;
      }
    }

    void retainTerminalError(Object error, StackTrace stackTrace) {
      terminalError ??= error;
      terminalStackTrace ??= stackTrace;
    }

    void addActiveReport({
      SyncDatasetStopReason? stopReason,
      bool cancelled = false,
    }) {
      final key = activeKey;
      if (key == null || byKey.containsKey(key)) return;
      final applied = activeApplication.status == SyncBoundaryStatus.succeeded;
      final report = SyncDatasetReport<K, C, F>(
        key: key,
        status: applied || !cancelled
            ? SyncDatasetStatus.incomplete
            : SyncDatasetStatus.cancelled,
        stopReason: stopReason,
        application: activeApplication,
        checkpoint: activeCheckpoint,
      );
      reports.add(report);
      byKey[key] = report;
      activeKey = null;
    }

    run._emit(SyncProgressPhase.runStarted, startedAt);
    _observe(() => _observer.runStarted(run.runId, run.plan.order.length));
    try {
      await record(SyncJournalFact.attemptStarted);
      final leaseStore = leases;
      if (leaseStore != null) {
        lease = await leaseStore.acquire(ownerId: run.runId, ttl: leaseTtl);
        if (lease == null) {
          for (final key in run.plan.order) {
            final report = SyncDatasetReport<K, C, F>(
              key: key,
              status: SyncDatasetStatus.skipped,
              stopReason: SyncDatasetStopReason.leaseUnavailable,
            );
            reports.add(report);
            byKey[key] = report;
            run._emit(SyncProgressPhase.datasetSkipped, _clock.now(), key: key);
            await record(
              SyncJournalFact.datasetSkipped,
              key: key,
              hasKey: true,
            );
          }
          return;
        }
        authority = _LeaseSyncAuthority(
          lease: lease,
          clock: _clock,
          ttl: leaseTtl,
          cancellation: run.cancellation,
          deadline: run.deadline,
        );
        leaseReleaseReceipt = const SyncBoundaryReceipt.notAttempted();
      }

      for (final key in run.plan.order) {
        final stopReason = _stopReason(run);
        if (stopReason != null) {
          final report = SyncDatasetReport<K, C, F>(
            key: key,
            status: SyncDatasetStatus.cancelled,
            stopReason: stopReason,
          );
          reports.add(report);
          byKey[key] = report;
          run._emit(SyncProgressPhase.cancelled, _clock.now(), key: key);
          await record(SyncJournalFact.datasetSkipped, key: key, hasKey: true);
          continue;
        }
        final blocked = run.plan.dependencies[key]!.any(
          (dependency) =>
              byKey[dependency]?.status != SyncDatasetStatus.succeeded,
        );
        if (blocked) {
          final report = SyncDatasetReport<K, C, F>(
            key: key,
            status: SyncDatasetStatus.skipped,
            stopReason: SyncDatasetStopReason.blockedDependency,
          );
          reports.add(report);
          byKey[key] = report;
          run._emit(SyncProgressPhase.datasetSkipped, _clock.now(), key: key);
          await record(SyncJournalFact.datasetSkipped, key: key, hasKey: true);
          _observe(() => _observer.datasetEnded(run.runId, key, 'skipped'));
          continue;
        }
        if (authority != null && !await authority.ensureAuthority()) {
          final report = SyncDatasetReport<K, C, F>(
            key: key,
            status: SyncDatasetStatus.skipped,
            stopReason: SyncDatasetStopReason.leaseExpired,
          );
          reports.add(report);
          byKey[key] = report;
          run._emit(SyncProgressPhase.datasetSkipped, _clock.now(), key: key);
          await record(SyncJournalFact.datasetSkipped, key: key, hasKey: true);
          continue;
        }

        run._emit(SyncProgressPhase.datasetStarted, _clock.now(), key: key);
        await record(SyncJournalFact.datasetStarted, key: key, hasKey: true);
        _observe(() => _observer.datasetStarted(run.runId, key));
        activeKey = key;
        activeApplication = const SyncBoundaryReceipt.notAttempted();
        activeCheckpoint = const SyncBoundaryReceipt.notAttempted();
        final C? checkpoint;
        try {
          checkpoint = await checkpoints.read(key, run.cancellation);
        } catch (error, stackTrace) {
          activeCheckpoint = SyncBoundaryReceipt.failed(error, stackTrace);
          rethrow;
        }
        run.cancellation.throwIfCancelled();
        final Result<SyncDatasetOutcome<C>, F> result;
        try {
          result = await _datasets[key]!.synchronize(
            SyncDatasetContext<K, C>(
              key: key,
              runId: run.runId,
              checkpoint: checkpoint,
              cancellation: run.cancellation,
              deadline: run.deadline,
              authority: authority,
            ),
          );
        } catch (error, stackTrace) {
          activeApplication = SyncBoundaryReceipt.failed(error, stackTrace);
          rethrow;
        }
        switch (result) {
          case Ok<dynamic>(:final value):
            final outcome = value as SyncDatasetOutcome<C>;
            activeApplication = const SyncBoundaryReceipt.succeeded();
            if (authority != null && !await authority.ensureAuthority()) {
              final report = SyncDatasetReport<K, C, F>(
                key: key,
                status: SyncDatasetStatus.incomplete,
                stopReason: SyncDatasetStopReason.leaseExpired,
                application: activeApplication,
                checkpoint: activeCheckpoint,
              );
              reports.add(report);
              byKey[key] = report;
              activeKey = null;
              run._emit(
                SyncProgressPhase.datasetSkipped,
                _clock.now(),
                key: key,
              );
              await record(
                SyncJournalFact.datasetSkipped,
                key: key,
                hasKey: true,
              );
              continue;
            }
            run.cancellation.throwIfCancelled();
            if (outcome.hasCheckpoint) {
              try {
                await checkpoints.write(
                  key,
                  outcome.checkpoint as C,
                  run.cancellation,
                  fencingToken: authority?.fencingToken,
                );
                activeCheckpoint = const SyncBoundaryReceipt.succeeded();
              } catch (error, stackTrace) {
                activeCheckpoint = SyncBoundaryReceipt.failed(
                  error,
                  stackTrace,
                );
                rethrow;
              }
            } else {
              activeCheckpoint = const SyncBoundaryReceipt.notRequired();
            }
            final report = SyncDatasetReport<K, C, F>(
              key: key,
              status: SyncDatasetStatus.succeeded,
              confirmedCheckpoint: outcome.checkpoint,
              hasConfirmedCheckpoint: outcome.hasCheckpoint,
              application: activeApplication,
              checkpoint: activeCheckpoint,
            );
            reports.add(report);
            byKey[key] = report;
            activeKey = null;
            run._emit(
              SyncProgressPhase.datasetSucceeded,
              _clock.now(),
              key: key,
            );
            await record(
              SyncJournalFact.datasetSucceeded,
              key: key,
              hasKey: true,
            );
            _observe(() => _observer.datasetEnded(run.runId, key, 'succeeded'));
          case Err<Object>(:final failure, :final stackTrace):
            activeApplication = SyncBoundaryReceipt.failed(failure, stackTrace);
            final report = SyncDatasetReport<K, C, F>(
              key: key,
              status: SyncDatasetStatus.failed,
              failure: failure as F,
              failureStackTrace: stackTrace,
              application: activeApplication,
              checkpoint: activeCheckpoint,
            );
            reports.add(report);
            byKey[key] = report;
            activeKey = null;
            run._emit(SyncProgressPhase.datasetFailed, _clock.now(), key: key);
            await record(SyncJournalFact.datasetFailed, key: key, hasKey: true);
            _observe(() => _observer.datasetEnded(run.runId, key, 'failed'));
        }
      }
    } on CancellationException {
      addActiveReport(
        stopReason: SyncDatasetStopReason.cancelled,
        cancelled: true,
      );
      try {
        for (final key in run.plan.order.where(
          (key) => !byKey.containsKey(key),
        )) {
          final report = SyncDatasetReport<K, C, F>(
            key: key,
            status: SyncDatasetStatus.cancelled,
            stopReason: SyncDatasetStopReason.cancelled,
          );
          reports.add(report);
          byKey[key] = report;
          await record(SyncJournalFact.datasetSkipped, key: key, hasKey: true);
        }
      } catch (error, stackTrace) {
        retainTerminalError(error, stackTrace);
      }
    } catch (error, stackTrace) {
      retainTerminalError(error, stackTrace);
      addActiveReport();
    } finally {
      final acquiredLease = lease;
      if (acquiredLease != null) {
        try {
          await acquiredLease.release();
          leaseReleaseReceipt = const SyncBoundaryReceipt.succeeded();
        } catch (error, stackTrace) {
          leaseReleaseReceipt = SyncBoundaryReceipt.failed(error, stackTrace);
          retainTerminalError(error, stackTrace);
        }
      }

      final runCleanup = cleanup;
      if (runCleanup != null) {
        try {
          await runCleanup.cleanup(run.runId);
        } catch (error, stackTrace) {
          cleanupReceipt = SyncBoundaryReceipt.failed(error, stackTrace);
          retainTerminalError(error, stackTrace);
        }
      }

      if (terminalError == null) {
        try {
          await record(SyncJournalFact.attemptCompleted);
        } catch (error, stackTrace) {
          retainTerminalError(error, stackTrace);
        }
      } else if (journalReceipt.status != SyncBoundaryStatus.failed) {
        try {
          await record(SyncJournalFact.attemptCrashed);
        } on Object {
          // The first terminal error stays primary; [record] retains the
          // independent journal failure in [journalReceipt].
        }
      }

      for (final key in run.plan.order.where(
        (key) => !byKey.containsKey(key),
      )) {
        final report = SyncDatasetReport<K, C, F>(
          key: key,
          status: SyncDatasetStatus.incomplete,
        );
        reports.add(report);
        byKey[key] = report;
      }

      final crashed = terminalError != null;
      run._emit(
        crashed ? SyncProgressPhase.runCrashed : SyncProgressPhase.runCompleted,
        _clock.now(),
      );
      _observe(
        () => _observer.runEnded(run.runId, crashed ? 'crashed' : 'completed'),
      );
      _runs.remove(run);
      try {
        await run._closeProgress();
      } catch (error, stackTrace) {
        cleanupReceipt = SyncBoundaryReceipt.failed(error, stackTrace);
        retainTerminalError(error, stackTrace);
      }

      final report = SyncReport<K, C, F>(
        runId: run.runId,
        startedAt: startedAt,
        finishedAt: _clock.now(),
        datasets: reports,
        journal: journalReceipt,
        leaseRelease: leaseReleaseReceipt,
        cleanup: cleanupReceipt,
      );
      final error = terminalError;
      if (error == null) {
        run._complete(report);
      } else {
        final stackTrace = terminalStackTrace ?? StackTrace.current;
        run._completeError(
          SyncRunTerminalException<K, C, F>(
            report: report,
            cause: error,
            causeStackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
    }
  }

  SyncDatasetStopReason? _stopReason(SyncRun<K, C, F> run) {
    if (run.cancellation.isCancelled) {
      return run.cancellation.reason == SyncDatasetStopReason.deadlineExceeded
          ? SyncDatasetStopReason.deadlineExceeded
          : SyncDatasetStopReason.cancelled;
    }
    final deadline = run.deadline;
    if (deadline != null && !_clock.now().isBefore(deadline)) {
      run.cancel(SyncDatasetStopReason.deadlineExceeded);
      return SyncDatasetStopReason.deadlineExceeded;
    }
    return null;
  }

  void _observe(void Function() action) {
    try {
      action();
    } on Object {
      // Optional payload-free diagnostics never change sync behavior.
      return;
    }
  }

  /// Cancels and drains all active runs; borrowed stores remain open.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _closing = true;
    final runs = _runs.toList(growable: false);
    for (final run in runs) {
      run.cancel('SyncEngine disposed');
    }
    await Future.wait<void>(
      runs.map((run) => run.done.then<void>((_) {}, onError: (_, _) {})),
    );
    _diagnostics?.emit(DartitectDiagnosticPhase.disposed);
  }
}

final class _LeaseSyncAuthority implements SyncAuthority {
  const _LeaseSyncAuthority({
    required SyncLease lease,
    required SyncClock clock,
    required Duration ttl,
    required CancellationSignal cancellation,
    required DateTime? deadline,
  }) : _lease = lease,
       _clock = clock,
       _ttl = ttl,
       _cancellation = cancellation,
       _deadline = deadline;

  final SyncLease _lease;
  final SyncClock _clock;
  final Duration _ttl;
  final CancellationSignal _cancellation;
  final DateTime? _deadline;

  @override
  String get ownerId => _lease.ownerId;

  @override
  int get fencingToken => _lease.fencingToken;

  @override
  DateTime get expiresAt => _lease.expiresAt;

  @override
  Future<bool> ensureAuthority() async {
    _cancellation.throwIfCancelled();
    final now = _clock.now();
    final deadline = _deadline;
    if (deadline != null && !now.isBefore(deadline)) return false;
    if (expiresAt.isAfter(now.add(_ttl ~/ 3))) return true;
    return renew();
  }

  @override
  Future<bool> renew() async {
    _cancellation.throwIfCancelled();
    final now = _clock.now();
    final deadline = _deadline;
    if (deadline != null && !now.isBefore(deadline)) return false;
    if (!await _lease.renew(_ttl)) return false;
    return expiresAt.isAfter(_clock.now());
  }
}

/// Owner of one cancelable synchronization attempt and its progress stream.
final class SyncRun<K, C, F extends Object> implements AsyncDisposable {
  SyncRun._({
    required this.runId,
    required this.plan,
    required this.deadline,
    required int maxRecentProgressEvents,
    required DartitectDiagnosticSubject? diagnostics,
    required int diagnosticGeneration,
  }) : _cancellation = CancellationSource(),
       _diagnostics = diagnostics,
       _diagnosticGeneration = diagnosticGeneration,
       _progress = SyncProgressController<K>(
         maxRecentEvents: maxRecentProgressEvents,
       );

  /// Stable run identifier.
  final String runId;

  /// Immutable plan used by this attempt.
  final SyncPlan<K> plan;

  /// Optional UTC command deadline.
  final DateTime? deadline;

  final CancellationSource _cancellation;
  final Completer<SyncReport<K, C, F>> _completion =
      Completer<SyncReport<K, C, F>>();
  final SyncProgressController<K> _progress;
  final DartitectDiagnosticSubject? _diagnostics;
  final int _diagnosticGeneration;
  var _sequence = 0;

  /// Borrowed cooperative cancellation signal.
  CancellationSignal get cancellation => _cancellation.signal;

  /// Read-only progress owned by this run.
  SyncProgressStream<K> get progress => _progress.stream;

  /// Terminal report, or the original unexpected crash.
  Future<SyncReport<K, C, F>> get done => _completion.future;

  /// Requests cooperative cancellation exactly once.
  void cancel([Object? reason]) => _cancellation.cancel(reason);

  void _emit(SyncProgressPhase phase, DateTime timestamp, {K? key}) {
    _sequence += 1;
    _diagnostics?.emit(
      switch (phase) {
        SyncProgressPhase.runStarted => DartitectDiagnosticPhase.started,
        SyncProgressPhase.runCompleted => DartitectDiagnosticPhase.succeeded,
        SyncProgressPhase.runCrashed => DartitectDiagnosticPhase.crashed,
        SyncProgressPhase.cancelled => DartitectDiagnosticPhase.cancelled,
        SyncProgressPhase.datasetFailed => DartitectDiagnosticPhase.failed,
        SyncProgressPhase.datasetStarted ||
        SyncProgressPhase.datasetSucceeded ||
        SyncProgressPhase.datasetSkipped => DartitectDiagnosticPhase.updated,
      },
      generation: _diagnosticGeneration,
      revision: _sequence,
    );
    _progress.add(
      SyncProgressEvent<K>(
        runId: runId,
        sequence: _sequence,
        phase: phase,
        timestamp: timestamp,
        key: key,
      ),
    );
  }

  void _complete(SyncReport<K, C, F> report) {
    if (!_completion.isCompleted) _completion.complete(report);
  }

  void _completeError(Object error, StackTrace stackTrace) {
    if (!_completion.isCompleted) {
      _completion.completeError(error, stackTrace);
    }
  }

  Future<void> _closeProgress() async {
    await _progress.close();
    _diagnostics?.emit(
      DartitectDiagnosticPhase.disposed,
      generation: _diagnosticGeneration,
      revision: _sequence,
    );
  }

  /// Cancels this run and waits for terminal cleanup.
  @override
  Future<void> disposeAsync() async {
    cancel('SyncRun disposed');
    await done.then<void>((_) {}, onError: (_, _) {});
  }
}
