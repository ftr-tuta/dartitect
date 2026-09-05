import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../drift_fixture/infrastructure/fixture_database.dart';

Future<void> main(List<String> args) async {
  final [mode, path, endpoint, owner, tokenText, point, identity, ...rest] =
      args;
  final token = int.parse(tokenText);
  final database = DriftFixtureDatabase(NativeDatabase(File(path)));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final bulkhead = Bulkhead(maxConcurrent: 2, maxQueue: 4);
  final budget = RetryBudget(
    maxAttempts: 30,
    maxElapsed: const Duration(seconds: 30),
    bulkhead: bulkhead,
    rateLimiter: RateLimiter(
      capacity: 30,
      refillTokens: 1,
      refillPeriod: const Duration(minutes: 1),
    ),
  );
  final executor = RetryExecutor();
  final codec = TitectSyncCodec();
  final received = TitectReadBudget(1048576);
  final elapsed = Stopwatch()..start();
  var appliedPages = 0;
  var retainedRows = 0;
  Stream<List<int>> charge(Stream<List<int>> stream) => stream.map((chunk) {
    received.admit(chunk.length);
    return chunk;
  });
  Future<void> barrier(String name) async {
    if (point != name) return;
    stdout.writeln('BARRIER:$name');
    await stdout.flush();
    await stdin.first;
  }

  Future<void> fence() async {
    final count = await database.customUpdate(
      "UPDATE titect_authority SET token=token WHERE id=1 AND owner=? AND token=? AND expires_ms > CAST(unixepoch('subsec')*1000 AS INTEGER)",
      variables: [Variable<String>(owner), Variable<int>(token)],
    );
    if (count != 1) throw StateError('Persistent authority rejected writer.');
  }

  try {
    // Reuse the real generated Drift fixture; these additional consumer tables
    // define persistent session authority, page proof and pending-value shadows.
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS titect_authority (id INTEGER PRIMARY KEY, owner TEXT NOT NULL, token INTEGER NOT NULL, expires_ms INTEGER NOT NULL)',
    );
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS titect_pages (proof TEXT PRIMARY KEY, cursor TEXT, token INTEGER NOT NULL)',
    );
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS titect_shadow (id TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS titect_bootstrap (id INTEGER PRIMARY KEY, session_id TEXT NOT NULL, document TEXT NOT NULL)',
    );
    if (mode == 'recover' || mode == 'reconcile') {
      await database.transaction(() async {
        await fence();
        await database.customStatement(
          "UPDATE fixture_outbox SET status='uncertain' WHERE status='syncing'",
        );
        await database.customStatement(
          "UPDATE fixture_tasks SET status='uncertain' WHERE id IN (SELECT task_id FROM fixture_outbox WHERE status='uncertain')",
        );
      });
    }
    final store = _Outbox(database, fence, barrier);
    Future<Result<String, String>> deliver(
      OutboxOperation<String, int> operation,
      CancellationSignal signal,
    ) async {
      signal.throwIfCancelled();
      try {
        final request = await client.postUrl(Uri.parse('$endpoint/operations'));
        request.headers.contentType = ContentType.json;
        request.headers.set('Idempotency-Key', operation.idempotencyKey);
        final registration = signal.register((_) => request.abort());
        try {
          request.write(
            jsonEncode({'id': operation.key, 'value': operation.argument}),
          );
          final response = await request.close();
          await TitectJsonCodec(limits: TitectJsonLimits(maxBytes: 4096))
              .read(charge(response));
          await barrier('response_received');
          if (response.statusCode == 200 || response.statusCode == 201) {
            return Ok(operation.key);
          }
          return Err('uncertain', StackTrace.current);
        } finally {
          registration.dispose();
        }
      } on IOException catch (_, stack) {
        return Err('uncertain', stack);
      }
    }

    Future<void> synchronizePages() async {
      final checkpoints = _Checkpoints(database, fence, barrier, token);
      final dataset = titectSyncDataset<String, String, String>(
        key: 'items',
        datasetId: 'items',
        generation: BigInt.one,
        cursorOf: (checkpoint) => rest.isNotEmpty
            ? rest.first
            : checkpoint == null
            ? null
            : (jsonDecode(checkpoint) as Map<String, Object?>)['cursor']
                  as String?,
        fetch: (context, cursor, attempt, signal, readBudget) async {
          final uri = Uri.parse('$endpoint/pages')
              .replace(queryParameters: {if (cursor != null) 'cursor': cursor});
          final request = await client.getUrl(uri);
          final registration = signal.register((_) => request.abort());
          try {
            return Ok(
              await TitectSyncResponse.read(
                charge(await request.close()),
                codec: codec,
                budget: readBudget,
              ),
            );
          } finally {
            registration.dispose();
          }
        },
        apply: (context, page) async {
          final proof = sha256.convert(codec.encode(page)).toString();
          await barrier('page_before_apply');
          await database.transaction(() async {
            await fence();
            for (final item in page.upserts) {
              final value = item.value! as Map<String, Object?>;
              final text = (value['value']! as TitectNumber).lexeme;
              await database.customStatement(
                'INSERT OR REPLACE INTO titect_shadow VALUES (?, ?)',
                [item.itemId, text],
              );
              final pending = await database
                  .customSelect(
                    "SELECT 1 FROM fixture_outbox WHERE task_id=? AND status IN ('pending','syncing','uncertain') LIMIT 1",
                    variables: [Variable<String>(item.itemId)],
                  )
                  .get();
              if (pending.isEmpty) {
                await database.customStatement(
                  "INSERT OR REPLACE INTO fixture_tasks (id,title,version,status) VALUES (?,?,1,'synced')",
                  [item.itemId, text],
                );
              }
            }
            await barrier('page_during_apply');
            await database.customStatement(
              'INSERT OR REPLACE INTO titect_pages VALUES (?,?,?)',
              [proof, page.nextCursor, token],
            );
            await barrier('page_before_commit');
          });
          appliedPages++;
          await barrier('page_after_commit');
          return Ok(jsonEncode({'proof': proof, 'cursor': page.nextCursor}));
        },
        retryExecutor: executor,
        retryBudget: budget,
        retryPolicy: RetryPolicy(
          classify: (_) => const RetryDecision.stop(),
          maxAttempts: 1,
        ),
        maxPages: 10,
        maxReceivedBytes: 1048576,
      );
      final engine = SyncEngine<String, String, TitectSyncFailure<String>>(
        datasets: [dataset],
        graph: SyncDependencyGraph(keys: ['items']),
        checkpoints: checkpoints,
      );
      try {
        final report = await engine.start().done;
        if (!report.succeeded)
          throw StateError(
            'Sync stopped: ${report.datasets.first.failure?.reason.name}',
          );
      } finally {
        await engine.disposeAsync();
      }
    }

    final mutation = MutationCommand<int, String, String, String>(
      store: store,
      synchronize: deliver,
      createIdempotencyKey: (key, argument) => 'mutation:$key',
      classifyFailure: (_) => const MutationFailurePolicy.uncertain(),
      retryBudget: budget,
      retryExecutor: executor,
      maxConcurrentKeys: 2,
      maxQueuePerKey: 4,
    );
    try {
      switch (mode) {
        case 'acquire':
          await database.customStatement(
            "INSERT INTO titect_authority VALUES (1, ?, 1, CAST(unixepoch('subsec')*1000 AS INTEGER)+60000) ON CONFLICT(id) DO UPDATE SET owner=excluded.owner, token=titect_authority.token+1, expires_ms=excluded.expires_ms",
            [owner],
          );
        case 'expire':
          await database.customStatement(
            'UPDATE titect_authority SET expires_ms=0',
          );
        case 'bootstrap':
          final existing = await database
              .customSelect('SELECT document FROM titect_bootstrap WHERE id=1')
              .get();
          if (existing.isEmpty) {
            final source = CancellationSource();
            try {
              final response = await executor
                  .execute<TitectSyncResponse, String>(
                    operation: (_, signal) async {
                      final request = await client.getUrl(
                        Uri.parse('$endpoint/bootstrap'),
                      );
                      final registration = signal.register(
                        (_) => request.abort(),
                      );
                      try {
                        return Ok(
                          await TitectSyncResponse.read(
                            charge(await request.close()),
                            codec: codec,
                          ),
                        );
                      } finally {
                        registration.dispose();
                      }
                    },
                    policy: RetryPolicy(
                      classify: (_) => const RetryDecision.stop(),
                    ),
                    cancellation: source.signal,
                    budget: budget,
                  );
              final document =
                  (response as Ok<TitectSyncResponse>).value.document
                      as TitectBootstrapResponse;
              if (document.datasets.single.datasetId != 'items') {
                throw StateError('Bootstrap selection differs.');
              }
              await database.transaction(() async {
                await fence();
                await database.customStatement(
                  'INSERT INTO titect_bootstrap VALUES (1,?,?)',
                  [
                    document.session.sessionId,
                    utf8.decode(codec.encode(document)),
                  ],
                );
                await barrier('bootstrap_before_commit');
              });
              await barrier('bootstrap_after_commit');
            } finally {
              source.dispose();
            }
          } else {
            final document = codec.decode(
              utf8.encode(existing.single.read<String>('document')),
            );
            if (document is! TitectBootstrapResponse)
              throw StateError('Stored bootstrap differs.');
          }
        case 'mutate':
          await mutation.execute(
            identity,
            rest.isEmpty ? 7 : int.parse(rest.first),
          );
        case 'recover':
          await mutation.recoverPending();
        case 'reconcile':
          final rows = await database
              .customSelect(
                "SELECT * FROM fixture_outbox WHERE status='uncertain' ORDER BY id LIMIT 32",
              )
              .get();
          for (final row in rows) {
            final request = await client.postUrl(
              Uri.parse('$endpoint/reconciliation'),
            );
            request.headers.contentType = ContentType.json;
            request.headers.set(
              'Idempotency-Key',
              row.read<String>('idempotency_key'),
            );
            request.write(
              jsonEncode({
                'id': row.read<String>('task_id'),
                'value': int.parse(row.read<String>('title')),
              }),
            );
            final response = await request.close();
            await TitectJsonCodec(limits: TitectJsonLimits(maxBytes: 4096))
                .read(charge(response));
            if (response.statusCode == 200) {
              final source = CancellationSource();
              try {
                await store.markState(
                  OutboxOperation(
                    key: row.read<String>('task_id'),
                    argument: int.parse(row.read<String>('title')),
                    idempotencyKey: row.read<String>('idempotency_key'),
                    syncState: EntitySyncState.synced,
                  ),
                  source.signal,
                );
              } finally {
                source.dispose();
              }
            }
          }
        case 'sync':
          await synchronizePages();
        case 'storm':
          final source = CancellationSource();
          final outcomes = <Map<String, Object?>>[];
          var backgroundActive = false;
          Future<void> offered(int index) async {
            final role = const [
              'refresh',
              'reconnect',
              'outbox',
              'background',
            ][index % 4];
            var disposition = 'succeeded';
            try {
              if (role == 'outbox') {
                final result = await mutation.execute('storm-$index', index);
                if (result
                    is CommandSucceeded<
                      MutationExecution<int, String, String, String>,
                      String
                    >) {
                  disposition = result.value.disposition.name;
                } else {
                  disposition = 'refused';
                }
              } else if (role == 'background') {
                if (backgroundActive) {
                  disposition = 'refused';
                } else {
                  backgroundActive = true;
                  try {
                    await synchronizePages();
                  } finally {
                    backgroundActive = false;
                  }
                }
              } else {
                await executor.execute<void, String>(
                  operation: (_, signal) async {
                    final request = await client.getUrl(
                      Uri.parse(
                        '$endpoint/${role == 'refresh' ? 'bootstrap' : 'pages'}',
                      ),
                    );
                    final response = await request.close();
                    await codec.read(charge(response));
                    return const Ok(null);
                  },
                  policy: RetryPolicy(
                    classify: (_) => const RetryDecision.stop(),
                    maxAttempts: 1,
                  ),
                  cancellation: source.signal,
                  budget: budget,
                );
              }
            } on BulkheadRejectedException {
              disposition = 'refused';
            } on RetryBudgetExceededException {
              disposition = 'deferred';
            } on SyncRunTerminalException<
              String,
              String,
              TitectSyncFailure<String>
            > catch (error) {
              if (error.cause is! BulkheadRejectedException &&
                  error.cause is! RetryBudgetExceededException)
                rethrow;
              disposition = 'deferred';
            }
            outcomes.add({'role': role, 'disposition': disposition});
          }
          try {
            await Future.wait(List.generate(30, offered));
          } finally {
            source.dispose();
          }
          stdout.writeln(
            'STORM:${jsonEncode({'offered': 30, 'outcomes': outcomes, 'maxConcurrent': bulkhead.peakRunningCount, 'maxQueue': bulkhead.peakQueuedCount, 'admitted': bulkhead.admittedCount, 'refused': bulkhead.rejectedCount, 'attempts': budget.attemptsStarted})}',
          );
        case 'cleanup':
          await database.transaction(() async {
            await fence();
            await database.customStatement(
              "DELETE FROM fixture_outbox WHERE id IN (SELECT id FROM fixture_outbox WHERE status='synced' ORDER BY id LIMIT 2)",
            );
          });
        default:
          throw ArgumentError('Unknown actor mode.');
      }
      stdout.writeln('DONE');
    } finally {
      await mutation.disposeAsync();
    }
  } finally {
    await bulkhead.disposeAsync();
    client.close(force: true);
    try {
      final row = await database
          .customSelect(
            'SELECT (SELECT count(*) FROM fixture_tasks) + '
            '(SELECT count(*) FROM fixture_outbox) + '
            '(SELECT count(*) FROM titect_shadow) + '
            '(SELECT count(*) FROM titect_pages) + '
            '(SELECT count(*) FROM titect_authority) + '
            '(SELECT count(*) FROM titect_bootstrap) + '
            '(SELECT count(*) FROM fixture_checkpoints) + '
            '(SELECT count(*) FROM fixture_receipts) + '
            '(SELECT count(*) FROM fixture_journal) + '
            '(SELECT count(*) FROM fixture_leases) AS retained',
          )
          .getSingle();
      retainedRows = row.read<int>('retained');
      if (retainedRows > 100)
        throw StateError('Fixture retention bound exceeded.');
    } finally {
      await database.close();
    }
    stdout.writeln(
      'RESIDUAL:${jsonEncode({'running': bulkhead.runningCount, 'queued': bulkhead.queuedCount, 'attempts': budget.attemptsStarted, 'peakRunning': bulkhead.peakRunningCount, 'peakQueued': bulkhead.peakQueuedCount, 'databaseClosed': true, 'httpClientClosed': true, 'admittedBytes': received.admittedBytes, 'appliedPages': appliedPages, 'retainedRows': retainedRows, 'elapsedMicros': elapsed.elapsedMicroseconds})}',
    );
  }
}

final class _Outbox implements MutationOutboxStore<String, int, String> {
  _Outbox(this.db, this.fence, this.barrier);
  final DriftFixtureDatabase db;
  final Future<void> Function() fence;
  final Future<void> Function(String) barrier;

  @override
  Future<Result<void, String>> applyLocalAndEnqueue(
    OutboxOperation<String, int> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    await db.transaction(() async {
      await fence();
      await db.customStatement(
        "INSERT OR REPLACE INTO fixture_tasks (id,title,version,status) VALUES (?,?,1,'pending')",
        [operation.key, '${operation.argument}'],
      );
      await db.customStatement(
        "INSERT INTO fixture_outbox (task_id,title,expected_version,status,idempotency_key) VALUES (?,?,0,'pending',?)",
        [operation.key, '${operation.argument}', operation.idempotencyKey],
      );
      await barrier('local_before_commit');
    });
    await barrier('local_after_commit');
    return const Ok(null);
  }

  @override
  Future<Result<void, String>> markState(
    OutboxOperation<String, int> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    await db.transaction(() async {
      await fence();
      await db.customStatement(
        'UPDATE fixture_outbox SET status=?,expected_version=? WHERE idempotency_key=?',
        [operation.syncState.name, operation.attempt, operation.idempotencyKey],
      );
      await db.customStatement('UPDATE fixture_tasks SET status=? WHERE id=?', [
        operation.syncState.name,
        operation.key,
      ]);
      if (operation.syncState == EntitySyncState.synced) {
        await db.customStatement(
          "INSERT OR REPLACE INTO fixture_receipts VALUES (?,'synced')",
          [operation.idempotencyKey],
        );
      }
    });
    return const Ok(null);
  }

  @override
  Future<Result<List<OutboxOperation<String, int>>, String>> loadRecoverable(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final rows = await db
        .customSelect(
          "SELECT * FROM fixture_outbox WHERE status='pending' ORDER BY id LIMIT 32",
        )
        .get();
    return Ok(
      rows
          .map(
            (row) => OutboxOperation<String, int>(
              key: row.read<String>('task_id'),
              argument: int.parse(row.read<String>('title')),
              idempotencyKey: row.read<String>('idempotency_key'),
              attempt: row.read<int>('expected_version'),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<Result<void, String>> compensate(
    OutboxOperation<String, int> operation,
    CancellationSignal signal,
  ) async =>
      Err('compensation is an explicit consumer decision', StackTrace.current);
}

final class _Checkpoints implements SyncCheckpointStore<String, String> {
  _Checkpoints(this.db, this.fence, this.barrier, this.token);
  final int token;
  final DriftFixtureDatabase db;
  final Future<void> Function() fence;
  final Future<void> Function(String) barrier;

  @override
  Future<String?> read(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    final rows = await db
        .customSelect(
          'SELECT checkpoint FROM fixture_checkpoints WHERE key=?',
          variables: [Variable<String>(key)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('checkpoint');
  }

  @override
  Future<void> write(
    String key,
    String checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    await barrier('checkpoint_before_commit');
    await db.transaction(() async {
      await fence();
      final value = jsonDecode(checkpoint) as Map<String, Object?>;
      final proof = await db
          .customSelect(
            'SELECT proof FROM titect_pages WHERE proof=? AND token=?',
            variables: [
              Variable<String>(value['proof']! as String),
              Variable<int>(token),
            ],
          )
          .get();
      if (proof.length != 1)
        throw StateError('Checkpoint exceeds durable page coverage.');
      await db.customStatement(
        'INSERT OR REPLACE INTO fixture_checkpoints VALUES (?,?,?)',
        [key, checkpoint, fencingToken ?? token],
      );
    });
    await barrier('checkpoint_after_commit');
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    await db.transaction(() async {
      await fence();
      await db.customStatement('DELETE FROM fixture_checkpoints WHERE key=?', [
        key,
      ]);
    });
  }
}
