// Best-effort rollback preserves the primary database configuration error.
// ignore_for_file: dartitect_empty_catch

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:drift/drift.dart';

import 'drift_instrumentation.dart';

/// Consumer-owned callback that creates a generated Drift database.
typedef OpenDriftDatabase<D extends GeneratedDatabase> = FutureOr<D> Function();

/// Explicitly owns or borrows a consumer-generated Drift database.
final class DriftDatabaseOwner<D extends GeneratedDatabase>
    implements AsyncDisposable {
  DriftDatabaseOwner._(
    this._database, {
    required bool ownsDatabase,
    required ResourceOwner resources,
  }) : _ownsDatabase = ownsDatabase,
       _resources = resources;

  final D _database;
  final bool _ownsDatabase;
  final ResourceOwner _resources;

  /// Opens, optionally configures, and owns a consumer-generated database.
  static Future<DriftDatabaseOwner<D>> create<D extends GeneratedDatabase>({
    required OpenDriftDatabase<D> openDatabase,
    FutureOr<void> Function(D database)? configure,
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    DriftInstrumentation? instrumentation,
  }) async {
    final resources = ResourceOwner(
      observer: observer,
      label: 'DriftDatabaseOwner',
    );
    try {
      final database = instrumentation == null
          ? await openDatabase()
          : await instrumentation.trace(
              DriftInstrumentedOperation.open,
              openDatabase,
            );
      resources.own(
        database,
        (value) => instrumentation == null
            ? value.close()
            : instrumentation.trace(
                DriftInstrumentedOperation.close,
                value.close,
              ),
        label: 'Drift database',
      );
      await configure?.call(database);
      return DriftDatabaseOwner<D>._(
        database,
        ownsDatabase: true,
        resources: resources,
      );
    } catch (error, stackTrace) {
      try {
        await resources.disposeAsync();
      } on Object {
        // Preserve the open/configuration failure as the primary cause.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Borrows [value] without taking responsibility for closing it.
  static DriftDatabaseOwner<D> value<D extends GeneratedDatabase>(
    D value, {
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
  }) => DriftDatabaseOwner<D>._(
    value,
    ownsDatabase: false,
    resources: ResourceOwner(observer: observer, label: 'DriftDatabaseOwner'),
  );

  /// Database access while this owner is active.
  D get database {
    if (_resources.isDisposing || _resources.isDisposed) {
      throw StateError('DriftDatabaseOwner has been disposed.');
    }
    return _database;
  }

  /// Whether this wrapper closes the database during disposal.
  bool get ownsDatabase => _ownsDatabase;

  /// Whether disposal has completed.
  bool get isDisposed => _resources.isDisposed;

  @override
  Future<void> disposeAsync() => _resources.disposeAsync();
}
