// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_fixture_database.dart';

// ignore_for_file: type=lint
class $DriftFixtureOrdersTable extends DriftFixtureOrders
    with TableInfo<$DriftFixtureOrdersTable, DriftFixtureOrder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriftFixtureOrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, description];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drift_fixture_orders';
  @override
  VerificationContext validateIntegrity(
    Insertable<DriftFixtureOrder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DriftFixtureOrder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriftFixtureOrder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
    );
  }

  @override
  $DriftFixtureOrdersTable createAlias(String alias) {
    return $DriftFixtureOrdersTable(attachedDatabase, alias);
  }
}

class DriftFixtureOrder extends DataClass
    implements Insertable<DriftFixtureOrder> {
  final String id;
  final String description;
  const DriftFixtureOrder({required this.id, required this.description});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['description'] = Variable<String>(description);
    return map;
  }

  DriftFixtureOrdersCompanion toCompanion(bool nullToAbsent) {
    return DriftFixtureOrdersCompanion(
      id: Value(id),
      description: Value(description),
    );
  }

  factory DriftFixtureOrder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriftFixtureOrder(
      id: serializer.fromJson<String>(json['id']),
      description: serializer.fromJson<String>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'description': serializer.toJson<String>(description),
    };
  }

  DriftFixtureOrder copyWith({String? id, String? description}) =>
      DriftFixtureOrder(
        id: id ?? this.id,
        description: description ?? this.description,
      );
  DriftFixtureOrder copyWithCompanion(DriftFixtureOrdersCompanion data) {
    return DriftFixtureOrder(
      id: data.id.present ? data.id.value : this.id,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DriftFixtureOrder(')
          ..write('id: $id, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, description);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DriftFixtureOrder &&
          other.id == this.id &&
          other.description == this.description);
}

class DriftFixtureOrdersCompanion extends UpdateCompanion<DriftFixtureOrder> {
  final Value<String> id;
  final Value<String> description;
  final Value<int> rowid;
  const DriftFixtureOrdersCompanion({
    this.id = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DriftFixtureOrdersCompanion.insert({
    required String id,
    required String description,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       description = Value(description);
  static Insertable<DriftFixtureOrder> custom({
    Expression<String>? id,
    Expression<String>? description,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (description != null) 'description': description,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DriftFixtureOrdersCompanion copyWith({
    Value<String>? id,
    Value<String>? description,
    Value<int>? rowid,
  }) {
    return DriftFixtureOrdersCompanion(
      id: id ?? this.id,
      description: description ?? this.description,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DriftFixtureOrdersCompanion(')
          ..write('id: $id, ')
          ..write('description: $description, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DriftFixtureOutboxTable extends DriftFixtureOutbox
    with TableInfo<$DriftFixtureOutboxTable, DriftFixtureOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriftFixtureOutboxTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'drift_fixture_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<DriftFixtureOutboxData> instance, {
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
  DriftFixtureOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriftFixtureOutboxData(
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
  $DriftFixtureOutboxTable createAlias(String alias) {
    return $DriftFixtureOutboxTable(attachedDatabase, alias);
  }
}

class DriftFixtureOutboxData extends DataClass
    implements Insertable<DriftFixtureOutboxData> {
  final int id;
  final String payload;
  const DriftFixtureOutboxData({required this.id, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  DriftFixtureOutboxCompanion toCompanion(bool nullToAbsent) {
    return DriftFixtureOutboxCompanion(id: Value(id), payload: Value(payload));
  }

  factory DriftFixtureOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriftFixtureOutboxData(
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

  DriftFixtureOutboxData copyWith({int? id, String? payload}) =>
      DriftFixtureOutboxData(
        id: id ?? this.id,
        payload: payload ?? this.payload,
      );
  DriftFixtureOutboxData copyWithCompanion(DriftFixtureOutboxCompanion data) {
    return DriftFixtureOutboxData(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DriftFixtureOutboxData(')
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
      (other is DriftFixtureOutboxData &&
          other.id == this.id &&
          other.payload == this.payload);
}

class DriftFixtureOutboxCompanion
    extends UpdateCompanion<DriftFixtureOutboxData> {
  final Value<int> id;
  final Value<String> payload;
  const DriftFixtureOutboxCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
  });
  DriftFixtureOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String payload,
  }) : payload = Value(payload);
  static Insertable<DriftFixtureOutboxData> custom({
    Expression<int>? id,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
    });
  }

  DriftFixtureOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? payload,
  }) {
    return DriftFixtureOutboxCompanion(
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
    return (StringBuffer('DriftFixtureOutboxCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

abstract class _$CoexistenceDriftDatabase extends GeneratedDatabase {
  _$CoexistenceDriftDatabase(QueryExecutor e) : super(e);
  $CoexistenceDriftDatabaseManager get managers =>
      $CoexistenceDriftDatabaseManager(this);
  late final $DriftFixtureOrdersTable driftFixtureOrders =
      $DriftFixtureOrdersTable(this);
  late final $DriftFixtureOutboxTable driftFixtureOutbox =
      $DriftFixtureOutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    driftFixtureOrders,
    driftFixtureOutbox,
  ];
}

typedef $$DriftFixtureOrdersTableCreateCompanionBuilder =
    DriftFixtureOrdersCompanion Function({
      required String id,
      required String description,
      Value<int> rowid,
    });
typedef $$DriftFixtureOrdersTableUpdateCompanionBuilder =
    DriftFixtureOrdersCompanion Function({
      Value<String> id,
      Value<String> description,
      Value<int> rowid,
    });

class $$DriftFixtureOrdersTableFilterComposer
    extends Composer<_$CoexistenceDriftDatabase, $DriftFixtureOrdersTable> {
  $$DriftFixtureOrdersTableFilterComposer({
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

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DriftFixtureOrdersTableOrderingComposer
    extends Composer<_$CoexistenceDriftDatabase, $DriftFixtureOrdersTable> {
  $$DriftFixtureOrdersTableOrderingComposer({
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

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DriftFixtureOrdersTableAnnotationComposer
    extends Composer<_$CoexistenceDriftDatabase, $DriftFixtureOrdersTable> {
  $$DriftFixtureOrdersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );
}

class $$DriftFixtureOrdersTableTableManager
    extends
        RootTableManager<
          _$CoexistenceDriftDatabase,
          $DriftFixtureOrdersTable,
          DriftFixtureOrder,
          $$DriftFixtureOrdersTableFilterComposer,
          $$DriftFixtureOrdersTableOrderingComposer,
          $$DriftFixtureOrdersTableAnnotationComposer,
          $$DriftFixtureOrdersTableCreateCompanionBuilder,
          $$DriftFixtureOrdersTableUpdateCompanionBuilder,
          (
            DriftFixtureOrder,
            BaseReferences<
              _$CoexistenceDriftDatabase,
              $DriftFixtureOrdersTable,
              DriftFixtureOrder
            >,
          ),
          DriftFixtureOrder,
          PrefetchHooks Function()
        > {
  $$DriftFixtureOrdersTableTableManager(
    _$CoexistenceDriftDatabase db,
    $DriftFixtureOrdersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriftFixtureOrdersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriftFixtureOrdersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DriftFixtureOrdersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DriftFixtureOrdersCompanion(
                id: id,
                description: description,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String description,
                Value<int> rowid = const Value.absent(),
              }) => DriftFixtureOrdersCompanion.insert(
                id: id,
                description: description,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DriftFixtureOrdersTableProcessedTableManager =
    ProcessedTableManager<
      _$CoexistenceDriftDatabase,
      $DriftFixtureOrdersTable,
      DriftFixtureOrder,
      $$DriftFixtureOrdersTableFilterComposer,
      $$DriftFixtureOrdersTableOrderingComposer,
      $$DriftFixtureOrdersTableAnnotationComposer,
      $$DriftFixtureOrdersTableCreateCompanionBuilder,
      $$DriftFixtureOrdersTableUpdateCompanionBuilder,
      (
        DriftFixtureOrder,
        BaseReferences<
          _$CoexistenceDriftDatabase,
          $DriftFixtureOrdersTable,
          DriftFixtureOrder
        >,
      ),
      DriftFixtureOrder,
      PrefetchHooks Function()
    >;
typedef $$DriftFixtureOutboxTableCreateCompanionBuilder =
    DriftFixtureOutboxCompanion Function({
      Value<int> id,
      required String payload,
    });
typedef $$DriftFixtureOutboxTableUpdateCompanionBuilder =
    DriftFixtureOutboxCompanion Function({
      Value<int> id,
      Value<String> payload,
    });

class $$DriftFixtureOutboxTableFilterComposer
    extends Composer<_$CoexistenceDriftDatabase, $DriftFixtureOutboxTable> {
  $$DriftFixtureOutboxTableFilterComposer({
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

class $$DriftFixtureOutboxTableOrderingComposer
    extends Composer<_$CoexistenceDriftDatabase, $DriftFixtureOutboxTable> {
  $$DriftFixtureOutboxTableOrderingComposer({
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

class $$DriftFixtureOutboxTableAnnotationComposer
    extends Composer<_$CoexistenceDriftDatabase, $DriftFixtureOutboxTable> {
  $$DriftFixtureOutboxTableAnnotationComposer({
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

class $$DriftFixtureOutboxTableTableManager
    extends
        RootTableManager<
          _$CoexistenceDriftDatabase,
          $DriftFixtureOutboxTable,
          DriftFixtureOutboxData,
          $$DriftFixtureOutboxTableFilterComposer,
          $$DriftFixtureOutboxTableOrderingComposer,
          $$DriftFixtureOutboxTableAnnotationComposer,
          $$DriftFixtureOutboxTableCreateCompanionBuilder,
          $$DriftFixtureOutboxTableUpdateCompanionBuilder,
          (
            DriftFixtureOutboxData,
            BaseReferences<
              _$CoexistenceDriftDatabase,
              $DriftFixtureOutboxTable,
              DriftFixtureOutboxData
            >,
          ),
          DriftFixtureOutboxData,
          PrefetchHooks Function()
        > {
  $$DriftFixtureOutboxTableTableManager(
    _$CoexistenceDriftDatabase db,
    $DriftFixtureOutboxTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriftFixtureOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriftFixtureOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DriftFixtureOutboxTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> payload = const Value.absent(),
          }) => DriftFixtureOutboxCompanion(id: id, payload: payload),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String payload,
          }) => DriftFixtureOutboxCompanion.insert(id: id, payload: payload),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DriftFixtureOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$CoexistenceDriftDatabase,
      $DriftFixtureOutboxTable,
      DriftFixtureOutboxData,
      $$DriftFixtureOutboxTableFilterComposer,
      $$DriftFixtureOutboxTableOrderingComposer,
      $$DriftFixtureOutboxTableAnnotationComposer,
      $$DriftFixtureOutboxTableCreateCompanionBuilder,
      $$DriftFixtureOutboxTableUpdateCompanionBuilder,
      (
        DriftFixtureOutboxData,
        BaseReferences<
          _$CoexistenceDriftDatabase,
          $DriftFixtureOutboxTable,
          DriftFixtureOutboxData
        >,
      ),
      DriftFixtureOutboxData,
      PrefetchHooks Function()
    >;

class $CoexistenceDriftDatabaseManager {
  final _$CoexistenceDriftDatabase _db;
  $CoexistenceDriftDatabaseManager(this._db);
  $$DriftFixtureOrdersTableTableManager get driftFixtureOrders =>
      $$DriftFixtureOrdersTableTableManager(_db, _db.driftFixtureOrders);
  $$DriftFixtureOutboxTableTableManager get driftFixtureOutbox =>
      $$DriftFixtureOutboxTableTableManager(_db, _db.driftFixtureOutbox);
}
