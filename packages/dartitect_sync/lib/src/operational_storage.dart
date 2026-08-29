/// One structural dataset registration in an operational storage context.
///
/// This metadata never defines domain schema, semantic mapping, conflict
/// policy, or a retention executor.
final class OperationalDatasetRegistration {
  /// Creates and actively validates a registration.
  OperationalDatasetRegistration({
    required this.feature,
    required this.dataset,
    required this.partition,
    required this.codec,
    required this.retention,
    required this.transactionBoundary,
  }) {
    for (final entry in <String, String>{
      'feature': feature,
      'dataset': dataset,
      'partition': partition,
      'codec': codec,
      'transactionBoundary': transactionBoundary,
    }.entries) {
      if (!_identifier.hasMatch(entry.value)) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Must be an ASCII snake_case identifier.',
        );
      }
    }
    if (retention != 'indefinite' &&
        !RegExp(r'^P[1-9][0-9]*D$').hasMatch(retention)) {
      throw ArgumentError.value(
        retention,
        'retention',
        'Must be indefinite or an ISO day duration such as P30D.',
      );
    }
  }

  /// Consumer feature declaring the dataset.
  final String feature;

  /// Unique dataset key within the storage context.
  final String dataset;

  /// Consumer-defined partition strategy identifier.
  final String partition;

  /// Consumer-owned codec identifier and version.
  final String codec;

  /// Declarative retention value; no deletion is run automatically.
  final String retention;

  /// Consumer-owned atomic transaction boundary identifier.
  final String transactionBoundary;
}

/// One versioned operational-schema migration step.
final class OperationalStorageMigration {
  /// Creates a contiguous upgrade step.
  OperationalStorageMigration({
    required this.fromVersion,
    required this.toVersion,
    required this.id,
  }) {
    if (fromVersion < 1 || toVersion != fromVersion + 1) {
      throw ArgumentError(
        'Operational migrations must advance exactly one positive version.',
      );
    }
    if (!_identifier.hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'Must be an ASCII snake_case identifier.',
      );
    }
  }

  /// Existing operational schema version.
  final int fromVersion;

  /// Resulting operational schema version.
  final int toVersion;

  /// Stable migration identifier implemented by the provider adapter.
  final String id;
}

/// Validated manifest for one provider-backed operational storage context.
final class OperationalStorageContextManifest {
  /// Creates a closed manifest and validates dataset/migration uniqueness.
  OperationalStorageContextManifest({
    required this.context,
    required this.provider,
    required this.schemaVersion,
    required Iterable<OperationalDatasetRegistration> datasets,
    required Iterable<OperationalStorageMigration> migrations,
  }) : datasets = List<OperationalDatasetRegistration>.unmodifiable(datasets),
       migrations = List<OperationalStorageMigration>.unmodifiable(migrations) {
    if (!_identifier.hasMatch(context)) {
      throw ArgumentError.value(context, 'context', 'Invalid context name.');
    }
    if (!_identifier.hasMatch(provider)) {
      throw ArgumentError.value(provider, 'provider', 'Invalid provider name.');
    }
    if (schemaVersion < 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Must be positive.',
      );
    }
    final datasetNames = <String>{};
    for (final registration in this.datasets) {
      if (!datasetNames.add(registration.dataset)) {
        throw ArgumentError.value(
          registration.dataset,
          'datasets',
          'Duplicate dataset in one operational context.',
        );
      }
    }
    var expectedFrom = 1;
    for (final migration in this.migrations) {
      if (migration.fromVersion != expectedFrom) {
        throw ArgumentError.value(
          migration.id,
          'migrations',
          'Operational migrations must be contiguous from version 1.',
        );
      }
      expectedFrom = migration.toVersion;
    }
    if (expectedFrom != schemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Must equal the terminal operational migration version.',
      );
    }
  }

  /// Named storage context from config v2.
  final String context;

  /// Selected provider identifier.
  final String provider;

  /// Current SDK-owned operational schema version.
  final int schemaVersion;

  /// Feature registrations sharing this context.
  final List<OperationalDatasetRegistration> datasets;

  /// Ordered operational-only migrations.
  final List<OperationalStorageMigration> migrations;
}

final RegExp _identifier = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');
