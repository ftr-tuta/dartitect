// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

/// Builds application UI from a fully committed runtime root.
typedef ApplicationReadyBuilder<R> = Widget Function(
  BuildContext context,
  R runtime,
);

/// Builds retryable application bootstrap failure UI.
typedef ApplicationFailureBuilder<R> = Widget Function(
  BuildContext context,
  BootstrapFailed<R> failure,
  VoidCallback retry,
);

/// Owns application bootstrap, atomic publication, retry, and graph teardown.
final class ApplicationHost<R> extends StatefulWidget {
  /// Creates and owns one coordinator for this widget State.
  const ApplicationHost.create({
    required BootstrapCoordinator<R> Function() create,
    required this.loading,
    required this.failure,
    required this.ready,
    super.key,
  }) : _create = create,
       _value = null,
       _ownsCoordinator = true;

  /// Borrows [value] while still owning every graph this host boots.
  const ApplicationHost.value({
    required BootstrapCoordinator<R> value,
    required this.loading,
    required this.failure,
    required this.ready,
    super.key,
  }) : _value = value,
       _create = null,
       _ownsCoordinator = false;

  final BootstrapCoordinator<R> Function()? _create;
  final BootstrapCoordinator<R>? _value;
  final bool _ownsCoordinator;

  /// Loading subtree shown before a graph is published.
  final WidgetBuilder loading;

  /// Failure subtree with an idempotent retry callback.
  final ApplicationFailureBuilder<R> failure;

  /// Ready subtree receiving the atomically published root.
  final ApplicationReadyBuilder<R> ready;

  @override
  State<ApplicationHost<R>> createState() => _ApplicationHostState<R>();
}

final class _ApplicationHostState<R> extends State<ApplicationHost<R>> {
  late BootstrapCoordinator<R> _coordinator;
  late bool _ownsCoordinator;
  OwnedGraph<R>? _graph;
  BootstrapFailed<R>? _failure;
  CancellationSource? _attemptCancellation;
  var _attemptId = 0;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _adoptCoordinator();
    _start();
  }

  @override
  void didUpdateWidget(covariant ApplicationHost<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._ownsCoordinator && widget._ownsCoordinator) return;
    if (!oldWidget._ownsCoordinator &&
        !widget._ownsCoordinator &&
        identical(oldWidget._value, widget._value)) {
      return;
    }
    _attemptCancellation?.cancel('ApplicationHost coordinator replaced');
    if (_ownsCoordinator) _watch(_coordinator.disposeAsync());
    _adoptCoordinator();
    _start();
  }

  void _adoptCoordinator() {
    _ownsCoordinator = widget._ownsCoordinator;
    _coordinator = _ownsCoordinator ? widget._create!() : widget._value!;
  }

  void _start() {
    final attemptId = ++_attemptId;
    _attemptCancellation?.dispose();
    final cancellation = CancellationSource();
    _attemptCancellation = cancellation;
    setStateIfMounted(() {
      _loading = true;
      _failure = null;
    });
    unawaited(
      _coordinator.run(cancellation: cancellation.signal).then<void>((attempt) {
        if (!mounted || attemptId != _attemptId) {
          if (attempt is BootstrapSucceeded<R>) {
            _watch(attempt.graph.disposeAsync());
          }
          return;
        }
        switch (attempt) {
          case BootstrapSucceeded<R>(:final graph):
            final previous = _graph;
            setState(() {
              _graph = graph;
              _failure = null;
              _loading = false;
            });
            if (previous != null) _watch(previous.disposeAsync());
          case BootstrapFailed<R>():
            setState(() {
              _failure = attempt;
              _loading = false;
            });
        }
      }, onError: _report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final graph = _graph;
    if (graph != null && !_loading) return widget.ready(context, graph.root);
    final failure = _failure;
    if (failure != null) return widget.failure(context, failure, _start);
    return widget.loading(context);
  }

  @override
  void dispose() {
    _attemptId += 1;
    _attemptCancellation?.cancel('ApplicationHost disposed');
    _attemptCancellation?.dispose();
    _watch(_graph?.disposeAsync());
    if (_ownsCoordinator) _watch(_coordinator.disposeAsync());
    super.dispose();
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
  }

  void _watch(Future<void>? future) {
    if (future == null) return;
    unawaited(future.catchError(_report));
  }

  void _report(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dartitect_flutter',
        context: ErrorDescription('while operating an ApplicationHost'),
      ),
    );
  }
}
