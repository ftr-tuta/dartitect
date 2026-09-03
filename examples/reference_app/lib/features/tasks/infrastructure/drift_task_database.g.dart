// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_task_database.dart';

// ignore_for_file: type=lint
class $DriftTaskRowsTable extends DriftTaskRows
    with TableInfo<$DriftTaskRowsTable, DriftTaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriftTaskRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    completed,
    version,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drift_task_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<DriftTaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    } else if (isInserting) {
      context.missing(_completedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DriftTaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriftTaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $DriftTaskRowsTable createAlias(String alias) {
    return $DriftTaskRowsTable(attachedDatabase, alias);
  }
}

class DriftTaskRow extends DataClass implements Insertable<DriftTaskRow> {
  final int id;
  final String title;
  final bool completed;
  final int version;
  final String syncState;
  const DriftTaskRow({
    required this.id,
    required this.title,
    required this.completed,
    required this.version,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['completed'] = Variable<bool>(completed);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  DriftTaskRowsCompanion toCompanion(bool nullToAbsent) {
    return DriftTaskRowsCompanion(
      id: Value(id),
      title: Value(title),
      completed: Value(completed),
      version: Value(version),
      syncState: Value(syncState),
    );
  }

  factory DriftTaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriftTaskRow(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      completed: serializer.fromJson<bool>(json['completed']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'completed': serializer.toJson<bool>(completed),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  DriftTaskRow copyWith({
    int? id,
    String? title,
    bool? completed,
    int? version,
    String? syncState,
  }) => DriftTaskRow(
    id: id ?? this.id,
    title: title ?? this.title,
    completed: completed ?? this.completed,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
  );
  DriftTaskRow copyWithCompanion(DriftTaskRowsCompanion data) {
    return DriftTaskRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      completed: data.completed.present ? data.completed.value : this.completed,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DriftTaskRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('completed: $completed, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, completed, version, syncState);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DriftTaskRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.completed == this.completed &&
          other.version == this.version &&
          other.syncState == this.syncState);
}

class DriftTaskRowsCompanion extends UpdateCompanion<DriftTaskRow> {
  final Value<int> id;
  final Value<String> title;
  final Value<bool> completed;
  final Value<int> version;
  final Value<String> syncState;
  const DriftTaskRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.completed = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
  });
  DriftTaskRowsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required bool completed,
    required int version,
    required String syncState,
  }) : title = Value(title),
       completed = Value(completed),
       version = Value(version),
       syncState = Value(syncState);
  static Insertable<DriftTaskRow> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<bool>? completed,
    Expression<int>? version,
    Expression<String>? syncState,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (completed != null) 'completed': completed,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
    });
  }

  DriftTaskRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<bool>? completed,
    Value<int>? version,
    Value<String>? syncState,
  }) {
    return DriftTaskRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DriftTaskRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('completed: $completed, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }
}

class $DriftTaskOutboxRowsTable extends DriftTaskOutboxRows
    with TableInfo<$DriftTaskOutboxRowsTable, DriftTaskOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriftTaskOutboxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<int> taskId = GeneratedColumn<int>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _attemptMeta = const VerificationMeta(
    'attempt',
  );
  @override
  late final GeneratedColumn<int> attempt = GeneratedColumn<int>(
    'attempt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    idempotencyKey,
    taskId,
    completed,
    attempt,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drift_task_outbox_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<DriftTaskOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    } else if (isInserting) {
      context.missing(_completedMeta);
    }
    if (data.containsKey('attempt')) {
      context.handle(
        _attemptMeta,
        attempt.isAcceptableOrUnknown(data['attempt']!, _attemptMeta),
      );
    } else if (isInserting) {
      context.missing(_attemptMeta);
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {idempotencyKey};
  @override
  DriftTaskOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriftTaskOutboxRow(
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}task_id'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      attempt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $DriftTaskOutboxRowsTable createAlias(String alias) {
    return $DriftTaskOutboxRowsTable(attachedDatabase, alias);
  }
}

class DriftTaskOutboxRow extends DataClass
    implements Insertable<DriftTaskOutboxRow> {
  final String idempotencyKey;
  final int taskId;
  final bool completed;
  final int attempt;
  final String syncState;
  const DriftTaskOutboxRow({
    required this.idempotencyKey,
    required this.taskId,
    required this.completed,
    required this.attempt,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['task_id'] = Variable<int>(taskId);
    map['completed'] = Variable<bool>(completed);
    map['attempt'] = Variable<int>(attempt);
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  DriftTaskOutboxRowsCompanion toCompanion(bool nullToAbsent) {
    return DriftTaskOutboxRowsCompanion(
      idempotencyKey: Value(idempotencyKey),
      taskId: Value(taskId),
      completed: Value(completed),
      attempt: Value(attempt),
      syncState: Value(syncState),
    );
  }

  factory DriftTaskOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriftTaskOutboxRow(
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      taskId: serializer.fromJson<int>(json['taskId']),
      completed: serializer.fromJson<bool>(json['completed']),
      attempt: serializer.fromJson<int>(json['attempt']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'taskId': serializer.toJson<int>(taskId),
      'completed': serializer.toJson<bool>(completed),
      'attempt': serializer.toJson<int>(attempt),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  DriftTaskOutboxRow copyWith({
    String? idempotencyKey,
    int? taskId,
    bool? completed,
    int? attempt,
    String? syncState,
  }) => DriftTaskOutboxRow(
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    taskId: taskId ?? this.taskId,
    completed: completed ?? this.completed,
    attempt: attempt ?? this.attempt,
    syncState: syncState ?? this.syncState,
  );
  DriftTaskOutboxRow copyWithCompanion(DriftTaskOutboxRowsCompanion data) {
    return DriftTaskOutboxRow(
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      completed: data.completed.present ? data.completed.value : this.completed,
      attempt: data.attempt.present ? data.attempt.value : this.attempt,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DriftTaskOutboxRow(')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('taskId: $taskId, ')
          ..write('completed: $completed, ')
          ..write('attempt: $attempt, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(idempotencyKey, taskId, completed, attempt, syncState);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DriftTaskOutboxRow &&
          other.idempotencyKey == this.idempotencyKey &&
          other.taskId == this.taskId &&
          other.completed == this.completed &&
          other.attempt == this.attempt &&
          other.syncState == this.syncState);
}

class DriftTaskOutboxRowsCompanion extends UpdateCompanion<DriftTaskOutboxRow> {
  final Value<String> idempotencyKey;
  final Value<int> taskId;
  final Value<bool> completed;
  final Value<int> attempt;
  final Value<String> syncState;
  final Value<int> rowid;
  const DriftTaskOutboxRowsCompanion({
    this.idempotencyKey = const Value.absent(),
    this.taskId = const Value.absent(),
    this.completed = const Value.absent(),
    this.attempt = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DriftTaskOutboxRowsCompanion.insert({
    required String idempotencyKey,
    required int taskId,
    required bool completed,
    required int attempt,
    required String syncState,
    this.rowid = const Value.absent(),
  }) : idempotencyKey = Value(idempotencyKey),
       taskId = Value(taskId),
       completed = Value(completed),
       attempt = Value(attempt),
       syncState = Value(syncState);
  static Insertable<DriftTaskOutboxRow> custom({
    Expression<String>? idempotencyKey,
    Expression<int>? taskId,
    Expression<bool>? completed,
    Expression<int>? attempt,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (taskId != null) 'task_id': taskId,
      if (completed != null) 'completed': completed,
      if (attempt != null) 'attempt': attempt,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DriftTaskOutboxRowsCompanion copyWith({
    Value<String>? idempotencyKey,
    Value<int>? taskId,
    Value<bool>? completed,
    Value<int>? attempt,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return DriftTaskOutboxRowsCompanion(
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      taskId: taskId ?? this.taskId,
      completed: completed ?? this.completed,
      attempt: attempt ?? this.attempt,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<int>(taskId.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (attempt.present) {
      map['attempt'] = Variable<int>(attempt.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DriftTaskOutboxRowsCompanion(')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('taskId: $taskId, ')
          ..write('completed: $completed, ')
          ..write('attempt: $attempt, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DriftTaskCheckpointRowsTable extends DriftTaskCheckpointRows
    with TableInfo<$DriftTaskCheckpointRowsTable, DriftTaskCheckpointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriftTaskCheckpointRowsTable(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumn<int> checkpoint = GeneratedColumn<int>(
    'checkpoint',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const String $name = 'drift_task_checkpoint_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<DriftTaskCheckpointRow> instance, {
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
  DriftTaskCheckpointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriftTaskCheckpointRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      checkpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}checkpoint'],
      )!,
      fencingToken: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fencing_token'],
      ),
    );
  }

  @override
  $DriftTaskCheckpointRowsTable createAlias(String alias) {
    return $DriftTaskCheckpointRowsTable(attachedDatabase, alias);
  }
}

class DriftTaskCheckpointRow extends DataClass
    implements Insertable<DriftTaskCheckpointRow> {
  final String key;
  final int checkpoint;
  final int? fencingToken;
  const DriftTaskCheckpointRow({
    required this.key,
    required this.checkpoint,
    this.fencingToken,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['checkpoint'] = Variable<int>(checkpoint);
    if (!nullToAbsent || fencingToken != null) {
      map['fencing_token'] = Variable<int>(fencingToken);
    }
    return map;
  }

  DriftTaskCheckpointRowsCompanion toCompanion(bool nullToAbsent) {
    return DriftTaskCheckpointRowsCompanion(
      key: Value(key),
      checkpoint: Value(checkpoint),
      fencingToken: fencingToken == null && nullToAbsent
          ? const Value.absent()
          : Value(fencingToken),
    );
  }

  factory DriftTaskCheckpointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriftTaskCheckpointRow(
      key: serializer.fromJson<String>(json['key']),
      checkpoint: serializer.fromJson<int>(json['checkpoint']),
      fencingToken: serializer.fromJson<int?>(json['fencingToken']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'checkpoint': serializer.toJson<int>(checkpoint),
      'fencingToken': serializer.toJson<int?>(fencingToken),
    };
  }

  DriftTaskCheckpointRow copyWith({
    String? key,
    int? checkpoint,
    Value<int?> fencingToken = const Value.absent(),
  }) => DriftTaskCheckpointRow(
    key: key ?? this.key,
    checkpoint: checkpoint ?? this.checkpoint,
    fencingToken: fencingToken.present ? fencingToken.value : this.fencingToken,
  );
  DriftTaskCheckpointRow copyWithCompanion(
    DriftTaskCheckpointRowsCompanion data,
  ) {
    return DriftTaskCheckpointRow(
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
    return (StringBuffer('DriftTaskCheckpointRow(')
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
      (other is DriftTaskCheckpointRow &&
          other.key == this.key &&
          other.checkpoint == this.checkpoint &&
          other.fencingToken == this.fencingToken);
}

class DriftTaskCheckpointRowsCompanion
    extends UpdateCompanion<DriftTaskCheckpointRow> {
  final Value<String> key;
  final Value<int> checkpoint;
  final Value<int?> fencingToken;
  final Value<int> rowid;
  const DriftTaskCheckpointRowsCompanion({
    this.key = const Value.absent(),
    this.checkpoint = const Value.absent(),
    this.fencingToken = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DriftTaskCheckpointRowsCompanion.insert({
    required String key,
    required int checkpoint,
    this.fencingToken = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       checkpoint = Value(checkpoint);
  static Insertable<DriftTaskCheckpointRow> custom({
    Expression<String>? key,
    Expression<int>? checkpoint,
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

  DriftTaskCheckpointRowsCompanion copyWith({
    Value<String>? key,
    Value<int>? checkpoint,
    Value<int?>? fencingToken,
    Value<int>? rowid,
  }) {
    return DriftTaskCheckpointRowsCompanion(
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
      map['checkpoint'] = Variable<int>(checkpoint.value);
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
    return (StringBuffer('DriftTaskCheckpointRowsCompanion(')
          ..write('key: $key, ')
          ..write('checkpoint: $checkpoint, ')
          ..write('fencingToken: $fencingToken, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DriftTaskJournalRowsTable extends DriftTaskJournalRows
    with TableInfo<$DriftTaskJournalRowsTable, DriftTaskJournalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriftTaskJournalRowsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'drift_task_journal_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<DriftTaskJournalRow> instance, {
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
  DriftTaskJournalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriftTaskJournalRow(
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
  $DriftTaskJournalRowsTable createAlias(String alias) {
    return $DriftTaskJournalRowsTable(attachedDatabase, alias);
  }
}

class DriftTaskJournalRow extends DataClass
    implements Insertable<DriftTaskJournalRow> {
  final String attemptId;
  final int sequence;
  final DateTime timestamp;
  final int fact;
  final String? datasetKey;
  final bool hasDatasetKey;
  const DriftTaskJournalRow({
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

  DriftTaskJournalRowsCompanion toCompanion(bool nullToAbsent) {
    return DriftTaskJournalRowsCompanion(
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

  factory DriftTaskJournalRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriftTaskJournalRow(
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

  DriftTaskJournalRow copyWith({
    String? attemptId,
    int? sequence,
    DateTime? timestamp,
    int? fact,
    Value<String?> datasetKey = const Value.absent(),
    bool? hasDatasetKey,
  }) => DriftTaskJournalRow(
    attemptId: attemptId ?? this.attemptId,
    sequence: sequence ?? this.sequence,
    timestamp: timestamp ?? this.timestamp,
    fact: fact ?? this.fact,
    datasetKey: datasetKey.present ? datasetKey.value : this.datasetKey,
    hasDatasetKey: hasDatasetKey ?? this.hasDatasetKey,
  );
  DriftTaskJournalRow copyWithCompanion(DriftTaskJournalRowsCompanion data) {
    return DriftTaskJournalRow(
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
    return (StringBuffer('DriftTaskJournalRow(')
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
      (other is DriftTaskJournalRow &&
          other.attemptId == this.attemptId &&
          other.sequence == this.sequence &&
          other.timestamp == this.timestamp &&
          other.fact == this.fact &&
          other.datasetKey == this.datasetKey &&
          other.hasDatasetKey == this.hasDatasetKey);
}

class DriftTaskJournalRowsCompanion
    extends UpdateCompanion<DriftTaskJournalRow> {
  final Value<String> attemptId;
  final Value<int> sequence;
  final Value<DateTime> timestamp;
  final Value<int> fact;
  final Value<String?> datasetKey;
  final Value<bool> hasDatasetKey;
  final Value<int> rowid;
  const DriftTaskJournalRowsCompanion({
    this.attemptId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.fact = const Value.absent(),
    this.datasetKey = const Value.absent(),
    this.hasDatasetKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DriftTaskJournalRowsCompanion.insert({
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
  static Insertable<DriftTaskJournalRow> custom({
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

  DriftTaskJournalRowsCompanion copyWith({
    Value<String>? attemptId,
    Value<int>? sequence,
    Value<DateTime>? timestamp,
    Value<int>? fact,
    Value<String?>? datasetKey,
    Value<bool>? hasDatasetKey,
    Value<int>? rowid,
  }) {
    return DriftTaskJournalRowsCompanion(
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
    return (StringBuffer('DriftTaskJournalRowsCompanion(')
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

abstract class _$DriftTaskDatabase extends GeneratedDatabase {
  _$DriftTaskDatabase(QueryExecutor e) : super(e);
  $DriftTaskDatabaseManager get managers => $DriftTaskDatabaseManager(this);
  late final $DriftTaskRowsTable driftTaskRows = $DriftTaskRowsTable(this);
  late final $DriftTaskOutboxRowsTable driftTaskOutboxRows =
      $DriftTaskOutboxRowsTable(this);
  late final $DriftTaskCheckpointRowsTable driftTaskCheckpointRows =
      $DriftTaskCheckpointRowsTable(this);
  late final $DriftTaskJournalRowsTable driftTaskJournalRows =
      $DriftTaskJournalRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    driftTaskRows,
    driftTaskOutboxRows,
    driftTaskCheckpointRows,
    driftTaskJournalRows,
  ];
}

typedef $$DriftTaskRowsTableCreateCompanionBuilder =
    DriftTaskRowsCompanion Function({
      Value<int> id,
      required String title,
      required bool completed,
      required int version,
      required String syncState,
    });
typedef $$DriftTaskRowsTableUpdateCompanionBuilder =
    DriftTaskRowsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<bool> completed,
      Value<int> version,
      Value<String> syncState,
    });

class $$DriftTaskRowsTableFilterComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskRowsTable> {
  $$DriftTaskRowsTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DriftTaskRowsTableOrderingComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskRowsTable> {
  $$DriftTaskRowsTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DriftTaskRowsTableAnnotationComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskRowsTable> {
  $$DriftTaskRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$DriftTaskRowsTableTableManager
    extends
        RootTableManager<
          _$DriftTaskDatabase,
          $DriftTaskRowsTable,
          DriftTaskRow,
          $$DriftTaskRowsTableFilterComposer,
          $$DriftTaskRowsTableOrderingComposer,
          $$DriftTaskRowsTableAnnotationComposer,
          $$DriftTaskRowsTableCreateCompanionBuilder,
          $$DriftTaskRowsTableUpdateCompanionBuilder,
          (
            DriftTaskRow,
            BaseReferences<
              _$DriftTaskDatabase,
              $DriftTaskRowsTable,
              DriftTaskRow
            >,
          ),
          DriftTaskRow,
          PrefetchHooks Function()
        > {
  $$DriftTaskRowsTableTableManager(
    _$DriftTaskDatabase db,
    $DriftTaskRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriftTaskRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriftTaskRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DriftTaskRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
              }) => DriftTaskRowsCompanion(
                id: id,
                title: title,
                completed: completed,
                version: version,
                syncState: syncState,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required bool completed,
                required int version,
                required String syncState,
              }) => DriftTaskRowsCompanion.insert(
                id: id,
                title: title,
                completed: completed,
                version: version,
                syncState: syncState,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DriftTaskRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftTaskDatabase,
      $DriftTaskRowsTable,
      DriftTaskRow,
      $$DriftTaskRowsTableFilterComposer,
      $$DriftTaskRowsTableOrderingComposer,
      $$DriftTaskRowsTableAnnotationComposer,
      $$DriftTaskRowsTableCreateCompanionBuilder,
      $$DriftTaskRowsTableUpdateCompanionBuilder,
      (
        DriftTaskRow,
        BaseReferences<_$DriftTaskDatabase, $DriftTaskRowsTable, DriftTaskRow>,
      ),
      DriftTaskRow,
      PrefetchHooks Function()
    >;
typedef $$DriftTaskOutboxRowsTableCreateCompanionBuilder =
    DriftTaskOutboxRowsCompanion Function({
      required String idempotencyKey,
      required int taskId,
      required bool completed,
      required int attempt,
      required String syncState,
      Value<int> rowid,
    });
typedef $$DriftTaskOutboxRowsTableUpdateCompanionBuilder =
    DriftTaskOutboxRowsCompanion Function({
      Value<String> idempotencyKey,
      Value<int> taskId,
      Value<bool> completed,
      Value<int> attempt,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$DriftTaskOutboxRowsTableFilterComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskOutboxRowsTable> {
  $$DriftTaskOutboxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DriftTaskOutboxRowsTableOrderingComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskOutboxRowsTable> {
  $$DriftTaskOutboxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempt => $composableBuilder(
    column: $table.attempt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DriftTaskOutboxRowsTableAnnotationComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskOutboxRowsTable> {
  $$DriftTaskOutboxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<int> get attempt =>
      $composableBuilder(column: $table.attempt, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$DriftTaskOutboxRowsTableTableManager
    extends
        RootTableManager<
          _$DriftTaskDatabase,
          $DriftTaskOutboxRowsTable,
          DriftTaskOutboxRow,
          $$DriftTaskOutboxRowsTableFilterComposer,
          $$DriftTaskOutboxRowsTableOrderingComposer,
          $$DriftTaskOutboxRowsTableAnnotationComposer,
          $$DriftTaskOutboxRowsTableCreateCompanionBuilder,
          $$DriftTaskOutboxRowsTableUpdateCompanionBuilder,
          (
            DriftTaskOutboxRow,
            BaseReferences<
              _$DriftTaskDatabase,
              $DriftTaskOutboxRowsTable,
              DriftTaskOutboxRow
            >,
          ),
          DriftTaskOutboxRow,
          PrefetchHooks Function()
        > {
  $$DriftTaskOutboxRowsTableTableManager(
    _$DriftTaskDatabase db,
    $DriftTaskOutboxRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriftTaskOutboxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriftTaskOutboxRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DriftTaskOutboxRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> idempotencyKey = const Value.absent(),
                Value<int> taskId = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<int> attempt = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DriftTaskOutboxRowsCompanion(
                idempotencyKey: idempotencyKey,
                taskId: taskId,
                completed: completed,
                attempt: attempt,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String idempotencyKey,
                required int taskId,
                required bool completed,
                required int attempt,
                required String syncState,
                Value<int> rowid = const Value.absent(),
              }) => DriftTaskOutboxRowsCompanion.insert(
                idempotencyKey: idempotencyKey,
                taskId: taskId,
                completed: completed,
                attempt: attempt,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DriftTaskOutboxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftTaskDatabase,
      $DriftTaskOutboxRowsTable,
      DriftTaskOutboxRow,
      $$DriftTaskOutboxRowsTableFilterComposer,
      $$DriftTaskOutboxRowsTableOrderingComposer,
      $$DriftTaskOutboxRowsTableAnnotationComposer,
      $$DriftTaskOutboxRowsTableCreateCompanionBuilder,
      $$DriftTaskOutboxRowsTableUpdateCompanionBuilder,
      (
        DriftTaskOutboxRow,
        BaseReferences<
          _$DriftTaskDatabase,
          $DriftTaskOutboxRowsTable,
          DriftTaskOutboxRow
        >,
      ),
      DriftTaskOutboxRow,
      PrefetchHooks Function()
    >;
typedef $$DriftTaskCheckpointRowsTableCreateCompanionBuilder =
    DriftTaskCheckpointRowsCompanion Function({
      required String key,
      required int checkpoint,
      Value<int?> fencingToken,
      Value<int> rowid,
    });
typedef $$DriftTaskCheckpointRowsTableUpdateCompanionBuilder =
    DriftTaskCheckpointRowsCompanion Function({
      Value<String> key,
      Value<int> checkpoint,
      Value<int?> fencingToken,
      Value<int> rowid,
    });

class $$DriftTaskCheckpointRowsTableFilterComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskCheckpointRowsTable> {
  $$DriftTaskCheckpointRowsTableFilterComposer({
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

  ColumnFilters<int> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DriftTaskCheckpointRowsTableOrderingComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskCheckpointRowsTable> {
  $$DriftTaskCheckpointRowsTableOrderingComposer({
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

  ColumnOrderings<int> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DriftTaskCheckpointRowsTableAnnotationComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskCheckpointRowsTable> {
  $$DriftTaskCheckpointRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => column,
  );
}

class $$DriftTaskCheckpointRowsTableTableManager
    extends
        RootTableManager<
          _$DriftTaskDatabase,
          $DriftTaskCheckpointRowsTable,
          DriftTaskCheckpointRow,
          $$DriftTaskCheckpointRowsTableFilterComposer,
          $$DriftTaskCheckpointRowsTableOrderingComposer,
          $$DriftTaskCheckpointRowsTableAnnotationComposer,
          $$DriftTaskCheckpointRowsTableCreateCompanionBuilder,
          $$DriftTaskCheckpointRowsTableUpdateCompanionBuilder,
          (
            DriftTaskCheckpointRow,
            BaseReferences<
              _$DriftTaskDatabase,
              $DriftTaskCheckpointRowsTable,
              DriftTaskCheckpointRow
            >,
          ),
          DriftTaskCheckpointRow,
          PrefetchHooks Function()
        > {
  $$DriftTaskCheckpointRowsTableTableManager(
    _$DriftTaskDatabase db,
    $DriftTaskCheckpointRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriftTaskCheckpointRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DriftTaskCheckpointRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DriftTaskCheckpointRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<int> checkpoint = const Value.absent(),
                Value<int?> fencingToken = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DriftTaskCheckpointRowsCompanion(
                key: key,
                checkpoint: checkpoint,
                fencingToken: fencingToken,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required int checkpoint,
                Value<int?> fencingToken = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DriftTaskCheckpointRowsCompanion.insert(
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

typedef $$DriftTaskCheckpointRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftTaskDatabase,
      $DriftTaskCheckpointRowsTable,
      DriftTaskCheckpointRow,
      $$DriftTaskCheckpointRowsTableFilterComposer,
      $$DriftTaskCheckpointRowsTableOrderingComposer,
      $$DriftTaskCheckpointRowsTableAnnotationComposer,
      $$DriftTaskCheckpointRowsTableCreateCompanionBuilder,
      $$DriftTaskCheckpointRowsTableUpdateCompanionBuilder,
      (
        DriftTaskCheckpointRow,
        BaseReferences<
          _$DriftTaskDatabase,
          $DriftTaskCheckpointRowsTable,
          DriftTaskCheckpointRow
        >,
      ),
      DriftTaskCheckpointRow,
      PrefetchHooks Function()
    >;
typedef $$DriftTaskJournalRowsTableCreateCompanionBuilder =
    DriftTaskJournalRowsCompanion Function({
      required String attemptId,
      required int sequence,
      required DateTime timestamp,
      required int fact,
      Value<String?> datasetKey,
      required bool hasDatasetKey,
      Value<int> rowid,
    });
typedef $$DriftTaskJournalRowsTableUpdateCompanionBuilder =
    DriftTaskJournalRowsCompanion Function({
      Value<String> attemptId,
      Value<int> sequence,
      Value<DateTime> timestamp,
      Value<int> fact,
      Value<String?> datasetKey,
      Value<bool> hasDatasetKey,
      Value<int> rowid,
    });

class $$DriftTaskJournalRowsTableFilterComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskJournalRowsTable> {
  $$DriftTaskJournalRowsTableFilterComposer({
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

class $$DriftTaskJournalRowsTableOrderingComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskJournalRowsTable> {
  $$DriftTaskJournalRowsTableOrderingComposer({
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

class $$DriftTaskJournalRowsTableAnnotationComposer
    extends Composer<_$DriftTaskDatabase, $DriftTaskJournalRowsTable> {
  $$DriftTaskJournalRowsTableAnnotationComposer({
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

class $$DriftTaskJournalRowsTableTableManager
    extends
        RootTableManager<
          _$DriftTaskDatabase,
          $DriftTaskJournalRowsTable,
          DriftTaskJournalRow,
          $$DriftTaskJournalRowsTableFilterComposer,
          $$DriftTaskJournalRowsTableOrderingComposer,
          $$DriftTaskJournalRowsTableAnnotationComposer,
          $$DriftTaskJournalRowsTableCreateCompanionBuilder,
          $$DriftTaskJournalRowsTableUpdateCompanionBuilder,
          (
            DriftTaskJournalRow,
            BaseReferences<
              _$DriftTaskDatabase,
              $DriftTaskJournalRowsTable,
              DriftTaskJournalRow
            >,
          ),
          DriftTaskJournalRow,
          PrefetchHooks Function()
        > {
  $$DriftTaskJournalRowsTableTableManager(
    _$DriftTaskDatabase db,
    $DriftTaskJournalRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriftTaskJournalRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriftTaskJournalRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DriftTaskJournalRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> attemptId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> fact = const Value.absent(),
                Value<String?> datasetKey = const Value.absent(),
                Value<bool> hasDatasetKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DriftTaskJournalRowsCompanion(
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
              }) => DriftTaskJournalRowsCompanion.insert(
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

typedef $$DriftTaskJournalRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftTaskDatabase,
      $DriftTaskJournalRowsTable,
      DriftTaskJournalRow,
      $$DriftTaskJournalRowsTableFilterComposer,
      $$DriftTaskJournalRowsTableOrderingComposer,
      $$DriftTaskJournalRowsTableAnnotationComposer,
      $$DriftTaskJournalRowsTableCreateCompanionBuilder,
      $$DriftTaskJournalRowsTableUpdateCompanionBuilder,
      (
        DriftTaskJournalRow,
        BaseReferences<
          _$DriftTaskDatabase,
          $DriftTaskJournalRowsTable,
          DriftTaskJournalRow
        >,
      ),
      DriftTaskJournalRow,
      PrefetchHooks Function()
    >;

class $DriftTaskDatabaseManager {
  final _$DriftTaskDatabase _db;
  $DriftTaskDatabaseManager(this._db);
  $$DriftTaskRowsTableTableManager get driftTaskRows =>
      $$DriftTaskRowsTableTableManager(_db, _db.driftTaskRows);
  $$DriftTaskOutboxRowsTableTableManager get driftTaskOutboxRows =>
      $$DriftTaskOutboxRowsTableTableManager(_db, _db.driftTaskOutboxRows);
  $$DriftTaskCheckpointRowsTableTableManager get driftTaskCheckpointRows =>
      $$DriftTaskCheckpointRowsTableTableManager(
        _db,
        _db.driftTaskCheckpointRows,
      );
  $$DriftTaskJournalRowsTableTableManager get driftTaskJournalRows =>
      $$DriftTaskJournalRowsTableTableManager(_db, _db.driftTaskJournalRows);
}
