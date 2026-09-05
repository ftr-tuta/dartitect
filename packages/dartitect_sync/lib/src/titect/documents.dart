part of 'codec.dart';

/// One immutable, validated `titect-sync/1` document.
///
/// Create values through [TitectSyncCodec.fromPayload] or its bounded readers.
/// Numeric protocol fields use [BigInt]; arbitrary JSON numbers remain
/// [TitectNumber]. No implicit narrowing or JSON numeric rounding occurs.
sealed class TitectSyncDocument {
  TitectSyncDocument._(this.kind, this._payload);

  /// Closed wire kind.
  final String kind;
  final Map<String, Object?> _payload;
}

/// A snapshot or delta page; data is committed before confirming its cursor.
sealed class TitectPage extends TitectSyncDocument {
  TitectPage._(super.kind, super.payload) : super._();

  /// Opaque dataset identity.
  String get datasetId;

  /// Exact server generation.
  BigInt get generation;

  /// Items supplied by the server, with consumer-owned payload schemas.
  List<TitectUpsert> get upserts;

  /// Opaque continuation, or null at the end of this traversal.
  String? get nextCursor;

  /// Declared integrity metadata; the pinned profile validates shape/count only.
  TitectIntegrity get integrity;
}

/// Validated session wire value.
final class TitectSession extends TitectSyncDocument {
  TitectSession._(Map<String, Object?> payload) : super._('session', payload);

  /// Validated `session_id` field.
  String get sessionId => _payload['session_id'] as String;

  /// Validated `created_at` field.
  DateTime get createdAt => _timestamp(_payload['created_at']);

  /// Validated `expires_at` field.
  DateTime get expiresAt => _timestamp(_payload['expires_at']);
}

/// Validated dataset wire value.
final class TitectDatasetDescriptor extends TitectSyncDocument {
  TitectDatasetDescriptor._(Map<String, Object?> payload)
    : super._('dataset', payload);

  /// Validated `dataset_id` field.
  String get datasetId => _payload['dataset_id'] as String;

  /// Validated `generation` field.
  BigInt get generation =>
      (_payload['generation'] as TitectNumber).toBigIntExact();

  /// Validated `modes` field.
  List<String> get modes => List<String>.unmodifiable(
    (_payload['modes'] as List<Object?>).map((item) => item! as String),
  );
}

/// Validated bootstrap_request wire value.
final class TitectBootstrapRequest extends TitectSyncDocument {
  TitectBootstrapRequest._(Map<String, Object?> payload)
    : super._('bootstrap_request', payload);

  /// Validated `client_id` field.
  String get clientId => _payload['client_id'] as String;

  /// Validated `dataset_ids` field.
  List<String> get datasetIds => List<String>.unmodifiable(
    (_payload['dataset_ids'] as List<Object?>).map((item) => item! as String),
  );

  /// Validated `capabilities` field.
  List<String> get capabilities => List<String>.unmodifiable(
    (_payload['capabilities'] as List<Object?>).map((item) => item! as String),
  );
}

/// Validated bootstrap_response wire value.
final class TitectBootstrapResponse extends TitectSyncDocument {
  TitectBootstrapResponse._(Map<String, Object?> payload)
    : super._('bootstrap_response', payload);

  /// Validated `session` field.
  TitectSession get session =>
      TitectSession._(_payload['session']! as Map<String, Object?>);

  /// Validated `datasets` field.
  List<TitectDatasetDescriptor> get datasets =>
      List<TitectDatasetDescriptor>.unmodifiable(
        (_payload['datasets'] as List<Object?>).map(
          (item) => TitectDatasetDescriptor._(item! as Map<String, Object?>),
        ),
      );

  /// Validated `limits` field.
  TitectSyncLimits get limits =>
      TitectSyncLimits._(_payload['limits']! as Map<String, Object?>);
}

/// Validated snapshot wire value.
final class TitectSnapshotPage extends TitectPage {
  TitectSnapshotPage._(Map<String, Object?> payload)
    : super._('snapshot', payload);

  /// Validated `dataset_id` field.
  @override
  String get datasetId => _payload['dataset_id'] as String;

  /// Validated `generation` field.
  @override
  BigInt get generation =>
      (_payload['generation'] as TitectNumber).toBigIntExact();

  /// Validated `upserts` field.
  @override
  List<TitectUpsert> get upserts => List<TitectUpsert>.unmodifiable(
    (_payload['upserts'] as List<Object?>).map(
      (item) => TitectUpsert._(item! as Map<String, Object?>),
    ),
  );

  /// Validated `next_cursor` field.
  @override
  String? get nextCursor => _payload['next_cursor'] as String?;

  /// Validated `integrity` field.
  @override
  TitectIntegrity get integrity =>
      TitectIntegrity._(_payload['integrity']! as Map<String, Object?>);
}

/// Validated delta wire value.
final class TitectDeltaPage extends TitectPage {
  TitectDeltaPage._(Map<String, Object?> payload) : super._('delta', payload);

  /// Validated `dataset_id` field.
  @override
  String get datasetId => _payload['dataset_id'] as String;

  /// Validated `generation` field.
  @override
  BigInt get generation =>
      (_payload['generation'] as TitectNumber).toBigIntExact();

  /// Validated `upserts` field.
  @override
  List<TitectUpsert> get upserts => List<TitectUpsert>.unmodifiable(
    (_payload['upserts'] as List<Object?>).map(
      (item) => TitectUpsert._(item! as Map<String, Object?>),
    ),
  );

  /// Validated `tombstones` field.
  List<TitectTombstone> get tombstones => List<TitectTombstone>.unmodifiable(
    (_payload['tombstones'] as List<Object?>).map(
      (item) => TitectTombstone._(item! as Map<String, Object?>),
    ),
  );

  /// Validated `next_cursor` field.
  @override
  String? get nextCursor => _payload['next_cursor'] as String?;

  /// Validated `integrity` field.
  @override
  TitectIntegrity get integrity =>
      TitectIntegrity._(_payload['integrity']! as Map<String, Object?>);
}

/// Validated reset_required wire value.
final class TitectResetRequired extends TitectSyncDocument {
  TitectResetRequired._(Map<String, Object?> payload)
    : super._('reset_required', payload);

  /// Validated `dataset_id` field.
  String get datasetId => _payload['dataset_id'] as String;

  /// Validated `generation` field.
  BigInt get generation =>
      (_payload['generation'] as TitectNumber).toBigIntExact();

  /// Validated `reason` field.
  String get reason => _payload['reason'] as String;
}

/// Validated generation_mismatch wire value.
final class TitectGenerationMismatch extends TitectSyncDocument {
  TitectGenerationMismatch._(Map<String, Object?> payload)
    : super._('generation_mismatch', payload);

  /// Validated `dataset_id` field.
  String get datasetId => _payload['dataset_id'] as String;

  /// Validated `expected` field.
  BigInt get expected => (_payload['expected'] as TitectNumber).toBigIntExact();

  /// Validated `actual` field.
  BigInt get actual => (_payload['actual'] as TitectNumber).toBigIntExact();
}

/// Validated readiness wire value.
final class TitectReadiness extends TitectSyncDocument {
  TitectReadiness._(Map<String, Object?> payload)
    : super._('readiness', payload);

  /// Validated `ready` field.
  bool get ready => _payload['ready'] as bool;

  /// Validated `checked_at` field.
  DateTime get checkedAt => _timestamp(_payload['checked_at']);

  /// Validated `reason` field.
  String? get reason => _payload['reason'] as String?;

  /// Validated `retry_after_ms` field.
  BigInt? get retryAfterMs =>
      (_payload['retry_after_ms'] as TitectNumber?)?.toBigIntExact();
}

/// Validated mutation_outcome wire value.
final class TitectMutationOutcome extends TitectSyncDocument {
  TitectMutationOutcome._(Map<String, Object?> payload)
    : super._('mutation_outcome', payload);

  /// Validated `mutation_id` field.
  String get mutationId => _payload['mutation_id'] as String;

  /// Validated `state` field.
  String get state => _payload['state'] as String;

  /// Validated `revision` field.
  BigInt? get revision =>
      (_payload['revision'] as TitectNumber?)?.toBigIntExact();

  /// Validated `receipt_id` field.
  String? get receiptId => _payload['receipt_id'] as String?;

  /// Validated `reason` field.
  String? get reason => _payload['reason'] as String?;
}

/// Validated mutation_outcomes wire value.
final class TitectMutationOutcomes extends TitectSyncDocument {
  TitectMutationOutcomes._(Map<String, Object?> payload)
    : super._('mutation_outcomes', payload);

  /// Validated `dataset_id` field.
  String get datasetId => _payload['dataset_id'] as String;

  /// Validated `generation` field.
  BigInt get generation =>
      (_payload['generation'] as TitectNumber).toBigIntExact();

  /// Validated `outcomes` field.
  List<TitectMutationOutcome> get outcomes =>
      List<TitectMutationOutcome>.unmodifiable(
        (_payload['outcomes'] as List<Object?>).map(
          (item) => TitectMutationOutcome._(item! as Map<String, Object?>),
        ),
      );
}

/// Validated Upsert wire value.
final class TitectUpsert {
  TitectUpsert._(this._payload);
  final Map<String, Object?> _payload;

  /// Validated `item_id` field.
  String get itemId => _payload['item_id'] as String;

  /// Validated `revision` field.
  BigInt get revision => (_payload['revision'] as TitectNumber).toBigIntExact();

  /// Validated `value` field.
  Object? get value => _payload['value'];
}

/// Validated Tombstone wire value.
final class TitectTombstone {
  TitectTombstone._(this._payload);
  final Map<String, Object?> _payload;

  /// Validated `item_id` field.
  String get itemId => _payload['item_id'] as String;

  /// Validated `revision` field.
  BigInt get revision => (_payload['revision'] as TitectNumber).toBigIntExact();

  /// Validated `deleted_at` field.
  DateTime get deletedAt => _timestamp(_payload['deleted_at']);
}

/// Validated Integrity wire value.
final class TitectIntegrity {
  TitectIntegrity._(this._payload);
  final Map<String, Object?> _payload;

  /// Validated `algorithm` field.
  String get algorithm => _payload['algorithm'] as String;

  /// Validated `digest` field.
  String get digest => _payload['digest'] as String;

  /// Validated `item_count` field.
  BigInt get itemCount =>
      (_payload['item_count'] as TitectNumber).toBigIntExact();
}

/// Validated SyncLimits wire value.
final class TitectSyncLimits {
  TitectSyncLimits._(this._payload);
  final Map<String, Object?> _payload;

  /// Validated `max_document_bytes` field.
  BigInt get maxDocumentBytes =>
      (_payload['max_document_bytes'] as TitectNumber).toBigIntExact();

  /// Validated `max_datasets` field.
  BigInt get maxDatasets =>
      (_payload['max_datasets'] as TitectNumber).toBigIntExact();

  /// Validated `max_items_per_page` field.
  BigInt get maxItemsPerPage =>
      (_payload['max_items_per_page'] as TitectNumber).toBigIntExact();

  /// Validated `max_mutations` field.
  BigInt get maxMutations =>
      (_payload['max_mutations'] as TitectNumber).toBigIntExact();

  /// Validated `max_opaque_id_bytes` field.
  BigInt get maxOpaqueIdBytes =>
      (_payload['max_opaque_id_bytes'] as TitectNumber).toBigIntExact();

  /// Validated `max_capabilities` field.
  BigInt get maxCapabilities =>
      (_payload['max_capabilities'] as TitectNumber).toBigIntExact();
}
