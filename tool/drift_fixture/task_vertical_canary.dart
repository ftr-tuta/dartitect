import 'dart:async';
import 'dart:convert';

import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import 'infrastructure/fixture_database.dart';

/// Deterministic transport outcomes exercised by the vertical canary.
enum TaskCanaryRemoteMode { online, conflict, uncertain }

/// Evidence retained after the canary runtime has been disposed.
final class TaskCanaryEvidence {
  int uiEmissions = 0;
  int appliedDeliveries = 0;
  int duplicateDeliveries = 0;
  int transportRequests = 0;
  int staleGenerationDrops = 0;
  int closeCalls = 0;
  final List<String> deliveredKeys = <String>[];
}

/// Real Drift + deterministic Dio vertical feature used on native and web.
///
/// The presentation snapshot is changed only by the database watcher. Remote
/// decoding, conflict policy, and domain writes remain explicit canary-owned
/// semantics; resource wiring and operational tables are managed test support.
final class TaskVerticalCanary {
  TaskVerticalCanary(DriftFixtureDatabase database)
    : _database = database,
      _adapter = _TaskCanaryHttpAdapter(),
      census = ResourceCensus() {
    _sessionLease = census.acquire('session-graph');
    _dioLease = census.acquire('dio-client');
    _dioOwner = DioOwner.create(
      options: BaseOptions(baseUrl: 'https://task-canary.invalid'),
      configure: (dio) => dio.httpClientAdapter = _adapter,
    );
  }

  final DriftFixtureDatabase _database;
  final _TaskCanaryHttpAdapter _adapter;
  final ResourceCensus census;
  final TaskCanaryEvidence evidence = TaskCanaryEvidence();
  late final DioOwner _dioOwner;
  late final CensusLease _sessionLease;
  late final CensusLease _dioLease;
  CensusLease? _watchLease;
  StreamSubscription<List<FixtureTask>>? _watch;
  List<FixtureTask> _visibleTasks = const <FixtureTask>[];
  var _generation = 1;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Current deterministic server behavior.
  TaskCanaryRemoteMode get remoteMode => _adapter.mode;

  set remoteMode(TaskCanaryRemoteMode value) => _adapter.mode = value;

  /// Immutable UI projection. Only the Drift watcher assigns this value.
  List<FixtureTask> get visibleTasks => _visibleTasks;

  /// Starts the database-only UI observation boundary.
  Future<void> start() async {
    _ensureActive();
    if (_watch != null) return;
    final initial = Completer<void>();
    _watchLease = census.acquire('drift-watch');
    _watch =
        (_database.select(_database.fixtureTasks)
              ..orderBy(<OrderClauseGenerator<$FixtureTasksTable>>[
                (row) => OrderingTerm.asc(row.id),
              ]))
            .watch()
            .listen((rows) {
              _visibleTasks = List<FixtureTask>.unmodifiable(rows);
              evidence.uiEmissions += 1;
              if (!initial.isCompleted) initial.complete();
            }, onError: initial.completeError);
    await initial.future.timeout(const Duration(seconds: 10));
  }

  /// Holds the next refresh after Dio dispatch for logout fencing tests.
  Future<void> holdNextRefresh() => _adapter.holdNextRefresh();

  /// Releases a refresh held by [holdNextRefresh].
  void releaseRefresh() => _adapter.releaseRefresh();

  /// Completes when the held deterministic request reached the adapter.
  Future<void> get heldRefreshStarted => _adapter.heldRefreshStarted;

  /// Refreshes through real Dio and commits before the database-only UI emits.
  Future<bool> refresh({
    String id = 'task-1',
    String title = 'Remote task',
    int version = 1,
  }) async {
    _ensureActive();
    final generation = _generation;
    final previousEmissions = evidence.uiEmissions;
    _adapter.nextTask = (id: id, title: title, version: version);
    final response = await _dioOwner.dio.get<Map<String, dynamic>>(
      '/tasks/$id',
    );
    if (generation != _generation) {
      evidence.staleGenerationDrops += 1;
      return false;
    }
    final payload = response.data!;
    if (evidence.uiEmissions != previousEmissions) {
      throw StateError('UI changed before the remote value reached Drift.');
    }
    await _database
        .into(_database.fixtureTasks)
        .insertOnConflictUpdate(
          FixtureTasksCompanion.insert(
            id: payload['id']! as String,
            title: payload['title']! as String,
            version: Value<int>(payload['version']! as int),
            status: const Value<String>('open'),
          ),
        );
    await _waitFor(
      () => _visibleTasks.any(
        (task) =>
            task.id == id && task.version == version && task.title == title,
      ),
    );
    return true;
  }

  /// Atomically changes the local Task and enqueues its durable operation.
  Future<String> mutate({
    required String id,
    required String title,
    String? idempotencyKey,
    bool crashBeforeOutbox = false,
  }) async {
    _ensureActive();
    final key =
        idempotencyKey ?? 'task-$id-${DateTime.now().microsecondsSinceEpoch}';
    await _database.transaction(() async {
      final current = await (_database.select(
        _database.fixtureTasks,
      )..where((row) => row.id.equals(id))).getSingle();
      await (_database.update(
        _database.fixtureTasks,
      )..where((row) => row.id.equals(id))).write(
        FixtureTasksCompanion(
          title: Value<String>(title),
          version: Value<int>(current.version + 1),
          status: const Value<String>('pending'),
        ),
      );
      if (crashBeforeOutbox) throw StateError('injected atomic mutation crash');
      await _database
          .into(_database.fixtureOutbox)
          .insert(
            FixtureOutboxCompanion.insert(
              taskId: id,
              title: title,
              expectedVersion: current.version,
              status: 'pending',
              idempotencyKey: key,
            ),
          );
    });
    await _waitFor(
      () => _visibleTasks.any(
        (task) =>
            task.id == id && task.title == title && task.status == 'pending',
      ),
    );
    return key;
  }

  /// Delivers one durable operation without changing its idempotency key.
  Future<String> deliver(String idempotencyKey) async {
    _ensureActive();
    final operation = await (_database.select(
      _database.fixtureOutbox,
    )..where((row) => row.idempotencyKey.equals(idempotencyKey))).getSingle();
    try {
      final response = await _dioOwner.dio.post<void>(
        '/tasks/${operation.taskId}',
        data: <String, Object?>{
          'title': operation.title,
          'expectedVersion': operation.expectedVersion,
        },
        options: Options(
          headers: <String, Object?>{'Idempotency-Key': idempotencyKey},
          validateStatus: (_) => true,
        ),
      );
      evidence
        ..transportRequests = _adapter.requests
        ..appliedDeliveries = _adapter.appliedDeliveries
        ..duplicateDeliveries = _adapter.duplicateDeliveries
        ..deliveredKeys.add(idempotencyKey);
      if (response.statusCode == 409) {
        await _markDelivery(operation, 'conflicted');
        return 'conflicted';
      }
      if (response.statusCode != 204) {
        throw StateError(
          'Unexpected deterministic status ${response.statusCode}.',
        );
      }
      await _database.transaction(() async {
        await (_database.update(
          _database.fixtureTasks,
        )..where((row) => row.id.equals(operation.taskId))).write(
          const FixtureTasksCompanion(status: Value<String>('synced')),
        );
        await _database
            .into(_database.fixtureReceipts)
            .insertOnConflictUpdate(
              FixtureReceiptsCompanion.insert(
                idempotencyKey: idempotencyKey,
                disposition: 'applied',
              ),
            );
        await (_database.delete(
          _database.fixtureOutbox,
        )..where((row) => row.id.equals(operation.id))).go();
      });
      return 'synced';
    } on DioException {
      await _markDelivery(operation, 'uncertain');
      return 'uncertain';
    }
  }

  /// Audits an explicit non-terminal outcome and retries the same operation.
  Future<String> auditAndRetry(String idempotencyKey) async {
    _ensureActive();
    final operation = await (_database.select(
      _database.fixtureOutbox,
    )..where((row) => row.idempotencyKey.equals(idempotencyKey))).getSingle();
    await _database.transaction(() async {
      await (_database.update(
        _database.fixtureOutbox,
      )..where((row) => row.id.equals(operation.id))).write(
        const FixtureOutboxCompanion(status: Value<String>('pending')),
      );
      await (_database.update(_database.fixtureTasks)
            ..where((row) => row.id.equals(operation.taskId)))
          .write(const FixtureTasksCompanion(status: Value<String>('pending')));
    });
    remoteMode = TaskCanaryRemoteMode.online;
    return deliver(idempotencyKey);
  }

  /// Advances a checkpoint and journal under a strictly increasing fence.
  Future<void> checkpoint({
    required String owner,
    required int fencingToken,
    required String checkpoint,
  }) async {
    _ensureActive();
    await _database.transaction(() async {
      final lease = await (_database.select(
        _database.fixtureLeases,
      )..where((row) => row.dataset.equals('tasks'))).getSingleOrNull();
      if (lease != null && fencingToken <= lease.fencingToken) {
        throw StateError('stale fencing token');
      }
      await _database
          .into(_database.fixtureLeases)
          .insertOnConflictUpdate(
            FixtureLeasesCompanion.insert(
              dataset: 'tasks',
              owner: owner,
              fencingToken: fencingToken,
            ),
          );
      await _database
          .into(_database.fixtureCheckpoints)
          .insertOnConflictUpdate(
            FixtureCheckpointsCompanion.insert(
              key: 'tasks',
              checkpoint: checkpoint,
              fencingToken: Value<int?>(fencingToken),
            ),
          );
      final sequence =
          (await _database.select(_database.fixtureJournal).get()).length;
      await _database
          .into(_database.fixtureJournal)
          .insert(
            FixtureJournalCompanion.insert(
              attemptId: '$owner-$fencingToken',
              sequence: sequence,
              timestamp: DateTime.utc(
                2030,
                1,
                1,
              ).add(Duration(seconds: sequence)),
              fact: 1,
              datasetKey: const Value<String?>('tasks'),
              hasDatasetKey: true,
            ),
          );
    });
  }

  /// Invalidates in-flight work and clears all session-scoped local data.
  Future<void> logout() async {
    _ensureActive();
    _generation += 1;
    await _database.transaction(() async {
      await _database.delete(_database.fixtureOutbox).go();
      await _database.delete(_database.fixtureTasks).go();
    });
  }

  /// Tears down watcher then transport and proves a zero resource census.
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _watch?.cancel();
    _watch = null;
    _watchLease?.dispose();
    _watchLease = null;
    _dioOwner.dispose();
    evidence.closeCalls = _adapter.closeCalls;
    _dioLease.dispose();
    _sessionLease.dispose();
    census.verifyZero();
  }

  Future<void> _markDelivery(FixtureOutboxData operation, String status) =>
      _database.transaction(() async {
        await (_database.update(_database.fixtureOutbox)
              ..where((row) => row.id.equals(operation.id)))
            .write(FixtureOutboxCompanion(status: Value<String>(status)));
        await (_database.update(_database.fixtureTasks)
              ..where((row) => row.id.equals(operation.taskId)))
            .write(FixtureTasksCompanion(status: Value<String>(status)));
      });

  void _ensureActive() {
    if (_disposed) throw StateError('Task vertical canary is disposed.');
  }
}

final class _TaskCanaryHttpAdapter implements HttpClientAdapter {
  TaskCanaryRemoteMode mode = TaskCanaryRemoteMode.online;
  ({String id, String title, int version}) nextTask = (
    id: 'task-1',
    title: 'Remote task',
    version: 1,
  );
  final Set<String> _appliedKeys = <String>{};
  Completer<void>? _heldStart;
  Completer<void>? _heldRelease;
  var requests = 0;
  var appliedDeliveries = 0;
  var duplicateDeliveries = 0;
  var closeCalls = 0;
  var _closed = false;

  Future<void> holdNextRefresh() async {
    if (_heldRelease != null) throw StateError('A refresh is already held.');
    _heldStart = Completer<void>();
    _heldRelease = Completer<void>();
  }

  Future<void> get heldRefreshStarted =>
      (_heldStart ?? (throw StateError('No refresh is held.'))).future;

  void releaseRefresh() {
    final release = _heldRelease ?? (throw StateError('No refresh is held.'));
    if (!release.isCompleted) release.complete();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) throw StateError('Task canary HTTP adapter is closed.');
    requests += 1;
    if (options.method == 'GET' && options.path.startsWith('/tasks/')) {
      final held = _heldRelease;
      if (held != null) {
        _heldStart!.complete();
        await held.future;
        _heldStart = null;
        _heldRelease = null;
      }
      return ResponseBody.fromString(
        jsonEncode(<String, Object?>{
          'id': nextTask.id,
          'title': nextTask.title,
          'version': nextTask.version,
        }),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'POST' && options.path.startsWith('/tasks/')) {
      if (mode == TaskCanaryRemoteMode.uncertain) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'deterministic uncertain delivery',
        );
      }
      if (mode == TaskCanaryRemoteMode.conflict) {
        return ResponseBody.fromString('', 409);
      }
      final key = options.headers['Idempotency-Key']! as String;
      if (_appliedKeys.add(key)) {
        appliedDeliveries += 1;
      } else {
        duplicateDeliveries += 1;
      }
      return ResponseBody.fromString('', 204);
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    closeCalls += 1;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 500; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Task vertical canary observation timed out.');
}
