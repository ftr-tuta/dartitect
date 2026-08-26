import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import 'app/app_runtime.dart';
import 'features/tasks/presentation/tasks_page.dart';

/// Starts the native-first reference application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReferenceApp());
}

/// Root widget that owns the asynchronously opened application runtime.
final class ReferenceApp extends StatefulWidget {
  /// Creates the reference application with an optional test composition.
  const ReferenceApp({
    this.createRuntime,
    this.autoDrainForcedLogout = true,
    super.key,
  });

  /// Optional injected runtime factory used by deterministic widget tests.
  final Future<AppRuntime> Function()? createRuntime;

  /// Whether the shell automatically drains after removing authenticated UI.
  ///
  /// Tests may disable this to inspect the forced-logout boundary before
  /// invoking the same public drain explicitly.
  final bool autoDrainForcedLogout;

  @override
  State<ReferenceApp> createState() => _ReferenceAppState();
}

final class _ReferenceAppState extends State<ReferenceApp> {
  late final Future<AppRuntime> _runtimeFuture;
  AppRuntime? _runtime;
  FlutterErrorBinding? _errorBinding;
  var _acceptRuntime = true;
  var _forcedLogoutDrainScheduled = false;

  @override
  void initState() {
    super.initState();
    _runtimeFuture = _initialize();
  }

  Future<AppRuntime> _initialize() async {
    final runtime = await (widget.createRuntime ?? AppRuntime.create)();
    if (!_acceptRuntime) {
      await runtime.disposeAsync();
      return runtime;
    }
    _runtime = runtime;
    _errorBinding = FlutterErrorBinding.install(
      reporter: runtime.flutterCrashReporter,
    );
    return runtime;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppRuntime>(
    future: _runtimeFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Could not open the local task store.')),
          ),
        );
      }
      final runtime = snapshot.data;
      if (runtime == null) {
        return const MaterialApp(
          home: Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          ),
        );
      }
      return DartitectScope<AppRuntime>(
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
                  home: TasksPage(session: runtime.tasks),
                ),
                SessionForcedLogout<ReferenceSessionDescription>() =>
                  _forcedLogoutShell(runtime),
                SessionTransitioning<ReferenceSessionDescription>() =>
                  const MaterialApp(
                    key: ValueKey<String>('transitioning-shell'),
                    home: Scaffold(
                      body: Center(child: CircularProgressIndicator.adaptive()),
                    ),
                  ),
                SessionAnonymous<ReferenceSessionDescription>() ||
                SessionSignedOut<ReferenceSessionDescription>() =>
                  const MaterialApp(
                    key: ValueKey<String>('signed-out-shell'),
                    home: Scaffold(
                      body: Center(child: Text('Session signed out')),
                    ),
                  ),
              },
            ),
      );
    },
  );

  Widget _forcedLogoutShell(AppRuntime runtime) {
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
    _acceptRuntime = false;
    _errorBinding?.dispose();
    final runtime = _runtime;
    if (runtime != null) unawaited(runtime.disposeAsync());
    super.dispose();
  }
}
