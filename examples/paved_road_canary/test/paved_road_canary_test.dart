import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paved_road_canary/features/paved_road/composition/paved_road.wiring.dartitect.g.dart';
import 'package:paved_road_canary/main.dart';

void main() {
  testWidgets('application host publishes the complete local runtime', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationHost<CanaryRuntime>.create(
          create: PavedRoadFeatureWiring.application(
            createModule: createCanaryFeatureModule,
          ),
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

  test('profile, progress, restoration, resilience, and transfer', () async {
    final currentName = Directory.current.path
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .last;
    final configFile = currentName == 'paved_road_canary'
        ? File('dartitect.json')
        : File('examples/paved_road_canary/dartitect.json');
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
    final features = config['features']! as Map<String, Object?>;
    final declarations = features['declarations']! as Map<String, Object?>;
    final pavedRoad = declarations['paved_road']! as Map<String, Object?>;
    expect(pavedRoad['profile'], 'offline-full');
    expect(
      (pavedRoad['headless']! as Map<String, Object?>).values,
      everyElement(isFalse),
    );
    expect(PavedRoadFeatureWiring.profile, 'offline-full');
    expect(PavedRoadFeatureWiring.pagination, 'cursor');

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

    progress.dispose();
    source.dispose();
  });
}

final class _Failure implements Exception {}

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
