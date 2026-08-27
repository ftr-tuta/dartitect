// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_database.dart';

// ignore_for_file: type=lint
class $DomainItemsTable extends DomainItems
    with TableInfo<$DomainItemsTable, DomainItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DomainItemsTable(this.attachedDatabase, [this._alias]);
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
  @override
  List<GeneratedColumn> get $columns => [id, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'domain_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<DomainItem> instance, {
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DomainItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DomainItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $DomainItemsTable createAlias(String alias) {
    return $DomainItemsTable(attachedDatabase, alias);
  }
}

class DomainItem extends DataClass implements Insertable<DomainItem> {
  final String id;
  final String value;
  const DomainItem({required this.id, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['value'] = Variable<String>(value);
    return map;
  }

  DomainItemsCompanion toCompanion(bool nullToAbsent) {
    return DomainItemsCompanion(id: Value(id), value: Value(value));
  }

  factory DomainItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DomainItem(
      id: serializer.fromJson<String>(json['id']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'value': serializer.toJson<String>(value),
    };
  }

  DomainItem copyWith({String? id, String? value}) =>
      DomainItem(id: id ?? this.id, value: value ?? this.value);
  DomainItem copyWithCompanion(DomainItemsCompanion data) {
    return DomainItem(
      id: data.id.present ? data.id.value : this.id,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DomainItem(')
          ..write('id: $id, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DomainItem && other.id == this.id && other.value == this.value);
}

class DomainItemsCompanion extends UpdateCompanion<DomainItem> {
  final Value<String> id;
  final Value<String> value;
  final Value<int> rowid;
  const DomainItemsCompanion({
    this.id = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DomainItemsCompanion.insert({
    required String id,
    required String value,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       value = Value(value);
  static Insertable<DomainItem> custom({
    Expression<String>? id,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DomainItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return DomainItemsCompanion(
      id: id ?? this.id,
      value: value ?? this.value,
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DomainItemsCompanion(')
          ..write('id: $id, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEntry> instance, {
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
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
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
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final int id;
  final String payload;
  const OutboxEntry({required this.id, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(id: Value(id), payload: Value(payload));
  }

  factory OutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
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

  OutboxEntry copyWith({int? id, String? payload}) =>
      OutboxEntry(id: id ?? this.id, payload: payload ?? this.payload);
  OutboxEntry copyWithCompanion(OutboxEntriesCompanion data) {
    return OutboxEntry(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
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
      (other is OutboxEntry &&
          other.id == this.id &&
          other.payload == this.payload);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<int> id;
  final Value<String> payload;
  const OutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String payload,
  }) : payload = Value(payload);
  static Insertable<OutboxEntry> custom({
    Expression<int>? id,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
    });
  }

  OutboxEntriesCompanion copyWith({Value<int>? id, Value<String>? payload}) {
    return OutboxEntriesCompanion(
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
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class $CheckpointRowsTable extends CheckpointRows
    with TableInfo<$CheckpointRowsTable, CheckpointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CheckpointRowsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'checkpoint_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CheckpointRow> instance, {
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
  CheckpointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CheckpointRow(
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
  $CheckpointRowsTable createAlias(String alias) {
    return $CheckpointRowsTable(attachedDatabase, alias);
  }
}

class CheckpointRow extends DataClass implements Insertable<CheckpointRow> {
  final String key;
  final String checkpoint;
  final int? fencingToken;
  const CheckpointRow({
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

  CheckpointRowsCompanion toCompanion(bool nullToAbsent) {
    return CheckpointRowsCompanion(
      key: Value(key),
      checkpoint: Value(checkpoint),
      fencingToken: fencingToken == null && nullToAbsent
          ? const Value.absent()
          : Value(fencingToken),
    );
  }

  factory CheckpointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CheckpointRow(
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

  CheckpointRow copyWith({
    String? key,
    String? checkpoint,
    Value<int?> fencingToken = const Value.absent(),
  }) => CheckpointRow(
    key: key ?? this.key,
    checkpoint: checkpoint ?? this.checkpoint,
    fencingToken: fencingToken.present ? fencingToken.value : this.fencingToken,
  );
  CheckpointRow copyWithCompanion(CheckpointRowsCompanion data) {
    return CheckpointRow(
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
    return (StringBuffer('CheckpointRow(')
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
      (other is CheckpointRow &&
          other.key == this.key &&
          other.checkpoint == this.checkpoint &&
          other.fencingToken == this.fencingToken);
}

class CheckpointRowsCompanion extends UpdateCompanion<CheckpointRow> {
  final Value<String> key;
  final Value<String> checkpoint;
  final Value<int?> fencingToken;
  final Value<int> rowid;
  const CheckpointRowsCompanion({
    this.key = const Value.absent(),
    this.checkpoint = const Value.absent(),
    this.fencingToken = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CheckpointRowsCompanion.insert({
    required String key,
    required String checkpoint,
    this.fencingToken = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       checkpoint = Value(checkpoint);
  static Insertable<CheckpointRow> custom({
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

  CheckpointRowsCompanion copyWith({
    Value<String>? key,
    Value<String>? checkpoint,
    Value<int?>? fencingToken,
    Value<int>? rowid,
  }) {
    return CheckpointRowsCompanion(
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
    return (StringBuffer('CheckpointRowsCompanion(')
          ..write('key: $key, ')
          ..write('checkpoint: $checkpoint, ')
          ..write('fencingToken: $fencingToken, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JournalRowsTable extends JournalRows
    with TableInfo<$JournalRowsTable, JournalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalRowsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'journal_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalRow> instance, {
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
  JournalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalRow(
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
  $JournalRowsTable createAlias(String alias) {
    return $JournalRowsTable(attachedDatabase, alias);
  }
}

class JournalRow extends DataClass implements Insertable<JournalRow> {
  final String attemptId;
  final int sequence;
  final DateTime timestamp;
  final int fact;
  final String? datasetKey;
  final bool hasDatasetKey;
  const JournalRow({
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

  JournalRowsCompanion toCompanion(bool nullToAbsent) {
    return JournalRowsCompanion(
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

  factory JournalRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalRow(
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

  JournalRow copyWith({
    String? attemptId,
    int? sequence,
    DateTime? timestamp,
    int? fact,
    Value<String?> datasetKey = const Value.absent(),
    bool? hasDatasetKey,
  }) => JournalRow(
    attemptId: attemptId ?? this.attemptId,
    sequence: sequence ?? this.sequence,
    timestamp: timestamp ?? this.timestamp,
    fact: fact ?? this.fact,
    datasetKey: datasetKey.present ? datasetKey.value : this.datasetKey,
    hasDatasetKey: hasDatasetKey ?? this.hasDatasetKey,
  );
  JournalRow copyWithCompanion(JournalRowsCompanion data) {
    return JournalRow(
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
    return (StringBuffer('JournalRow(')
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
      (other is JournalRow &&
          other.attemptId == this.attemptId &&
          other.sequence == this.sequence &&
          other.timestamp == this.timestamp &&
          other.fact == this.fact &&
          other.datasetKey == this.datasetKey &&
          other.hasDatasetKey == this.hasDatasetKey);
}

class JournalRowsCompanion extends UpdateCompanion<JournalRow> {
  final Value<String> attemptId;
  final Value<int> sequence;
  final Value<DateTime> timestamp;
  final Value<int> fact;
  final Value<String?> datasetKey;
  final Value<bool> hasDatasetKey;
  final Value<int> rowid;
  const JournalRowsCompanion({
    this.attemptId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.fact = const Value.absent(),
    this.datasetKey = const Value.absent(),
    this.hasDatasetKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalRowsCompanion.insert({
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
  static Insertable<JournalRow> custom({
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

  JournalRowsCompanion copyWith({
    Value<String>? attemptId,
    Value<int>? sequence,
    Value<DateTime>? timestamp,
    Value<int>? fact,
    Value<String?>? datasetKey,
    Value<bool>? hasDatasetKey,
    Value<int>? rowid,
  }) {
    return JournalRowsCompanion(
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
    return (StringBuffer('JournalRowsCompanion(')
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

abstract class _$TestDatabase extends GeneratedDatabase {
  _$TestDatabase(QueryExecutor e) : super(e);
  $TestDatabaseManager get managers => $TestDatabaseManager(this);
  late final $DomainItemsTable domainItems = $DomainItemsTable(this);
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  late final $CheckpointRowsTable checkpointRows = $CheckpointRowsTable(this);
  late final $JournalRowsTable journalRows = $JournalRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    domainItems,
    outboxEntries,
    checkpointRows,
    journalRows,
  ];
}

typedef $$DomainItemsTableCreateCompanionBuilder =
    DomainItemsCompanion Function({
      required String id,
      required String value,
      Value<int> rowid,
    });
typedef $$DomainItemsTableUpdateCompanionBuilder =
    DomainItemsCompanion Function({
      Value<String> id,
      Value<String> value,
      Value<int> rowid,
    });

class $$DomainItemsTableFilterComposer
    extends Composer<_$TestDatabase, $DomainItemsTable> {
  $$DomainItemsTableFilterComposer({
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
}

class $$DomainItemsTableOrderingComposer
    extends Composer<_$TestDatabase, $DomainItemsTable> {
  $$DomainItemsTableOrderingComposer({
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
}

class $$DomainItemsTableAnnotationComposer
    extends Composer<_$TestDatabase, $DomainItemsTable> {
  $$DomainItemsTableAnnotationComposer({
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
}

class $$DomainItemsTableTableManager
    extends
        RootTableManager<
          _$TestDatabase,
          $DomainItemsTable,
          DomainItem,
          $$DomainItemsTableFilterComposer,
          $$DomainItemsTableOrderingComposer,
          $$DomainItemsTableAnnotationComposer,
          $$DomainItemsTableCreateCompanionBuilder,
          $$DomainItemsTableUpdateCompanionBuilder,
          (
            DomainItem,
            BaseReferences<_$TestDatabase, $DomainItemsTable, DomainItem>,
          ),
          DomainItem,
          PrefetchHooks Function()
        > {
  $$DomainItemsTableTableManager(_$TestDatabase db, $DomainItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DomainItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DomainItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DomainItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => DomainItemsCompanion(id: id, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String id,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => DomainItemsCompanion.insert(id: id, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DomainItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$TestDatabase,
      $DomainItemsTable,
      DomainItem,
      $$DomainItemsTableFilterComposer,
      $$DomainItemsTableOrderingComposer,
      $$DomainItemsTableAnnotationComposer,
      $$DomainItemsTableCreateCompanionBuilder,
      $$DomainItemsTableUpdateCompanionBuilder,
      (
        DomainItem,
        BaseReferences<_$TestDatabase, $DomainItemsTable, DomainItem>,
      ),
      DomainItem,
      PrefetchHooks Function()
    >;
typedef $$OutboxEntriesTableCreateCompanionBuilder =
    OutboxEntriesCompanion Function({Value<int> id, required String payload});
typedef $$OutboxEntriesTableUpdateCompanionBuilder =
    OutboxEntriesCompanion Function({Value<int> id, Value<String> payload});

class $$OutboxEntriesTableFilterComposer
    extends Composer<_$TestDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableFilterComposer({
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

class $$OutboxEntriesTableOrderingComposer
    extends Composer<_$TestDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableOrderingComposer({
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

class $$OutboxEntriesTableAnnotationComposer
    extends Composer<_$TestDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableAnnotationComposer({
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

class $$OutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$TestDatabase,
          $OutboxEntriesTable,
          OutboxEntry,
          $$OutboxEntriesTableFilterComposer,
          $$OutboxEntriesTableOrderingComposer,
          $$OutboxEntriesTableAnnotationComposer,
          $$OutboxEntriesTableCreateCompanionBuilder,
          $$OutboxEntriesTableUpdateCompanionBuilder,
          (
            OutboxEntry,
            BaseReferences<_$TestDatabase, $OutboxEntriesTable, OutboxEntry>,
          ),
          OutboxEntry,
          PrefetchHooks Function()
        > {
  $$OutboxEntriesTableTableManager(_$TestDatabase db, $OutboxEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> payload = const Value.absent(),
          }) => OutboxEntriesCompanion(id: id, payload: payload),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String payload,
          }) => OutboxEntriesCompanion.insert(id: id, payload: payload),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$TestDatabase,
      $OutboxEntriesTable,
      OutboxEntry,
      $$OutboxEntriesTableFilterComposer,
      $$OutboxEntriesTableOrderingComposer,
      $$OutboxEntriesTableAnnotationComposer,
      $$OutboxEntriesTableCreateCompanionBuilder,
      $$OutboxEntriesTableUpdateCompanionBuilder,
      (
        OutboxEntry,
        BaseReferences<_$TestDatabase, $OutboxEntriesTable, OutboxEntry>,
      ),
      OutboxEntry,
      PrefetchHooks Function()
    >;
typedef $$CheckpointRowsTableCreateCompanionBuilder =
    CheckpointRowsCompanion Function({
      required String key,
      required String checkpoint,
      Value<int?> fencingToken,
      Value<int> rowid,
    });
typedef $$CheckpointRowsTableUpdateCompanionBuilder =
    CheckpointRowsCompanion Function({
      Value<String> key,
      Value<String> checkpoint,
      Value<int?> fencingToken,
      Value<int> rowid,
    });

class $$CheckpointRowsTableFilterComposer
    extends Composer<_$TestDatabase, $CheckpointRowsTable> {
  $$CheckpointRowsTableFilterComposer({
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

class $$CheckpointRowsTableOrderingComposer
    extends Composer<_$TestDatabase, $CheckpointRowsTable> {
  $$CheckpointRowsTableOrderingComposer({
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

class $$CheckpointRowsTableAnnotationComposer
    extends Composer<_$TestDatabase, $CheckpointRowsTable> {
  $$CheckpointRowsTableAnnotationComposer({
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

class $$CheckpointRowsTableTableManager
    extends
        RootTableManager<
          _$TestDatabase,
          $CheckpointRowsTable,
          CheckpointRow,
          $$CheckpointRowsTableFilterComposer,
          $$CheckpointRowsTableOrderingComposer,
          $$CheckpointRowsTableAnnotationComposer,
          $$CheckpointRowsTableCreateCompanionBuilder,
          $$CheckpointRowsTableUpdateCompanionBuilder,
          (
            CheckpointRow,
            BaseReferences<_$TestDatabase, $CheckpointRowsTable, CheckpointRow>,
          ),
          CheckpointRow,
          PrefetchHooks Function()
        > {
  $$CheckpointRowsTableTableManager(
    _$TestDatabase db,
    $CheckpointRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CheckpointRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CheckpointRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CheckpointRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> checkpoint = const Value.absent(),
                Value<int?> fencingToken = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CheckpointRowsCompanion(
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
              }) => CheckpointRowsCompanion.insert(
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

typedef $$CheckpointRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$TestDatabase,
      $CheckpointRowsTable,
      CheckpointRow,
      $$CheckpointRowsTableFilterComposer,
      $$CheckpointRowsTableOrderingComposer,
      $$CheckpointRowsTableAnnotationComposer,
      $$CheckpointRowsTableCreateCompanionBuilder,
      $$CheckpointRowsTableUpdateCompanionBuilder,
      (
        CheckpointRow,
        BaseReferences<_$TestDatabase, $CheckpointRowsTable, CheckpointRow>,
      ),
      CheckpointRow,
      PrefetchHooks Function()
    >;
typedef $$JournalRowsTableCreateCompanionBuilder =
    JournalRowsCompanion Function({
      required String attemptId,
      required int sequence,
      required DateTime timestamp,
      required int fact,
      Value<String?> datasetKey,
      required bool hasDatasetKey,
      Value<int> rowid,
    });
typedef $$JournalRowsTableUpdateCompanionBuilder =
    JournalRowsCompanion Function({
      Value<String> attemptId,
      Value<int> sequence,
      Value<DateTime> timestamp,
      Value<int> fact,
      Value<String?> datasetKey,
      Value<bool> hasDatasetKey,
      Value<int> rowid,
    });

class $$JournalRowsTableFilterComposer
    extends Composer<_$TestDatabase, $JournalRowsTable> {
  $$JournalRowsTableFilterComposer({
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

class $$JournalRowsTableOrderingComposer
    extends Composer<_$TestDatabase, $JournalRowsTable> {
  $$JournalRowsTableOrderingComposer({
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

class $$JournalRowsTableAnnotationComposer
    extends Composer<_$TestDatabase, $JournalRowsTable> {
  $$JournalRowsTableAnnotationComposer({
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

class $$JournalRowsTableTableManager
    extends
        RootTableManager<
          _$TestDatabase,
          $JournalRowsTable,
          JournalRow,
          $$JournalRowsTableFilterComposer,
          $$JournalRowsTableOrderingComposer,
          $$JournalRowsTableAnnotationComposer,
          $$JournalRowsTableCreateCompanionBuilder,
          $$JournalRowsTableUpdateCompanionBuilder,
          (
            JournalRow,
            BaseReferences<_$TestDatabase, $JournalRowsTable, JournalRow>,
          ),
          JournalRow,
          PrefetchHooks Function()
        > {
  $$JournalRowsTableTableManager(_$TestDatabase db, $JournalRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> attemptId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> fact = const Value.absent(),
                Value<String?> datasetKey = const Value.absent(),
                Value<bool> hasDatasetKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalRowsCompanion(
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
              }) => JournalRowsCompanion.insert(
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

typedef $$JournalRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$TestDatabase,
      $JournalRowsTable,
      JournalRow,
      $$JournalRowsTableFilterComposer,
      $$JournalRowsTableOrderingComposer,
      $$JournalRowsTableAnnotationComposer,
      $$JournalRowsTableCreateCompanionBuilder,
      $$JournalRowsTableUpdateCompanionBuilder,
      (
        JournalRow,
        BaseReferences<_$TestDatabase, $JournalRowsTable, JournalRow>,
      ),
      JournalRow,
      PrefetchHooks Function()
    >;

class $TestDatabaseManager {
  final _$TestDatabase _db;
  $TestDatabaseManager(this._db);
  $$DomainItemsTableTableManager get domainItems =>
      $$DomainItemsTableTableManager(_db, _db.domainItems);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
  $$CheckpointRowsTableTableManager get checkpointRows =>
      $$CheckpointRowsTableTableManager(_db, _db.checkpointRows);
  $$JournalRowsTableTableManager get journalRows =>
      $$JournalRowsTableTableManager(_db, _db.journalRows);
}
