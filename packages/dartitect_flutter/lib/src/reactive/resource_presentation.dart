import 'package:dartitect/dartitect.dart';

import 'resource_lifecycle.dart';

/// Immutable presentation projection of one local-authority resource state.
sealed class ResourcePresentationState<T, F extends Object, M> {
  const ResourcePresentationState();

  /// Last-known authoritative local snapshot, when retained by policy.
  ResourceSnapshot<T, M>? get snapshot;
}

/// Presentation is waiting for the first authoritative local snapshot.
final class ResourcePresentationWaiting<T, F extends Object, M>
    extends ResourcePresentationState<T, F, M> {
  /// Creates a waiting projection, optionally retaining a prior snapshot.
  const ResourcePresentationWaiting({this.snapshot});

  @override
  final ResourceSnapshot<T, M>? snapshot;
}

/// Presentation has a non-empty authoritative local snapshot.
final class ResourcePresentationContent<T, F extends Object, M>
    extends ResourcePresentationState<T, F, M> {
  /// Creates a content projection.
  const ResourcePresentationContent(this.snapshot);

  @override
  final ResourceSnapshot<T, M> snapshot;
}

/// Presentation has an authoritative local snapshot classified as empty.
final class ResourcePresentationEmpty<T, F extends Object, M>
    extends ResourcePresentationState<T, F, M> {
  /// Creates an empty projection.
  const ResourcePresentationEmpty(this.snapshot);

  @override
  final ResourceSnapshot<T, M> snapshot;
}

/// Cause retained by a failure projection without erasing crash semantics.
sealed class ResourcePresentationFailureCause<F extends Object> {
  const ResourcePresentationFailureCause();
}

/// Expected typed failure returned by the local source.
final class ResourcePresentationExpectedFailure<F extends Object>
    extends ResourcePresentationFailureCause<F> {
  /// Creates an expected failure cause.
  const ResourcePresentationExpectedFailure(this.failure);

  /// Typed expected failure.
  final F failure;
}

/// Unexpected source crash preserving the original stack trace.
final class ResourcePresentationCrash<F extends Object>
    extends ResourcePresentationFailureCause<F> {
  /// Creates an unexpected crash cause.
  const ResourcePresentationCrash(this.error, this.stackTrace);

  /// Original unexpected error.
  final Object error;

  /// Original stack trace.
  final StackTrace stackTrace;
}

/// Presentation failed and may retain the last authoritative local snapshot.
final class ResourcePresentationFailure<T, F extends Object, M>
    extends ResourcePresentationState<T, F, M> {
  /// Creates a failure projection.
  const ResourcePresentationFailure(this.cause, {this.snapshot});

  /// Expected failure or unexpected crash, kept as distinct variants.
  final ResourcePresentationFailureCause<F> cause;

  @override
  final ResourceSnapshot<T, M>? snapshot;
}

/// Pure projection from a `LiveResource<ResourceSnapshot<T, M>, F>` state.
extension ResourceSnapshotPresentation<T, F extends Object, M>
    on ResourceDataState<ResourceSnapshot<T, M>, F> {
  /// Maps resource state to waiting/content/empty/failure without creating an
  /// owner, source, subscription, cache, or retry policy.
  ResourcePresentationState<T, F, M> toPresentation({
    required bool Function(T value) isEmpty,
    bool retainLastKnownOnFailure = true,
  }) => switch (this) {
    ResourceWaiting<ResourceSnapshot<T, M>, F>(
      :final lastData,
      :final hasData,
    ) =>
      ResourcePresentationWaiting<T, F, M>(snapshot: hasData ? lastData : null),
    ResourceReady<ResourceSnapshot<T, M>, F>(:final data) =>
      isEmpty(data.value)
          ? ResourcePresentationEmpty<T, F, M>(data)
          : ResourcePresentationContent<T, F, M>(data),
    ResourceFailed<ResourceSnapshot<T, M>, F>(
      :final failure,
      :final lastData,
      :final hasData,
    ) =>
      ResourcePresentationFailure<T, F, M>(
        ResourcePresentationExpectedFailure<F>(failure),
        snapshot: retainLastKnownOnFailure && hasData ? lastData : null,
      ),
    ResourceCrashed<ResourceSnapshot<T, M>, F>(
      :final error,
      :final stackTrace,
      :final lastData,
      :final hasData,
    ) =>
      ResourcePresentationFailure<T, F, M>(
        ResourcePresentationCrash<F>(error, stackTrace),
        snapshot: retainLastKnownOnFailure && hasData ? lastData : null,
      ),
  };
}
