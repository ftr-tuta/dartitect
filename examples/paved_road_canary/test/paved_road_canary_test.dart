import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_devtools/dartitect_devtools.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paved_road_canary/main.dart';

void main() {
  testWidgets('application host publishes the complete local runtime', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationHost<CanaryRuntime>.create(
          create: createCanaryCoordinator,
          loading: (_) => const Text('loading'),
          failure: (_, _, retry) =>
              TextButton(onPressed: retry, child: const Text('retry')),
          ready: (_, runtime) => CanaryApp(runtime: runtime),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('value 0'), findsOneWidget);
    expect(find.text('lazy 0'), findsOneWidget);
    await tester.tap(find.text('Increment local state'));
    await tester.pump();
    expect(find.text('value 1'), findsOneWidget);
    expect(find.text('lazy 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test(
    'profile, progress, restoration, resilience, jobs, transfer, and RPC',
    () async {
      final config = jsonDecode(
        File('dartitect.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final features = config['features']! as Map<String, Object?>;
      final declarations = features['declarations']! as Map<String, Object?>;
      final pavedRoad = declarations['paved_road']! as Map<String, Object?>;
      expect(pavedRoad['profile'], 'offline-full');
      expect(pavedRoad['headlessSync'], isTrue);

      final source = CancellationSource();
      final progress = BoundedProgressReporter<String>(capacity: 2);
      final context = CommandExecutionContext<String>(
        executionId: 7,
        cancellation: source.signal,
        progress: progress,
      );
      expect(context.publish('admitted'), isTrue);
      expect(context.publish('complete'), isTrue);
      expect(progress.events.map((event) => event.sequence), <int>[1, 2]);

      final codec = VersionedRestorationCodec<int, VersionedRestorationIssue>(
        currentVersion: 2,
        encodePayload: (value) => value,
        decodePayload: (payload) => payload is int
            ? Ok<int>(payload)
            : const Err<VersionedRestorationIssue>(
                VersionedRestorationIssue.invalidEnvelope,
                StackTrace.empty,
              ),
        mapIssue: (issue) => issue,
        migrations:
            <int, VersionedRestorationMigration<VersionedRestorationIssue>>{
              1: (payload) => payload is int
                  ? Ok<int>(payload + 1)
                  : const Err<VersionedRestorationIssue>(
                      VersionedRestorationIssue.invalidEnvelope,
                      StackTrace.empty,
                    ),
            },
      );
      final restored = codec.decode(<String, Object?>{
        'version': 1,
        'payload': 3,
      });
      expect((restored as Ok<int>).value, 4);

      var attempts = 0;
      final retried = await RetryExecutor().execute<int, _Failure>(
        operation: (attempt, _) async {
          attempts = attempt;
          return attempt == 1
              ? Err<_Failure>(_Failure(), StackTrace.current)
              : const Ok<int>(8);
        },
        policy: RetryPolicy<_Failure>(
          classify: (_) => const RetryDecision.retry(),
          maxAttempts: 2,
          backoff: FixedBackoff(Duration.zero),
        ),
        cancellation: source.signal,
      );
      expect((retried as Ok<int>).value, 8);
      expect(attempts, 2);

      final jobProgress = BoundedProgressReporter<int>();
      final dispatcher = JobDispatcher<int, int, _Failure, int>(
        definitions: <JobDefinition<int, int, _Failure, int>>[
          JobDefinition<int, int, _Failure, int>(
            name: 'synthetic',
            createGraph: (_) => ResourceTransaction.create(
              (transaction) => _CanaryJobHandler(),
            ),
          ),
        ],
        progressReporter: (_) => jobProgress,
      );
      final terminal = await dispatcher.handle(
        JobEnvelope<int>(
          jobId: 'canary-job',
          definition: 'synthetic',
          deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
          payload: 4,
        ),
      );
      expect((terminal as JobCompleted<int, _Failure>).result, 8);
      expect(jobProgress.events.single.payload, 4);
      await dispatcher.disposeAsync();

      final checkpoints = _CanaryCheckpoints();
      final transfer = TransferEngine<_Failure>(
        source: _CanarySource(<int>[1, 2, 3]),
        transport: const _CanaryTransport(),
        checkpoints: checkpoints,
        chunkSize: 2,
      );
      final transferred = await transfer.start('canary-transfer').done;
      expect((transferred as Ok<TransferReport>).value.committedBytes, 3);
      expect(checkpoints.value!.committedOffset, 3);
      await transfer.disposeAsync();

      final buffer = DartitectDiagnosticBuffer(capacity: 2);
      final emitter = DartitectDiagnosticsEmitter(
        detail: DartitectDiagnosticDetail.topology,
        reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      );
      final subject = emitter.subject(DartitectDiagnosticSubjectKind.owner);
      subject
        ..emit(DartitectDiagnosticPhase.started)
        ..emit(DartitectDiagnosticPhase.succeeded);
      expect(buffer.length, 2);
      final registrar = _CanaryRegistrar();
      final registration = DartitectDevToolsRegistration.register(
        enabled: true,
        buffer: buffer,
        detail: DartitectDiagnosticDetail.topology,
        registrar: registrar,
      );
      expect(registrar.handlers.keys, dartitectReadOnlyServiceExtensions);
      expect(
        registrar.handlers.keys.any(
          (method) => RegExp(
            'retry|cancel|clear',
            caseSensitive: false,
          ).hasMatch(method),
        ),
        isFalse,
      );
      registration.dispose();
      expect(buffer.length, 0);
      await emitter.disposeAsync();

      progress.dispose();
      jobProgress.dispose();
      source.dispose();
    },
  );
}

final class _Failure implements Exception {}

final class _CanaryJobHandler implements JobHandler<int, int, _Failure, int> {
  @override
  Future<Result<int, _Failure>> execute(
    int payload,
    JobExecutionContext<int> context,
  ) async {
    context.command.publish(payload);
    return Ok<int>(payload * 2);
  }
}

final class _CanarySource implements TransferSource {
  const _CanarySource(this.bytes);

  final List<int> bytes;

  @override
  Future<TransferChunk?> read({
    required int offset,
    required int maxBytes,
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    if (offset == bytes.length) return null;
    final end = (offset + maxBytes).clamp(0, bytes.length);
    return TransferChunk(offset: offset, bytes: bytes.sublist(offset, end));
  }
}

final class _CanaryTransport implements TransferTransport<_Failure> {
  const _CanaryTransport();

  @override
  Future<Result<TransferCommit, _Failure>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<TransferCommit>(TransferCommit(chunk.nextOffset));
  }
}

final class _CanaryCheckpoints implements TransferCheckpointStore {
  TransferCheckpoint? value;

  @override
  Future<TransferCheckpoint?> load(String transferId) async => value;

  @override
  Future<void> save(TransferCheckpoint checkpoint) async => value = checkpoint;
}

final class _CanaryRegistrar implements DartitectServiceExtensionRegistrar {
  final Map<String, ServiceExtensionHandler> handlers =
      <String, ServiceExtensionHandler>{};

  @override
  void register(String method, ServiceExtensionHandler handler) {
    handlers[method] = handler;
  }
}
