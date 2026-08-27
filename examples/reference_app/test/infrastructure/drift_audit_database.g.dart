// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_audit_database.dart';

// ignore_for_file: type=lint
class $AuditEventsTable extends AuditEvents
    with TableInfo<$AuditEventsTable, AuditEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditEventsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, message];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
    );
  }

  @override
  $AuditEventsTable createAlias(String alias) {
    return $AuditEventsTable(attachedDatabase, alias);
  }
}

class AuditEvent extends DataClass implements Insertable<AuditEvent> {
  final int id;
  final String message;
  const AuditEvent({required this.id, required this.message});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message'] = Variable<String>(message);
    return map;
  }

  AuditEventsCompanion toCompanion(bool nullToAbsent) {
    return AuditEventsCompanion(id: Value(id), message: Value(message));
  }

  factory AuditEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditEvent(
      id: serializer.fromJson<int>(json['id']),
      message: serializer.fromJson<String>(json['message']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'message': serializer.toJson<String>(message),
    };
  }

  AuditEvent copyWith({int? id, String? message}) =>
      AuditEvent(id: id ?? this.id, message: message ?? this.message);
  AuditEvent copyWithCompanion(AuditEventsCompanion data) {
    return AuditEvent(
      id: data.id.present ? data.id.value : this.id,
      message: data.message.present ? data.message.value : this.message,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditEvent(')
          ..write('id: $id, ')
          ..write('message: $message')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, message);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditEvent &&
          other.id == this.id &&
          other.message == this.message);
}

class AuditEventsCompanion extends UpdateCompanion<AuditEvent> {
  final Value<int> id;
  final Value<String> message;
  const AuditEventsCompanion({
    this.id = const Value.absent(),
    this.message = const Value.absent(),
  });
  AuditEventsCompanion.insert({
    this.id = const Value.absent(),
    required String message,
  }) : message = Value(message);
  static Insertable<AuditEvent> custom({
    Expression<int>? id,
    Expression<String>? message,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (message != null) 'message': message,
    });
  }

  AuditEventsCompanion copyWith({Value<int>? id, Value<String>? message}) {
    return AuditEventsCompanion(
      id: id ?? this.id,
      message: message ?? this.message,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventsCompanion(')
          ..write('id: $id, ')
          ..write('message: $message')
          ..write(')'))
        .toString();
  }
}

abstract class _$AuditDatabase extends GeneratedDatabase {
  _$AuditDatabase(QueryExecutor e) : super(e);
  $AuditDatabaseManager get managers => $AuditDatabaseManager(this);
  late final $AuditEventsTable auditEvents = $AuditEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [auditEvents];
}

typedef $$AuditEventsTableCreateCompanionBuilder =
    AuditEventsCompanion Function({Value<int> id, required String message});
typedef $$AuditEventsTableUpdateCompanionBuilder =
    AuditEventsCompanion Function({Value<int> id, Value<String> message});

class $$AuditEventsTableFilterComposer
    extends Composer<_$AuditDatabase, $AuditEventsTable> {
  $$AuditEventsTableFilterComposer({
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

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditEventsTableOrderingComposer
    extends Composer<_$AuditDatabase, $AuditEventsTable> {
  $$AuditEventsTableOrderingComposer({
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

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditEventsTableAnnotationComposer
    extends Composer<_$AuditDatabase, $AuditEventsTable> {
  $$AuditEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);
}

class $$AuditEventsTableTableManager
    extends
        RootTableManager<
          _$AuditDatabase,
          $AuditEventsTable,
          AuditEvent,
          $$AuditEventsTableFilterComposer,
          $$AuditEventsTableOrderingComposer,
          $$AuditEventsTableAnnotationComposer,
          $$AuditEventsTableCreateCompanionBuilder,
          $$AuditEventsTableUpdateCompanionBuilder,
          (
            AuditEvent,
            BaseReferences<_$AuditDatabase, $AuditEventsTable, AuditEvent>,
          ),
          AuditEvent,
          PrefetchHooks Function()
        > {
  $$AuditEventsTableTableManager(_$AuditDatabase db, $AuditEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> message = const Value.absent(),
          }) => AuditEventsCompanion(id: id, message: message),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String message,
          }) => AuditEventsCompanion.insert(id: id, message: message),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AuditDatabase,
      $AuditEventsTable,
      AuditEvent,
      $$AuditEventsTableFilterComposer,
      $$AuditEventsTableOrderingComposer,
      $$AuditEventsTableAnnotationComposer,
      $$AuditEventsTableCreateCompanionBuilder,
      $$AuditEventsTableUpdateCompanionBuilder,
      (
        AuditEvent,
        BaseReferences<_$AuditDatabase, $AuditEventsTable, AuditEvent>,
      ),
      AuditEvent,
      PrefetchHooks Function()
    >;

class $AuditDatabaseManager {
  final _$AuditDatabase _db;
  $AuditDatabaseManager(this._db);
  $$AuditEventsTableTableManager get auditEvents =>
      $$AuditEventsTableTableManager(_db, _db.auditEvents);
}
