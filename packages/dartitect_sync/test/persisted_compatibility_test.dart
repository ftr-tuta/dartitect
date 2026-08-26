import 'dart:convert';
import 'dart:io';

import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:test/test.dart';

void main() {
  final fixture = _fixtureObject();

  test('consumer codec round-trips the frozen persisted v1 fixture', () {
    final persisted = _PersistedV1.decode(fixture);

    expect(persisted.outbox, hasLength(2));
    expect(persisted.outbox.first.syncState, EntitySyncState.pending);
    expect(persisted.outbox.last.syncState, EntitySyncState.uncertain);
    expect(persisted.checkpoints.last.hasCheckpoint, isTrue);
    expect(persisted.checkpoints.last.checkpoint, isNull);
    expect(persisted.journal.last.fact, SyncJournalFact.attemptCrashed);
    expect(persisted.incompleteAttempts.single.completedDatasetKeys, <String>[
      'profile',
    ]);
    expect(persisted.encode(), fixture);
  });

  test('consumer codec persists enum names and rejects schema drift', () {
    for (final schema in const <int>[0, 2]) {
      final changed = _copyFixture(fixture)..['schemaVersion'] = schema;
      expect(() => _PersistedV1.decode(changed), throwsFormatException);
    }

    final unknownEnum = _copyFixture(fixture);
    final outbox = unknownEnum['outbox']! as List<Object?>;
    (outbox.first! as Map<String, Object?>)['syncState'] = 'futureState';
    expect(() => _PersistedV1.decode(unknownEnum), throwsFormatException);

    final futureField = _copyFixture(fixture)..['futureField'] = true;
    expect(() => _PersistedV1.decode(futureField), throwsFormatException);
  });
}

final class _PersistedV1 {
  const _PersistedV1({
    required this.outbox,
    required this.checkpoints,
    required this.journal,
    required this.incompleteAttempts,
  });

  factory _PersistedV1.decode(Map<String, Object?> source) {
    _requireExactKeys(source, const <String>{
      'schemaVersion',
      'outbox',
      'checkpoints',
      'journal',
      'incompleteAttempts',
    });
    if (source['schemaVersion'] != 1) {
      throw const FormatException('Unsupported persisted schema.');
    }
    return _PersistedV1(
      outbox: _objects(source['outbox']).map(_decodeOutbox).toList(),
      checkpoints: _objects(source['checkpoints'])
          .map(_CheckpointFixture.decode)
          .toList(),
      journal: _objects(source['journal']).map(_decodeJournal).toList(),
      incompleteAttempts: _objects(source['incompleteAttempts'])
          .map(_decodeIncomplete)
          .toList(),
    );
  }

  final List<OutboxOperation<String, Map<String, Object?>>> outbox;
  final List<_CheckpointFixture> checkpoints;
  final List<SyncJournalEntry<String>> journal;
  final List<IncompleteSyncAttempt<String>> incompleteAttempts;

  Map<String, Object?> encode() => <String, Object?>{
    'schemaVersion': 1,
    'outbox': outbox
        .map(
          (operation) => <String, Object?>{
            'idempotencyKey': operation.idempotencyKey,
            'key': operation.key,
            'argument': operation.argument,
            'attempt': operation.attempt,
            'syncState': operation.syncState.name,
          },
        )
        .toList(),
    'checkpoints': checkpoints
        .map((checkpoint) => checkpoint.encode())
        .toList(),
    'journal': journal
        .map(
          (entry) => <String, Object?>{
            'attemptId': entry.attemptId,
            'sequence': entry.sequence,
            'timestamp': entry.timestamp.toIso8601String(),
            'fact': entry.fact.name,
            'datasetKey': entry.datasetKey,
            'hasDatasetKey': entry.hasDatasetKey,
          },
        )
        .toList(),
    'incompleteAttempts': incompleteAttempts
        .map(
          (attempt) => <String, Object?>{
            'attemptId': attempt.attemptId,
            'startedAt': attempt.startedAt.toIso8601String(),
            'completedDatasetKeys': attempt.completedDatasetKeys,
          },
        )
        .toList(),
  };
}

OutboxOperation<String, Map<String, Object?>> _decodeOutbox(
  Map<String, Object?> source,
) {
  _requireExactKeys(source, const <String>{
    'idempotencyKey',
    'key',
    'argument',
    'attempt',
    'syncState',
  });
  return OutboxOperation<String, Map<String, Object?>>(
    idempotencyKey: _string(source['idempotencyKey']),
    key: _string(source['key']),
    argument: _object(source['argument']),
    attempt: _integer(source['attempt']),
    syncState: _enumByName(EntitySyncState.values, source['syncState']),
  );
}

SyncJournalEntry<String> _decodeJournal(Map<String, Object?> source) {
  _requireExactKeys(source, const <String>{
    'attemptId',
    'sequence',
    'timestamp',
    'fact',
    'datasetKey',
    'hasDatasetKey',
  });
  final hasDatasetKey = _boolean(source['hasDatasetKey']);
  final datasetKey = source['datasetKey'];
  if (hasDatasetKey && datasetKey is! String ||
      !hasDatasetKey && datasetKey != null) {
    throw const FormatException('Invalid journal dataset key.');
  }
  return SyncJournalEntry<String>(
    attemptId: _string(source['attemptId']),
    sequence: _integer(source['sequence']),
    timestamp: _utc(source['timestamp']),
    fact: _enumByName(SyncJournalFact.values, source['fact']),
    datasetKey: datasetKey as String?,
    hasDatasetKey: hasDatasetKey,
  );
}

IncompleteSyncAttempt<String> _decodeIncomplete(Map<String, Object?> source) {
  _requireExactKeys(source, const <String>{
    'attemptId',
    'startedAt',
    'completedDatasetKeys',
  });
  final keys = source['completedDatasetKeys'];
  if (keys is! List<Object?> || keys.any((key) => key is! String)) {
    throw const FormatException('Invalid completed dataset keys.');
  }
  return IncompleteSyncAttempt<String>(
    attemptId: _string(source['attemptId']),
    startedAt: _utc(source['startedAt']),
    completedDatasetKeys: keys.cast<String>(),
  );
}

final class _CheckpointFixture {
  const _CheckpointFixture({
    required this.datasetKey,
    required this.hasCheckpoint,
    this.checkpoint,
  });

  factory _CheckpointFixture.decode(Map<String, Object?> source) {
    _requireExactKeys(source, const <String>{
      'datasetKey',
      'hasCheckpoint',
      'checkpoint',
    });
    final hasCheckpoint = _boolean(source['hasCheckpoint']);
    if (!hasCheckpoint && source['checkpoint'] != null) {
      throw const FormatException('Absent checkpoint must be null.');
    }
    final checkpoint = source['checkpoint'];
    if (checkpoint != null && checkpoint is! String) {
      throw const FormatException('Invalid checkpoint.');
    }
    return _CheckpointFixture(
      datasetKey: _string(source['datasetKey']),
      hasCheckpoint: hasCheckpoint,
      checkpoint: checkpoint as String?,
    );
  }

  final String datasetKey;
  final bool hasCheckpoint;
  final String? checkpoint;

  Map<String, Object?> encode() => <String, Object?>{
    'datasetKey': datasetKey,
    'hasCheckpoint': hasCheckpoint,
    'checkpoint': checkpoint,
  };
}

T _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) throw const FormatException('Invalid enum name.');
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown enum name: $name.');
}

DateTime _utc(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('Expected an ISO-8601 UTC timestamp.');
  }
  return parsed;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected a string.');
  return value;
}

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected an integer.');
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Expected a boolean.');
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?> ||
      value.any((item) => item is! Map<String, Object?>)) {
    throw const FormatException('Expected a list of objects.');
  }
  return value.cast<Map<String, Object?>>();
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an object.');
  }
  return value;
}

void _requireExactKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.keys.toSet().length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const FormatException('Persisted object fields changed.');
  }
}

Map<String, Object?> _fixtureObject() {
  for (final path in const <String>[
    'packages/dartitect_sync/test/fixtures/persisted_v1.json',
    'test/fixtures/persisted_v1.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return _object(jsonDecode(file.readAsStringSync()));
    }
  }
  throw StateError('Persisted compatibility fixture is missing.');
}

Map<String, Object?> _copyFixture(Map<String, Object?> source) =>
    _object(jsonDecode(jsonEncode(source)));
