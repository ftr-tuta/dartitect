// The one intentionally empty catch preserves an already captured original
// crash when the best-effort crash-journal write is the secondary failure.
// ignore_for_file: dartitect_empty_catch

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect/dartitect_incremental.dart';

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
    this.executionPolicy = const SyncExecutionPolicy.sequential(),
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
    if (executionPolicy.maxConcurrent <= 0) {
      throw ArgumentError.value(
        executionPolicy.maxConcurrent,
        'executionPolicy.maxConcurrent',
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

  /// Sequential by default, or bounded parallel across independent nodes.
  final SyncExecutionPolicy executionPolicy;

  final Map<K, SyncDataset<K, C, F>> _datasets;
  final SyncClock _clock;
  final IdGenerator _ids;
  final SyncObserver<K> _observer;
  final DartitectDiagnosticSubject? _diagnostics;
  final Set<SyncRun<K, C, F>> _runs = <SyncRun<K, C, F>>{};
  final _SerialExecutor _checkpointCalls = _SerialExecutor();
  final _SerialExecutor _journalCalls = _SerialExecutor();
  final _SerialExecutor _leaseCalls = _SerialExecutor();
  final _SerialExecutor _cleanupCalls = _SerialExecutor();
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
    final incomplete = await _journalCalls.run(
      durableJournal.loadIncompleteAttempts,
    );
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
    var journalSequence = 0;
    Future<void> record(
      SyncJournalFact fact, {
      K? key,
      bool hasKey = false,
    }) async {
      final durableJournal = journal;
      if (durableJournal == null) return;
      try {
        await _journalCalls.run(() async {
          journalSequence += 1;
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
        });
      } catch (error, stackTrace) {
        journalReceipt = SyncBoundaryReceipt.failed(error, stackTrace);
        rethrow;
      }
    }

    void retainTerminalError(Object error, StackTrace stackTrace) {
      terminalError ??= error;
      terminalStackTrace ??= stackTrace;
    }

    run._emit(SyncProgressPhase.runStarted, startedAt);
    _observe(() => _observer.runStarted(run.runId, run.plan.order.length));
    try {
      await record(SyncJournalFact.attemptStarted);
      final leaseStore = leases;
      if (leaseStore != null) {
        lease = await _leaseCalls.run(
          () => leaseStore.acquire(ownerId: run.runId, ttl: leaseTtl),
        );
        if (lease == null) {
          for (final key in run.plan.order) {
            final report = SyncDatasetReport<K, C, F>(
              key: key,
              status: SyncDatasetStatus.skipped,
              stopReason: SyncDatasetStopReason.leaseUnavailable,
            );
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
          serial: _leaseCalls,
        );
        leaseReleaseReceipt = const SyncBoundaryReceipt.notAttempted();
      }

      if (executionPolicy.kind == SyncExecutionPolicyKind.sequential) {
        await _executeSequential(run, byKey, authority, record);
      } else {
        await _executeParallel(run, byKey, authority, record);
      }
    } on CancellationException {
      try {
        for (final key in run.plan.order.where(
          (key) => !byKey.containsKey(key),
        )) {
          final report = SyncDatasetReport<K, C, F>(
            key: key,
            status: SyncDatasetStatus.cancelled,
            stopReason: SyncDatasetStopReason.cancelled,
          );
          byKey[key] = report;
          await record(SyncJournalFact.datasetSkipped, key: key, hasKey: true);
        }
      } catch (error, stackTrace) {
        retainTerminalError(error, stackTrace);
      }
    } catch (error, stackTrace) {
      retainTerminalError(error, stackTrace);
    } finally {
      final acquiredLease = lease;
      if (acquiredLease != null) {
        try {
          await _leaseCalls.run(acquiredLease.release);
          leaseReleaseReceipt = const SyncBoundaryReceipt.succeeded();
        } catch (error, stackTrace) {
          leaseReleaseReceipt = SyncBoundaryReceipt.failed(error, stackTrace);
          retainTerminalError(error, stackTrace);
        }
      }

      final runCleanup = cleanup;
      if (runCleanup != null) {
        try {
          await _cleanupCalls.run(() => runCleanup.cleanup(run.runId));
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
        datasets: run.plan.order.map((key) => byKey[key]!),
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

  Future<void> _executeSequential(
    SyncRun<K, C, F> run,
    Map<K, SyncDatasetReport<K, C, F>> byKey,
    SyncAuthority? authority,
    _SyncRecord<K> record,
  ) async {
    for (final key in run.plan.order) {
      final preflight = await _preflightDataset(run, key, byKey, record);
      if (preflight != null) {
        byKey[key] = preflight;
        continue;
      }
      try {
        byKey[key] = await _executeDataset(run, key, authority, record);
      } on _SyncDatasetCrash<K, C, F> catch (crash) {
        byKey[key] = crash.report;
        Error.throwWithStackTrace(crash.cause, crash.stackTrace);
      }
    }
  }

  Future<void> _executeParallel(
    SyncRun<K, C, F> run,
    Map<K, SyncDatasetReport<K, C, F>> byKey,
    SyncAuthority? authority,
    _SyncRecord<K> record,
  ) async {
    final pending = <K>[...run.plan.order];
    final active = <K, Future<_SyncDatasetSettlement<K, C, F>>>{};

    Future<_SyncDatasetSettlement<K, C, F>> start(K key) async {
      try {
        return _SyncDatasetSettlement<K, C, F>.completed(
          key,
          await _executeDataset(run, key, authority, record),
        );
      } on _SyncDatasetCrash<K, C, F> catch (crash) {
        return _SyncDatasetSettlement<K, C, F>.crashed(key, crash);
      }
    }

    while (pending.isNotEmpty || active.isNotEmpty) {
      final stopReason = _stopReason(run);
      if (stopReason != null) {
        for (final key in List<K>.of(pending)) {
          byKey[key] = await _finishWithoutExecution(
            run,
            key,
            stopReason,
            record,
          );
          pending.remove(key);
        }
      }

      var changed = true;
      while (changed) {
        changed = false;
        for (final key in List<K>.of(pending)) {
          final dependencies = run.plan.dependencies[key]!;
          if (!dependencies.every(byKey.containsKey)) continue;
          if (dependencies.any(
            (dependency) =>
                byKey[dependency]!.status != SyncDatasetStatus.succeeded,
          )) {
            final report = await _finishWithoutExecution(
              run,
              key,
              SyncDatasetStopReason.blockedDependency,
              record,
            );
            byKey[key] = report;
            pending.remove(key);
            changed = true;
          }
        }
      }

      while (active.length < executionPolicy.maxConcurrent) {
        K? ready;
        for (final key in pending) {
          if (run.plan.dependencies[key]!.every(
            (dependency) =>
                byKey[dependency]?.status == SyncDatasetStatus.succeeded,
          )) {
            ready = key;
            break;
          }
        }
        if (ready == null) break;
        pending.remove(ready);
        active[ready] = start(ready);
      }

      if (active.isEmpty) {
        if (pending.isEmpty) continue;
        throw StateError('Sync DAG scheduler made no progress.');
      }

      final settlement = await Future.any(active.values);
      unawaited(active.remove(settlement.key)!);
      byKey[settlement.key] = settlement.report;
      final crash = settlement.crash;
      if (crash != null) {
        run.cancel(crash.cause);
        final draining = active.values.toList(growable: false);
        active.clear();
        for (final drained in await Future.wait(draining)) {
          byKey[drained.key] = drained.report;
        }
        Error.throwWithStackTrace(crash.cause, crash.stackTrace);
      }
    }
  }

  Future<SyncDatasetReport<K, C, F>?> _preflightDataset(
    SyncRun<K, C, F> run,
    K key,
    Map<K, SyncDatasetReport<K, C, F>> byKey,
    _SyncRecord<K> record,
  ) async {
    final stopReason = _stopReason(run);
    if (stopReason != null) {
      return _finishWithoutExecution(run, key, stopReason, record);
    }
    final blocked = run.plan.dependencies[key]!.any(
      (dependency) => byKey[dependency]?.status != SyncDatasetStatus.succeeded,
    );
    if (blocked) {
      return _finishWithoutExecution(
        run,
        key,
        SyncDatasetStopReason.blockedDependency,
        record,
      );
    }
    return null;
  }

  Future<SyncDatasetReport<K, C, F>> _finishWithoutExecution(
    SyncRun<K, C, F> run,
    K key,
    SyncDatasetStopReason reason,
    _SyncRecord<K> record,
  ) async {
    final cancelled =
        reason == SyncDatasetStopReason.cancelled ||
        reason == SyncDatasetStopReason.deadlineExceeded;
    final report = SyncDatasetReport<K, C, F>(
      key: key,
      status: cancelled
          ? SyncDatasetStatus.cancelled
          : SyncDatasetStatus.skipped,
      stopReason: reason,
    );
    run._emit(
      cancelled
          ? SyncProgressPhase.cancelled
          : SyncProgressPhase.datasetSkipped,
      _clock.now(),
      key: key,
    );
    await record(SyncJournalFact.datasetSkipped, key: key, hasKey: true);
    _observe(() => _observer.datasetEnded(run.runId, key, 'skipped'));
    return report;
  }

  Future<SyncDatasetReport<K, C, F>> _executeDataset(
    SyncRun<K, C, F> run,
    K key,
    SyncAuthority? authority,
    _SyncRecord<K> record,
  ) async {
    final tracker = _SyncDatasetTracker<K, C, F>(key);
    try {
      try {
        final stopReason = _stopReason(run);
        if (stopReason != null) {
          return await _finishStoppedDataset(run, tracker, stopReason, record);
        }
        if (authority != null && !await authority.ensureAuthority()) {
          return await _finishStoppedDataset(
            run,
            tracker,
            SyncDatasetStopReason.leaseExpired,
            record,
          );
        }

        run._emit(SyncProgressPhase.datasetStarted, _clock.now(), key: key);
        await record(SyncJournalFact.datasetStarted, key: key, hasKey: true);
        _observe(() => _observer.datasetStarted(run.runId, key));
        final C? checkpoint;
        try {
          checkpoint = await _checkpointCalls.run(
            () => checkpoints.read(key, run.cancellation),
          );
        } catch (error, stackTrace) {
          tracker.checkpoint = SyncBoundaryReceipt.failed(error, stackTrace);
          rethrow;
        }
        run.cancellation.throwIfCancelled();
        final context = SyncDatasetContext<K, C>(
          key: key,
          runId: run.runId,
          checkpoint: checkpoint,
          cancellation: run.cancellation,
          deadline: run.deadline,
          authority: authority,
        );
        final dataset = _datasets[key]!;
        final incremental = dataset.synchronizeIncrementally;
        if (incremental != null) {
          return await _executeIncrementalDataset(
            run,
            tracker,
            incremental(context),
            authority,
            record,
          );
        }
        return await _executeOneShotDataset(
          run,
          tracker,
          dataset,
          context,
          authority,
          record,
        );
      } on OperationDeadlineExceededException {
        run.cancel(SyncDatasetStopReason.deadlineExceeded);
        return await _finishStoppedDataset(
          run,
          tracker,
          SyncDatasetStopReason.deadlineExceeded,
          record,
        );
      } on CancellationException {
        return await _finishStoppedDataset(
          run,
          tracker,
          _stopReason(run) ?? SyncDatasetStopReason.cancelled,
          record,
        );
      } on _SyncLeaseExpiredException {
        return await _finishStoppedDataset(
          run,
          tracker,
          SyncDatasetStopReason.leaseExpired,
          record,
        );
      }
    } catch (error, stackTrace) {
      tracker.application =
          tracker.application.status == SyncBoundaryStatus.notAttempted
          ? SyncBoundaryReceipt.failed(error, stackTrace)
          : tracker.application;
      throw _SyncDatasetCrash<K, C, F>(
        report: tracker.terminal ?? tracker.interrupted(),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<SyncDatasetReport<K, C, F>> _executeOneShotDataset(
    SyncRun<K, C, F> run,
    _SyncDatasetTracker<K, C, F> tracker,
    SyncDataset<K, C, F> dataset,
    SyncDatasetContext<K, C> context,
    SyncAuthority? authority,
    _SyncRecord<K> record,
  ) async {
    final Result<SyncDatasetOutcome<C>, F> result;
    try {
      result = await dataset.synchronize(context);
    } catch (error, stackTrace) {
      tracker.application = SyncBoundaryReceipt.failed(error, stackTrace);
      rethrow;
    }
    switch (result) {
      case Ok<dynamic>(:final value):
        tracker.application = const SyncBoundaryReceipt.succeeded();
        await _confirmOutcome(
          run,
          tracker,
          value as SyncDatasetOutcome<C>,
          authority,
        );
        return _finishSuccessfulDataset(run, tracker, record);
      case Err<Object>(:final failure, :final stackTrace):
        tracker.application = SyncBoundaryReceipt.failed(failure, stackTrace);
        return _finishFailedDataset(
          run,
          tracker,
          failure as F,
          stackTrace,
          record,
        );
    }
  }

  Future<SyncDatasetReport<K, C, F>> _executeIncrementalDataset(
    SyncRun<K, C, F> run,
    _SyncDatasetTracker<K, C, F> tracker,
    IncrementalOperation<SyncDatasetOutcome<C>, F> operation,
    SyncAuthority? authority,
    _SyncRecord<K> record,
  ) async {
    final result = await operation.consume(
      cancellation: run.cancellation,
      deadline: run.deadline,
      onValue: (outcome, _) async {
        final stopReason = _stopReason(run);
        if (stopReason != null) throw CancellationException(stopReason);
        tracker.application = const SyncBoundaryReceipt.succeeded();
        await _confirmOutcome(run, tracker, outcome, authority);
      },
    );
    switch (result.outcome) {
      case Ok<void>():
        tracker.application = const SyncBoundaryReceipt.succeeded();
        if (tracker.checkpoint.status == SyncBoundaryStatus.notAttempted) {
          tracker.checkpoint = const SyncBoundaryReceipt.notRequired();
        }
        return _finishSuccessfulDataset(run, tracker, record);
      case Err<Object>(:final failure, :final stackTrace):
        tracker.application = SyncBoundaryReceipt.failed(failure, stackTrace);
        return _finishFailedDataset(
          run,
          tracker,
          failure as F,
          stackTrace,
          record,
        );
    }
  }

  Future<void> _confirmOutcome(
    SyncRun<K, C, F> run,
    _SyncDatasetTracker<K, C, F> tracker,
    SyncDatasetOutcome<C> outcome,
    SyncAuthority? authority,
  ) async {
    if (authority != null && !await authority.ensureAuthority()) {
      throw const _SyncLeaseExpiredException();
    }
    final stopReason = _stopReason(run);
    if (stopReason != null) throw CancellationException(stopReason);
    if (outcome.hasCheckpoint) {
      try {
        await _checkpointCalls.run(
          () => checkpoints.write(
            tracker.key,
            outcome.checkpoint as C,
            run.cancellation,
            fencingToken: authority?.fencingToken,
          ),
        );
        tracker.checkpoint = const SyncBoundaryReceipt.succeeded();
      } catch (error, stackTrace) {
        tracker.checkpoint = SyncBoundaryReceipt.failed(error, stackTrace);
        rethrow;
      }
      tracker.confirmedCheckpoint = outcome.checkpoint;
      tracker.hasConfirmedCheckpoint = true;
    } else if (tracker.checkpoint.status == SyncBoundaryStatus.notAttempted) {
      tracker.checkpoint = const SyncBoundaryReceipt.notRequired();
    }
    tracker.confirmedStepCount += 1;
    run._emitCheckpoint(tracker.key, tracker.confirmedStepCount, _clock.now());
  }

  Future<SyncDatasetReport<K, C, F>> _finishSuccessfulDataset(
    SyncRun<K, C, F> run,
    _SyncDatasetTracker<K, C, F> tracker,
    _SyncRecord<K> record,
  ) async {
    final report = tracker.complete(SyncDatasetStatus.succeeded);
    run._emit(
      SyncProgressPhase.datasetSucceeded,
      _clock.now(),
      key: tracker.key,
    );
    await record(
      SyncJournalFact.datasetSucceeded,
      key: tracker.key,
      hasKey: true,
    );
    _observe(() => _observer.datasetEnded(run.runId, tracker.key, 'succeeded'));
    return report;
  }

  Future<SyncDatasetReport<K, C, F>> _finishFailedDataset(
    SyncRun<K, C, F> run,
    _SyncDatasetTracker<K, C, F> tracker,
    F failure,
    StackTrace stackTrace,
    _SyncRecord<K> record,
  ) async {
    final report = tracker.complete(
      SyncDatasetStatus.failed,
      failure: failure,
      failureStackTrace: stackTrace,
    );
    run._emit(SyncProgressPhase.datasetFailed, _clock.now(), key: tracker.key);
    await record(SyncJournalFact.datasetFailed, key: tracker.key, hasKey: true);
    _observe(() => _observer.datasetEnded(run.runId, tracker.key, 'failed'));
    return report;
  }

  Future<SyncDatasetReport<K, C, F>> _finishStoppedDataset(
    SyncRun<K, C, F> run,
    _SyncDatasetTracker<K, C, F> tracker,
    SyncDatasetStopReason reason,
    _SyncRecord<K> record,
  ) async {
    final applied = tracker.application.status == SyncBoundaryStatus.succeeded;
    final cancelled =
        reason == SyncDatasetStopReason.cancelled ||
        reason == SyncDatasetStopReason.deadlineExceeded;
    final status = applied
        ? SyncDatasetStatus.incomplete
        : cancelled
        ? SyncDatasetStatus.cancelled
        : SyncDatasetStatus.skipped;
    final report = tracker.complete(status, stopReason: reason);
    run._emit(
      cancelled
          ? SyncProgressPhase.cancelled
          : SyncProgressPhase.datasetSkipped,
      _clock.now(),
      key: tracker.key,
    );
    await record(
      SyncJournalFact.datasetSkipped,
      key: tracker.key,
      hasKey: true,
    );
    _observe(() => _observer.datasetEnded(run.runId, tracker.key, 'skipped'));
    return report;
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
  _LeaseSyncAuthority({
    required SyncLease lease,
    required SyncClock clock,
    required Duration ttl,
    required CancellationSignal cancellation,
    required DateTime? deadline,
    required _SerialExecutor serial,
  }) : _lease = lease,
       _clock = clock,
       _ttl = ttl,
       _cancellation = cancellation,
       _deadline = deadline,
       _serial = serial;

  final SyncLease _lease;
  final SyncClock _clock;
  final Duration _ttl;
  final CancellationSignal _cancellation;
  final DateTime? _deadline;
  final _SerialExecutor _serial;
  Future<bool>? _ensuring;
  Future<bool>? _renewing;

  @override
  String get ownerId => _lease.ownerId;

  @override
  int get fencingToken => _lease.fencingToken;

  @override
  DateTime get expiresAt => _lease.expiresAt;

  @override
  Future<bool> ensureAuthority() => _ensuring ??= _ensure().whenComplete(() {
    _ensuring = null;
  });

  Future<bool> _ensure() async {
    _cancellation.throwIfCancelled();
    final now = _clock.now();
    final deadline = _deadline;
    if (deadline != null && !now.isBefore(deadline)) return false;
    if (expiresAt.isAfter(now.add(_ttl ~/ 3))) return true;
    return renew();
  }

  @override
  Future<bool> renew() => _renewing ??= _renew().whenComplete(() {
    _renewing = null;
  });

  Future<bool> _renew() async {
    _cancellation.throwIfCancelled();
    final now = _clock.now();
    final deadline = _deadline;
    if (deadline != null && !now.isBefore(deadline)) return false;
    if (!await _serial.run(() => _lease.renew(_ttl))) return false;
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
       ),
       _checkpointProgress =
           StreamController<SyncCheckpointProgressEvent<K>>.broadcast();

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
  final StreamController<SyncCheckpointProgressEvent<K>> _checkpointProgress;
  final DartitectDiagnosticSubject? _diagnostics;
  final int _diagnosticGeneration;
  var _sequence = 0;
  var _checkpointSequence = 0;

  /// Borrowed cooperative cancellation signal.
  CancellationSignal get cancellation => _cancellation.signal;

  /// Read-only progress owned by this run.
  SyncProgressStream<K> get progress => _progress.stream;

  /// Additive payload-free stream of confirmed incremental checkpoint steps.
  Stream<SyncCheckpointProgressEvent<K>> get checkpointProgress =>
      _checkpointProgress.stream;

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

  void _emitCheckpoint(K key, int confirmedStepCount, DateTime timestamp) {
    if (_checkpointProgress.isClosed) return;
    _checkpointSequence += 1;
    _checkpointProgress.add(
      SyncCheckpointProgressEvent<K>(
        runId: runId,
        sequence: _checkpointSequence,
        key: key,
        confirmedStepCount: confirmedStepCount,
        timestamp: timestamp,
      ),
    );
  }

  Future<void> _closeProgress() async {
    await _progress.close();
    await _checkpointProgress.close();
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

final class _SerialExecutor {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

typedef _SyncRecord<K> = Future<void> Function(
  SyncJournalFact fact, {
  K? key,
  bool hasKey,
});

final class _SyncLeaseExpiredException implements Exception {
  const _SyncLeaseExpiredException();
}

final class _SyncDatasetTracker<K, C, F extends Object> {
  _SyncDatasetTracker(this.key);

  final K key;
  SyncBoundaryReceipt application = const SyncBoundaryReceipt.notAttempted();
  SyncBoundaryReceipt checkpoint = const SyncBoundaryReceipt.notAttempted();
  C? confirmedCheckpoint;
  var hasConfirmedCheckpoint = false;
  var confirmedStepCount = 0;
  SyncDatasetReport<K, C, F>? terminal;

  SyncDatasetReport<K, C, F> complete(
    SyncDatasetStatus status, {
    F? failure,
    StackTrace? failureStackTrace,
    SyncDatasetStopReason? stopReason,
  }) => terminal ??= SyncDatasetReport<K, C, F>(
    key: key,
    status: status,
    failure: failure,
    failureStackTrace: failureStackTrace,
    stopReason: stopReason,
    confirmedCheckpoint: confirmedCheckpoint,
    hasConfirmedCheckpoint: hasConfirmedCheckpoint,
    confirmedStepCount: confirmedStepCount,
    application: application,
    checkpoint: checkpoint,
  );

  SyncDatasetReport<K, C, F> interrupted() => SyncDatasetReport<K, C, F>(
    key: key,
    status: SyncDatasetStatus.incomplete,
    confirmedCheckpoint: confirmedCheckpoint,
    hasConfirmedCheckpoint: hasConfirmedCheckpoint,
    confirmedStepCount: confirmedStepCount,
    application: application,
    checkpoint: checkpoint,
  );
}

final class _SyncDatasetCrash<K, C, F extends Object> implements Exception {
  const _SyncDatasetCrash({
    required this.report,
    required this.cause,
    required this.stackTrace,
  });

  final SyncDatasetReport<K, C, F> report;
  final Object cause;
  final StackTrace stackTrace;
}

final class _SyncDatasetSettlement<K, C, F extends Object> {
  const _SyncDatasetSettlement.completed(this.key, this.report) : crash = null;

  _SyncDatasetSettlement.crashed(this.key, _SyncDatasetCrash<K, C, F> failure)
    : report = failure.report,
      crash = failure;

  final K key;
  final SyncDatasetReport<K, C, F> report;
  final _SyncDatasetCrash<K, C, F>? crash;
}
