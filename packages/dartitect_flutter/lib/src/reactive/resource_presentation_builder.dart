// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'dart:async';

import 'package:dartitect/dartitect.dart' show ResourceSnapshot;
import 'package:flutter/widgets.dart';

import 'live_resource.dart';
import 'resource_lifecycle.dart';
import 'resource_presentation.dart';

/// Exhaustive rendering of a borrowed local-authority resource.
final class ResourcePresentationBuilder<T, F extends Object, M>
    extends StatefulWidget {
  /// Creates a complete waiting/content/empty/failure/crash renderer.
  const ResourcePresentationBuilder({
    required this.resource,
    required this.isEmpty,
    required this.waiting,
    required this.content,
    required this.empty,
    required this.failure,
    required this.crashed,
    this.retainLastKnownOnFailure = true,
    super.key,
  });

  /// Borrowed resource. The widget owns only its observation.
  final LiveResource<ResourceSnapshot<T, M>, F> resource;

  /// Consumer-owned empty-state classification.
  final bool Function(T value) isEmpty;

  /// Renders first-load waiting with an optional retained snapshot.
  final Widget Function(BuildContext, ResourcePresentationWaiting<T, F, M>)
  waiting;

  /// Renders a non-empty authoritative snapshot.
  final Widget Function(BuildContext, ResourcePresentationContent<T, F, M>)
  content;

  /// Renders an authoritative snapshot classified as empty.
  final Widget Function(BuildContext, ResourcePresentationEmpty<T, F, M>) empty;

  /// Renders an expected typed failure and optional retained snapshot.
  final Widget Function(
    BuildContext,
    ResourcePresentationFailure<T, F, M>,
    ResourcePresentationExpectedFailure<F>,
  )
  failure;

  /// Renders an unexpected crash with its original stack.
  final Widget Function(
    BuildContext,
    ResourcePresentationFailure<T, F, M>,
    ResourcePresentationCrash<F>,
  )
  crashed;

  /// Whether failure variants retain the last-known local snapshot.
  final bool retainLastKnownOnFailure;

  @override
  State<ResourcePresentationBuilder<T, F, M>> createState() =>
      _ResourcePresentationBuilderState<T, F, M>();
}

final class _ResourcePresentationBuilderState<T, F extends Object, M>
    extends State<ResourcePresentationBuilder<T, F, M>> {
  late ReactiveObservation<ResourceSnapshot<T, M>, F> _observation;
  var _tickerEnabled = false;

  @override
  void initState() {
    super.initState();
    _observation = _createObservation(widget.resource);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled == enabled) return;
    _tickerEnabled = enabled;
    unawaited(_observation.setTickerEnabled(enabled));
  }

  @override
  void didUpdateWidget(ResourcePresentationBuilder<T, F, M> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.resource, widget.resource)) return;
    final previous = _observation;
    previous.removeListener(_changed);
    unawaited(previous.close());
    _observation = _createObservation(widget.resource);
    unawaited(_observation.setTickerEnabled(_tickerEnabled));
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _observation.state.toPresentation(
      isEmpty: widget.isEmpty,
      retainLastKnownOnFailure: widget.retainLastKnownOnFailure,
    );
    return switch (presentation) {
      final ResourcePresentationWaiting<T, F, M> state => widget.waiting(
        context,
        state,
      ),
      final ResourcePresentationContent<T, F, M> state => widget.content(
        context,
        state,
      ),
      final ResourcePresentationEmpty<T, F, M> state => widget.empty(
        context,
        state,
      ),
      final ResourcePresentationFailure<T, F, M> state => switch (state.cause) {
        final ResourcePresentationExpectedFailure<F> cause => widget.failure(
          context,
          state,
          cause,
        ),
        final ResourcePresentationCrash<F> cause => widget.crashed(
          context,
          state,
          cause,
        ),
      },
    };
  }

  @override
  void dispose() {
    _observation.removeListener(_changed);
    unawaited(_observation.close());
    super.dispose();
  }

  ReactiveObservation<ResourceSnapshot<T, M>, F> _createObservation(
    LiveResource<ResourceSnapshot<T, M>, F> resource,
  ) {
    final observation = resource.observe(tickerEnabled: false);
    observation.addListener(_changed);
    return observation;
  }

  void _changed() {
    if (mounted && _observation.isActive) setState(() {});
  }
}
