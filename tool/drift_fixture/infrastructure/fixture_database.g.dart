// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fixture_database.dart';

// ignore_for_file: type=lint
class $FixtureItemsTable extends FixtureItems
    with TableInfo<$FixtureItemsTable, FixtureItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixtureItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, value, revision];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixture_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixtureItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FixtureItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixtureItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $FixtureItemsTable createAlias(String alias) {
    return $FixtureItemsTable(attachedDatabase, alias);
  }
}

class FixtureItem extends DataClass implements Insertable<FixtureItem> {
  final String id;
  final String value;
  final int revision;
  const FixtureItem({
    required this.id,
    required this.value,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['value'] = Variable<String>(value);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  FixtureItemsCompanion toCompanion(bool nullToAbsent) {
    return FixtureItemsCompanion(
      id: Value(id),
      value: Value(value),
      revision: Value(revision),
    );
  }

  factory FixtureItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureItem(
      id: serializer.fromJson<String>(json['id']),
      value: serializer.fromJson<String>(json['value']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'value': serializer.toJson<String>(value),
      'revision': serializer.toJson<int>(revision),
    };
  }

  FixtureItem copyWith({String? id, String? value, int? revision}) =>
      FixtureItem(
        id: id ?? this.id,
        value: value ?? this.value,
        revision: revision ?? this.revision,
      );
  FixtureItem copyWithCompanion(FixtureItemsCompanion data) {
    return FixtureItem(
      id: data.id.present ? data.id.value : this.id,
      value: data.value.present ? data.value.value : this.value,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureItem(')
          ..write('id: $id, ')
          ..write('value: $value, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, value, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureItem &&
          other.id == this.id &&
          other.value == this.value &&
          other.revision == this.revision);
}

class FixtureItemsCompanion extends UpdateCompanion<FixtureItem> {
  final Value<String> id;
  final Value<String> value;
  final Value<int> revision;
  final Value<int> rowid;
  const FixtureItemsCompanion({
    this.id = const Value.absent(),
    this.value = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixtureItemsCompanion.insert({
    required String id,
    required String value,
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       value = Value(value);
  static Insertable<FixtureItem> custom({
    Expression<String>? id,
    Expression<String>? value,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (value != null) 'value': value,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixtureItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? value,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return FixtureItemsCompanion(
      id: id ?? this.id,
      value: value ?? this.value,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixtureItemsCompanion(')
          ..write('id: $id, ')
          ..write('value: $value, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FixtureOutboxTable extends FixtureOutbox
    with TableInfo<$FixtureOutboxTable, FixtureOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixtureOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixture_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixtureOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FixtureOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixtureOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $FixtureOutboxTable createAlias(String alias) {
    return $FixtureOutboxTable(attachedDatabase, alias);
  }
}

class FixtureOutboxData extends DataClass
    implements Insertable<FixtureOutboxData> {
  final int id;
  final String payload;
  const FixtureOutboxData({required this.id, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  FixtureOutboxCompanion toCompanion(bool nullToAbsent) {
    return FixtureOutboxCompanion(id: Value(id), payload: Value(payload));
  }

  factory FixtureOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureOutboxData(
      id: serializer.fromJson<int>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'payload': serializer.toJson<String>(payload),
    };
  }

  FixtureOutboxData copyWith({int? id, String? payload}) =>
      FixtureOutboxData(id: id ?? this.id, payload: payload ?? this.payload);
  FixtureOutboxData copyWithCompanion(FixtureOutboxCompanion data) {
    return FixtureOutboxData(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureOutboxData(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureOutboxData &&
          other.id == this.id &&
          other.payload == this.payload);
}

class FixtureOutboxCompanion extends UpdateCompanion<FixtureOutboxData> {
  final Value<int> id;
  final Value<String> payload;
  const FixtureOutboxCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
  });
  FixtureOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String payload,
  }) : payload = Value(payload);
  static Insertable<FixtureOutboxData> custom({
    Expression<int>? id,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
    });
  }

  FixtureOutboxCompanion copyWith({Value<int>? id, Value<String>? payload}) {
    return FixtureOutboxCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixtureOutboxCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class $FixtureCheckpointsTable extends FixtureCheckpoints
    with TableInfo<$FixtureCheckpointsTable, FixtureCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixtureCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkpointMeta = const VerificationMeta(
    'checkpoint',
  );
  @override
  late final GeneratedColumn<String> checkpoint = GeneratedColumn<String>(
    'checkpoint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fencingTokenMeta = const VerificationMeta(
    'fencingToken',
  );
  @override
  late final GeneratedColumn<int> fencingToken = GeneratedColumn<int>(
    'fencing_token',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, checkpoint, fencingToken];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixture_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixtureCheckpoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('checkpoint')) {
      context.handle(
        _checkpointMeta,
        checkpoint.isAcceptableOrUnknown(data['checkpoint']!, _checkpointMeta),
      );
    } else if (isInserting) {
      context.missing(_checkpointMeta);
    }
    if (data.containsKey('fencing_token')) {
      context.handle(
        _fencingTokenMeta,
        fencingToken.isAcceptableOrUnknown(
          data['fencing_token']!,
          _fencingTokenMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  FixtureCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixtureCheckpoint(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      checkpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checkpoint'],
      )!,
      fencingToken: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fencing_token'],
      ),
    );
  }

  @override
  $FixtureCheckpointsTable createAlias(String alias) {
    return $FixtureCheckpointsTable(attachedDatabase, alias);
  }
}

class FixtureCheckpoint extends DataClass
    implements Insertable<FixtureCheckpoint> {
  final String key;
  final String checkpoint;
  final int? fencingToken;
  const FixtureCheckpoint({
    required this.key,
    required this.checkpoint,
    this.fencingToken,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['checkpoint'] = Variable<String>(checkpoint);
    if (!nullToAbsent || fencingToken != null) {
      map['fencing_token'] = Variable<int>(fencingToken);
    }
    return map;
  }

  FixtureCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return FixtureCheckpointsCompanion(
      key: Value(key),
      checkpoint: Value(checkpoint),
      fencingToken: fencingToken == null && nullToAbsent
          ? const Value.absent()
          : Value(fencingToken),
    );
  }

  factory FixtureCheckpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureCheckpoint(
      key: serializer.fromJson<String>(json['key']),
      checkpoint: serializer.fromJson<String>(json['checkpoint']),
      fencingToken: serializer.fromJson<int?>(json['fencingToken']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'checkpoint': serializer.toJson<String>(checkpoint),
      'fencingToken': serializer.toJson<int?>(fencingToken),
    };
  }

  FixtureCheckpoint copyWith({
    String? key,
    String? checkpoint,
    Value<int?> fencingToken = const Value.absent(),
  }) => FixtureCheckpoint(
    key: key ?? this.key,
    checkpoint: checkpoint ?? this.checkpoint,
    fencingToken: fencingToken.present ? fencingToken.value : this.fencingToken,
  );
  FixtureCheckpoint copyWithCompanion(FixtureCheckpointsCompanion data) {
    return FixtureCheckpoint(
      key: data.key.present ? data.key.value : this.key,
      checkpoint: data.checkpoint.present
          ? data.checkpoint.value
          : this.checkpoint,
      fencingToken: data.fencingToken.present
          ? data.fencingToken.value
          : this.fencingToken,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureCheckpoint(')
          ..write('key: $key, ')
          ..write('checkpoint: $checkpoint, ')
          ..write('fencingToken: $fencingToken')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, checkpoint, fencingToken);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureCheckpoint &&
          other.key == this.key &&
          other.checkpoint == this.checkpoint &&
          other.fencingToken == this.fencingToken);
}

class FixtureCheckpointsCompanion extends UpdateCompanion<FixtureCheckpoint> {
  final Value<String> key;
  final Value<String> checkpoint;
  final Value<int?> fencingToken;
  final Value<int> rowid;
  const FixtureCheckpointsCompanion({
    this.key = const Value.absent(),
    this.checkpoint = const Value.absent(),
    this.fencingToken = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixtureCheckpointsCompanion.insert({
    required String key,
    required String checkpoint,
    this.fencingToken = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       checkpoint = Value(checkpoint);
  static Insertable<FixtureCheckpoint> custom({
    Expression<String>? key,
    Expression<String>? checkpoint,
    Expression<int>? fencingToken,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (checkpoint != null) 'checkpoint': checkpoint,
      if (fencingToken != null) 'fencing_token': fencingToken,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixtureCheckpointsCompanion copyWith({
    Value<String>? key,
    Value<String>? checkpoint,
    Value<int?>? fencingToken,
    Value<int>? rowid,
  }) {
    return FixtureCheckpointsCompanion(
      key: key ?? this.key,
      checkpoint: checkpoint ?? this.checkpoint,
      fencingToken: fencingToken ?? this.fencingToken,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (checkpoint.present) {
      map['checkpoint'] = Variable<String>(checkpoint.value);
    }
    if (fencingToken.present) {
      map['fencing_token'] = Variable<int>(fencingToken.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixtureCheckpointsCompanion(')
          ..write('key: $key, ')
          ..write('checkpoint: $checkpoint, ')
          ..write('fencingToken: $fencingToken, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FixtureJournalTable extends FixtureJournal
    with TableInfo<$FixtureJournalTable, FixtureJournalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixtureJournalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _factMeta = const VerificationMeta('fact');
  @override
  late final GeneratedColumn<int> fact = GeneratedColumn<int>(
    'fact',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _datasetKeyMeta = const VerificationMeta(
    'datasetKey',
  );
  @override
  late final GeneratedColumn<String> datasetKey = GeneratedColumn<String>(
    'dataset_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hasDatasetKeyMeta = const VerificationMeta(
    'hasDatasetKey',
  );
  @override
  late final GeneratedColumn<bool> hasDatasetKey = GeneratedColumn<bool>(
    'has_dataset_key',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_dataset_key" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    attemptId,
    sequence,
    timestamp,
    fact,
    datasetKey,
    hasDatasetKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixture_journal';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixtureJournalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_attemptIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('fact')) {
      context.handle(
        _factMeta,
        fact.isAcceptableOrUnknown(data['fact']!, _factMeta),
      );
    } else if (isInserting) {
      context.missing(_factMeta);
    }
    if (data.containsKey('dataset_key')) {
      context.handle(
        _datasetKeyMeta,
        datasetKey.isAcceptableOrUnknown(data['dataset_key']!, _datasetKeyMeta),
      );
    }
    if (data.containsKey('has_dataset_key')) {
      context.handle(
        _hasDatasetKeyMeta,
        hasDatasetKey.isAcceptableOrUnknown(
          data['has_dataset_key']!,
          _hasDatasetKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasDatasetKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {attemptId, sequence};
  @override
  FixtureJournalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixtureJournalData(
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      fact: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fact'],
      )!,
      datasetKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset_key'],
      ),
      hasDatasetKey: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_dataset_key'],
      )!,
    );
  }

  @override
  $FixtureJournalTable createAlias(String alias) {
    return $FixtureJournalTable(attachedDatabase, alias);
  }
}

class FixtureJournalData extends DataClass
    implements Insertable<FixtureJournalData> {
  final String attemptId;
  final int sequence;
  final DateTime timestamp;
  final int fact;
  final String? datasetKey;
  final bool hasDatasetKey;
  const FixtureJournalData({
    required this.attemptId,
    required this.sequence,
    required this.timestamp,
    required this.fact,
    this.datasetKey,
    required this.hasDatasetKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['attempt_id'] = Variable<String>(attemptId);
    map['sequence'] = Variable<int>(sequence);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['fact'] = Variable<int>(fact);
    if (!nullToAbsent || datasetKey != null) {
      map['dataset_key'] = Variable<String>(datasetKey);
    }
    map['has_dataset_key'] = Variable<bool>(hasDatasetKey);
    return map;
  }

  FixtureJournalCompanion toCompanion(bool nullToAbsent) {
    return FixtureJournalCompanion(
      attemptId: Value(attemptId),
      sequence: Value(sequence),
      timestamp: Value(timestamp),
      fact: Value(fact),
      datasetKey: datasetKey == null && nullToAbsent
          ? const Value.absent()
          : Value(datasetKey),
      hasDatasetKey: Value(hasDatasetKey),
    );
  }

  factory FixtureJournalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureJournalData(
      attemptId: serializer.fromJson<String>(json['attemptId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      fact: serializer.fromJson<int>(json['fact']),
      datasetKey: serializer.fromJson<String?>(json['datasetKey']),
      hasDatasetKey: serializer.fromJson<bool>(json['hasDatasetKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'attemptId': serializer.toJson<String>(attemptId),
      'sequence': serializer.toJson<int>(sequence),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'fact': serializer.toJson<int>(fact),
      'datasetKey': serializer.toJson<String?>(datasetKey),
      'hasDatasetKey': serializer.toJson<bool>(hasDatasetKey),
    };
  }

  FixtureJournalData copyWith({
    String? attemptId,
    int? sequence,
    DateTime? timestamp,
    int? fact,
    Value<String?> datasetKey = const Value.absent(),
    bool? hasDatasetKey,
  }) => FixtureJournalData(
    attemptId: attemptId ?? this.attemptId,
    sequence: sequence ?? this.sequence,
    timestamp: timestamp ?? this.timestamp,
    fact: fact ?? this.fact,
    datasetKey: datasetKey.present ? datasetKey.value : this.datasetKey,
    hasDatasetKey: hasDatasetKey ?? this.hasDatasetKey,
  );
  FixtureJournalData copyWithCompanion(FixtureJournalCompanion data) {
    return FixtureJournalData(
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      fact: data.fact.present ? data.fact.value : this.fact,
      datasetKey: data.datasetKey.present
          ? data.datasetKey.value
          : this.datasetKey,
      hasDatasetKey: data.hasDatasetKey.present
          ? data.hasDatasetKey.value
          : this.hasDatasetKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureJournalData(')
          ..write('attemptId: $attemptId, ')
          ..write('sequence: $sequence, ')
          ..write('timestamp: $timestamp, ')
          ..write('fact: $fact, ')
          ..write('datasetKey: $datasetKey, ')
          ..write('hasDatasetKey: $hasDatasetKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    attemptId,
    sequence,
    timestamp,
    fact,
    datasetKey,
    hasDatasetKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureJournalData &&
          other.attemptId == this.attemptId &&
          other.sequence == this.sequence &&
          other.timestamp == this.timestamp &&
          other.fact == this.fact &&
          other.datasetKey == this.datasetKey &&
          other.hasDatasetKey == this.hasDatasetKey);
}

class FixtureJournalCompanion extends UpdateCompanion<FixtureJournalData> {
  final Value<String> attemptId;
  final Value<int> sequence;
  final Value<DateTime> timestamp;
  final Value<int> fact;
  final Value<String?> datasetKey;
  final Value<bool> hasDatasetKey;
  final Value<int> rowid;
  const FixtureJournalCompanion({
    this.attemptId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.fact = const Value.absent(),
    this.datasetKey = const Value.absent(),
    this.hasDatasetKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixtureJournalCompanion.insert({
    required String attemptId,
    required int sequence,
    required DateTime timestamp,
    required int fact,
    this.datasetKey = const Value.absent(),
    required bool hasDatasetKey,
    this.rowid = const Value.absent(),
  }) : attemptId = Value(attemptId),
       sequence = Value(sequence),
       timestamp = Value(timestamp),
       fact = Value(fact),
       hasDatasetKey = Value(hasDatasetKey);
  static Insertable<FixtureJournalData> custom({
    Expression<String>? attemptId,
    Expression<int>? sequence,
    Expression<DateTime>? timestamp,
    Expression<int>? fact,
    Expression<String>? datasetKey,
    Expression<bool>? hasDatasetKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (attemptId != null) 'attempt_id': attemptId,
      if (sequence != null) 'sequence': sequence,
      if (timestamp != null) 'timestamp': timestamp,
      if (fact != null) 'fact': fact,
      if (datasetKey != null) 'dataset_key': datasetKey,
      if (hasDatasetKey != null) 'has_dataset_key': hasDatasetKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixtureJournalCompanion copyWith({
    Value<String>? attemptId,
    Value<int>? sequence,
    Value<DateTime>? timestamp,
    Value<int>? fact,
    Value<String?>? datasetKey,
    Value<bool>? hasDatasetKey,
    Value<int>? rowid,
  }) {
    return FixtureJournalCompanion(
      attemptId: attemptId ?? this.attemptId,
      sequence: sequence ?? this.sequence,
      timestamp: timestamp ?? this.timestamp,
      fact: fact ?? this.fact,
      datasetKey: datasetKey ?? this.datasetKey,
      hasDatasetKey: hasDatasetKey ?? this.hasDatasetKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (fact.present) {
      map['fact'] = Variable<int>(fact.value);
    }
    if (datasetKey.present) {
      map['dataset_key'] = Variable<String>(datasetKey.value);
    }
    if (hasDatasetKey.present) {
      map['has_dataset_key'] = Variable<bool>(hasDatasetKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixtureJournalCompanion(')
          ..write('attemptId: $attemptId, ')
          ..write('sequence: $sequence, ')
          ..write('timestamp: $timestamp, ')
          ..write('fact: $fact, ')
          ..write('datasetKey: $datasetKey, ')
          ..write('hasDatasetKey: $hasDatasetKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$DriftFixtureDatabase extends GeneratedDatabase {
  _$DriftFixtureDatabase(QueryExecutor e) : super(e);
  $DriftFixtureDatabaseManager get managers =>
      $DriftFixtureDatabaseManager(this);
  late final $FixtureItemsTable fixtureItems = $FixtureItemsTable(this);
  late final $FixtureOutboxTable fixtureOutbox = $FixtureOutboxTable(this);
  late final $FixtureCheckpointsTable fixtureCheckpoints =
      $FixtureCheckpointsTable(this);
  late final $FixtureJournalTable fixtureJournal = $FixtureJournalTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    fixtureItems,
    fixtureOutbox,
    fixtureCheckpoints,
    fixtureJournal,
  ];
}

typedef $$FixtureItemsTableCreateCompanionBuilder =
    FixtureItemsCompanion Function({
      required String id,
      required String value,
      Value<int> revision,
      Value<int> rowid,
    });
typedef $$FixtureItemsTableUpdateCompanionBuilder =
    FixtureItemsCompanion Function({
      Value<String> id,
      Value<String> value,
      Value<int> revision,
      Value<int> rowid,
    });

class $$FixtureItemsTableFilterComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureItemsTable> {
  $$FixtureItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixtureItemsTableOrderingComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureItemsTable> {
  $$FixtureItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixtureItemsTableAnnotationComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureItemsTable> {
  $$FixtureItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$FixtureItemsTableTableManager
    extends
        RootTableManager<
          _$DriftFixtureDatabase,
          $FixtureItemsTable,
          FixtureItem,
          $$FixtureItemsTableFilterComposer,
          $$FixtureItemsTableOrderingComposer,
          $$FixtureItemsTableAnnotationComposer,
          $$FixtureItemsTableCreateCompanionBuilder,
          $$FixtureItemsTableUpdateCompanionBuilder,
          (
            FixtureItem,
            BaseReferences<
              _$DriftFixtureDatabase,
              $FixtureItemsTable,
              FixtureItem
            >,
          ),
          FixtureItem,
          PrefetchHooks Function()
        > {
  $$FixtureItemsTableTableManager(
    _$DriftFixtureDatabase db,
    $FixtureItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixtureItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixtureItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixtureItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureItemsCompanion(
                id: id,
                value: value,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String value,
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureItemsCompanion.insert(
                id: id,
                value: value,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixtureItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftFixtureDatabase,
      $FixtureItemsTable,
      FixtureItem,
      $$FixtureItemsTableFilterComposer,
      $$FixtureItemsTableOrderingComposer,
      $$FixtureItemsTableAnnotationComposer,
      $$FixtureItemsTableCreateCompanionBuilder,
      $$FixtureItemsTableUpdateCompanionBuilder,
      (
        FixtureItem,
        BaseReferences<_$DriftFixtureDatabase, $FixtureItemsTable, FixtureItem>,
      ),
      FixtureItem,
      PrefetchHooks Function()
    >;
typedef $$FixtureOutboxTableCreateCompanionBuilder =
    FixtureOutboxCompanion Function({Value<int> id, required String payload});
typedef $$FixtureOutboxTableUpdateCompanionBuilder =
    FixtureOutboxCompanion Function({Value<int> id, Value<String> payload});

class $$FixtureOutboxTableFilterComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureOutboxTable> {
  $$FixtureOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixtureOutboxTableOrderingComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureOutboxTable> {
  $$FixtureOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixtureOutboxTableAnnotationComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureOutboxTable> {
  $$FixtureOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$FixtureOutboxTableTableManager
    extends
        RootTableManager<
          _$DriftFixtureDatabase,
          $FixtureOutboxTable,
          FixtureOutboxData,
          $$FixtureOutboxTableFilterComposer,
          $$FixtureOutboxTableOrderingComposer,
          $$FixtureOutboxTableAnnotationComposer,
          $$FixtureOutboxTableCreateCompanionBuilder,
          $$FixtureOutboxTableUpdateCompanionBuilder,
          (
            FixtureOutboxData,
            BaseReferences<
              _$DriftFixtureDatabase,
              $FixtureOutboxTable,
              FixtureOutboxData
            >,
          ),
          FixtureOutboxData,
          PrefetchHooks Function()
        > {
  $$FixtureOutboxTableTableManager(
    _$DriftFixtureDatabase db,
    $FixtureOutboxTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixtureOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixtureOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixtureOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> payload = const Value.absent(),
          }) => FixtureOutboxCompanion(id: id, payload: payload),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String payload,
          }) => FixtureOutboxCompanion.insert(id: id, payload: payload),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixtureOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftFixtureDatabase,
      $FixtureOutboxTable,
      FixtureOutboxData,
      $$FixtureOutboxTableFilterComposer,
      $$FixtureOutboxTableOrderingComposer,
      $$FixtureOutboxTableAnnotationComposer,
      $$FixtureOutboxTableCreateCompanionBuilder,
      $$FixtureOutboxTableUpdateCompanionBuilder,
      (
        FixtureOutboxData,
        BaseReferences<
          _$DriftFixtureDatabase,
          $FixtureOutboxTable,
          FixtureOutboxData
        >,
      ),
      FixtureOutboxData,
      PrefetchHooks Function()
    >;
typedef $$FixtureCheckpointsTableCreateCompanionBuilder =
    FixtureCheckpointsCompanion Function({
      required String key,
      required String checkpoint,
      Value<int?> fencingToken,
      Value<int> rowid,
    });
typedef $$FixtureCheckpointsTableUpdateCompanionBuilder =
    FixtureCheckpointsCompanion Function({
      Value<String> key,
      Value<String> checkpoint,
      Value<int?> fencingToken,
      Value<int> rowid,
    });

class $$FixtureCheckpointsTableFilterComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureCheckpointsTable> {
  $$FixtureCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixtureCheckpointsTableOrderingComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureCheckpointsTable> {
  $$FixtureCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixtureCheckpointsTableAnnotationComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureCheckpointsTable> {
  $$FixtureCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => column,
  );
}

class $$FixtureCheckpointsTableTableManager
    extends
        RootTableManager<
          _$DriftFixtureDatabase,
          $FixtureCheckpointsTable,
          FixtureCheckpoint,
          $$FixtureCheckpointsTableFilterComposer,
          $$FixtureCheckpointsTableOrderingComposer,
          $$FixtureCheckpointsTableAnnotationComposer,
          $$FixtureCheckpointsTableCreateCompanionBuilder,
          $$FixtureCheckpointsTableUpdateCompanionBuilder,
          (
            FixtureCheckpoint,
            BaseReferences<
              _$DriftFixtureDatabase,
              $FixtureCheckpointsTable,
              FixtureCheckpoint
            >,
          ),
          FixtureCheckpoint,
          PrefetchHooks Function()
        > {
  $$FixtureCheckpointsTableTableManager(
    _$DriftFixtureDatabase db,
    $FixtureCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixtureCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixtureCheckpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixtureCheckpointsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> checkpoint = const Value.absent(),
                Value<int?> fencingToken = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureCheckpointsCompanion(
                key: key,
                checkpoint: checkpoint,
                fencingToken: fencingToken,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String checkpoint,
                Value<int?> fencingToken = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureCheckpointsCompanion.insert(
                key: key,
                checkpoint: checkpoint,
                fencingToken: fencingToken,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixtureCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftFixtureDatabase,
      $FixtureCheckpointsTable,
      FixtureCheckpoint,
      $$FixtureCheckpointsTableFilterComposer,
      $$FixtureCheckpointsTableOrderingComposer,
      $$FixtureCheckpointsTableAnnotationComposer,
      $$FixtureCheckpointsTableCreateCompanionBuilder,
      $$FixtureCheckpointsTableUpdateCompanionBuilder,
      (
        FixtureCheckpoint,
        BaseReferences<
          _$DriftFixtureDatabase,
          $FixtureCheckpointsTable,
          FixtureCheckpoint
        >,
      ),
      FixtureCheckpoint,
      PrefetchHooks Function()
    >;
typedef $$FixtureJournalTableCreateCompanionBuilder =
    FixtureJournalCompanion Function({
      required String attemptId,
      required int sequence,
      required DateTime timestamp,
      required int fact,
      Value<String?> datasetKey,
      required bool hasDatasetKey,
      Value<int> rowid,
    });
typedef $$FixtureJournalTableUpdateCompanionBuilder =
    FixtureJournalCompanion Function({
      Value<String> attemptId,
      Value<int> sequence,
      Value<DateTime> timestamp,
      Value<int> fact,
      Value<String?> datasetKey,
      Value<bool> hasDatasetKey,
      Value<int> rowid,
    });

class $$FixtureJournalTableFilterComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureJournalTable> {
  $$FixtureJournalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fact => $composableBuilder(
    column: $table.fact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasDatasetKey => $composableBuilder(
    column: $table.hasDatasetKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixtureJournalTableOrderingComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureJournalTable> {
  $$FixtureJournalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fact => $composableBuilder(
    column: $table.fact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasDatasetKey => $composableBuilder(
    column: $table.hasDatasetKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixtureJournalTableAnnotationComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureJournalTable> {
  $$FixtureJournalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get fact =>
      $composableBuilder(column: $table.fact, builder: (column) => column);

  GeneratedColumn<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasDatasetKey => $composableBuilder(
    column: $table.hasDatasetKey,
    builder: (column) => column,
  );
}

class $$FixtureJournalTableTableManager
    extends
        RootTableManager<
          _$DriftFixtureDatabase,
          $FixtureJournalTable,
          FixtureJournalData,
          $$FixtureJournalTableFilterComposer,
          $$FixtureJournalTableOrderingComposer,
          $$FixtureJournalTableAnnotationComposer,
          $$FixtureJournalTableCreateCompanionBuilder,
          $$FixtureJournalTableUpdateCompanionBuilder,
          (
            FixtureJournalData,
            BaseReferences<
              _$DriftFixtureDatabase,
              $FixtureJournalTable,
              FixtureJournalData
            >,
          ),
          FixtureJournalData,
          PrefetchHooks Function()
        > {
  $$FixtureJournalTableTableManager(
    _$DriftFixtureDatabase db,
    $FixtureJournalTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixtureJournalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixtureJournalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixtureJournalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> attemptId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> fact = const Value.absent(),
                Value<String?> datasetKey = const Value.absent(),
                Value<bool> hasDatasetKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureJournalCompanion(
                attemptId: attemptId,
                sequence: sequence,
                timestamp: timestamp,
                fact: fact,
                datasetKey: datasetKey,
                hasDatasetKey: hasDatasetKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String attemptId,
                required int sequence,
                required DateTime timestamp,
                required int fact,
                Value<String?> datasetKey = const Value.absent(),
                required bool hasDatasetKey,
                Value<int> rowid = const Value.absent(),
              }) => FixtureJournalCompanion.insert(
                attemptId: attemptId,
                sequence: sequence,
                timestamp: timestamp,
                fact: fact,
                datasetKey: datasetKey,
                hasDatasetKey: hasDatasetKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixtureJournalTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftFixtureDatabase,
      $FixtureJournalTable,
      FixtureJournalData,
      $$FixtureJournalTableFilterComposer,
      $$FixtureJournalTableOrderingComposer,
      $$FixtureJournalTableAnnotationComposer,
      $$FixtureJournalTableCreateCompanionBuilder,
      $$FixtureJournalTableUpdateCompanionBuilder,
      (
        FixtureJournalData,
        BaseReferences<
          _$DriftFixtureDatabase,
          $FixtureJournalTable,
          FixtureJournalData
        >,
      ),
      FixtureJournalData,
      PrefetchHooks Function()
    >;

class $DriftFixtureDatabaseManager {
  final _$DriftFixtureDatabase _db;
  $DriftFixtureDatabaseManager(this._db);
  $$FixtureItemsTableTableManager get fixtureItems =>
      $$FixtureItemsTableTableManager(_db, _db.fixtureItems);
  $$FixtureOutboxTableTableManager get fixtureOutbox =>
      $$FixtureOutboxTableTableManager(_db, _db.fixtureOutbox);
  $$FixtureCheckpointsTableTableManager get fixtureCheckpoints =>
      $$FixtureCheckpointsTableTableManager(_db, _db.fixtureCheckpoints);
  $$FixtureJournalTableTableManager get fixtureJournal =>
      $$FixtureJournalTableTableManager(_db, _db.fixtureJournal);
}
