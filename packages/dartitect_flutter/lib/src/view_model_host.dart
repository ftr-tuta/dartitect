// This library is itself the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

/// Builds a widget with a route-owned or borrowed view model.
typedef ViewModelWidgetBuilder<T extends Object> = Widget Function(
  BuildContext context,
  T viewModel,
);

/// Starts a newly created view model without becoming a readiness barrier.
typedef ViewModelStarter<T extends Object> = FutureOr<void> Function(
  T viewModel,
);

/// Releases an owned view model.
typedef ViewModelDisposer<T extends Object> = FutureOr<void> Function(
  T viewModel,
);

/// Rebinds hot-reload-safe definitions without replacing owned state.
typedef ViewModelReassembler<T extends Object> = void Function(T viewModel);

/// Binds a view model to Flutter's existing [State] lifecycle.
///
/// [ViewModelHost.create] owns, starts, and releases the value it creates.
/// [ViewModelHost.value] borrows its value and never starts or releases
/// it. The host deliberately does not listen to the view model; put
/// `ListenableBuilder` or `ValueListenableBuilder` near the fragment that needs
/// to rebuild.
final class ViewModelHost<T extends Object> extends StatefulWidget {
  /// Creates and owns one view model for this State instance.
  const ViewModelHost.create({
    required T Function() create,
    required this.builder,
    this.start,
    this.dispose,
    this.onReassemble,
    super.key,
  }) : _create = create,
       _value = null,
       _ownsValue = true;

  /// Borrows [value] without initializing or disposing it.
  const ViewModelHost.value({
    required T value,
    required this.builder,
    this.onReassemble,
    super.key,
  }) : _value = value,
       _create = null,
       start = null,
       dispose = null,
       _ownsValue = false;

  final T Function()? _create;
  final T? _value;
  final bool _ownsValue;

  /// Builds the subtree. The host itself is not reactive to [T].
  final ViewModelWidgetBuilder<T> builder;

  /// Called once for a value created by [ViewModelHost.create].
  final ViewModelStarter<T>? start;

  /// Custom cleanup for an owned value.
  ///
  /// When omitted, [AsyncDisposable], [Disposable], and [ChangeNotifier] are
  /// recognized in that order.
  final ViewModelDisposer<T>? dispose;

  /// Optional hot-reload callback for rebinding compatible definitions.
  ///
  /// The existing value remains authoritative. Incompatible definitions should
  /// fail diagnostically instead of replacing owner-local state silently.
  final ViewModelReassembler<T>? onReassemble;

  @override
  State<ViewModelHost<T>> createState() => _ViewModelHostState<T>();
}

final class _ViewModelHostState<T extends Object>
    extends State<ViewModelHost<T>> {
  late T _viewModel;
  late bool _ownsValue;
  ViewModelDisposer<T>? _ownedDisposer;

  @override
  void initState() {
    super.initState();
    _adoptWidgetValue(startOwned: true);
  }

  @override
  void didUpdateWidget(covariant ViewModelHost<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._ownsValue && widget._ownsValue) {
      return;
    }
    if (!oldWidget._ownsValue && !widget._ownsValue) {
      _viewModel = widget._value as T;
      return;
    }

    if (_ownsValue) {
      _release(_viewModel, _ownedDisposer);
    }
    _adoptWidgetValue(startOwned: widget._ownsValue);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _viewModel);

  @override
  void reassemble() {
    super.reassemble();
    final reassemble = widget.onReassemble;
    if (reassemble == null) return;
    try {
      reassemble(_viewModel);
    } catch (error, stackTrace) {
      _reportLifecycleError(
        error,
        stackTrace,
        context: 'while reassembling a ViewModelHost value',
      );
    }
  }

  @override
  void dispose() {
    if (_ownsValue) {
      _release(_viewModel, _ownedDisposer);
    }
    super.dispose();
  }

  void _adoptWidgetValue({required bool startOwned}) {
    _ownsValue = widget._ownsValue;
    _viewModel = _ownsValue ? widget._create!() : widget._value as T;
    _ownedDisposer = _ownsValue ? widget.dispose : null;
    if (startOwned) {
      try {
        _start(_viewModel);
      } catch (_) {
        _release(_viewModel, _ownedDisposer);
        _ownsValue = false;
        rethrow;
      }
    }
  }

  void _start(T value) {
    final start = widget.start;
    if (start == null) {
      return;
    }
    final FutureOr<void> result;
    try {
      result = start(value);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (result is Future<void>) {
      unawaited(
        result.catchError((Object error, StackTrace stackTrace) {
          _reportLifecycleError(
            error,
            stackTrace,
            context: 'while asynchronously starting a ViewModelHost value',
          );
        }),
      );
    }
  }

  void _release(T value, ViewModelDisposer<T>? disposer) {
    try {
      if (disposer != null) {
        _watchDisposal(disposer(value));
      } else if (value is AsyncDisposable) {
        _watchDisposal(value.disposeAsync());
      } else if (value is Disposable) {
        value.dispose();
      } else if (value is ChangeNotifier) {
        value.dispose();
      }
    } catch (error, stackTrace) {
      _reportLifecycleError(
        error,
        stackTrace,
        context: 'while disposing a ViewModelHost value',
      );
    }
  }

  void _watchDisposal(FutureOr<void> result) {
    if (result is Future<void>) {
      unawaited(
        result.catchError((Object error, StackTrace stackTrace) {
          _reportLifecycleError(
            error,
            stackTrace,
            context: 'while asynchronously disposing a ViewModelHost value',
          );
        }),
      );
    }
  }

  void _reportLifecycleError(
    Object error,
    StackTrace stackTrace, {
    required String context,
  }) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dartitect_flutter',
        context: ErrorDescription(context),
      ),
    );
  }
}
