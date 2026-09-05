import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:test/test.dart';

void main() {
  late _Harness harness;
  setUp(() => harness = _Harness());
  tearDown(() async {
    await harness.engine?.disposeAsync();
    await harness.bulkhead.disposeAsync();
  });
  test('next page waits for the durable checkpoint acknowledgement', () async {
    harness.store.blockWrite = Completer<void>();
    final future = harness.start();
    await harness.store.writing.future;
    expect(harness.events, ['fetch:null', 'apply:opaque/+=']);
    expect(harness.store.value, isNull);
    harness.store.blockWrite!.complete();
    expect((await future).succeeded, isTrue);
    expect(harness.events, [
      'fetch:null',
      'apply:opaque/+=',
      'fetch:opaque/+=',
      'apply:null',
    ]);
    expect(harness.store.value, 'done');
  });
  test(
    'a full page limit returns a typed stop after its last checkpoint',
    () async {
      final report = await harness.start(maxPages: 1);
      expect(report.datasets.single.failure?.reason, TitectSyncStop.limit);
      expect(harness.store.value, 'opaque/+=');
      expect(harness.budget.attemptsStarted, 1);
    },
  );
  test('cumulative body limit stops before applying another page', () async {
    final report = await harness.start(
      maxBytes: harness.page('opaque/+=').length + 1,
    );
    expect(report.datasets.single.failure?.reason, TitectSyncStop.wire);
    expect(harness.store.value, 'opaque/+=');
    expect(
      harness.events.where((event) => event.startsWith('apply:')),
      hasLength(1),
    );
  });
  test(
    'application failures preserve the stack and are never replayed',
    () async {
      harness.applyFailure = 'storage failed';
      final report = await harness.start();
      expect(report.datasets.single.failure?.failure, 'storage failed');
      expect(harness.budget.attemptsStarted, 1);
      expect(harness.store.value, isNull);
    },
  );
  test('generation mismatch never reaches consumer storage', () async {
    harness.generation = 2;
    final report = await harness.start();
    expect(report.datasets.single.failure?.reason, TitectSyncStop.selection);
    expect(harness.events, ['fetch:null']);
    expect(harness.store.value, isNull);
  });
}

final class _Harness {
  _Harness() {
    budget = RetryBudget(
      maxAttempts: 10,
      maxElapsed: const Duration(seconds: 10),
      bulkhead: bulkhead,
      rateLimiter: RateLimiter(
        capacity: 10,
        refillTokens: 10,
        refillPeriod: const Duration(seconds: 1),
      ),
    );
  }
  final codec = TitectSyncCodec();
  final bulkhead = Bulkhead(maxConcurrent: 1, maxQueue: 1);
  late final RetryBudget budget;
  final store = _Store();
  final events = <String>[];
  String? applyFailure;
  var generation = 1;
  SyncEngine<String, String, TitectSyncFailure<String>>? engine;

  List<int> page(String? next) => codec.encode(
    codec.fromPayload('snapshot', {
      'dataset_id': 'd',
      'generation': generation,
      'upserts': <Object?>[],
      'next_cursor': next,
      'integrity': {
        'algorithm': 'sha-256',
        'digest': 'a' * 64,
        'item_count': 0,
      },
    }),
  );
  Future<SyncReport<String, String, TitectSyncFailure<String>>> start({
    int maxPages = 2,
    int maxBytes = 4096,
  }) {
    final dataset = titectSyncDataset<String, String, String>(
      key: 'd',
      datasetId: 'd',
      generation: BigInt.one,
      cursorOf: (checkpoint) => checkpoint,
      fetch: (_, cursor, attempt, signal, readBudget) async {
        events.add('fetch:$cursor');
        return Ok(
          await TitectSyncResponse.read(
            Stream.value(page(cursor == null ? 'opaque/+=' : null)),
            codec: codec,
            budget: readBudget,
          ),
        );
      },
      apply: (_, page) async {
        events.add('apply:${page.nextCursor}');
        if (applyFailure != null) return Err(applyFailure!, StackTrace.current);
        return Ok(page.nextCursor ?? 'done');
      },
      retryExecutor: RetryExecutor(),
      retryPolicy: RetryPolicy(classify: (_) => const RetryDecision.stop()),
      retryBudget: budget,
      maxPages: maxPages,
      maxReceivedBytes: maxBytes,
    );
    engine = SyncEngine(
      datasets: [dataset],
      graph: SyncDependencyGraph(keys: ['d']),
      checkpoints: store,
    );
    return engine!.start().done;
  }
}

final class _Store implements SyncCheckpointStore<String, String> {
  String? value;
  final writing = Completer<void>();
  Completer<void>? blockWrite;
  @override
  Future<String?> read(String key, CancellationSignal signal) async => value;
  @override
  Future<void> remove(String key, CancellationSignal signal) async =>
      value = null;
  @override
  Future<void> write(
    String key,
    String checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    if (!writing.isCompleted) writing.complete();
    await blockWrite?.future;
    value = checkpoint;
  }
}
