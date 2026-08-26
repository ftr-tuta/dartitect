import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:flutter/material.dart';

import '../application/offline_first_task_session.dart';
import '../application/offline_task_store.dart';
import '../application/task_remote.dart';
import '../domain/task.dart';
import '../domain/task_repository.dart';

/// Route-owned callbacks and lifecycle around the offline-first task session.
final class TasksPage extends StatefulWidget {
  /// Creates the task route.
  const TasksPage({required this.session, super.key});

  /// Borrowed feature/session composition supplied by the application root.
  final OfflineFirstTaskSession session;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

final class _TasksPageState extends State<TasksPage>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  OfflineFirstTaskSession? _session;
  String? _mutationStatus;

  OfflineFirstTaskSession get session => _session!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    _session = widget.session;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(session.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    session.setForeground(
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dartitect Tasks'),
      actions: <Widget>[
        IconButton(
          tooltip: 'Open diagnostics',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => _DiagnosticsPage(session: session),
            ),
          ),
          icon: const Icon(Icons.monitor_heart_outlined),
        ),
      ],
    ),
    body: Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search 10,000 local tasks',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _search.clear();
                  unawaited(session.search(''));
                },
                icon: const Icon(Icons.clear),
              ),
            ),
            onSubmitted: (value) => unawaited(session.search(value)),
          ),
        ),
        SwitchListTile(
          title: const Text('Airplane mode'),
          subtitle: Text(
            session.remote.mode == ReferenceRemoteMode.offline
                ? 'Changes stay in the durable outbox'
                : 'Remote delivery enabled',
          ),
          value: session.remote.mode == ReferenceRemoteMode.offline,
          onChanged: (offline) {
            setState(() {
              session.remote.mode = offline
                  ? ReferenceRemoteMode.offline
                  : ReferenceRemoteMode.online;
            });
            if (!offline) unawaited(session.reconnect());
          },
        ),
        if (_mutationStatus case final status?)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(status),
            ),
          ),
        Expanded(
          child: _TasksPagedView(
            resource: session.paged,
            onRefresh: session.refresh,
            onLoadMore: session.loadMore,
            onToggle: _toggle,
          ),
        ),
      ],
    ),
  );

  Future<void> _toggle(int key) async {
    final outcome = await session.toggle(key);
    if (!mounted) return;
    final message = switch (outcome) {
      CommandSucceeded<
        MutationExecution<TaskMutation, int, void, TaskFailure>,
        TaskFailure
      >(
        :final value,
      ) =>
        switch (value.disposition) {
          CommitDisposition.committed => 'Change synchronized',
          CommitDisposition.queued => 'Offline change queued',
          CommitDisposition.rejected => 'Change needs review',
          CommitDisposition.uncertain => 'Delivery needs an audit',
        },
      CommandFailed<Object?, TaskFailure>() => 'Local change failed',
      CommandRejected<Object?, TaskFailure>() => 'Task lane is unavailable',
      CommandDropped<Object?, TaskFailure>() => 'Duplicate action dropped',
      CommandCancelled<Object?, TaskFailure>() => 'Action cancelled',
    };
    setState(() => _mutationStatus = message);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }
}

final class _TasksPagedView extends StatelessWidget {
  const _TasksPagedView({
    required this.resource,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onToggle,
  });

  final PagedLiveResource<TaskCursor, int, Task, TaskFailure> resource;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final Future<void> Function(int key) onToggle;

  @override
  Widget build(BuildContext context) =>
      PagedLiveBuilder<TaskCursor, int, Task, TaskFailure>(
        resource: resource,
        builder: (context, resource, keys, child) => Semantics(
          container: true,
          label: 'Offline-first tasks',
          child: Column(
            children: <Widget>[
              if (resource.isBusy)
                const LinearProgressIndicator(semanticsLabel: 'Loading tasks'),
              if (resource.lastFailure != null || resource.crash != null)
                Semantics(
                  liveRegion: true,
                  child: FilledButton(
                    onPressed: () => unawaited(onRefresh()),
                    child: const Text('Retry page'),
                  ),
                ),
              Expanded(
                child: keys.isEmpty && !resource.isBusy
                    ? const Center(child: Text('No local tasks'))
                    : RefreshIndicator(
                        onRefresh: onRefresh,
                        child: ListView.builder(
                          itemCount: keys.length,
                          itemBuilder: (context, index) {
                            final key = keys[index];
                            final item = resource.collection.item(key);
                            return ReactiveValueBuilder<Task?>(
                              key: ValueKey<int>(key),
                              value: item,
                              builder: (context, task, child) => task == null
                                  ? const SizedBox.shrink()
                                  : CheckboxListTile(
                                      title: Text(task.title),
                                      subtitle: Text(
                                        'Sync: ${task.syncState.name}',
                                      ),
                                      value: task.completed,
                                      onChanged: (_) =>
                                          unawaited(onToggle(key)),
                                    ),
                            );
                          },
                        ),
                      ),
              ),
              if (resource.nextCursor != null)
                FilledButton(
                  onPressed: resource.isLoadingMore
                      ? null
                      : () => unawaited(onLoadMore()),
                  child: const Text('Load more tasks'),
                ),
            ],
          ),
        ),
      );
}

final class _DiagnosticsPage extends StatelessWidget {
  const _DiagnosticsPage({required this.session});

  final OfflineFirstTaskSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Runtime diagnostics')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Store: ${session.store.isNativeObjectBox ? 'ObjectBox' : 'memory'}',
        ),
        Text('Journal entries: ${session.journal.length}'),
        Text('Remote requests: ${session.remote.diagnostics.mutationRequests}'),
        Text('Active watchers: ${session.store.diagnostics.activeWatchers}'),
      ],
    ),
  );
}
