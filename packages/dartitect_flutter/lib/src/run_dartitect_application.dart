// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

import 'application_host.dart';
import 'first_frame_gate.dart';

/// Starts a basic Flutter application through Dartitect's owned paved road.
///
/// The helper initializes the binding, defers the first frame, installs an
/// [ApplicationHost], publishes only a committed graph, and delegates graph
/// teardown to that host. It installs no container or service locator.
void runDartitectApplication<R>({
  required BootstrapCoordinator<R> Function() create,
  required Widget Function(R runtime) application,
  Widget? loading,
  Widget Function(BootstrapFailed<R> failure, VoidCallback retry)? failure,
  DartitectDiagnosticSubject? diagnostics,
}) {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final firstFrame = FirstFrameGate.defer(binding);
  try {
    runApp(
      _DartitectApplication<R>(
        firstFrame: firstFrame,
        create: create,
        diagnostics: diagnostics,
        loading: loading,
        failure: failure,
        application: application,
      ),
    );
  } catch (_) {
    firstFrame.release();
    rethrow;
  }
}

final class _DartitectApplication<R> extends StatefulWidget {
  const _DartitectApplication({
    required this.firstFrame,
    required this.create,
    required this.application,
    required this.loading,
    required this.failure,
    required this.diagnostics,
  });

  final FirstFrameGateOwner firstFrame;
  final BootstrapCoordinator<R> Function() create;
  final Widget Function(R runtime) application;
  final Widget? loading;
  final Widget Function(BootstrapFailed<R> failure, VoidCallback retry)?
  failure;
  final DartitectDiagnosticSubject? diagnostics;

  @override
  State<_DartitectApplication<R>> createState() =>
      _DartitectApplicationState<R>();
}

final class _DartitectApplicationState<R>
    extends State<_DartitectApplication<R>> {
  @override
  Widget build(BuildContext context) => ApplicationHost<R>.create(
    create: widget.create,
    diagnostics: widget.diagnostics,
    loading: (_) => widget.loading ?? const SizedBox.shrink(),
    failure: (_, attempt, retry) {
      widget.firstFrame.release();
      return widget.failure?.call(attempt, retry) ??
          _BootstrapFailure(retry: retry);
    },
    ready: (_, runtime) {
      widget.firstFrame.release();
      return widget.application(runtime);
    },
  );

  @override
  void dispose() {
    widget.firstFrame.dispose();
    super.dispose();
  }
}

final class _BootstrapFailure extends StatelessWidget {
  const _BootstrapFailure({required this.retry});

  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: Semantics(
        button: true,
        label: 'Retry application startup',
        child: GestureDetector(
          onTap: retry,
          child: const Text('Application startup failed. Tap to retry.'),
        ),
      ),
    ),
  );
}
