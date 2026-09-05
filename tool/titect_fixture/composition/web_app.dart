import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:crypto/crypto.dart';
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:drift/drift.dart';
import 'package:web/web.dart' as web;

import '../../drift_fixture/executor.dart';
import '../../drift_fixture/infrastructure/fixture_database.dart';

void status(String value) {
  web.console.log(value.toJS);
  web.document.body!.textContent = value;
}

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  try {
    final query = Uri.parse(web.window.location.href).queryParameters;
    final databaseName = query['database']!;
    final role = query['role']!;
    final opened = await openDriftFixtureExecutor(
      databaseName: databaseName,
      databaseUri: Uri(),
      sqlite3Uri: Uri.parse('/sqlite3.wasm'),
      workerUri: Uri.parse('/drift_worker.dart.js'),
    );
    final implementation = opened.storageImplementation;
    require(
      const {
        'sharedIndexedDb',
        'opfsShared',
        'opfsLocks',
      }.contains(implementation),
      'persistent shared authority is unavailable',
    );
    final db = DriftFixtureDatabase(opened.executor);
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
    var readers = 0;
    Future<Object?> request(
      String path, {
      Map<String, Object?>? payload,
      String? key,
      bool sync = false,
      TitectReadBudget? readBudget,
    }) async {
      final headers = web.Headers()
        ..set('Titect-Sync-Protocol', 'titect-sync/1');
      if (key != null) headers.set('Idempotency-Key', key);
      if (payload != null) headers.set('Content-Type', 'application/json');
      final response = await web.window
          .fetch(
            '/reference$path'.toJS,
            web.RequestInit(
              method: payload == null ? 'GET' : 'POST',
              headers: headers,
              body: payload == null ? null : jsonEncode(payload).toJS,
            ),
          )
          .toDart;
      final reader = web.ReadableStreamDefaultReader(response.body!);
      readers++;
      Stream<List<int>> chunks() async* {
        try {
          while (true) {
            final next = await reader.read().toDart;
            if (next.done) return;
            yield (next.value as JSUint8Array).toDart;
          }
        } finally {
          await reader.cancel().toDart;
          reader.releaseLock();
          readers--;
        }
      }

      final value = sync
          ? await TitectSyncResponse.read(
              chunks(),
              codec: TitectSyncCodec(),
              budget: readBudget,
            )
          : await TitectJsonCodec(limits: TitectJsonLimits(maxBytes: 4096))
                .read(chunks());
      require(
        response.status == 200 || response.status == 201,
        'HTTP fixture rejected request',
      );
      return value;
    }

    Future<void> fence(int token) async {
      final changed = await db.customUpdate(
        "UPDATE titect_authority SET token=token WHERE id=1 AND token=? AND expires_ms > CAST(unixepoch('subsec')*1000 AS INTEGER)",
        variables: [Variable<int>(token)],
      );
      require(changed == 1, 'stale persistent writer');
    }

    String? outcome;
    try {
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS titect_authority (id INTEGER PRIMARY KEY, token INTEGER NOT NULL, expires_ms INTEGER NOT NULL)',
      );
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS titect_pages (proof TEXT PRIMARY KEY, cursor TEXT, token INTEGER NOT NULL)',
      );
      final identity = 'web-$databaseName';
      final key = 'mutation:$identity';
      final payload = <String, Object?>{'id': identity, 'value': 17};
      if (role == 'reload') {
        final stageKey = 'titect-stage-$databaseName';
        final stage = web.window.sessionStorage.getItem(stageKey) ?? '0';
        web.console.log('stage:$stage:storage:$implementation'.toJS);
        if (stage == '0') {
          await durableTransaction(db, () async {
            await db.customStatement(
              "INSERT INTO titect_authority VALUES (1,1,CAST(unixepoch('subsec')*1000 AS INTEGER)+60000)",
            );
            await db.customStatement(
              "INSERT INTO fixture_tasks (id,title,version,status) VALUES (?, '17',1,'pending')",
              [identity],
            );
            await db.customStatement(
              "INSERT INTO fixture_outbox (task_id,title,expected_version,status,idempotency_key) VALUES (?,'17',1,'syncing',?)",
              [identity, key],
            );
          });
          await request('/operations', payload: payload, key: key);
          web.window.sessionStorage.setItem(stageKey, '1');
          status('BARRIER:$implementation:response');
          await Completer<void>().future;
        }
        if (stage == '1') {
          final rows = await db
              .customSelect('SELECT status,idempotency_key FROM fixture_outbox')
              .get();
          require(rows.length == 1, 'reload outbox rows: ${rows.length}');
          final row = rows.single;
          require(
            row.read<String>('status') == 'syncing' &&
                row.read<String>('idempotency_key') == key,
            'reload lost uncertain identity',
          );
          await db.customStatement(
            "UPDATE fixture_outbox SET status='uncertain'",
          );
          await request('/reconciliation', payload: payload, key: key);
          await durableTransaction(db, () async {
            await fence(1);
            await db.customStatement(
              "UPDATE fixture_outbox SET status='synced'",
            );
            await db.customStatement(
              "INSERT INTO fixture_receipts VALUES (?,'synced')",
              [key],
            );
          });
        }
        if (stage == '2') {
          require(
            (await db.customSelect('SELECT * FROM fixture_checkpoints').get())
                .isEmpty,
            'checkpoint advanced before confirmation',
          );
          require(
            (await db.customSelect('SELECT * FROM titect_pages').get())
                .isNotEmpty,
            'applied page was not durable across reload',
          );
        }
        final checkpoints = _WebCheckpoints(db, () => fence(1), () async {
          if (stage == '1') {
            web.window.sessionStorage.setItem(stageKey, '2');
            status('BARRIER:$implementation:checkpoint');
            await Completer<void>().future;
          }
        });
        final codec = TitectSyncCodec();
        final dataset = titectSyncDataset<String, String, String>(
          key: 'items',
          datasetId: 'items',
          generation: BigInt.one,
          cursorOf: (checkpoint) => checkpoint == null
              ? null
              : (jsonDecode(checkpoint) as Map<String, Object?>)['cursor']
                    as String?,
          fetch: (context, cursor, attempt, signal, readBudget) async => Ok(
            await request(
              Uri(
                path: '/pages',
                queryParameters: {if (cursor != null) 'cursor': cursor},
              ).toString(),
              sync: true,
              readBudget: readBudget,
            ) as TitectSyncResponse,
          ),
          apply: (context, page) async {
            final proof = sha256.convert(codec.encode(page)).toString();
            await durableTransaction(db, () async {
              await fence(1);
              for (final item in page.upserts) {
                final value =
                    ((item.value! as Map<String, Object?>)['value']!
                            as TitectNumber)
                        .lexeme;
                await db.customStatement(
                  "INSERT OR REPLACE INTO fixture_tasks (id,title,version,status) VALUES (?,?,1,'synced')",
                  [item.itemId, value],
                );
              }
              await db.customStatement(
                'INSERT OR REPLACE INTO titect_pages VALUES (?,?,1)',
                [proof, page.nextCursor],
              );
            });
            return Ok(jsonEncode({'proof': proof, 'cursor': page.nextCursor}));
          },
          retryExecutor: RetryExecutor(),
          retryPolicy: RetryPolicy(
            classify: (_) => const RetryDecision.stop(),
            maxAttempts: 1,
          ),
          retryBudget: budget,
          maxPages: 10,
          maxReceivedBytes: 1048576,
        );
        final engine = SyncEngine<String, String, TitectSyncFailure<String>>(
          datasets: [dataset],
          graph: SyncDependencyGraph(keys: ['items']),
          checkpoints: checkpoints,
        );
        try {
          require((await engine.start().done).succeeded, 'web sync failed');
        } finally {
          await engine.disposeAsync();
        }
        outcome = 'PASS:$implementation:reload';
      } else if (role == 'reopen') {
        final row = await db
            .customSelect('SELECT status,idempotency_key FROM fixture_outbox')
            .getSingle();
        require(
          row.read<String>('status') == 'synced' &&
              row.read<String>('idempotency_key') == key,
          'reopen lost durable receipt',
        );
        final checkpoint = await db
            .customSelect('SELECT checkpoint FROM fixture_checkpoints')
            .getSingle();
        final proof =
            (jsonDecode(checkpoint.read<String>('checkpoint'))
                    as Map<String, Object?>)['proof']!
                as String;
        require(
          (await db
                      .customSelect(
                        'SELECT * FROM titect_pages WHERE proof=?',
                        variables: [Variable<String>(proof)],
                      )
                      .get())
                  .length ==
              1,
          'checkpoint lacks durable proof',
        );
        outcome = 'PASS:$implementation:reopen';
      } else if (role == 'old') {
        final token =
            (await db
                    .customSelect('SELECT token FROM titect_authority')
                    .getSingle())
                .read<int>('token');
        status('READY:$implementation:old');
        while (web.window.localStorage.getItem(
              'titect-replaced-$databaseName',
            ) !=
            'yes') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        var rejected = false;
        try {
          await durableTransaction(db, () async {
            await fence(token);
            await db.customStatement(
              "INSERT INTO fixture_tasks (id,title) VALUES ('stale','forbidden')",
            );
          });
        } on StateError {
          rejected = true;
        }
        require(rejected, 'old tab was allowed to commit');
        outcome = 'PASS:$implementation:stale-rejected';
      } else if (role == 'replacement') {
        await db.customStatement('UPDATE titect_authority SET token=token+1');
        web.window.localStorage.setItem('titect-replaced-$databaseName', 'yes');
        outcome = 'PASS:$implementation:replacement';
      } else {
        throw ArgumentError('unknown role');
      }
    } finally {
      await bulkhead.disposeAsync();
      await db.close();
      require(
        readers == 0 && bulkhead.runningCount == 0 && bulkhead.queuedCount == 0,
        'web owned resources remain',
      );
    }
    status('$outcome:closed');
  } catch (error, stack) {
    web.console.error('$error\n$stack'.toJS);
    status('FAIL:${error.runtimeType}:$error');
  }
}

final class _WebCheckpoints implements SyncCheckpointStore<String, String> {
  _WebCheckpoints(this.db, this.fence, this.barrier);
  final DriftFixtureDatabase db;
  final Future<void> Function() fence;
  final Future<void> Function() barrier;
  @override
  Future<String?> read(String key, CancellationSignal signal) async {
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
    await barrier();
    await durableTransaction(db, () async {
      await fence();
      final proof =
          (jsonDecode(checkpoint) as Map<String, Object?>)['proof']! as String;
      require(
        (await db
                    .customSelect(
                      'SELECT * FROM titect_pages WHERE proof=? AND token=1',
                      variables: [Variable<String>(proof)],
                    )
                    .get())
                .length ==
            1,
        'missing page proof',
      );
      await db.customStatement(
        'INSERT OR REPLACE INTO fixture_checkpoints VALUES (?,?,1)',
        [key, checkpoint],
      );
    });
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async =>
      throw UnsupportedError('consumer must explicitly reset');
}

// Drift 2.34.3 defers IndexedDB flush while its transaction delegate is active,
// including COMMIT. An awaited standalone statement reaches the VFS flush only
// after that delegate releases the transaction. This is a consumer persistence
// barrier, required before externally observable effects or checkpoints.
Future<void> durableTransaction(
  DriftFixtureDatabase db,
  Future<void> Function() action,
) async {
  await db.transaction(action);
  await db.customStatement('PRAGMA user_version');
}
