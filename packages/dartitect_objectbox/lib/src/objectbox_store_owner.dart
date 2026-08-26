// Best-effort rollback preserves the primary Store acquisition/configuration error.
// ignore_for_file: dartitect_empty_catch

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:objectbox/objectbox.dart';

import 'objectbox_instrumentation.dart';
import 'objectbox_observation_owner.dart';

/// Callback implemented by the consumer's generated ObjectBox composition.
typedef OpenObjectBoxStore = FutureOr<Store> Function(String? directoryPath);

/// Explicitly owns or borrows a real ObjectBox [Store].
///
/// Observations registered through [observations] are always owned by this
/// wrapper and drain before an owned Store closes.
final class ObjectBoxStoreOwner implements AsyncDisposable {
  ObjectBoxStoreOwner._(
    this._store, {
    required bool ownsStore,
    required ObjectBoxObservationOwner observations,
    required ResourceOwner resources,
  }) : _ownsStore = ownsStore,
       observations = observations,
       _resources = resources;

  final Store _store;
  final bool _ownsStore;
  final ResourceOwner _resources;

  /// Registry whose resources close before the Store.
  final ObjectBoxObservationOwner observations;

  /// Opens and owns a Store through consumer-generated [openStore].
  static Future<ObjectBoxStoreOwner> create({
    required OpenObjectBoxStore openStore,
    String? directoryPath,
    FutureOr<void> Function(
      Store store,
      ObjectBoxObservationOwner observations,
    )?
    configure,
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    ObjectBoxInstrumentation? instrumentation,
  }) async {
    final resources = ResourceOwner(
      observer: observer,
      label: 'ObjectBoxStoreOwner',
    );
    final observations = ObjectBoxObservationOwner(observer: observer);
    try {
      final store = instrumentation == null
          ? await openStore(directoryPath)
          : await instrumentation.traceOpen(() => openStore(directoryPath));
      resources
        ..own(
          store,
          (value) => instrumentation == null
              ? value.close()
              : instrumentation.traceClose(value.close),
          label: 'ObjectBox Store',
        )
        ..own(
          observations,
          (value) => value.disposeAsync(),
          label: 'ObjectBox observations',
        );
      await configure?.call(store, observations);
      return ObjectBoxStoreOwner._(
        store,
        ownsStore: true,
        observations: observations,
        resources: resources,
      );
    } catch (error, stackTrace) {
      try {
        await resources.disposeAsync();
      } on Object {
        // Preserve the acquisition/configuration failure as the first cause.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Borrows [value]. Observations are still owned and drained on disposal.
  static ObjectBoxStoreOwner value(
    Store value, {
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
  }) {
    final resources = ResourceOwner(
      observer: observer,
      label: 'ObjectBoxStoreOwner',
    );
    final observations = ObjectBoxObservationOwner(observer: observer);
    resources.own(
      observations,
      (owned) => owned.disposeAsync(),
      label: 'ObjectBox observations',
    );
    return ObjectBoxStoreOwner._(
      value,
      ownsStore: false,
      observations: observations,
      resources: resources,
    );
  }

  /// Creates an isolated temporary directory, opens a Store there, and owns
  /// both. Cleanup never deletes a path it did not create and validate.
  static Future<ObjectBoxStoreOwner> temporary({
    required OpenObjectBoxStore openStore,
    Directory? parent,
    FutureOr<void> Function(
      Store store,
      ObjectBoxObservationOwner observations,
    )?
    configure,
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    ObjectBoxInstrumentation? instrumentation,
  }) async {
    final temporary = await (parent ?? Directory.systemTemp).createTemp(
      'dartitect-objectbox-',
    );
    final resources = ResourceOwner(
      observer: observer,
      label: 'TemporaryObjectBoxStore',
    );
    final observations = ObjectBoxObservationOwner(observer: observer);
    try {
      resources.own(
        temporary,
        _deleteOwnedTemporaryDirectory,
        label: 'ObjectBox temporary directory',
      );
      final store = instrumentation == null
          ? await openStore(temporary.path)
          : await instrumentation.traceOpen(() => openStore(temporary.path));
      resources
        ..own(
          store,
          (value) => instrumentation == null
              ? value.close()
              : instrumentation.traceClose(value.close),
          label: 'ObjectBox Store',
        )
        ..own(
          observations,
          (value) => value.disposeAsync(),
          label: 'ObjectBox observations',
        );
      await configure?.call(store, observations);
      return ObjectBoxStoreOwner._(
        store,
        ownsStore: true,
        observations: observations,
        resources: resources,
      );
    } catch (error, stackTrace) {
      try {
        await resources.disposeAsync();
      } on Object {
        // Preserve the open/configuration error.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Store access while this owner is active.
  Store get store {
    if (_resources.isDisposing || _resources.isDisposed) {
      throw StateError('ObjectBoxStoreOwner has been disposed.');
    }
    return _store;
  }

  /// Whether the Store itself is owned by this wrapper.
  bool get ownsStore => _ownsStore;

  /// Whether observations and any owned Store have been released.
  bool get isDisposed => _resources.isDisposed;

  @override
  Future<void> disposeAsync() => _resources.disposeAsync();

  static Future<void> _deleteOwnedTemporaryDirectory(
    Directory directory,
  ) async {
    final name = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (!name.startsWith('dartitect-objectbox-')) {
      throw StateError(
        'Refusing to delete an unrecognized temporary path: ${directory.path}',
      );
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

/// Returns ObjectBox's isolate-transferable reference bytes.
///
/// The receiving isolate must create its own Store wrapper with the consumer's
/// generated model and close it in `finally`; no Store object crosses isolates.
ByteData objectBoxStoreReference(Store store) => store.reference;
