// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_database.dart';

// ignore_for_file: type=lint
class $ProviderRowsTable extends ProviderRows
    with TableInfo<$ProviderRowsTable, ProviderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderRowsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'provider_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderRow> instance, {
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
  ProviderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderRow(
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
  $ProviderRowsTable createAlias(String alias) {
    return $ProviderRowsTable(attachedDatabase, alias);
  }
}

class ProviderRow extends DataClass implements Insertable<ProviderRow> {
  /// Stable consumer identifier.
  final String id;

  /// Consumer payload kept outside the adapter.
  final String value;
  const ProviderRow({required this.id, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['value'] = Variable<String>(value);
    return map;
  }

  ProviderRowsCompanion toCompanion(bool nullToAbsent) {
    return ProviderRowsCompanion(id: Value(id), value: Value(value));
  }

  factory ProviderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderRow(
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

  ProviderRow copyWith({String? id, String? value}) =>
      ProviderRow(id: id ?? this.id, value: value ?? this.value);
  ProviderRow copyWithCompanion(ProviderRowsCompanion data) {
    return ProviderRow(
      id: data.id.present ? data.id.value : this.id,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderRow(')
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
      (other is ProviderRow &&
          other.id == this.id &&
          other.value == this.value);
}

class ProviderRowsCompanion extends UpdateCompanion<ProviderRow> {
  final Value<String> id;
  final Value<String> value;
  final Value<int> rowid;
  const ProviderRowsCompanion({
    this.id = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderRowsCompanion.insert({
    required String id,
    required String value,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       value = Value(value);
  static Insertable<ProviderRow> custom({
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

  ProviderRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return ProviderRowsCompanion(
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
    return (StringBuffer('ProviderRowsCompanion(')
          ..write('id: $id, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProviderCheckpointsTable extends ProviderCheckpoints
    with TableInfo<$ProviderCheckpointsTable, ProviderCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderCheckpointsTable(this.attachedDatabase, [this._alias]);
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
  @override
  List<GeneratedColumn> get $columns => [key, checkpoint];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderCheckpoint> instance, {
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ProviderCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderCheckpoint(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      checkpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}checkpoint'],
      )!,
    );
  }

  @override
  $ProviderCheckpointsTable createAlias(String alias) {
    return $ProviderCheckpointsTable(attachedDatabase, alias);
  }
}

class ProviderCheckpoint extends DataClass
    implements Insertable<ProviderCheckpoint> {
  /// Dataset key.
  final String key;

  /// Confirmed checkpoint.
  final int checkpoint;
  const ProviderCheckpoint({required this.key, required this.checkpoint});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['checkpoint'] = Variable<int>(checkpoint);
    return map;
  }

  ProviderCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return ProviderCheckpointsCompanion(
      key: Value(key),
      checkpoint: Value(checkpoint),
    );
  }

  factory ProviderCheckpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderCheckpoint(
      key: serializer.fromJson<String>(json['key']),
      checkpoint: serializer.fromJson<int>(json['checkpoint']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'checkpoint': serializer.toJson<int>(checkpoint),
    };
  }

  ProviderCheckpoint copyWith({String? key, int? checkpoint}) =>
      ProviderCheckpoint(
        key: key ?? this.key,
        checkpoint: checkpoint ?? this.checkpoint,
      );
  ProviderCheckpoint copyWithCompanion(ProviderCheckpointsCompanion data) {
    return ProviderCheckpoint(
      key: data.key.present ? data.key.value : this.key,
      checkpoint: data.checkpoint.present
          ? data.checkpoint.value
          : this.checkpoint,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderCheckpoint(')
          ..write('key: $key, ')
          ..write('checkpoint: $checkpoint')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, checkpoint);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderCheckpoint &&
          other.key == this.key &&
          other.checkpoint == this.checkpoint);
}

class ProviderCheckpointsCompanion extends UpdateCompanion<ProviderCheckpoint> {
  final Value<String> key;
  final Value<int> checkpoint;
  final Value<int> rowid;
  const ProviderCheckpointsCompanion({
    this.key = const Value.absent(),
    this.checkpoint = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderCheckpointsCompanion.insert({
    required String key,
    required int checkpoint,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       checkpoint = Value(checkpoint);
  static Insertable<ProviderCheckpoint> custom({
    Expression<String>? key,
    Expression<int>? checkpoint,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (checkpoint != null) 'checkpoint': checkpoint,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProviderCheckpointsCompanion copyWith({
    Value<String>? key,
    Value<int>? checkpoint,
    Value<int>? rowid,
  }) {
    return ProviderCheckpointsCompanion(
      key: key ?? this.key,
      checkpoint: checkpoint ?? this.checkpoint,
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderCheckpointsCompanion(')
          ..write('key: $key, ')
          ..write('checkpoint: $checkpoint, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProviderDatabase extends GeneratedDatabase {
  _$ProviderDatabase(QueryExecutor e) : super(e);
  $ProviderDatabaseManager get managers => $ProviderDatabaseManager(this);
  late final $ProviderRowsTable providerRows = $ProviderRowsTable(this);
  late final $ProviderCheckpointsTable providerCheckpoints =
      $ProviderCheckpointsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    providerRows,
    providerCheckpoints,
  ];
}

typedef $$ProviderRowsTableCreateCompanionBuilder =
    ProviderRowsCompanion Function({
      required String id,
      required String value,
      Value<int> rowid,
    });
typedef $$ProviderRowsTableUpdateCompanionBuilder =
    ProviderRowsCompanion Function({
      Value<String> id,
      Value<String> value,
      Value<int> rowid,
    });

class $$ProviderRowsTableFilterComposer
    extends Composer<_$ProviderDatabase, $ProviderRowsTable> {
  $$ProviderRowsTableFilterComposer({
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

class $$ProviderRowsTableOrderingComposer
    extends Composer<_$ProviderDatabase, $ProviderRowsTable> {
  $$ProviderRowsTableOrderingComposer({
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

class $$ProviderRowsTableAnnotationComposer
    extends Composer<_$ProviderDatabase, $ProviderRowsTable> {
  $$ProviderRowsTableAnnotationComposer({
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

class $$ProviderRowsTableTableManager
    extends
        RootTableManager<
          _$ProviderDatabase,
          $ProviderRowsTable,
          ProviderRow,
          $$ProviderRowsTableFilterComposer,
          $$ProviderRowsTableOrderingComposer,
          $$ProviderRowsTableAnnotationComposer,
          $$ProviderRowsTableCreateCompanionBuilder,
          $$ProviderRowsTableUpdateCompanionBuilder,
          (
            ProviderRow,
            BaseReferences<_$ProviderDatabase, $ProviderRowsTable, ProviderRow>,
          ),
          ProviderRow,
          PrefetchHooks Function()
        > {
  $$ProviderRowsTableTableManager(
    _$ProviderDatabase db,
    $ProviderRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProviderRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProviderRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => ProviderRowsCompanion(id: id, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => ProviderRowsCompanion.insert(
                id: id,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProviderRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProviderDatabase,
      $ProviderRowsTable,
      ProviderRow,
      $$ProviderRowsTableFilterComposer,
      $$ProviderRowsTableOrderingComposer,
      $$ProviderRowsTableAnnotationComposer,
      $$ProviderRowsTableCreateCompanionBuilder,
      $$ProviderRowsTableUpdateCompanionBuilder,
      (
        ProviderRow,
        BaseReferences<_$ProviderDatabase, $ProviderRowsTable, ProviderRow>,
      ),
      ProviderRow,
      PrefetchHooks Function()
    >;
typedef $$ProviderCheckpointsTableCreateCompanionBuilder =
    ProviderCheckpointsCompanion Function({
      required String key,
      required int checkpoint,
      Value<int> rowid,
    });
typedef $$ProviderCheckpointsTableUpdateCompanionBuilder =
    ProviderCheckpointsCompanion Function({
      Value<String> key,
      Value<int> checkpoint,
      Value<int> rowid,
    });

class $$ProviderCheckpointsTableFilterComposer
    extends Composer<_$ProviderDatabase, $ProviderCheckpointsTable> {
  $$ProviderCheckpointsTableFilterComposer({
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
}

class $$ProviderCheckpointsTableOrderingComposer
    extends Composer<_$ProviderDatabase, $ProviderCheckpointsTable> {
  $$ProviderCheckpointsTableOrderingComposer({
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
}

class $$ProviderCheckpointsTableAnnotationComposer
    extends Composer<_$ProviderDatabase, $ProviderCheckpointsTable> {
  $$ProviderCheckpointsTableAnnotationComposer({
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
}

class $$ProviderCheckpointsTableTableManager
    extends
        RootTableManager<
          _$ProviderDatabase,
          $ProviderCheckpointsTable,
          ProviderCheckpoint,
          $$ProviderCheckpointsTableFilterComposer,
          $$ProviderCheckpointsTableOrderingComposer,
          $$ProviderCheckpointsTableAnnotationComposer,
          $$ProviderCheckpointsTableCreateCompanionBuilder,
          $$ProviderCheckpointsTableUpdateCompanionBuilder,
          (
            ProviderCheckpoint,
            BaseReferences<
              _$ProviderDatabase,
              $ProviderCheckpointsTable,
              ProviderCheckpoint
            >,
          ),
          ProviderCheckpoint,
          PrefetchHooks Function()
        > {
  $$ProviderCheckpointsTableTableManager(
    _$ProviderDatabase db,
    $ProviderCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProviderCheckpointsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProviderCheckpointsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<int> checkpoint = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProviderCheckpointsCompanion(
                key: key,
                checkpoint: checkpoint,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required int checkpoint,
                Value<int> rowid = const Value.absent(),
              }) => ProviderCheckpointsCompanion.insert(
                key: key,
                checkpoint: checkpoint,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProviderCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProviderDatabase,
      $ProviderCheckpointsTable,
      ProviderCheckpoint,
      $$ProviderCheckpointsTableFilterComposer,
      $$ProviderCheckpointsTableOrderingComposer,
      $$ProviderCheckpointsTableAnnotationComposer,
      $$ProviderCheckpointsTableCreateCompanionBuilder,
      $$ProviderCheckpointsTableUpdateCompanionBuilder,
      (
        ProviderCheckpoint,
        BaseReferences<
          _$ProviderDatabase,
          $ProviderCheckpointsTable,
          ProviderCheckpoint
        >,
      ),
      ProviderCheckpoint,
      PrefetchHooks Function()
    >;

class $ProviderDatabaseManager {
  final _$ProviderDatabase _db;
  $ProviderDatabaseManager(this._db);
  $$ProviderRowsTableTableManager get providerRows =>
      $$ProviderRowsTableTableManager(_db, _db.providerRows);
  $$ProviderCheckpointsTableTableManager get providerCheckpoints =>
      $$ProviderCheckpointsTableTableManager(_db, _db.providerCheckpoints);
}
