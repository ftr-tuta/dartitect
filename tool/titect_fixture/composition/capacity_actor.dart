import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:drift/native.dart';

import '../../drift_fixture/infrastructure/fixture_database.dart';
import 'exact_message.dart';

/// Real Dart offered-load client. The enclosing compiled actor supplies identity.
Future<void> runCapacity(List<String> args) async {
  final [path, endpoint, scenario, seedText, rateText] = args;
  final seed = int.parse(seedText);
  final rate = int.parse(rateText);
  if (seed != 41 ||
      rate != (scenario == 'saturation' ? 400 : 50) ||
      !const {'offered', 'saturation', 'recovery'}.contains(scenario)) {
    throw ArgumentError('Unsupported capacity control.');
  }
  final database = DriftFixtureDatabase(NativeDatabase(File(path)));
  final bulkhead = Bulkhead(maxConcurrent: 2, maxQueue: 4);
  final source = CancellationSource();
  final budget = RetryBudget(
    maxAttempts: 2400,
    maxElapsed: const Duration(seconds: 22),
    bulkhead: bulkhead,
    rateLimiter: RateLimiter(
      capacity: 2400,
      refillTokens: 1,
      refillPeriod: const Duration(minutes: 1),
    ),
  );
  final received = TitectReadBudget(8 * 1024 * 1024);
  final sent = TitectReadBudget(8 * 1024 * 1024);
  HttpClient newClient() => HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 500)
    ..maxConnectionsPerHost = 2;
  var client = newClient();
  var reconnects = 0;
  var disconnects = 0;
  var retained = 0;
  var reconciliations = 0;
  final outcomes = <Map<String, Object?>>[];
  final pending = <Future<void>>{};
  final elapsed = Stopwatch();
  final timer = Timer(const Duration(seconds: 22), () => source.cancel());

  Future<void> waitUntil(int dueMicros) async {
    while (elapsed.elapsedMicroseconds < dueMicros) {
      final remaining = dueMicros - elapsed.elapsedMicroseconds;
      // Timers have millisecond granularity. Round upward and check the clock
      // again so neither an offer nor the two-second window ends early.
      await Future<void>.delayed(
        Duration(milliseconds: max(1, (remaining + 999) ~/ 1000)),
      );
    }
  }

  Future<(int, Uint8List)> request(
    String resource,
    String identity,
    List<int> wire,
  ) async {
    source.signal.throwIfCancelled();
    budget.startAttempt();
    sent.admit(wire.length);
    HttpClientRequest? request;
    final registration = source.signal.register((_) => request?.abort());
    try {
      request = await client.postUrl(Uri.parse('$endpoint/$resource'));
      request.headers.contentType = ContentType.json;
      request.headers.set('Idempotency-Key', identity);
      request.add(wire);
      final response = await request.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          request!.abort();
          throw TimeoutException('capacity response deadline');
        },
      );
      final bytes = BytesBuilder(copy: true);
      await for (final chunk in response.timeout(const Duration(seconds: 1))) {
        received.admit(chunk.length);
        if (bytes.length + chunk.length > 8192) {
          throw const TitectWireException(TitectWireProblem.limit);
        }
        bytes.add(chunk);
      }
      final raw = bytes.takeBytes();
      TitectJsonCodec(limits: TitectJsonLimits(maxBytes: 8192)).decode(raw);
      return (response.statusCode, raw);
    } on IOException {
      disconnects++;
      client.close(force: true);
      client = newClient();
      reconnects++;
      rethrow;
    } finally {
      registration.dispose();
    }
  }

  Future<void> offer(int index, int nonce) async {
    final identity = 's$seed-$index-$nonce';
    final started = elapsed.elapsedMicroseconds;
    var status = 'generator_rejected';
    var finalState = 'refused';
    String? hash;
    try {
      await bulkhead.run<void>((signal) async {
        final wire = exactMessage(identity);
        hash = sha256.convert(wire).toString();
        if (++retained > 800) throw StateError('Capacity retention exceeded.');
        await database.customStatement(
          'INSERT INTO capacity_offers(id,wire,state) VALUES (?,?,?)',
          [identity, wire, 'pending'],
        );
        Uint8List? confirmed;
        try {
          final (code, body) = await request(
            'exact-operations',
            identity,
            wire,
          );
          status = '$code';
          if (code == 200 || code == 201) {
            confirmed = body;
          } else if (code == 503 || code == 429) {
            finalState = 'refused';
          } else {
            finalState = 'uncertain';
          }
        } on IOException {
          status = 'network_error';
          finalState = 'uncertain';
        } on TimeoutException {
          status = 'timeout';
          finalState = 'uncertain';
        }
        if (finalState == 'uncertain') {
          // Reconciliation always precedes any possible resubmission. This
          // control records confirmed absence and never resubmits uncertain work.
          while (elapsed.elapsed < const Duration(seconds: 21)) {
            signal.throwIfCancelled();
            try {
              reconciliations++;
              final (code, body) = await request(
                'exact-reconciliation',
                identity,
                wire,
              );
              if (code == 200) {
                confirmed = body;
                break;
              }
              if (code == 404) {
                finalState = 'not_committed';
                break;
              }
            } on IOException {
              // The same scenario budget charges each reconnect attempt.
            } on TimeoutException {
              // Finite reconciliation continues after the server restarts.
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        if (confirmed != null) {
          if (base64Encode(confirmed) != base64Encode(wire)) {
            throw StateError(
              'Capacity response differs from exact Dart bytes.',
            );
          }
          finalState = 'committed';
          await database.customStatement(
            'UPDATE capacity_offers SET response=? WHERE id=?',
            [confirmed, identity],
          );
        }
        await database.customStatement(
          'UPDATE capacity_offers SET state=? WHERE id=?',
          [finalState, identity],
        );
      }, cancellation: source.signal);
    } on BulkheadRejectedException {
      status = 'generator_rejected';
    } on RetryBudgetExceededException {
      status = 'budget_exceeded';
      finalState = 'failed';
    } catch (error) {
      status = 'client_error';
      finalState = 'failed';
      stderr.writeln('Capacity failure: ${error.runtimeType}');
    }
    final row = <String, Object?>{
      'index': index,
      'id': identity,
      'status': status,
      'state': finalState,
      'latencyMicros': elapsed.elapsedMicroseconds - started,
      'offeredMicros': started,
      'wireSha256': hash,
    };
    outcomes.add(row);
    stdout.writeln('OFFER:${jsonEncode(row)}');
  }

  try {
    await database.customStatement(
      'CREATE TABLE capacity_offers(id TEXT PRIMARY KEY, wire BLOB NOT NULL, response BLOB, state TEXT NOT NULL)',
    );
    final random = Random(seed);
    elapsed.start();
    stdout.writeln('CAPACITY_READY');
    await stdout.flush();
    for (var index = 0; index < rate * 2; index++) {
      await waitUntil(index * 1000000 ~/ rate);
      final future = offer(index, random.nextInt(1000000));
      pending.add(future);
      unawaited(future.whenComplete(() => pending.remove(future)));
    }
    await waitUntil(2000000);
    final offerMicros = elapsed.elapsedMicroseconds;
    await Future.wait(pending.toList());
    final rows = await database
        .customSelect('SELECT count(*) AS total FROM capacity_offers')
        .getSingle();
    if (rows.read<int>('total') != retained || outcomes.length != rate * 2) {
      throw StateError('Capacity offers or retained records do not reconcile.');
    }
    stdout.writeln(
      'CAPACITY:${jsonEncode({'scenario': scenario, 'seed': seed, 'offered': rate * 2, 'offerMicros': offerMicros, 'elapsedMicros': elapsed.elapsedMicroseconds, 'attempts': budget.attemptsStarted, 'receivedBytes': received.admittedBytes, 'sentBytes': sent.admittedBytes, 'peakRunning': bulkhead.peakRunningCount, 'peakQueued': bulkhead.peakQueuedCount, 'retainedRecords': retained, 'reconciliations': reconciliations, 'disconnects': disconnects, 'reconnects': reconnects, 'outcomes': outcomes})}',
    );
  } finally {
    timer.cancel();
    source.cancel();
    await bulkhead.disposeAsync();
    source.dispose();
    client.close(force: true);
    await database.close();
    stdout.writeln(
      'RESIDUAL:${jsonEncode({'running': bulkhead.runningCount, 'queued': bulkhead.queuedCount, 'databaseClosed': true, 'httpClientClosed': true})}',
    );
  }
}
