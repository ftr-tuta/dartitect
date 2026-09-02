import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/task.dart';
import 'tasks_view_model.dart';

/// Route lifecycle, controllers, navigation, and mounted effects for tasks.
final class TasksPage extends StatefulWidget {
  /// Creates the route around its generated, borrowed ViewModel.
  const TasksPage({required this.viewModel, super.key});

  /// ViewModel owned by the generated feature host.
  final TasksViewModel viewModel;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

final class _TasksPageState extends State<TasksPage>
    with WidgetsBindingObserver {
  late final TextEditingController _search;
  final ScrollController _scroll = ScrollController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'tasks.search');

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.viewModel.query);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.viewModel.setForeground(
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    );
  }

  @override
  Widget build(BuildContext context) => EffectListener<TasksEffect>(
    channel: widget.viewModel.effects,
    onEffect: _onEffect,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Dartitect Tasks'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Open diagnostics',
            onPressed: widget.viewModel.openDiagnostics,
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
        ],
      ),
      body: TasksView(
        viewModel: widget.viewModel,
        searchController: _search,
        scrollController: _scroll,
        searchFocusNode: _searchFocus,
      ),
    ),
  );

  Future<void> _onEffect(BuildContext context, TasksEffect effect) async {
    switch (effect) {
      case TasksMutationEffect(:final result):
        final message = switch (result) {
          TaskMutationPresentation.synchronized => 'Change synchronized',
          TaskMutationPresentation.queued => 'Offline change queued',
          TaskMutationPresentation.review => 'Change needs review',
          TaskMutationPresentation.audit => 'Delivery needs an audit',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      case OpenTasksDiagnosticsEffect(:final data):
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => TasksDiagnosticsPage(data: data),
          ),
        );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocus.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }
}

/// Consumer-owned UI that observes only the tasks ViewModel.
final class TasksView extends StatelessWidget {
  /// Creates responsive task presentation around route-owned controllers.
  const TasksView({
    required this.viewModel,
    required this.searchController,
    required this.scrollController,
    required this.searchFocusNode,
    super.key,
  });

  /// Borrowed presentation owner.
  final TasksViewModel viewModel;

  /// Route-owned controller retained across responsive branches.
  final TextEditingController searchController;

  /// Route-owned scroll position retained across responsive branches.
  final ScrollController scrollController;

  /// Route-owned focus retained across responsive branches.
  final FocusNode searchFocusNode;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, child) => Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            key: const ValueKey<String>('tasks-search'),
            controller: searchController,
            focusNode: searchFocusNode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search 10,000 local tasks',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  searchController.clear();
                  unawaited(viewModel.searchCommand.execute(''));
                },
                icon: const Icon(Icons.clear),
              ),
            ),
            onSubmitted: (value) =>
                unawaited(viewModel.searchCommand.execute(value)),
          ),
        ),
        SwitchListTile(
          title: const Text('Airplane mode'),
          subtitle: Text(
            viewModel.isOffline
                ? 'Changes stay in the durable outbox'
                : 'Remote delivery enabled',
          ),
          value: viewModel.isOffline,
          onChanged: (offline) =>
              unawaited(viewModel.connectivityCommand.execute(offline)),
        ),
        Expanded(
          child: PagedLiveBuilder(
            resource: viewModel.tasks,
            builder: (context, resource, keys, child) => Semantics(
              container: true,
              label: 'Offline-first tasks',
              child: Column(
                children: <Widget>[
                  if (resource.isBusy)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Loading tasks',
                    ),
                  if (resource.lastFailure != null || resource.crash != null)
                    Semantics(
                      liveRegion: true,
                      child: FilledButton(
                        onPressed: () =>
                            unawaited(viewModel.refreshCommand.execute()),
                        child: const Text('Retry page'),
                      ),
                    ),
                  Expanded(
                    child: TasksContent(
                      taskIds: keys,
                      taskAt: resource.collection.item,
                      selectedTaskId: viewModel.selectedTaskId,
                      selectedTask: viewModel.selectedTask,
                      scrollController: scrollController,
                      onRefresh: () async {
                        await viewModel.refreshCommand.execute();
                      },
                      onSelect: viewModel.selectTask,
                      onToggle: (id) async {
                        await viewModel.toggleCommand.execute(id, id);
                      },
                    ),
                  ),
                  if (resource.nextCursor != null)
                    FilledButton(
                      onPressed: resource.isLoadingMore
                          ? null
                          : () =>
                                unawaited(viewModel.loadMoreCommand.execute()),
                      child: const Text('Load more tasks'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Constraint-driven content that receives only values and callbacks.
final class TasksContent extends StatelessWidget {
  /// Creates a responsive list/detail surface.
  const TasksContent({
    required this.taskIds,
    required this.taskAt,
    required this.selectedTaskId,
    required this.selectedTask,
    required this.scrollController,
    required this.onRefresh,
    required this.onSelect,
    required this.onToggle,
    super.key,
  });

  /// Stable task IDs; rows remain lazily materialized.
  final List<int> taskIds;

  /// Value-only row selector supplied by the presentation bridge.
  final ValueListenable<Task?> Function(int id) taskAt;

  /// Selected identifier retained by the ViewModel.
  final int? selectedTaskId;

  /// Selected immutable task projection.
  final Task? selectedTask;

  /// Route-owned retained scroll position.
  final ScrollController scrollController;

  /// Refresh callback.
  final RefreshCallback onRefresh;

  /// Selection callback.
  final ValueChanged<int> onSelect;

  /// Mutation callback.
  final Future<void> Function(int id) onToggle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final list = TasksList(
        taskIds: taskIds,
        taskAt: taskAt,
        selectedTaskId: selectedTaskId,
        scrollController: scrollController,
        onRefresh: onRefresh,
        onSelect: onSelect,
        onToggle: onToggle,
      );
      final details = TaskDetails(
        task: selectedTask,
        onToggle: selectedTask == null
            ? null
            : () => unawaited(onToggle(selectedTask!.id)),
      );
      if (constraints.maxWidth < 600) {
        return Column(
          key: const ValueKey<String>('compact-layout'),
          children: <Widget>[
            Expanded(child: list),
            if (selectedTask != null) SizedBox(height: 116, child: details),
          ],
        );
      }
      final detailWidth = constraints.maxWidth < 1000 ? 280.0 : 400.0;
      return Row(
        key: ValueKey<String>(
          constraints.maxWidth < 1000 ? 'medium-layout' : 'expanded-layout',
        ),
        children: <Widget>[
          Expanded(child: list),
          const VerticalDivider(width: 1),
          SizedBox(width: detailWidth, child: details),
        ],
      );
    },
  );
}

/// Lazily materialized task list with per-row reactive selectors.
final class TasksList extends StatelessWidget {
  /// Creates a virtualized list from values and callbacks.
  const TasksList({
    required this.taskIds,
    required this.taskAt,
    required this.selectedTaskId,
    required this.scrollController,
    required this.onRefresh,
    required this.onSelect,
    required this.onToggle,
    super.key,
  });

  /// Stable task IDs used by [ListView.builder].
  final List<int> taskIds;

  /// Selector for one immutable row value.
  final ValueListenable<Task?> Function(int id) taskAt;

  /// Selected task ID, when any.
  final int? selectedTaskId;

  /// Route-owned retained scroll position.
  final ScrollController scrollController;

  /// Refresh callback.
  final RefreshCallback onRefresh;

  /// Selection callback.
  final ValueChanged<int> onSelect;

  /// Mutation callback.
  final Future<void> Function(int id) onToggle;

  @override
  Widget build(BuildContext context) => taskIds.isEmpty
      ? const Center(child: Text('No local tasks'))
      : RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            key: const PageStorageKey<String>('tasks-list'),
            controller: scrollController,
            itemCount: taskIds.length,
            itemBuilder: (context, index) {
              final id = taskIds[index];
              return ReactiveValueBuilder<Task?>(
                key: ValueKey<int>(id),
                value: taskAt(id),
                builder: (context, task, child) => task == null
                    ? const SizedBox.shrink()
                    : TaskRow(
                        task: task,
                        selected: selectedTaskId == id,
                        onSelect: () => onSelect(id),
                        onToggle: () => unawaited(onToggle(id)),
                      ),
              );
            },
          ),
        );
}

/// Reusable task row receiving only immutable values and callbacks.
final class TaskRow extends StatelessWidget {
  /// Creates one task row.
  const TaskRow({
    required this.task,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
    super.key,
  });

  /// Immutable task values.
  final Task task;

  /// Whether this row is selected.
  final bool selected;

  /// Pure selection callback.
  final VoidCallback onSelect;

  /// Pure mutation callback.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    selected: selected,
    title: Text(task.title),
    subtitle: Text('Sync: ${task.syncState.name}'),
    value: task.completed,
    onChanged: (_) => onToggle(),
    secondary: IconButton(
      tooltip: 'Select ${task.title}',
      onPressed: onSelect,
      icon: const Icon(Icons.chevron_right),
    ),
  );
}

/// Selected-task detail projection receiving no repository or session.
final class TaskDetails extends StatelessWidget {
  /// Creates a detail panel for [task].
  const TaskDetails({required this.task, required this.onToggle, super.key});

  /// Selected immutable task values.
  final Task? task;

  /// Pure mutation callback when a task is selected.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final selected = task;
    if (selected == null) {
      return const Center(child: Text('Select a task for details'));
    }
    return ListView(
      key: ValueKey<int>(selected.id),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(selected.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Sync: ${selected.syncState.name}'),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: onToggle,
          child: Text(selected.completed ? 'Mark incomplete' : 'Mark complete'),
        ),
      ],
    );
  }
}

/// Diagnostics route that receives only a payload-free view-data projection.
final class TasksDiagnosticsPage extends StatelessWidget {
  /// Creates the diagnostics route.
  const TasksDiagnosticsPage({required this.data, super.key});

  /// Immutable diagnostics presentation values.
  final TasksDiagnosticsViewData data;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Runtime diagnostics')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Store: ${data.storeKind}'),
        Text('Journal entries: ${data.journalEntries}'),
        Text('Remote requests: ${data.remoteRequests}'),
        Text('Active watchers: ${data.activeWatchers}'),
        Text('Active queries: ${data.activeQueries}'),
        Text('Active workers: ${data.activeWorkers}'),
      ],
    ),
  );
}
