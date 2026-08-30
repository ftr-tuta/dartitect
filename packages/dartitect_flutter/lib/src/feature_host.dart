// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

/// Stable phase in which feature publication failed.
enum FeatureHostFailurePhase {
  /// The child graph or one of its resources could not be constructed.
  graph,

  /// The consumer-owned ViewModel could not be constructed.
  viewModel,

  /// The ViewModel failed while starting before publication.
  start,
}

/// Failure retained by [FeatureHost] without erasing its original stack.
final class FeatureHostFailure {
  /// Creates failure evidence for one fenced host attempt.
  const FeatureHostFailure({
    required this.error,
    required this.stackTrace,
    required this.phase,
    required this.attemptId,
  });

  /// Original failure object.
  final Object error;

  /// Original stack trace.
  final StackTrace stackTrace;

  /// Construction phase that failed.
  final FeatureHostFailurePhase phase;

  /// Monotonic host-local attempt identity.
  final int attemptId;
}

/// Builds feature-local resources inside the host's transaction.
typedef FeatureGraphBuilder<Parent, Root> = FutureOr<Root> Function(
  Parent parent,
  ResourceTransaction transaction,
);

/// Creates a consumer-owned ViewModel from a committed child root.
typedef FeatureViewModelFactory<Root, ViewModel extends Object> =
    ViewModel Function(Root root);

/// Starts a ViewModel before its child graph is published to the widget tree.
typedef FeatureViewModelStarter<ViewModel extends Object> =
    FutureOr<void> Function(ViewModel viewModel);

/// Disposes a ViewModel before feature-local graph resources.
typedef FeatureViewModelDisposer<ViewModel extends Object> =
    FutureOr<void> Function(ViewModel viewModel);

/// Renders a ready feature from its concrete child root and ViewModel.
typedef FeatureReadyBuilder<Root, ViewModel extends Object> = Widget Function(
  BuildContext context,
  Root root,
  ViewModel viewModel,
);

/// Renders a retryable feature construction failure.
typedef FeatureFailureBuilder = Widget Function(
  BuildContext context,
  FeatureHostFailure failure,
  VoidCallback retry,
);

/// Material-neutral owner for one generated feature graph and ViewModel.
///
/// The host borrows [parent], transactionally creates one child graph, owns the
/// ViewModel last, awaits its optional start, and only then publishes ready.
/// Reverse transaction disposal therefore always closes the ViewModel before
/// any feature-local resource. Late attempts are fenced and disposed.
final class FeatureHost<Parent, Root, ViewModel extends Object>
    extends StatefulWidget {
  /// Creates a host for one application- or session-graph root.
  const FeatureHost({
    required this.parent,
    required this.createGraph,
    required this.createViewModel,
    required this.loading,
    required this.failure,
    required this.ready,
    this.generationKey,
    this.start,
    this.disposeViewModel,
    this.diagnostics,
    this.onDisposed,
    super.key,
  });

  /// Borrowed concrete application or session graph root.
  final Parent parent;

  /// Optional identity that fences a consumer factory or feature generation.
  final Object? generationKey;

  /// Builds feature-local resources in the host-owned transaction.
  final FeatureGraphBuilder<Parent, Root> createGraph;

  /// Creates consumer-owned presentation state.
  final FeatureViewModelFactory<Root, ViewModel> createViewModel;

  /// Optional readiness barrier invoked exactly once per created ViewModel.
  final FeatureViewModelStarter<ViewModel>? start;

  /// Explicit ViewModel cleanup, or automatic recognized cleanup when absent.
  final FeatureViewModelDisposer<ViewModel>? disposeViewModel;

  /// Optional payload-free host diagnostics.
  final DartitectDiagnosticSubject? diagnostics;

  /// Optional route-removal fence notified after owned graph teardown.
  final FutureOr<void> Function()? onDisposed;

  /// Loading subtree.
  final WidgetBuilder loading;

  /// Failure subtree with a fenced retry callback.
  final FeatureFailureBuilder failure;

  /// Ready subtree.
  final FeatureReadyBuilder<Root, ViewModel> ready;

  @override
  State<FeatureHost<Parent, Root, ViewModel>> createState() =>
      _FeatureHostState<Parent, Root, ViewModel>();
}

final class _FeatureHostState<Parent, Root, ViewModel extends Object>
    extends State<FeatureHost<Parent, Root, ViewModel>> {
  OwnedGraph<_FeaturePublication<Root, ViewModel>>? _graph;
  FeatureHostFailure? _failure;
  var _attemptId = 0;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    final diagnostics = widget.diagnostics;
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.host) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'FeatureHost requires a host diagnostic subject.',
      );
    }
    _start();
  }

  @override
  void didUpdateWidget(
    covariant FeatureHost<Parent, Root, ViewModel> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.parent, widget.parent) &&
        identical(oldWidget.generationKey, widget.generationKey)) {
      return;
    }
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final graph = _graph;
    if (graph != null && !_loading) {
      return widget.ready(context, graph.root.root, graph.root.viewModel);
    }
    final failure = _failure;
    if (failure != null) return widget.failure(context, failure, _start);
    return widget.loading(context);
  }

  void _start() {
    final attemptId = ++_attemptId;
    final previous = _graph;
    _graph = null;
    widget.diagnostics?.emit(
      DartitectDiagnosticPhase.started,
      generation: attemptId,
    );
    if (mounted) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }
    unawaited(_build(attemptId, previous));
  }

  Future<void> _build(
    int attemptId,
    OwnedGraph<_FeaturePublication<Root, ViewModel>>? previous,
  ) async {
    var phase = FeatureHostFailurePhase.graph;
    OwnedGraph<_FeaturePublication<Root, ViewModel>>? next;
    try {
      if (previous != null) await previous.disposeAsync();
      if (!mounted || attemptId != _attemptId) return;
      next = await ResourceTransaction.create((transaction) async {
        final root = await widget.createGraph(widget.parent, transaction);
        phase = FeatureHostFailurePhase.viewModel;
        final viewModel = widget.createViewModel(root);
        transaction.own<ViewModel>(
          viewModel,
          _disposeViewModel,
          label: 'feature.viewModel',
        );
        phase = FeatureHostFailurePhase.start;
        await widget.start?.call(viewModel);
        return _FeaturePublication(root, viewModel);
      }, label: 'FeatureHost.transaction');
      if (!mounted || attemptId != _attemptId) {
        await next.disposeAsync();
        return;
      }
      setState(() {
        _graph = next;
        _failure = null;
        _loading = false;
      });
      widget.diagnostics?.emit(
        DartitectDiagnosticPhase.succeeded,
        generation: attemptId,
      );
    } catch (error, stackTrace) {
      if (!mounted || attemptId != _attemptId) return;
      widget.diagnostics?.emit(
        DartitectDiagnosticPhase.failed,
        generation: attemptId,
      );
      setState(() {
        _failure = FeatureHostFailure(
          error: error,
          stackTrace: stackTrace,
          phase: phase,
          attemptId: attemptId,
        );
        _loading = false;
      });
    }
  }

  FutureOr<void> _disposeViewModel(ViewModel value) {
    final disposer = widget.disposeViewModel;
    if (disposer != null) return disposer(value);
    if (value is AsyncDisposable) return value.disposeAsync();
    if (value is Disposable) {
      value.dispose();
      return Future<void>.value();
    }
    if (value is ChangeNotifier) {
      value.dispose();
      return Future<void>.value();
    }
    return Future<void>.value();
  }

  @override
  void dispose() {
    _attemptId += 1;
    final graph = _graph;
    _graph = null;
    unawaited(_reporting(_disposeAndNotify(graph)));
    widget.diagnostics?.emit(
      DartitectDiagnosticPhase.disposed,
      generation: _attemptId,
    );
    super.dispose();
  }

  Future<void> _disposeAndNotify(
    OwnedGraph<_FeaturePublication<Root, ViewModel>>? graph,
  ) async {
    if (graph != null) await graph.disposeAsync();
    await widget.onDisposed?.call();
  }

  Future<void> _reporting(Future<void> future) async {
    try {
      await future;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dartitect_flutter',
          context: ErrorDescription('while disposing a FeatureHost graph'),
        ),
      );
    }
  }
}

final class _FeaturePublication<Root, ViewModel extends Object>(
  final Root root,
  final ViewModel viewModel,
);
