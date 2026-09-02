import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import '../composition/application_module.wiring.dartitect.g.dart';
import '../features/tasks/composition/tasks.wiring.dartitect.g.dart';
import '../features/tasks/composition/tasks_factory.dart';
import '../features/tasks/presentation/tasks_page.dart';
import 'app_runtime.dart';

/// Root shell borrowing the generated application graph.
final class ReferenceApp extends StatefulWidget {
  /// Creates the application shell for one committed graph.
  const ReferenceApp({
    required this.graph,
    this.autoDrainForcedLogout = true,
    super.key,
  });

  /// Borrowed graph retained by the application host.
  final ApplicationGraph graph;

  /// Whether forced logout drains immediately after authenticated routes leave.
  final bool autoDrainForcedLogout;

  @override
  State<ReferenceApp> createState() => _ReferenceAppState();
}

final class _ReferenceAppState extends State<ReferenceApp> {
  FlutterErrorBinding? _errorBinding;
  var _forcedLogoutDrainScheduled = false;

  AppRuntime get runtime => widget.graph.referenceRuntime;

  @override
  void initState() {
    super.initState();
    runtime.markAuthenticatedRoutesMounted();
    _errorBinding = FlutterErrorBinding.install(
      reporter: runtime.flutterCrashReporter,
    );
  }

  @override
  Widget build(BuildContext context) => DartitectScope<AppRuntime>(
    value: runtime,
    child:
        ListenableSelector<
          SessionStateController<ReferenceSessionDescription>,
          SessionState<ReferenceSessionDescription>
        >(
          source: runtime.sessionState,
          select: (source) => source.value,
          builder: (context, session, child) => switch (session) {
            SessionActive<ReferenceSessionDescription>() => MaterialApp(
              key: const ValueKey<String>('authenticated-shell'),
              home: _AuthenticatedTasksRoute(
                graph: widget.graph,
                runtime: runtime,
              ),
            ),
            SessionForcedLogout<ReferenceSessionDescription>() =>
              _forcedLogoutShell(),
            SessionTransitioning<ReferenceSessionDescription>() =>
              const MaterialApp(
                key: ValueKey<String>('transitioning-shell'),
                home: Scaffold(
                  body: Center(child: CircularProgressIndicator.adaptive()),
                ),
              ),
            SessionTransitionFailed<ReferenceSessionDescription>() =>
              const MaterialApp(
                key: ValueKey<String>('transition-failed-shell'),
                home: Scaffold(
                  body: Center(child: Text('Session transition failed')),
                ),
              ),
            SessionAnonymous<ReferenceSessionDescription>() ||
            SessionSignedOut<ReferenceSessionDescription>() =>
              const MaterialApp(
                key: ValueKey<String>('signed-out-shell'),
                home: Scaffold(body: Center(child: Text('Session signed out'))),
              ),
          },
        ),
  );

  Widget _forcedLogoutShell() {
    if (widget.autoDrainForcedLogout && !_forcedLogoutDrainScheduled) {
      _forcedLogoutDrainScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(runtime.completeForcedLogout());
      });
    }
    return const MaterialApp(
      key: ValueKey<String>('signed-out-shell'),
      home: Scaffold(body: Center(child: Text('Session signed out'))),
    );
  }

  @override
  void dispose() {
    _errorBinding?.dispose();
    super.dispose();
  }
}

final class _AuthenticatedTasksRoute extends StatefulWidget {
  const _AuthenticatedTasksRoute({required this.graph, required this.runtime});

  final ApplicationGraph graph;
  final AppRuntime runtime;

  @override
  State<_AuthenticatedTasksRoute> createState() =>
      _AuthenticatedTasksRouteState();
}

final class _AuthenticatedTasksRouteState
    extends State<_AuthenticatedTasksRoute> {
  @override
  Widget build(BuildContext context) => TasksFeatureHost(
    graph: widget.graph,
    factory: const TasksFactory(),
    loading: (_) => const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    ),
    failure: (_, failure, retry) => Scaffold(
      body: Center(
        child: TextButton(onPressed: retry, child: const Text('Retry Tasks')),
      ),
    ),
    start: (viewModel) => viewModel.start(),
    ready: (_, feature, viewModel) => TasksPage(viewModel: viewModel),
  );

  @override
  void dispose() {
    widget.runtime.confirmAuthenticatedRoutesRemoved();
    super.dispose();
  }
}
