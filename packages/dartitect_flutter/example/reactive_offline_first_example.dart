import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/widgets.dart';

/// Small route-owned local-first example using only the headless entrypoint.
final class HeadlessOfflineFirstTasksExample extends StatefulWidget {
  /// Creates the example route.
  const HeadlessOfflineFirstTasksExample({super.key});

  @override
  State<HeadlessOfflineFirstTasksExample> createState() =>
      _HeadlessOfflineFirstTasksExampleState();
}

final class _HeadlessOfflineFirstTasksExampleState
    extends State<HeadlessOfflineFirstTasksExample> {
  late final ExampleTasksRuntime runtime;

  @override
  void initState() {
    super.initState();
    runtime = ExampleTasksRuntime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(runtime.paged.refresh());
    });
  }

  @override
  void dispose() {
    unawaited(runtime.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: PagedLiveBuilder<int, int, ExampleTask, String>(
      resource: runtime.paged,
      builder: (context, resource, keys, child) => Column(
        children: <Widget>[
          if (resource.lastFailure != null)
            const Text('Offline: showing the local snapshot'),
          Expanded(
            child: ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final item = resource.collection.item(key);
                return ReactiveValueBuilder<ExampleTask?>(
                  key: ValueKey<int>(key),
                  value: item,
                  builder: (context, value, child) => item.isPresent
                      ? Text(value!.title)
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
          Semantics(
            button: true,
            label: 'Refresh tasks',
            child: GestureDetector(
              onTap: () => unawaited(runtime.paged.refresh()),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Refresh'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Route-owned example composition with a local authoritative source.
final class ExampleTasksRuntime {
  /// Creates a fresh feature graph without globals or provider resources.
  factory ExampleTasksRuntime() {
    final source = _ExampleLocalSource();
    final local = LiveResource<PagedLocalSnapshot<int, ExampleTask>, String>(
      source: source,
      policy: const ActivationPolicy.whileObserved(),
    );
    late final PagedLiveResource<int, int, ExampleTask, String> paged;
    paged = PagedLiveResource<int, int, ExampleTask, String>(
      local: local,
      initialCursor: 0,
      requestPage: (request, signal) async {
        signal.throwIfCancelled();
        if (!source.online) {
          return Err<String>('offline', StackTrace.current);
        }
        return switch (request.cursor) {
          0 => const Ok<PageBatch<int, ExampleTask>>(
            PageBatch<int, ExampleTask>(
              items: <ExampleTask>[
                ExampleTask(id: 1, version: 1, title: 'Inspect field'),
                ExampleTask(id: 2, version: 1, title: 'Sync inventory'),
              ],
              nextCursor: 2,
            ),
          ),
          _ => const Ok<PageBatch<int, ExampleTask>>(
            PageBatch<int, ExampleTask>(
              items: <ExampleTask>[
                ExampleTask(id: 3, version: 1, title: 'Review offline outbox'),
              ],
              nextCursor: null,
            ),
          ),
        };
      },
      writePage: (write, signal) async {
        signal.throwIfCancelled();
        final revision = source.write(write.items, reset: write.reset);
        return Ok<PageWriteReceipt<int>>(
          PageWriteReceipt<int>(
            localRevision: revision,
            nextCursor: write.nextCursor,
          ),
        );
      },
      keyOf: (task) => task.id,
      versionOf: (task) => task.version,
      collectionPolicy: CollectionUpdatePolicy.versionedByKey,
      observationTimeout: const Duration(seconds: 2),
      mapObservationTimeout: (receipt) => 'local observation timed out',
    );
    return ExampleTasksRuntime._(source, local, paged);
  }

  ExampleTasksRuntime._(this._source, this.local, this.paged);

  final _ExampleLocalSource _source;

  /// Owned local reactive resource.
  final LiveResource<PagedLocalSnapshot<int, ExampleTask>, String> local;

  /// Owned paged resource that borrows [local].
  final PagedLiveResource<int, int, ExampleTask, String> paged;

  /// Whether the fake remote is reachable.
  bool get isOnline => _source.online;

  /// Toggles the fake remote without changing the authoritative local data.
  void setOnline(bool value) => _source.online = value;

  /// Disposes the paged consumer before its local source.
  Future<void> dispose() async {
    await paged.dispose();
    await local.dispose();
  }
}

/// Immutable local entity/DTO used only by the package example.
final class const ExampleTask({
  /// Stable local key.
  required final int id,

  /// Projection version.
  required final int version,

  /// Presentational title.
  required final String title,
}) {
  /// Creates a task with stable ID and explicit projection version.
  this;
}

final class _ExampleLocalSource
    implements ReactiveSource<PagedLocalSnapshot<int, ExampleTask>, String> {
  final List<_ExampleLocalSession> _sessions = <_ExampleLocalSession>[];
  List<ExampleTask> _items = <ExampleTask>[];
  var _revision = 0;
  var online = true;

  int write(List<ExampleTask> items, {required bool reset}) {
    final values = <int, ExampleTask>{
      if (!reset)
        for (final task in _items) task.id: task,
      for (final task in items) task.id: task,
    };
    _items = List<ExampleTask>.unmodifiable(values.values);
    _revision += 1;
    for (final session in _sessions.toList(growable: false)) {
      session.signal();
    }
    return _revision;
  }

  @override
  Future<
    Result<
      ReactiveSourceSession<PagedLocalSnapshot<int, ExampleTask>, String>,
      String
    >
  >
  open() async {
    final session = _ExampleLocalSession(this);
    _sessions.add(session);
    return Ok<
      ReactiveSourceSession<PagedLocalSnapshot<int, ExampleTask>, String>
    >(session);
  }

  PagedLocalSnapshot<int, ExampleTask> snapshot() =>
      PagedLocalSnapshot<int, ExampleTask>(
        revision: _revision,
        items: List<ExampleTask>.unmodifiable(_items),
      );
}

final class _ExampleLocalSession
    implements
        ReactiveSourceSession<PagedLocalSnapshot<int, ExampleTask>, String> {
  _ExampleLocalSession(this.source);

  final _ExampleLocalSource source;
  final StreamController<void> _signals = StreamController<void>.broadcast(
    sync: true,
  );
  var _closed = false;

  @override
  Stream<void> get signals => _signals.stream;

  void signal() {
    if (!_closed) _signals.add(null);
  }

  @override
  Future<Result<PagedLocalSnapshot<int, ExampleTask>, String>> read(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    return Ok<PagedLocalSnapshot<int, ExampleTask>>(source.snapshot());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    source._sessions.remove(this);
    await _signals.close();
  }
}
