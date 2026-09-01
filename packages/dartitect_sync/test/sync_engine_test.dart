import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect/dartitect_incremental.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:test/test.dart';

void main() {
  test('graph validates edges and produces stable topological order', () {
    final graph = SyncDependencyGraph<String>(
      keys: const <String>['catalog', 'images', 'search'],
      dependencies: const <String, List<String>>{
        'search': <String>['catalog'],
      },
    );

    expect(graph.plan().order, <String>['catalog', 'images', 'search']);
    expect(
      () => SyncDependencyGraph<String>(
        keys: const <String>['a'],
        dependencies: const <String, List<String>>{
          'a': <String>['a'],
        },
      ),
      throwsA(isA<SyncDependencyGraphException<String>>()),
    );
    expect(
      () => SyncDependencyGraph<String>(
        keys: const <String>['a', 'b'],
        dependencies: const <String, List<String>>{
          'a': <String>['b'],
          'b': <String>['a'],
        },
      ),
      throwsA(isA<SyncDependencyGraphException<String>>()),
    );
  });

  test(
    'failure blocks dependents but preserves independent branches',
    () async {
      final diagnostics = DartitectDiagnosticBuffer(capacity: 64);
      final emitter = DartitectDiagnosticsEmitter(
        reporter: DartitectDiagnosticReporterRegistration.borrowed(diagnostics),
        detail: DartitectDiagnosticDetail.topology,
      );
      final calls = <String>[];
      final checkpoints = _MemoryCheckpoints<String, int>();
      final datasets = <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'catalog',
          synchronize: (_) async {
            calls.add('catalog');
            return Err<_Failure>(const _Failure(), StackTrace.current);
          },
        ),
        SyncDataset<String, int, _Failure>(
          key: 'images',
          synchronize: (_) async {
            calls.add('images');
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(2),
            );
          },
        ),
        SyncDataset<String, int, _Failure>(
          key: 'search',
          synchronize: (_) async {
            calls.add('search');
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
      ];
      final engine = SyncEngine<String, int, _Failure>(
        datasets: datasets,
        graph: SyncDependencyGraph<String>(
          keys: const <String>['catalog', 'images', 'search'],
          dependencies: const <String, List<String>>{
            'search': <String>['catalog'],
          },
        ),
        checkpoints: checkpoints,
        diagnostics: emitter.subject(DartitectDiagnosticSubjectKind.owner),
      );

      final run = engine.start();
      final report = await run.done;

      expect(calls, <String>['catalog', 'images']);
      expect(
        report.datasets.map((dataset) => dataset.status),
        <SyncDatasetStatus>[
          SyncDatasetStatus.failed,
          SyncDatasetStatus.succeeded,
          SyncDatasetStatus.skipped,
        ],
      );
      expect(checkpoints.values['images'], 2);
      expect(run.progress.recent.last.phase, SyncProgressPhase.runCompleted);
      await engine.disposeAsync();
      expect(engine.activeRunCount, 0);
      expect(
        diagnostics.events
            .where(
              (event) =>
                  event.subjectKind == DartitectDiagnosticSubjectKind.sync,
            )
            .map((event) => event.phase),
        containsAll(<DartitectDiagnosticPhase>{
          DartitectDiagnosticPhase.started,
          DartitectDiagnosticPhase.failed,
          DartitectDiagnosticPhase.succeeded,
          DartitectDiagnosticPhase.disposed,
        }),
      );
      await emitter.dispose();
      diagnostics.dispose();
    },
  );

  test(
    'headless endpoint deduplicates and always disposes a fresh graph',
    () async {
      var graphCount = 0;
      var disposeCount = 0;
      final endpoint = HeadlessSyncEndpoint<int, int, _Failure>(
        createGraph: (payload) {
          graphCount += 1;
          return ResourceTransaction.create<
            HeadlessSyncHandler<int, int, _Failure>
          >((transaction) {
            transaction.own(
              _Handler(),
              (_) => disposeCount += 1,
              label: 'handler',
            );
            return _Handler();
          });
        },
        validatePayload: (payload) => payload >= 0,
      );
      final envelope = SyncCommandEnvelope<int>(
        requestId: 'request-1',
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        payload: 4,
      );

      final first = endpoint.accept(envelope);
      final duplicate = endpoint.accept(envelope);
      expect(first.ack, isA<SyncCommandAccepted<int, _Failure>>());
      expect(await first.terminal, isA<SyncCommandCompleted<int, _Failure>>());
      expect(
        await duplicate.terminal,
        isA<SyncCommandCompleted<int, _Failure>>(),
      );
      expect(graphCount, 1);
      expect(disposeCount, 1);

      final rejected = await endpoint.handle(
        SyncCommandEnvelope<int>(
          protocolVersion: 99,
          requestId: 'request-2',
          deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
          payload: 1,
        ),
      );
      expect(rejected, isA<SyncCommandRejected<int, _Failure>>());
      expect(graphCount, 1);
      await endpoint.disposeAsync();
    },
  );

  test(
    'headless dedup cache stays bounded without evicting active work',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var graphCount = 0;
      final endpoint = HeadlessSyncEndpoint<int, int, _Failure>(
        maxRememberedRequests: 1,
        createGraph: (_) {
          graphCount += 1;
          return ResourceTransaction.create((transaction) {
            final handler = _BlockingHandler(entered, release);
            transaction.own(handler, (_) {});
            return handler;
          });
        },
      );
      SyncCommandEnvelope<int> envelope(String id) => SyncCommandEnvelope<int>(
        requestId: id,
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        payload: 1,
      );

      final first = endpoint.accept(envelope('first'));
      await entered.future;
      final duplicate = endpoint.accept(envelope('first'));
      final atCapacity = endpoint.accept(envelope('second'));
      expect(duplicate.ack, isA<SyncCommandAccepted<int, _Failure>>());
      expect(atCapacity.ack, isA<SyncCommandRejected<int, _Failure>>());
      expect(
        (atCapacity.ack as SyncCommandRejected<int, _Failure>).reason,
        SyncCommandRejection.notReady,
      );
      expect(graphCount, 1);

      release.complete();
      await first.terminal;
      await duplicate.terminal;
      final afterCompletion = endpoint.accept(envelope('second'));
      expect(
        await afterCompletion.terminal,
        isA<SyncCommandCompleted<int, _Failure>>(),
      );
      expect(graphCount, 2);
      await endpoint.disposeAsync();
    },
  );

  test(
    'lease token fences checkpoints and progress history stays bounded',
    () async {
      final clock = _Clock(DateTime.utc(2026, 8, 24));
      final checkpoints = _MemoryCheckpoints<String, int>();
      final lease = _Lease(clock.now().add(const Duration(minutes: 2)), 7);
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>(
            key: 'notes',
            synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(3),
            ),
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: checkpoints,
        leases: _LeaseStore(lease),
        clock: clock,
        leaseTtl: const Duration(minutes: 1),
        maxRecentProgressEvents: 2,
      );

      final run = engine.start();
      final report = await run.done;

      expect(report.succeeded, isTrue);
      expect(checkpoints.fencingTokens, <int?>[7]);
      expect(lease.releaseCount, 1);
      expect(run.progress.recent, hasLength(2));
      expect(
        run.progress.recent.map((event) => event.sequence),
        orderedEquals(<int>[3, 4]),
      );
      await engine.disposeAsync();
    },
  );

  test('stale lease cannot authorize a consumer dataset commit', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 24));
    final lease = _Lease(
      clock.now().add(const Duration(minutes: 2)),
      7,
      renewResult: false,
    );
    var datasetApplied = false;
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (context) async {
            clock.value = clock.value.add(const Duration(minutes: 3));
            final authority = context.authority;
            if (authority == null || !await authority.ensureAuthority()) {
              return Err<_Failure>(const _Failure(), StackTrace.current);
            }
            datasetApplied = true;
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(1),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
      leases: _LeaseStore(lease),
      clock: clock,
      leaseTtl: const Duration(minutes: 1),
    );

    final report = await engine.start().done;

    expect(datasetApplied, isFalse);
    expect(report.datasets.single.status, SyncDatasetStatus.failed);
    expect(
      report.datasets.single.application.status,
      SyncBoundaryStatus.failed,
    );
    await engine.disposeAsync();
  });

  test('consumer store atomically rejects a stale fencing token', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 24));
    final lease = _Lease(clock.now().add(const Duration(minutes: 10)), 7);
    final dataset = _FencedDatasetStore(currentToken: 8);
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (context) async {
            final authority = context.authority!;
            if (!await authority.ensureAuthority() ||
                !dataset.tryCommit(authority.fencingToken)) {
              return Err<_Failure>(const _Failure(), StackTrace.current);
            }
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(1),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
      leases: _LeaseStore(lease),
      clock: clock,
      leaseTtl: const Duration(minutes: 1),
    );

    final report = await engine.start().done;

    expect(dataset.applied, isFalse);
    expect(report.datasets.single.status, SyncDatasetStatus.failed);
    await engine.disposeAsync();
  });

  test(
    'journal failure after application is not a generic terminal error',
    () async {
      final checkpoints = _MemoryCheckpoints<String, int>();
      var datasetApplied = false;
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>(
            key: 'notes',
            synchronize: (_) async {
              datasetApplied = true;
              return const Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.checkpoint(4),
              );
            },
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: checkpoints,
        journal: _FailingJournal<String>(SyncJournalFact.datasetSucceeded),
      );

      Object? terminalError;
      try {
        await engine.start().done;
      } catch (error) {
        terminalError = error;
      }

      expect(datasetApplied, isTrue);
      expect(checkpoints.values['notes'], 4);
      expect(
        terminalError,
        isA<SyncRunTerminalException<String, int, _Failure>>(),
      );
      final terminal =
          terminalError as SyncRunTerminalException<String, int, _Failure>;
      expect(terminal.cause, isA<StateError>());
      expect(
        terminal.report.datasets.single.application.status,
        SyncBoundaryStatus.succeeded,
      );
      expect(
        terminal.report.datasets.single.checkpoint.status,
        SyncBoundaryStatus.succeeded,
      );
      expect(terminal.report.journal.status, SyncBoundaryStatus.failed);
      expect(
        terminal.report.leaseRelease.status,
        SyncBoundaryStatus.notRequired,
      );
      expect(terminal.report.cleanup.status, SyncBoundaryStatus.succeeded);
      await engine.disposeAsync();
    },
  );

  test(
    'lease release failure is not a generic post-application error',
    () async {
      final clock = _Clock(DateTime.utc(2026, 8, 24));
      final lease = _Lease(
        clock.now().add(const Duration(minutes: 2)),
        9,
        releaseError: StateError('release failed'),
      );
      final checkpoints = _MemoryCheckpoints<String, int>();
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>(
            key: 'notes',
            synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(5),
            ),
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: checkpoints,
        leases: _LeaseStore(lease),
        clock: clock,
        leaseTtl: const Duration(minutes: 1),
      );

      Object? terminalError;
      try {
        await engine.start().done;
      } catch (error) {
        terminalError = error;
      }

      expect(checkpoints.values['notes'], 5);
      expect(
        terminalError,
        isA<SyncRunTerminalException<String, int, _Failure>>(),
      );
      final terminal =
          terminalError as SyncRunTerminalException<String, int, _Failure>;
      expect(terminal.cause, isA<StateError>());
      expect(
        terminal.report.datasets.single.application.status,
        SyncBoundaryStatus.succeeded,
      );
      expect(
        terminal.report.datasets.single.checkpoint.status,
        SyncBoundaryStatus.succeeded,
      );
      expect(terminal.report.leaseRelease.status, SyncBoundaryStatus.failed);
      expect(terminal.report.cleanup.status, SyncBoundaryStatus.succeeded);
      await engine.disposeAsync();
    },
  );

  test('checkpoint failure reports application without blind replay', () async {
    var datasetApplied = false;
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (_) async {
            datasetApplied = true;
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(6),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(
        writeError: StateError('checkpoint failed'),
      ),
    );

    final terminal = await _terminalFailure(engine.start().done);

    expect(datasetApplied, isTrue);
    expect(
      terminal.report.datasets.single.status,
      SyncDatasetStatus.incomplete,
    );
    expect(
      terminal.report.datasets.single.application.status,
      SyncBoundaryStatus.succeeded,
    );
    expect(
      terminal.report.datasets.single.checkpoint.status,
      SyncBoundaryStatus.failed,
    );
    await engine.disposeAsync();
  });

  test(
    'consumer cleanup failure has an independent terminal receipt',
    () async {
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>(
            key: 'notes',
            synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            ),
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: _MemoryCheckpoints<String, int>(),
        cleanup: const _FailingCleanup(),
      );

      final terminal = await _terminalFailure(engine.start().done);

      expect(
        terminal.report.datasets.single.application.status,
        SyncBoundaryStatus.succeeded,
      );
      expect(
        terminal.report.datasets.single.checkpoint.status,
        SyncBoundaryStatus.notRequired,
      );
      expect(terminal.report.cleanup.status, SyncBoundaryStatus.failed);
      await engine.disposeAsync();
    },
  );

  test('deadline and cooperative cancellation produce typed reports', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 24));
    var deadlineCalls = 0;
    final deadlineEngine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (_) async {
            deadlineCalls += 1;
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
      clock: clock,
    );
    final deadlineReport = await deadlineEngine
        .start(deadline: clock.now())
        .done;
    expect(deadlineCalls, 0);
    expect(
      deadlineReport.datasets.single.stopReason,
      SyncDatasetStopReason.deadlineExceeded,
    );
    await deadlineEngine.disposeAsync();

    final entered = Completer<void>();
    final cancellationEngine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (context) async {
            entered.complete();
            await context.cancellation.whenCancelled;
            context.cancellation.throwIfCancelled();
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
    );
    final cancelledRun = cancellationEngine.start();
    await entered.future;
    cancelledRun.cancel('test');
    final cancelledReport = await cancelledRun.done;
    expect(cancelledReport.cancelled, isTrue);
    expect(
      cancelledReport.datasets.single.stopReason,
      SyncDatasetStopReason.cancelled,
    );
    await cancellationEngine.disposeAsync();
  });

  test('unexpected dataset crash retains its original stack', () async {
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'notes',
          synchronize: (_) => _crash(),
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(),
    );
    final run = engine.start();

    Object? caught;
    StackTrace? stack;
    try {
      await run.done;
    } catch (error, caughtStack) {
      caught = error;
      stack = caughtStack;
    }
    expect(caught, isA<SyncRunTerminalException<String, int, _Failure>>());
    final terminal = caught as SyncRunTerminalException<String, int, _Failure>;
    expect(terminal.cause, isA<StateError>());
    expect(
      terminal.report.datasets.single.application.status,
      SyncBoundaryStatus.failed,
    );
    expect(stack.toString(), contains('_crash'));
    expect(run.progress.recent.last.phase, SyncProgressPhase.runCrashed);
    await engine.disposeAsync();
  });

  test(
    'journal records payload-free facts and resumes missing datasets',
    () async {
      final journal = _Journal<String>();
      final checkpoints = _MemoryCheckpoints<String, int>();
      final calls = <String>[];
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          for (final key in const <String>['catalog', 'images'])
            SyncDataset<String, int, _Failure>(
              key: key,
              synchronize: (_) async {
                calls.add(key);
                return const Ok<SyncDatasetOutcome<int>>(
                  SyncDatasetOutcome<int>.unchanged(),
                );
              },
            ),
        ],
        graph: SyncDependencyGraph<String>(
          keys: const <String>['catalog', 'images'],
        ),
        checkpoints: checkpoints,
        journal: journal,
        clock: _Clock(DateTime.utc(2026, 8, 24)),
      );

      await engine.start().done;

      expect(journal.entries.map((entry) => entry.fact), <SyncJournalFact>[
        SyncJournalFact.attemptStarted,
        SyncJournalFact.datasetStarted,
        SyncJournalFact.datasetSucceeded,
        SyncJournalFact.datasetStarted,
        SyncJournalFact.datasetSucceeded,
        SyncJournalFact.attemptCompleted,
      ]);
      expect(
        journal.entries.map((entry) => entry.sequence),
        orderedEquals(<int>[1, 2, 3, 4, 5, 6]),
      );
      journal.incomplete = <IncompleteSyncAttempt<String>>[
        IncompleteSyncAttempt<String>(
          attemptId: 'interrupted',
          startedAt: DateTime.utc(2026, 8, 23),
          completedDatasetKeys: const <String>['catalog'],
        ),
      ];

      final resumed = await engine.resumeIncomplete();
      expect(resumed, hasLength(1));
      await resumed.single.done;
      expect(calls, <String>['catalog', 'images', 'images']);
      await engine.disposeAsync();
    },
  );

  test('incremental checkpoints complete before the next pull', () async {
    final checkpoints = _GatedCheckpoints<String, int>();
    final trace = <String>[];
    Stream<Result<SyncDatasetOutcome<int>, _Failure>> produce() async* {
      trace.add('yield-1');
      yield const Ok<SyncDatasetOutcome<int>>(
        SyncDatasetOutcome<int>.checkpoint(1),
      );
      trace.add('yield-2');
      yield const Ok<SyncDatasetOutcome<int>>(
        SyncDatasetOutcome<int>.checkpoint(2),
      );
    }

    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>.incremental(
          key: 'notes',
          synchronize: (_) => IncrementalOperation.async(produce),
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: checkpoints,
    );
    final run = engine.start();
    final checkpointProgress = <SyncCheckpointProgressEvent<String>>[];
    final subscription = run.checkpointProgress.listen(checkpointProgress.add);

    await checkpoints.firstWriteStarted.future;
    expect(trace, <String>['yield-1']);
    checkpoints.allowFirstWrite.complete();
    final report = await run.done;

    expect(trace, <String>['yield-1', 'yield-2']);
    expect(checkpoints.values['notes'], 2);
    expect(report.datasets.single.confirmedStepCount, 2);
    expect(report.datasets.single.confirmedCheckpoint, 2);
    expect(checkpointProgress.map((event) => event.confirmedStepCount), <int>[
      1,
      2,
    ]);
    await subscription.cancel();
    await engine.disposeAsync();
  });

  test(
    'incremental typed failure retains confirmed partial progress',
    () async {
      final failureStack = StackTrace.current;
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>.incremental(
            key: 'notes',
            synchronize: (_) => IncrementalOperation.sync(
              () => <Result<SyncDatasetOutcome<int>, _Failure>>[
                const Ok<SyncDatasetOutcome<int>>(
                  SyncDatasetOutcome<int>.checkpoint(4),
                ),
                Err<_Failure>(const _Failure(), failureStack),
                const Ok<SyncDatasetOutcome<int>>(
                  SyncDatasetOutcome<int>.checkpoint(9),
                ),
              ],
            ),
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: _MemoryCheckpoints<String, int>(),
      );

      final report = await engine.start().done;
      final dataset = report.datasets.single;

      expect(dataset.status, SyncDatasetStatus.failed);
      expect(dataset.confirmedStepCount, 1);
      expect(dataset.confirmedCheckpoint, 4);
      expect(dataset.failureStackTrace, same(failureStack));
      await engine.disposeAsync();
    },
  );

  test(
    'incremental cancellation drains the producer before terminal',
    () async {
      late StreamController<Result<SyncDatasetOutcome<int>, _Failure>> source;
      final sourceCancelled = Completer<void>();
      final checkpoints = _MemoryCheckpoints<String, int>();
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>.incremental(
            key: 'notes',
            synchronize: (_) {
              source =
                  StreamController<Result<SyncDatasetOutcome<int>, _Failure>>(
                    onListen: () {
                      source.add(
                        const Ok<SyncDatasetOutcome<int>>(
                          SyncDatasetOutcome<int>.checkpoint(1),
                        ),
                      );
                    },
                    onCancel: () {
                      if (!sourceCancelled.isCompleted)
                        sourceCancelled.complete();
                    },
                  );
              return IncrementalOperation.async(() => source.stream);
            },
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
        checkpoints: checkpoints,
      );
      final run = engine.start();
      await run.checkpointProgress.first;

      run.cancel('test');
      final report = await run.done;

      expect(sourceCancelled.isCompleted, isTrue);
      expect(report.datasets.single.status, SyncDatasetStatus.incomplete);
      expect(report.datasets.single.confirmedStepCount, 1);
      await source.close();
      await engine.disposeAsync();
    },
  );

  test('incremental runs resume from the last confirmed checkpoint', () async {
    final checkpoints = _MemoryCheckpoints<String, int>();
    final received = <int?>[];
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>.incremental(
          key: 'notes',
          synchronize: (context) {
            received.add(context.checkpoint);
            return IncrementalOperation.sync(
              () => <Result<SyncDatasetOutcome<int>, _Failure>>[
                Ok<SyncDatasetOutcome<int>>(
                  SyncDatasetOutcome<int>.checkpoint(
                    (context.checkpoint ?? 0) + 1,
                  ),
                ),
              ],
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: checkpoints,
    );

    await engine.start().done;
    await engine.start().done;

    expect(received, <int?>[null, 1]);
    expect(checkpoints.values['notes'], 2);
    await engine.disposeAsync();
  });

  test('incremental checkpoint failure stops before the next pull', () async {
    final pulled = <int>[];
    Iterable<Result<SyncDatasetOutcome<int>, _Failure>> produce() sync* {
      pulled.add(1);
      yield const Ok<SyncDatasetOutcome<int>>(
        SyncDatasetOutcome<int>.checkpoint(1),
      );
      pulled.add(2);
      yield const Ok<SyncDatasetOutcome<int>>(
        SyncDatasetOutcome<int>.checkpoint(2),
      );
    }

    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>.incremental(
          key: 'notes',
          synchronize: (_) => IncrementalOperation.sync(produce),
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['notes']),
      checkpoints: _MemoryCheckpoints<String, int>(
        writeError: StateError('checkpoint failed'),
      ),
    );

    final terminal = await _terminalFailure(engine.start().done);
    final report = terminal.report.datasets.single;

    expect(pulled, <int>[1]);
    expect(report.status, SyncDatasetStatus.incomplete);
    expect(report.confirmedStepCount, 0);
    expect(report.application.status, SyncBoundaryStatus.succeeded);
    expect(report.checkpoint.status, SyncBoundaryStatus.failed);
    await engine.disposeAsync();
  });

  test(
    'bounded DAG admits ready datasets in plan order and reuses capacity',
    () async {
      final gates = <String, Completer<void>>{
        for (final key in const <String>['a', 'b', 'c']) key: Completer<void>(),
      };
      final entered = <String, Completer<void>>{
        for (final key in const <String>['a', 'b', 'c']) key: Completer<void>(),
      };
      final startOrder = <String>[];
      var active = 0;
      var maxActive = 0;
      SyncDataset<String, int, _Failure> dataset(String key) =>
          SyncDataset<String, int, _Failure>(
            key: key,
            synchronize: (_) async {
              startOrder.add(key);
              active += 1;
              if (active > maxActive) maxActive = active;
              entered[key]!.complete();
              await gates[key]!.future;
              active -= 1;
              return const Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.unchanged(),
              );
            },
          );
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          dataset('a'),
          dataset('b'),
          dataset('c'),
        ],
        graph: SyncDependencyGraph<String>(
          keys: const <String>['a', 'b', 'c'],
          dependencies: const <String, List<String>>{
            'c': <String>['a'],
          },
        ),
        checkpoints: _MemoryCheckpoints<String, int>(),
        executionPolicy: const SyncExecutionPolicy.boundedParallel(2),
      );
      final run = engine.start();

      await Future.wait(<Future<void>>[
        entered['a']!.future,
        entered['b']!.future,
      ]);
      expect(startOrder, <String>['a', 'b']);
      expect(entered['c']!.isCompleted, isFalse);
      gates['a']!.complete();
      await entered['c']!.future;
      expect(active, 2);
      gates['b']!.complete();
      gates['c']!.complete();
      final report = await run.done;

      expect(maxActive, 2);
      expect(startOrder, <String>['a', 'b', 'c']);
      expect(report.datasets.map((dataset) => dataset.key), <String>[
        'a',
        'b',
        'c',
      ]);
      expect(
        report.datasets.map((dataset) => dataset.status),
        everyElement(SyncDatasetStatus.succeeded),
      );
      await engine.disposeAsync();
    },
  );

  test(
    'parallel typed failure blocks descendants but not other branches',
    () async {
      final calls = <String>[];
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>(
            key: 'a',
            synchronize: (_) async {
              calls.add('a');
              return Err<_Failure>(const _Failure(), StackTrace.current);
            },
          ),
          SyncDataset<String, int, _Failure>(
            key: 'b',
            synchronize: (_) async {
              calls.add('b');
              return const Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.unchanged(),
              );
            },
          ),
          SyncDataset<String, int, _Failure>(
            key: 'c',
            synchronize: (_) async {
              calls.add('c');
              return const Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.unchanged(),
              );
            },
          ),
        ],
        graph: SyncDependencyGraph<String>(
          keys: const <String>['a', 'b', 'c'],
          dependencies: const <String, List<String>>{
            'c': <String>['a'],
          },
        ),
        checkpoints: _MemoryCheckpoints<String, int>(),
        executionPolicy: const SyncExecutionPolicy.boundedParallel(2),
      );

      final report = await engine.start().done;

      expect(calls, containsAll(<String>['a', 'b']));
      expect(calls, isNot(contains('c')));
      expect(
        report.datasets.map((dataset) => dataset.status),
        <SyncDatasetStatus>[
          SyncDatasetStatus.failed,
          SyncDatasetStatus.succeeded,
          SyncDatasetStatus.skipped,
        ],
      );
      await engine.disposeAsync();
    },
  );

  test('parallel crash cancels and drains already admitted work', () async {
    final bothEntered = Completer<void>();
    var enteredCount = 0;
    var siblingDrained = false;
    void entered() {
      enteredCount += 1;
      if (enteredCount == 2) bothEntered.complete();
    }

    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>(
          key: 'crash',
          synchronize: (_) async {
            entered();
            await bothEntered.future;
            throw StateError('parallel crash');
          },
        ),
        SyncDataset<String, int, _Failure>(
          key: 'sibling',
          synchronize: (context) async {
            entered();
            await context.cancellation.whenCancelled;
            siblingDrained = true;
            context.cancellation.throwIfCancelled();
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(
        keys: const <String>['crash', 'sibling'],
      ),
      checkpoints: _MemoryCheckpoints<String, int>(),
      executionPolicy: const SyncExecutionPolicy.boundedParallel(2),
    );

    final terminal = await _terminalFailure(engine.start().done);

    expect(terminal.cause, isA<StateError>());
    expect(siblingDrained, isTrue);
    expect(terminal.report.datasets, hasLength(2));
    expect(terminal.report.datasets[1].status, SyncDatasetStatus.cancelled);
    await engine.disposeAsync();
  });

  test(
    'parallel execution serializes borrowed checkpoint and journal ports',
    () async {
      final checkpoints = _SingleFlightCheckpoints<String, int>();
      final journal = _SingleFlightJournal<String>();
      final engine = SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          for (final key in const <String>['a', 'b', 'c', 'd'])
            SyncDataset<String, int, _Failure>(
              key: key,
              synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.checkpoint(1),
              ),
            ),
        ],
        graph: SyncDependencyGraph<String>(
          keys: const <String>['a', 'b', 'c', 'd'],
        ),
        checkpoints: checkpoints,
        journal: journal,
        executionPolicy: const SyncExecutionPolicy.boundedParallel(4),
      );

      final report = await engine.start().done;

      expect(report.succeeded, isTrue);
      expect(checkpoints.maxActive, 1);
      expect(journal.maxActive, 1);
      await engine.disposeAsync();
    },
  );

  test('parallel lease renewal is coalesced and serialized', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 24));
    final lease = _SingleFlightLease(clock.now());
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        for (final key in const <String>['a', 'b', 'c', 'd'])
          SyncDataset<String, int, _Failure>(
            key: key,
            synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            ),
          ),
      ],
      graph: SyncDependencyGraph<String>(
        keys: const <String>['a', 'b', 'c', 'd'],
      ),
      checkpoints: _MemoryCheckpoints<String, int>(),
      leases: _LeaseStore(lease),
      clock: clock,
      executionPolicy: const SyncExecutionPolicy.boundedParallel(4),
    );

    final report = await engine.start().done;

    expect(report.succeeded, isTrue);
    expect(lease.renewCount, 1);
    expect(lease.maxActive, 1);
    expect(lease.releaseCount, 1);
    await engine.disposeAsync();
  });

  test('execution policy rejects non-positive bounds without asserts', () {
    expect(
      () => SyncEngine<String, int, _Failure>(
        datasets: <SyncDataset<String, int, _Failure>>[
          SyncDataset<String, int, _Failure>(
            key: 'a',
            synchronize: (_) async => const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            ),
          ),
        ],
        graph: SyncDependencyGraph<String>(keys: const <String>['a']),
        checkpoints: _MemoryCheckpoints<String, int>(),
        executionPolicy: const SyncExecutionPolicy.boundedParallel(0),
      ),
      throwsArgumentError,
    );
  });
}

Future<Result<SyncDatasetOutcome<int>, _Failure>> _crash() async {
  throw StateError('unexpected sync crash');
}

Future<SyncRunTerminalException<String, int, _Failure>> _terminalFailure(
  Future<SyncReport<String, int, _Failure>> done,
) async {
  try {
    await done;
  } on SyncRunTerminalException<String, int, _Failure> catch (error) {
    return error;
  }
  throw StateError('Expected a terminal sync failure.');
}

final class _Failure implements Exception {
  const _Failure();
}

final class _MemoryCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  _MemoryCheckpoints({this.writeError});

  final Map<K, C> values = <K, C>{};
  final List<int?> fencingTokens = <int?>[];
  final Object? writeError;

  @override
  Future<C?> read(K key, CancellationSignal signal) async => values[key];

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    final error = writeError;
    if (error != null) throw error;
    fencingTokens.add(fencingToken);
    values[key] = checkpoint;
  }
}

final class _GatedCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  final Map<K, C> values = <K, C>{};
  final Completer<void> firstWriteStarted = Completer<void>();
  final Completer<void> allowFirstWrite = Completer<void>();
  var _writeCount = 0;

  @override
  Future<C?> read(K key, CancellationSignal signal) async => values[key];

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    _writeCount += 1;
    if (_writeCount == 1) {
      firstWriteStarted.complete();
      await allowFirstWrite.future;
    }
    signal.throwIfCancelled();
    values[key] = checkpoint;
  }
}

base class _SingleFlightPort {
  var active = 0;
  var maxActive = 0;

  Future<T> guard<T>(FutureOr<T> Function() action) async {
    active += 1;
    if (active > maxActive) maxActive = active;
    try {
      await Future<void>.delayed(Duration.zero);
      return await action();
    } finally {
      active -= 1;
    }
  }
}

final class _SingleFlightCheckpoints<K, C> extends _SingleFlightPort
    implements SyncCheckpointStore<K, C> {
  final Map<K, C> values = <K, C>{};

  @override
  Future<C?> read(K key, CancellationSignal signal) => guard(() => values[key]);

  @override
  Future<void> remove(K key, CancellationSignal signal) => guard(() {
    values.remove(key);
  });

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) => guard(() {
    signal.throwIfCancelled();
    values[key] = checkpoint;
  });
}

final class _SingleFlightJournal<K> extends _SingleFlightPort
    implements SyncRunJournal<K> {
  @override
  Future<void> append(SyncJournalEntry<K> entry) => guard(() {});

  @override
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts() =>
      guard(() => <IncompleteSyncAttempt<K>>[]);
}

final class _FencedDatasetStore {
  _FencedDatasetStore({required this.currentToken});

  final int currentToken;
  var applied = false;

  bool tryCommit(int fencingToken) {
    if (fencingToken != currentToken) return false;
    applied = true;
    return true;
  }
}

final class _FailingCleanup implements SyncRunCleanup {
  const _FailingCleanup();

  @override
  Future<void> cleanup(String runId) async {
    throw StateError('cleanup failed');
  }
}

final class _Clock implements SyncClock {
  _Clock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final class _Journal<K> implements SyncRunJournal<K> {
  final List<SyncJournalEntry<K>> entries = <SyncJournalEntry<K>>[];
  List<IncompleteSyncAttempt<K>> incomplete = <IncompleteSyncAttempt<K>>[];

  @override
  Future<void> append(SyncJournalEntry<K> entry) async {
    final previous = entries
        .where((candidate) => candidate.attemptId == entry.attemptId)
        .lastOrNull;
    if (previous != null && entry.sequence != previous.sequence + 1) {
      throw StateError('non-monotonic journal sequence');
    }
    entries.add(entry);
  }

  @override
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts() async =>
      List<IncompleteSyncAttempt<K>>.unmodifiable(incomplete);
}

final class _FailingJournal<K> implements SyncRunJournal<K> {
  const _FailingJournal(this.failOn);

  final SyncJournalFact failOn;

  @override
  Future<void> append(SyncJournalEntry<K> entry) async {
    if (entry.fact == failOn) throw StateError('journal failed: $failOn');
  }

  @override
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts() async =>
      <IncompleteSyncAttempt<K>>[];
}

final class _LeaseStore implements SyncLeaseStore {
  const _LeaseStore(this.lease);

  final SyncLease? lease;

  @override
  Future<SyncLease?> acquire({
    required String ownerId,
    required Duration ttl,
  }) async => lease;
}

final class _Lease implements SyncLease {
  _Lease(
    this.expiresAt,
    this.fencingToken, {
    this.renewResult = true,
    this.releaseError,
  });

  @override
  final int fencingToken;

  @override
  DateTime expiresAt;

  @override
  String get ownerId => 'lease-owner';

  int releaseCount = 0;
  final bool renewResult;
  final Object? releaseError;

  @override
  Future<void> release() async {
    releaseCount += 1;
    final error = releaseError;
    if (error != null) throw error;
  }

  @override
  Future<bool> renew(Duration ttl) async {
    if (!renewResult) return false;
    expiresAt = expiresAt.add(ttl);
    return true;
  }
}

final class _SingleFlightLease extends _SingleFlightPort implements SyncLease {
  _SingleFlightLease(this.expiresAt);

  @override
  final int fencingToken = 11;

  @override
  DateTime expiresAt;

  @override
  String get ownerId => 'single-flight-lease';

  var renewCount = 0;
  var releaseCount = 0;

  @override
  Future<void> release() => guard(() {
    releaseCount += 1;
  });

  @override
  Future<bool> renew(Duration ttl) => guard(() {
    renewCount += 1;
    expiresAt = expiresAt.add(ttl);
    return true;
  });
}

final class _Handler implements HeadlessSyncHandler<int, int, _Failure> {
  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    CancellationSignal cancellation,
  ) async => Ok<int>(payload * 2);
}

final class _BlockingHandler
    implements HeadlessSyncHandler<int, int, _Failure> {
  const _BlockingHandler(this.entered, this.release);

  final Completer<void> entered;
  final Completer<void> release;

  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    CancellationSignal cancellation,
  ) async {
    if (!entered.isCompleted) entered.complete();
    if (!release.isCompleted) await release.future;
    cancellation.throwIfCancelled();
    return Ok<int>(payload);
  }
}
