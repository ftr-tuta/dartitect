// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fixture_database.dart';

// ignore_for_file: type=lint
class $FixtureTasksTable extends FixtureTasks
    with TableInfo<$FixtureTasksTable, FixtureTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixtureTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>('open'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, title, version, status];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixture_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixtureTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FixtureTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixtureTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $FixtureTasksTable createAlias(String alias) {
    return $FixtureTasksTable(attachedDatabase, alias);
  }
}

class FixtureTask extends DataClass implements Insertable<FixtureTask> {
  final String id;
  final String title;
  final int version;
  final String status;
  const FixtureTask({
    required this.id,
    required this.title,
    required this.version,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['version'] = Variable<int>(version);
    map['status'] = Variable<String>(status);
    return map;
  }

  FixtureTasksCompanion toCompanion(bool nullToAbsent) {
    return FixtureTasksCompanion(
      id: Value(id),
      title: Value(title),
      version: Value(version),
      status: Value(status),
    );
  }

  factory FixtureTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureTask(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      version: serializer.fromJson<int>(json['version']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'version': serializer.toJson<int>(version),
      'status': serializer.toJson<String>(status),
    };
  }

  FixtureTask copyWith({
    String? id,
    String? title,
    int? version,
    String? status,
  }) => FixtureTask(
    id: id ?? this.id,
    title: title ?? this.title,
    version: version ?? this.version,
    status: status ?? this.status,
  );
  FixtureTask copyWithCompanion(FixtureTasksCompanion data) {
    return FixtureTask(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      version: data.version.present ? data.version.value : this.version,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureTask(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('version: $version, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, version, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureTask &&
          other.id == this.id &&
          other.title == this.title &&
          other.version == this.version &&
          other.status == this.status);
}

class FixtureTasksCompanion extends UpdateCompanion<FixtureTask> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> version;
  final Value<String> status;
  final Value<int> rowid;
  const FixtureTasksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.version = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixtureTasksCompanion.insert({
    required String id,
    required String title,
    this.version = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title);
  static Insertable<FixtureTask> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? version,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (version != null) 'version': version,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixtureTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<int>? version,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return FixtureTasksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      version: version ?? this.version,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixtureTasksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('version: $version, ')
          ..write('status: $status, ')
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
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _expectedVersionMeta = const VerificationMeta(
    'expectedVersion',
  );
  @override
  late final GeneratedColumn<int> expectedVersion = GeneratedColumn<int>(
    'expected_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    title,
    expectedVersion,
    status,
    idempotencyKey,
  ];
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
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('expected_version')) {
      context.handle(
        _expectedVersionMeta,
        expectedVersion.isAcceptableOrUnknown(
          data['expected_version']!,
          _expectedVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedVersionMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
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
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      expectedVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_version'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
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
  final String taskId;
  final String title;
  final int expectedVersion;
  final String status;
  final String idempotencyKey;
  const FixtureOutboxData({
    required this.id,
    required this.taskId,
    required this.title,
    required this.expectedVersion,
    required this.status,
    required this.idempotencyKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['task_id'] = Variable<String>(taskId);
    map['title'] = Variable<String>(title);
    map['expected_version'] = Variable<int>(expectedVersion);
    map['status'] = Variable<String>(status);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    return map;
  }

  FixtureOutboxCompanion toCompanion(bool nullToAbsent) {
    return FixtureOutboxCompanion(
      id: Value(id),
      taskId: Value(taskId),
      title: Value(title),
      expectedVersion: Value(expectedVersion),
      status: Value(status),
      idempotencyKey: Value(idempotencyKey),
    );
  }

  factory FixtureOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureOutboxData(
      id: serializer.fromJson<int>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      title: serializer.fromJson<String>(json['title']),
      expectedVersion: serializer.fromJson<int>(json['expectedVersion']),
      status: serializer.fromJson<String>(json['status']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'taskId': serializer.toJson<String>(taskId),
      'title': serializer.toJson<String>(title),
      'expectedVersion': serializer.toJson<int>(expectedVersion),
      'status': serializer.toJson<String>(status),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
    };
  }

  FixtureOutboxData copyWith({
    int? id,
    String? taskId,
    String? title,
    int? expectedVersion,
    String? status,
    String? idempotencyKey,
  }) => FixtureOutboxData(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    title: title ?? this.title,
    expectedVersion: expectedVersion ?? this.expectedVersion,
    status: status ?? this.status,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
  );
  FixtureOutboxData copyWithCompanion(FixtureOutboxCompanion data) {
    return FixtureOutboxData(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      title: data.title.present ? data.title.value : this.title,
      expectedVersion: data.expectedVersion.present
          ? data.expectedVersion.value
          : this.expectedVersion,
      status: data.status.present ? data.status.value : this.status,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureOutboxData(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('expectedVersion: $expectedVersion, ')
          ..write('status: $status, ')
          ..write('idempotencyKey: $idempotencyKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, taskId, title, expectedVersion, status, idempotencyKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureOutboxData &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.title == this.title &&
          other.expectedVersion == this.expectedVersion &&
          other.status == this.status &&
          other.idempotencyKey == this.idempotencyKey);
}

class FixtureOutboxCompanion extends UpdateCompanion<FixtureOutboxData> {
  final Value<int> id;
  final Value<String> taskId;
  final Value<String> title;
  final Value<int> expectedVersion;
  final Value<String> status;
  final Value<String> idempotencyKey;
  const FixtureOutboxCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.title = const Value.absent(),
    this.expectedVersion = const Value.absent(),
    this.status = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
  });
  FixtureOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String taskId,
    required String title,
    required int expectedVersion,
    required String status,
    required String idempotencyKey,
  }) : taskId = Value(taskId),
       title = Value(title),
       expectedVersion = Value(expectedVersion),
       status = Value(status),
       idempotencyKey = Value(idempotencyKey);
  static Insertable<FixtureOutboxData> custom({
    Expression<int>? id,
    Expression<String>? taskId,
    Expression<String>? title,
    Expression<int>? expectedVersion,
    Expression<String>? status,
    Expression<String>? idempotencyKey,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (title != null) 'title': title,
      if (expectedVersion != null) 'expected_version': expectedVersion,
      if (status != null) 'status': status,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    });
  }

  FixtureOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? taskId,
    Value<String>? title,
    Value<int>? expectedVersion,
    Value<String>? status,
    Value<String>? idempotencyKey,
  }) {
    return FixtureOutboxCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      expectedVersion: expectedVersion ?? this.expectedVersion,
      status: status ?? this.status,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (expectedVersion.present) {
      map['expected_version'] = Variable<int>(expectedVersion.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixtureOutboxCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('expectedVersion: $expectedVersion, ')
          ..write('status: $status, ')
          ..write('idempotencyKey: $idempotencyKey')
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

class $FixtureLeasesTable extends FixtureLeases
    with TableInfo<$FixtureLeasesTable, FixtureLease> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixtureLeasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _datasetMeta = const VerificationMeta(
    'dataset',
  );
  @override
  late final GeneratedColumn<String> dataset = GeneratedColumn<String>(
    'dataset',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
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
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [dataset, owner, fencingToken];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixture_leases';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixtureLease> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dataset')) {
      context.handle(
        _datasetMeta,
        dataset.isAcceptableOrUnknown(data['dataset']!, _datasetMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetMeta);
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('fencing_token')) {
      context.handle(
        _fencingTokenMeta,
        fencingToken.isAcceptableOrUnknown(
          data['fencing_token']!,
          _fencingTokenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fencingTokenMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {dataset};
  @override
  FixtureLease map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixtureLease(
      dataset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset'],
      )!,
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      fencingToken: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fencing_token'],
      )!,
    );
  }

  @override
  $FixtureLeasesTable createAlias(String alias) {
    return $FixtureLeasesTable(attachedDatabase, alias);
  }
}

class FixtureLease extends DataClass implements Insertable<FixtureLease> {
  final String dataset;
  final String owner;
  final int fencingToken;
  const FixtureLease({
    required this.dataset,
    required this.owner,
    required this.fencingToken,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dataset'] = Variable<String>(dataset);
    map['owner'] = Variable<String>(owner);
    map['fencing_token'] = Variable<int>(fencingToken);
    return map;
  }

  FixtureLeasesCompanion toCompanion(bool nullToAbsent) {
    return FixtureLeasesCompanion(
      dataset: Value(dataset),
      owner: Value(owner),
      fencingToken: Value(fencingToken),
    );
  }

  factory FixtureLease.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureLease(
      dataset: serializer.fromJson<String>(json['dataset']),
      owner: serializer.fromJson<String>(json['owner']),
      fencingToken: serializer.fromJson<int>(json['fencingToken']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dataset': serializer.toJson<String>(dataset),
      'owner': serializer.toJson<String>(owner),
      'fencingToken': serializer.toJson<int>(fencingToken),
    };
  }

  FixtureLease copyWith({String? dataset, String? owner, int? fencingToken}) =>
      FixtureLease(
        dataset: dataset ?? this.dataset,
        owner: owner ?? this.owner,
        fencingToken: fencingToken ?? this.fencingToken,
      );
  FixtureLease copyWithCompanion(FixtureLeasesCompanion data) {
    return FixtureLease(
      dataset: data.dataset.present ? data.dataset.value : this.dataset,
      owner: data.owner.present ? data.owner.value : this.owner,
      fencingToken: data.fencingToken.present
          ? data.fencingToken.value
          : this.fencingToken,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureLease(')
          ..write('dataset: $dataset, ')
          ..write('owner: $owner, ')
          ..write('fencingToken: $fencingToken')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(dataset, owner, fencingToken);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureLease &&
          other.dataset == this.dataset &&
          other.owner == this.owner &&
          other.fencingToken == this.fencingToken);
}

class FixtureLeasesCompanion extends UpdateCompanion<FixtureLease> {
  final Value<String> dataset;
  final Value<String> owner;
  final Value<int> fencingToken;
  final Value<int> rowid;
  const FixtureLeasesCompanion({
    this.dataset = const Value.absent(),
    this.owner = const Value.absent(),
    this.fencingToken = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixtureLeasesCompanion.insert({
    required String dataset,
    required String owner,
    required int fencingToken,
    this.rowid = const Value.absent(),
  }) : dataset = Value(dataset),
       owner = Value(owner),
       fencingToken = Value(fencingToken);
  static Insertable<FixtureLease> custom({
    Expression<String>? dataset,
    Expression<String>? owner,
    Expression<int>? fencingToken,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dataset != null) 'dataset': dataset,
      if (owner != null) 'owner': owner,
      if (fencingToken != null) 'fencing_token': fencingToken,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixtureLeasesCompanion copyWith({
    Value<String>? dataset,
    Value<String>? owner,
    Value<int>? fencingToken,
    Value<int>? rowid,
  }) {
    return FixtureLeasesCompanion(
      dataset: dataset ?? this.dataset,
      owner: owner ?? this.owner,
      fencingToken: fencingToken ?? this.fencingToken,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dataset.present) {
      map['dataset'] = Variable<String>(dataset.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
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
    return (StringBuffer('FixtureLeasesCompanion(')
          ..write('dataset: $dataset, ')
          ..write('owner: $owner, ')
          ..write('fencingToken: $fencingToken, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FixtureReceiptsTable extends FixtureReceipts
    with TableInfo<$FixtureReceiptsTable, FixtureReceipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixtureReceiptsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _dispositionMeta = const VerificationMeta(
    'disposition',
  );
  @override
  late final GeneratedColumn<String> disposition = GeneratedColumn<String>(
    'disposition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [idempotencyKey, disposition];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixture_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixtureReceipt> instance, {
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
    if (data.containsKey('disposition')) {
      context.handle(
        _dispositionMeta,
        disposition.isAcceptableOrUnknown(
          data['disposition']!,
          _dispositionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dispositionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {idempotencyKey};
  @override
  FixtureReceipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixtureReceipt(
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      disposition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}disposition'],
      )!,
    );
  }

  @override
  $FixtureReceiptsTable createAlias(String alias) {
    return $FixtureReceiptsTable(attachedDatabase, alias);
  }
}

class FixtureReceipt extends DataClass implements Insertable<FixtureReceipt> {
  final String idempotencyKey;
  final String disposition;
  const FixtureReceipt({
    required this.idempotencyKey,
    required this.disposition,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['disposition'] = Variable<String>(disposition);
    return map;
  }

  FixtureReceiptsCompanion toCompanion(bool nullToAbsent) {
    return FixtureReceiptsCompanion(
      idempotencyKey: Value(idempotencyKey),
      disposition: Value(disposition),
    );
  }

  factory FixtureReceipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixtureReceipt(
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      disposition: serializer.fromJson<String>(json['disposition']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'disposition': serializer.toJson<String>(disposition),
    };
  }

  FixtureReceipt copyWith({String? idempotencyKey, String? disposition}) =>
      FixtureReceipt(
        idempotencyKey: idempotencyKey ?? this.idempotencyKey,
        disposition: disposition ?? this.disposition,
      );
  FixtureReceipt copyWithCompanion(FixtureReceiptsCompanion data) {
    return FixtureReceipt(
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      disposition: data.disposition.present
          ? data.disposition.value
          : this.disposition,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixtureReceipt(')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('disposition: $disposition')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(idempotencyKey, disposition);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixtureReceipt &&
          other.idempotencyKey == this.idempotencyKey &&
          other.disposition == this.disposition);
}

class FixtureReceiptsCompanion extends UpdateCompanion<FixtureReceipt> {
  final Value<String> idempotencyKey;
  final Value<String> disposition;
  final Value<int> rowid;
  const FixtureReceiptsCompanion({
    this.idempotencyKey = const Value.absent(),
    this.disposition = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixtureReceiptsCompanion.insert({
    required String idempotencyKey,
    required String disposition,
    this.rowid = const Value.absent(),
  }) : idempotencyKey = Value(idempotencyKey),
       disposition = Value(disposition);
  static Insertable<FixtureReceipt> custom({
    Expression<String>? idempotencyKey,
    Expression<String>? disposition,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (disposition != null) 'disposition': disposition,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixtureReceiptsCompanion copyWith({
    Value<String>? idempotencyKey,
    Value<String>? disposition,
    Value<int>? rowid,
  }) {
    return FixtureReceiptsCompanion(
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      disposition: disposition ?? this.disposition,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (disposition.present) {
      map['disposition'] = Variable<String>(disposition.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixtureReceiptsCompanion(')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('disposition: $disposition, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$DriftFixtureDatabase extends GeneratedDatabase {
  _$DriftFixtureDatabase(QueryExecutor e) : super(e);
  $DriftFixtureDatabaseManager get managers =>
      $DriftFixtureDatabaseManager(this);
  late final $FixtureTasksTable fixtureTasks = $FixtureTasksTable(this);
  late final $FixtureOutboxTable fixtureOutbox = $FixtureOutboxTable(this);
  late final $FixtureCheckpointsTable fixtureCheckpoints =
      $FixtureCheckpointsTable(this);
  late final $FixtureJournalTable fixtureJournal = $FixtureJournalTable(this);
  late final $FixtureLeasesTable fixtureLeases = $FixtureLeasesTable(this);
  late final $FixtureReceiptsTable fixtureReceipts = $FixtureReceiptsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    fixtureTasks,
    fixtureOutbox,
    fixtureCheckpoints,
    fixtureJournal,
    fixtureLeases,
    fixtureReceipts,
  ];
}

typedef $$FixtureTasksTableCreateCompanionBuilder =
    FixtureTasksCompanion Function({
      required String id,
      required String title,
      Value<int> version,
      Value<String> status,
      Value<int> rowid,
    });
typedef $$FixtureTasksTableUpdateCompanionBuilder =
    FixtureTasksCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<int> version,
      Value<String> status,
      Value<int> rowid,
    });

class $$FixtureTasksTableFilterComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureTasksTable> {
  $$FixtureTasksTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixtureTasksTableOrderingComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureTasksTable> {
  $$FixtureTasksTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixtureTasksTableAnnotationComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureTasksTable> {
  $$FixtureTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$FixtureTasksTableTableManager
    extends
        RootTableManager<
          _$DriftFixtureDatabase,
          $FixtureTasksTable,
          FixtureTask,
          $$FixtureTasksTableFilterComposer,
          $$FixtureTasksTableOrderingComposer,
          $$FixtureTasksTableAnnotationComposer,
          $$FixtureTasksTableCreateCompanionBuilder,
          $$FixtureTasksTableUpdateCompanionBuilder,
          (
            FixtureTask,
            BaseReferences<
              _$DriftFixtureDatabase,
              $FixtureTasksTable,
              FixtureTask
            >,
          ),
          FixtureTask,
          PrefetchHooks Function()
        > {
  $$FixtureTasksTableTableManager(
    _$DriftFixtureDatabase db,
    $FixtureTasksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixtureTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixtureTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixtureTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureTasksCompanion(
                id: id,
                title: title,
                version: version,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<int> version = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureTasksCompanion.insert(
                id: id,
                title: title,
                version: version,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixtureTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftFixtureDatabase,
      $FixtureTasksTable,
      FixtureTask,
      $$FixtureTasksTableFilterComposer,
      $$FixtureTasksTableOrderingComposer,
      $$FixtureTasksTableAnnotationComposer,
      $$FixtureTasksTableCreateCompanionBuilder,
      $$FixtureTasksTableUpdateCompanionBuilder,
      (
        FixtureTask,
        BaseReferences<_$DriftFixtureDatabase, $FixtureTasksTable, FixtureTask>,
      ),
      FixtureTask,
      PrefetchHooks Function()
    >;
typedef $$FixtureOutboxTableCreateCompanionBuilder =
    FixtureOutboxCompanion Function({
      Value<int> id,
      required String taskId,
      required String title,
      required int expectedVersion,
      required String status,
      required String idempotencyKey,
    });
typedef $$FixtureOutboxTableUpdateCompanionBuilder =
    FixtureOutboxCompanion Function({
      Value<int> id,
      Value<String> taskId,
      Value<String> title,
      Value<int> expectedVersion,
      Value<String> status,
      Value<String> idempotencyKey,
    });

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

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedVersion => $composableBuilder(
    column: $table.expectedVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
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

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedVersion => $composableBuilder(
    column: $table.expectedVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
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

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get expectedVersion => $composableBuilder(
    column: $table.expectedVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );
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
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> expectedVersion = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
              }) => FixtureOutboxCompanion(
                id: id,
                taskId: taskId,
                title: title,
                expectedVersion: expectedVersion,
                status: status,
                idempotencyKey: idempotencyKey,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String taskId,
                required String title,
                required int expectedVersion,
                required String status,
                required String idempotencyKey,
              }) => FixtureOutboxCompanion.insert(
                id: id,
                taskId: taskId,
                title: title,
                expectedVersion: expectedVersion,
                status: status,
                idempotencyKey: idempotencyKey,
              ),
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
typedef $$FixtureLeasesTableCreateCompanionBuilder =
    FixtureLeasesCompanion Function({
      required String dataset,
      required String owner,
      required int fencingToken,
      Value<int> rowid,
    });
typedef $$FixtureLeasesTableUpdateCompanionBuilder =
    FixtureLeasesCompanion Function({
      Value<String> dataset,
      Value<String> owner,
      Value<int> fencingToken,
      Value<int> rowid,
    });

class $$FixtureLeasesTableFilterComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureLeasesTable> {
  $$FixtureLeasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get dataset => $composableBuilder(
    column: $table.dataset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixtureLeasesTableOrderingComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureLeasesTable> {
  $$FixtureLeasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get dataset => $composableBuilder(
    column: $table.dataset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixtureLeasesTableAnnotationComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureLeasesTable> {
  $$FixtureLeasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get dataset =>
      $composableBuilder(column: $table.dataset, builder: (column) => column);

  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<int> get fencingToken => $composableBuilder(
    column: $table.fencingToken,
    builder: (column) => column,
  );
}

class $$FixtureLeasesTableTableManager
    extends
        RootTableManager<
          _$DriftFixtureDatabase,
          $FixtureLeasesTable,
          FixtureLease,
          $$FixtureLeasesTableFilterComposer,
          $$FixtureLeasesTableOrderingComposer,
          $$FixtureLeasesTableAnnotationComposer,
          $$FixtureLeasesTableCreateCompanionBuilder,
          $$FixtureLeasesTableUpdateCompanionBuilder,
          (
            FixtureLease,
            BaseReferences<
              _$DriftFixtureDatabase,
              $FixtureLeasesTable,
              FixtureLease
            >,
          ),
          FixtureLease,
          PrefetchHooks Function()
        > {
  $$FixtureLeasesTableTableManager(
    _$DriftFixtureDatabase db,
    $FixtureLeasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixtureLeasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixtureLeasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixtureLeasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> dataset = const Value.absent(),
                Value<String> owner = const Value.absent(),
                Value<int> fencingToken = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureLeasesCompanion(
                dataset: dataset,
                owner: owner,
                fencingToken: fencingToken,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String dataset,
                required String owner,
                required int fencingToken,
                Value<int> rowid = const Value.absent(),
              }) => FixtureLeasesCompanion.insert(
                dataset: dataset,
                owner: owner,
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

typedef $$FixtureLeasesTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftFixtureDatabase,
      $FixtureLeasesTable,
      FixtureLease,
      $$FixtureLeasesTableFilterComposer,
      $$FixtureLeasesTableOrderingComposer,
      $$FixtureLeasesTableAnnotationComposer,
      $$FixtureLeasesTableCreateCompanionBuilder,
      $$FixtureLeasesTableUpdateCompanionBuilder,
      (
        FixtureLease,
        BaseReferences<
          _$DriftFixtureDatabase,
          $FixtureLeasesTable,
          FixtureLease
        >,
      ),
      FixtureLease,
      PrefetchHooks Function()
    >;
typedef $$FixtureReceiptsTableCreateCompanionBuilder =
    FixtureReceiptsCompanion Function({
      required String idempotencyKey,
      required String disposition,
      Value<int> rowid,
    });
typedef $$FixtureReceiptsTableUpdateCompanionBuilder =
    FixtureReceiptsCompanion Function({
      Value<String> idempotencyKey,
      Value<String> disposition,
      Value<int> rowid,
    });

class $$FixtureReceiptsTableFilterComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureReceiptsTable> {
  $$FixtureReceiptsTableFilterComposer({
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

  ColumnFilters<String> get disposition => $composableBuilder(
    column: $table.disposition,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixtureReceiptsTableOrderingComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureReceiptsTable> {
  $$FixtureReceiptsTableOrderingComposer({
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

  ColumnOrderings<String> get disposition => $composableBuilder(
    column: $table.disposition,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixtureReceiptsTableAnnotationComposer
    extends Composer<_$DriftFixtureDatabase, $FixtureReceiptsTable> {
  $$FixtureReceiptsTableAnnotationComposer({
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

  GeneratedColumn<String> get disposition => $composableBuilder(
    column: $table.disposition,
    builder: (column) => column,
  );
}

class $$FixtureReceiptsTableTableManager
    extends
        RootTableManager<
          _$DriftFixtureDatabase,
          $FixtureReceiptsTable,
          FixtureReceipt,
          $$FixtureReceiptsTableFilterComposer,
          $$FixtureReceiptsTableOrderingComposer,
          $$FixtureReceiptsTableAnnotationComposer,
          $$FixtureReceiptsTableCreateCompanionBuilder,
          $$FixtureReceiptsTableUpdateCompanionBuilder,
          (
            FixtureReceipt,
            BaseReferences<
              _$DriftFixtureDatabase,
              $FixtureReceiptsTable,
              FixtureReceipt
            >,
          ),
          FixtureReceipt,
          PrefetchHooks Function()
        > {
  $$FixtureReceiptsTableTableManager(
    _$DriftFixtureDatabase db,
    $FixtureReceiptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixtureReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixtureReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixtureReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> disposition = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FixtureReceiptsCompanion(
                idempotencyKey: idempotencyKey,
                disposition: disposition,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String idempotencyKey,
                required String disposition,
                Value<int> rowid = const Value.absent(),
              }) => FixtureReceiptsCompanion.insert(
                idempotencyKey: idempotencyKey,
                disposition: disposition,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixtureReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$DriftFixtureDatabase,
      $FixtureReceiptsTable,
      FixtureReceipt,
      $$FixtureReceiptsTableFilterComposer,
      $$FixtureReceiptsTableOrderingComposer,
      $$FixtureReceiptsTableAnnotationComposer,
      $$FixtureReceiptsTableCreateCompanionBuilder,
      $$FixtureReceiptsTableUpdateCompanionBuilder,
      (
        FixtureReceipt,
        BaseReferences<
          _$DriftFixtureDatabase,
          $FixtureReceiptsTable,
          FixtureReceipt
        >,
      ),
      FixtureReceipt,
      PrefetchHooks Function()
    >;

class $DriftFixtureDatabaseManager {
  final _$DriftFixtureDatabase _db;
  $DriftFixtureDatabaseManager(this._db);
  $$FixtureTasksTableTableManager get fixtureTasks =>
      $$FixtureTasksTableTableManager(_db, _db.fixtureTasks);
  $$FixtureOutboxTableTableManager get fixtureOutbox =>
      $$FixtureOutboxTableTableManager(_db, _db.fixtureOutbox);
  $$FixtureCheckpointsTableTableManager get fixtureCheckpoints =>
      $$FixtureCheckpointsTableTableManager(_db, _db.fixtureCheckpoints);
  $$FixtureJournalTableTableManager get fixtureJournal =>
      $$FixtureJournalTableTableManager(_db, _db.fixtureJournal);
  $$FixtureLeasesTableTableManager get fixtureLeases =>
      $$FixtureLeasesTableTableManager(_db, _db.fixtureLeases);
  $$FixtureReceiptsTableTableManager get fixtureReceipts =>
      $$FixtureReceiptsTableTableManager(_db, _db.fixtureReceipts);
}
