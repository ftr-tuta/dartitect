import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:dio/dio.dart';

import '../application/offline_task_store.dart';
import '../application/task_remote.dart';
import '../domain/task.dart';
import '../domain/task_repository.dart';

/// Owned Dio boundary with an in-process deterministic HTTP adapter.
final class ReferenceTaskRemote implements TaskRemote {
  /// Creates an owned client in the selected deterministic [mode].
  ReferenceTaskRemote({ReferenceRemoteMode mode = ReferenceRemoteMode.online})
    : _mode = mode {
    _adapter = _ReferenceHttpAdapter(this);
    _owner = DioOwner.create(
      options: BaseOptions(baseUrl: 'https://reference.invalid'),
      configure: (dio) => dio.httpClientAdapter = _adapter,
    );
  }

  late final DioOwner _owner;
  late final _ReferenceHttpAdapter _adapter;
  final Set<String> _deliveredKeys = <String>{};
  ReferenceRemoteMode _mode;
  var _disposed = false;

  /// Stable diagnostics readable after disposal.
  @override
  final ReferenceRemoteDiagnostics diagnostics = ReferenceRemoteDiagnostics();

  /// Current deterministic remote behavior.
  @override
  ReferenceRemoteMode get mode => _mode;

  /// Selects the next request behavior without changing local state.
  @override
  set mode(ReferenceRemoteMode value) {
    _ensureActive();
    _mode = value;
  }

  /// Fetches one 50-row page through Dio with cooperative cancellation.
  @override
  Future<Result<PageBatch<TaskCursor, Task>, TaskFailure>> requestPage(
    PageRequest<TaskCursor> request,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final token = bindCancelToken(signal);
    final captured = await captureDioException<Response<dynamic>>(
      () => _owner.dio.get<dynamic>(
        '/tasks',
        queryParameters: <String, Object?>{
          'query': request.cursor.query,
          'offset': request.cursor.offset,
          'limit': 50,
        },
        cancelToken: token,
      ),
    );
    signal.throwIfCancelled();
    switch (captured) {
      case Err<Object>(:final failure, :final stackTrace):
        return Err<TaskFailure>(_mapFailure(failure as DioFailure), stackTrace);
      case Ok<dynamic>(:final value):
        final response = value as Response<dynamic>;
        final payload = response.data as Map<String, dynamic>;
        final rows = payload['items']! as List<dynamic>;
        final tasks = rows
            .cast<Map<String, dynamic>>()
            .map(
              (row) => Task(
                id: row['id']! as int,
                title: row['title']! as String,
                completed: row['completed']! as bool,
                version: row['version']! as int,
              ),
            )
            .toList(growable: false);
        final nextOffset = payload['nextOffset'] as int?;
        return Ok<PageBatch<TaskCursor, Task>>(
          PageBatch<TaskCursor, Task>(
            items: tasks,
            nextCursor: nextOffset == null
                ? null
                : TaskCursor(query: request.cursor.query, offset: nextOffset),
          ),
        );
    }
  }

  /// Delivers one idempotent mutation through the owned Dio client.
  @override
  Future<Result<void, TaskFailure>> synchronize(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    if (_mode == ReferenceRemoteMode.crash) {
      throw StateError('Reference remote invariant failed.');
    }
    final token = bindCancelToken(signal);
    final captured = await captureDioException<Response<dynamic>>(
      () => _owner.dio.post<dynamic>(
        '/tasks/${operation.key}',
        data: <String, Object?>{'completed': operation.argument.completed},
        options: Options(
          headers: <String, Object?>{
            'Idempotency-Key': operation.idempotencyKey,
          },
        ),
        cancelToken: token,
      ),
    );
    signal.throwIfCancelled();
    return switch (captured) {
      Ok<dynamic>() => const Ok<void>(null),
      Err<Object>(:final failure, :final stackTrace) => Err<TaskFailure>(
        _mapFailure(failure as DioFailure),
        stackTrace,
      ),
    };
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owner.dispose();
  }

  TaskFailure _mapFailure(DioFailure failure) {
    if (failure case DioHttpFailure(:final statusCode)) {
      return switch (statusCode) {
        409 => const TaskConflictFailure(),
        422 => const TaskRejectedFailure(),
        _ => const TaskOfflineFailure(),
      };
    }
    if (_mode == ReferenceRemoteMode.uncertain) {
      return const TaskUncertainFailure();
    }
    return const TaskOfflineFailure();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ReferenceTaskRemote is disposed.');
  }
}

final class _ReferenceHttpAdapter implements HttpClientAdapter {
  _ReferenceHttpAdapter(this.remote);

  final ReferenceTaskRemote remote;
  var closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (closed) throw StateError('Reference HTTP adapter is closed.');
    if (options.method == 'GET' && options.path == '/tasks') {
      return _page(options, cancelFuture);
    }
    if (options.method == 'POST' && options.path.startsWith('/tasks/')) {
      return _mutation(options);
    }
    return ResponseBody.fromString('', 404);
  }

  Future<ResponseBody> _page(
    RequestOptions options,
    Future<void>? cancelFuture,
  ) async {
    final query = (options.queryParameters['query'] as String? ?? '')
        .trim()
        .toLowerCase();
    final offset = options.queryParameters['offset']! as int;
    final limit = options.queryParameters['limit']! as int;
    if (query.contains('slow')) {
      final delay = Future<void>.delayed(const Duration(milliseconds: 40));
      if (cancelFuture == null) {
        await delay;
      } else {
        await Future.any<void>(<Future<void>>[delay, cancelFuture]);
      }
    }
    if (remote.mode == ReferenceRemoteMode.offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final matching = <Map<String, Object?>>[
      for (var id = 1; id <= 10000; id += 1)
        if (_title(id).toLowerCase().contains(query))
          <String, Object?>{
            'id': id,
            'title': _title(id),
            'completed': false,
            'version': 1,
          },
    ];
    final end = (offset + limit).clamp(0, matching.length);
    final items = offset >= matching.length
        ? const <Map<String, Object?>>[]
        : matching.sublist(offset, end);
    final body = jsonEncode(<String, Object?>{
      'items': items,
      'nextOffset': end < matching.length ? end : null,
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  ResponseBody _mutation(RequestOptions options) {
    remote.diagnostics.mutationRequests += 1;
    switch (remote.mode) {
      case ReferenceRemoteMode.offline || ReferenceRemoteMode.uncertain:
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'transport unavailable',
        );
      case ReferenceRemoteMode.reject:
        return ResponseBody.fromString('', 422);
      case ReferenceRemoteMode.conflict:
        return ResponseBody.fromString('', 409);
      case ReferenceRemoteMode.online:
        final key = options.headers['Idempotency-Key']! as String;
        if (remote._deliveredKeys.add(key)) {
          remote.diagnostics.appliedDeliveries += 1;
        } else {
          remote.diagnostics.duplicateDeliveries += 1;
        }
        return ResponseBody.fromString('', 204);
      case ReferenceRemoteMode.crash:
        throw StateError('Crash mode is handled before Dio dispatch.');
    }
  }

  @override
  void close({bool force = false}) {
    if (closed) return;
    closed = true;
    remote.diagnostics.closeCalls += 1;
  }
}

String _title(int id) => id == 1
    ? 'Inspect explicit composition'
    : 'Field task ${id.toString().padLeft(5, '0')}';
