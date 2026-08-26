// GENERATED CODE - DO NOT MODIFY BY HAND
// Consumer-owned ObjectBox 5.3.2 model; see objectbox-model.json.

// ignore_for_file: camel_case_types, depend_on_referenced_packages
// ignore_for_file: public_member_api_docs
// coverage:ignore-file

import 'dart:typed_data';

import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:objectbox/internal.dart' as obx_int;
import 'package:objectbox/objectbox.dart' as obx;
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';

import 'features/tasks/infrastructure/task_records.dart';

export 'package:objectbox/objectbox.dart';

final _entities = <obx_int.ModelEntity>[
  obx_int.ModelEntity(
    id: const obx_int.IdUid(1, 731904221560000001),
    name: 'TaskRecord',
    lastPropertyId: const obx_int.IdUid(5, 731904221560000105),
    flags: 0,
    properties: <obx_int.ModelProperty>[
      obx_int.ModelProperty(
        id: const obx_int.IdUid(1, 731904221560000101),
        name: 'id',
        type: 6,
        flags: 129,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(2, 731904221560000102),
        name: 'title',
        type: 9,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(3, 731904221560000103),
        name: 'completed',
        type: 1,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(4, 731904221560000104),
        name: 'version',
        type: 6,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(5, 731904221560000105),
        name: 'syncState',
        type: 9,
        flags: 0,
      ),
    ],
    relations: <obx_int.ModelRelation>[],
    backlinks: <obx_int.ModelBacklink>[],
  ),
  obx_int.ModelEntity(
    id: const obx_int.IdUid(2, 731904221560000002),
    name: 'OutboxRecord',
    lastPropertyId: const obx_int.IdUid(6, 731904221560000206),
    flags: 0,
    properties: <obx_int.ModelProperty>[
      obx_int.ModelProperty(
        id: const obx_int.IdUid(1, 731904221560000201),
        name: 'id',
        type: 6,
        flags: 1,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(2, 731904221560000202),
        name: 'idempotencyKey',
        type: 9,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(3, 731904221560000203),
        name: 'taskId',
        type: 6,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(4, 731904221560000204),
        name: 'completed',
        type: 1,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(5, 731904221560000205),
        name: 'attempt',
        type: 6,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(6, 731904221560000206),
        name: 'syncState',
        type: 9,
        flags: 0,
      ),
    ],
    relations: <obx_int.ModelRelation>[],
    backlinks: <obx_int.ModelBacklink>[],
  ),
  obx_int.ModelEntity(
    id: const obx_int.IdUid(3, 731904221560000003),
    name: 'SyncJournalRecord',
    lastPropertyId: const obx_int.IdUid(7, 731904221560000307),
    flags: 0,
    properties: <obx_int.ModelProperty>[
      obx_int.ModelProperty(
        id: const obx_int.IdUid(1, 731904221560000301),
        name: 'id',
        type: 6,
        flags: 1,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(2, 731904221560000302),
        name: 'attemptId',
        type: 9,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(3, 731904221560000303),
        name: 'sequence',
        type: 6,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(4, 731904221560000304),
        name: 'timestampMicros',
        type: 6,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(5, 731904221560000305),
        name: 'fact',
        type: 9,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(6, 731904221560000306),
        name: 'datasetKey',
        type: 9,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(7, 731904221560000307),
        name: 'hasDatasetKey',
        type: 1,
        flags: 0,
      ),
    ],
    relations: <obx_int.ModelRelation>[],
    backlinks: <obx_int.ModelBacklink>[],
  ),
  obx_int.ModelEntity(
    id: const obx_int.IdUid(4, 731904221560000004),
    name: 'SyncCheckpointRecord',
    lastPropertyId: const obx_int.IdUid(4, 731904221560000404),
    flags: 0,
    properties: <obx_int.ModelProperty>[
      obx_int.ModelProperty(
        id: const obx_int.IdUid(1, 731904221560000401),
        name: 'id',
        type: 6,
        flags: 1,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(2, 731904221560000402),
        name: 'datasetKey',
        type: 9,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(3, 731904221560000403),
        name: 'checkpoint',
        type: 6,
        flags: 0,
      ),
      obx_int.ModelProperty(
        id: const obx_int.IdUid(4, 731904221560000404),
        name: 'fencingToken',
        type: 6,
        flags: 0,
      ),
    ],
    relations: <obx_int.ModelRelation>[],
    backlinks: <obx_int.ModelBacklink>[],
  ),
];

Future<obx.Store> openStore({String? directory}) async {
  await loadObjectBoxLibraryAndroidCompat();
  return obx.Store(
    getObjectBoxModel(),
    directory: directory ?? (await defaultStoreDirectory()).path,
  );
}

obx_int.ModelDefinition getObjectBoxModel() {
  final model = obx_int.ModelInfo(
    generatorVersion: obx_int.GeneratorVersion.v2025_12_16,
    entities: _entities,
    lastEntityId: const obx_int.IdUid(4, 731904221560000004),
    lastIndexId: const obx_int.IdUid(0, 0),
    lastRelationId: const obx_int.IdUid(0, 0),
    lastSequenceId: const obx_int.IdUid(0, 0),
    retiredEntityUids: const <int>[],
    retiredIndexUids: const <int>[],
    retiredPropertyUids: const <int>[],
    retiredRelationUids: const <int>[],
    modelVersion: 5,
    modelVersionParserMinimum: 5,
    version: 1,
  );
  final bindings = <Type, obx_int.EntityDefinition<dynamic>>{
    TaskRecord: obx_int.EntityDefinition<TaskRecord>(
      model: _entities[0],
      toOneRelations: (TaskRecord object) => [],
      toManyRelations: (TaskRecord object) => {},
      getId: (TaskRecord object) => object.id,
      setId: (TaskRecord object, int id) => object.id = id,
      objectToFB: (TaskRecord object, fb.Builder fbb) {
        final titleOffset = fbb.writeString(object.title);
        final syncStateOffset = fbb.writeString(object.syncState);
        fbb.startTable(6);
        fbb.addInt64(0, object.id);
        fbb.addOffset(1, titleOffset);
        fbb.addBool(2, object.completed);
        fbb.addInt64(3, object.version);
        fbb.addOffset(4, syncStateOffset);
        fbb.finish(fbb.endTable());
        return object.id;
      },
      objectFromFB: (obx.Store store, ByteData fbData) {
        final buffer = fb.BufferContext(fbData);
        final rootOffset = buffer.derefObject(0);
        return TaskRecord(
          id: const fb.Int64Reader().vTableGet(buffer, rootOffset, 4, 0),
          title: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 6, ''),
          completed: const fb.BoolReader().vTableGet(
            buffer,
            rootOffset,
            8,
            false,
          ),
          version: const fb.Int64Reader().vTableGet(buffer, rootOffset, 10, 0),
          syncState: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 12, ''),
        );
      },
    ),
    OutboxRecord: obx_int.EntityDefinition<OutboxRecord>(
      model: _entities[1],
      toOneRelations: (OutboxRecord object) => [],
      toManyRelations: (OutboxRecord object) => {},
      getId: (OutboxRecord object) => object.id,
      setId: (OutboxRecord object, int id) => object.id = id,
      objectToFB: (OutboxRecord object, fb.Builder fbb) {
        final keyOffset = fbb.writeString(object.idempotencyKey);
        final syncStateOffset = fbb.writeString(object.syncState);
        fbb.startTable(7);
        fbb.addInt64(0, object.id);
        fbb.addOffset(1, keyOffset);
        fbb.addInt64(2, object.taskId);
        fbb.addBool(3, object.completed);
        fbb.addInt64(4, object.attempt);
        fbb.addOffset(5, syncStateOffset);
        fbb.finish(fbb.endTable());
        return object.id;
      },
      objectFromFB: (obx.Store store, ByteData fbData) {
        final buffer = fb.BufferContext(fbData);
        final rootOffset = buffer.derefObject(0);
        return OutboxRecord(
          id: const fb.Int64Reader().vTableGet(buffer, rootOffset, 4, 0),
          idempotencyKey: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 6, ''),
          taskId: const fb.Int64Reader().vTableGet(buffer, rootOffset, 8, 0),
          completed: const fb.BoolReader().vTableGet(
            buffer,
            rootOffset,
            10,
            false,
          ),
          attempt: const fb.Int64Reader().vTableGet(buffer, rootOffset, 12, 0),
          syncState: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 14, ''),
        );
      },
    ),
    SyncJournalRecord: obx_int.EntityDefinition<SyncJournalRecord>(
      model: _entities[2],
      toOneRelations: (SyncJournalRecord object) => [],
      toManyRelations: (SyncJournalRecord object) => {},
      getId: (SyncJournalRecord object) => object.id,
      setId: (SyncJournalRecord object, int id) => object.id = id,
      objectToFB: (SyncJournalRecord object, fb.Builder fbb) {
        final attemptIdOffset = fbb.writeString(object.attemptId);
        final factOffset = fbb.writeString(object.fact);
        final datasetKeyOffset = fbb.writeString(object.datasetKey);
        fbb.startTable(8);
        fbb.addInt64(0, object.id);
        fbb.addOffset(1, attemptIdOffset);
        fbb.addInt64(2, object.sequence);
        fbb.addInt64(3, object.timestampMicros);
        fbb.addOffset(4, factOffset);
        fbb.addOffset(5, datasetKeyOffset);
        fbb.addBool(6, object.hasDatasetKey);
        fbb.finish(fbb.endTable());
        return object.id;
      },
      objectFromFB: (obx.Store store, ByteData fbData) {
        final buffer = fb.BufferContext(fbData);
        final rootOffset = buffer.derefObject(0);
        return SyncJournalRecord(
          id: const fb.Int64Reader().vTableGet(buffer, rootOffset, 4, 0),
          attemptId: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 6, ''),
          sequence: const fb.Int64Reader().vTableGet(buffer, rootOffset, 8, 0),
          timestampMicros: const fb.Int64Reader().vTableGet(
            buffer,
            rootOffset,
            10,
            0,
          ),
          fact: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 12, ''),
          datasetKey: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 14, ''),
          hasDatasetKey: const fb.BoolReader().vTableGet(
            buffer,
            rootOffset,
            16,
            false,
          ),
        );
      },
    ),
    SyncCheckpointRecord: obx_int.EntityDefinition<SyncCheckpointRecord>(
      model: _entities[3],
      toOneRelations: (SyncCheckpointRecord object) => [],
      toManyRelations: (SyncCheckpointRecord object) => {},
      getId: (SyncCheckpointRecord object) => object.id,
      setId: (SyncCheckpointRecord object, int id) => object.id = id,
      objectToFB: (SyncCheckpointRecord object, fb.Builder fbb) {
        final datasetKeyOffset = fbb.writeString(object.datasetKey);
        fbb.startTable(5);
        fbb.addInt64(0, object.id);
        fbb.addOffset(1, datasetKeyOffset);
        fbb.addInt64(2, object.checkpoint);
        fbb.addInt64(3, object.fencingToken);
        fbb.finish(fbb.endTable());
        return object.id;
      },
      objectFromFB: (obx.Store store, ByteData fbData) {
        final buffer = fb.BufferContext(fbData);
        final rootOffset = buffer.derefObject(0);
        return SyncCheckpointRecord(
          id: const fb.Int64Reader().vTableGet(buffer, rootOffset, 4, 0),
          datasetKey: const fb.StringReader(asciiOptimization: true)
              .vTableGet(buffer, rootOffset, 6, ''),
          checkpoint: const fb.Int64Reader().vTableGet(
            buffer,
            rootOffset,
            8,
            0,
          ),
          fencingToken: const fb.Int64Reader().vTableGet(
            buffer,
            rootOffset,
            10,
            0,
          ),
        );
      },
    ),
  };
  return obx_int.ModelDefinition(model, bindings);
}

class TaskRecord_ {
  static final id = obx.QueryIntegerProperty<TaskRecord>(
    _entities[0].properties[0],
  );
  static final title = obx.QueryStringProperty<TaskRecord>(
    _entities[0].properties[1],
  );
  static final completed = obx.QueryBooleanProperty<TaskRecord>(
    _entities[0].properties[2],
  );
  static final version = obx.QueryIntegerProperty<TaskRecord>(
    _entities[0].properties[3],
  );
  static final syncState = obx.QueryStringProperty<TaskRecord>(
    _entities[0].properties[4],
  );
}

class OutboxRecord_ {
  static final id = obx.QueryIntegerProperty<OutboxRecord>(
    _entities[1].properties[0],
  );
  static final idempotencyKey = obx.QueryStringProperty<OutboxRecord>(
    _entities[1].properties[1],
  );
  static final taskId = obx.QueryIntegerProperty<OutboxRecord>(
    _entities[1].properties[2],
  );
  static final completed = obx.QueryBooleanProperty<OutboxRecord>(
    _entities[1].properties[3],
  );
  static final attempt = obx.QueryIntegerProperty<OutboxRecord>(
    _entities[1].properties[4],
  );
  static final syncState = obx.QueryStringProperty<OutboxRecord>(
    _entities[1].properties[5],
  );
}

class SyncJournalRecord_ {
  static final id = obx.QueryIntegerProperty<SyncJournalRecord>(
    _entities[2].properties[0],
  );
  static final attemptId = obx.QueryStringProperty<SyncJournalRecord>(
    _entities[2].properties[1],
  );
  static final sequence = obx.QueryIntegerProperty<SyncJournalRecord>(
    _entities[2].properties[2],
  );
  static final timestampMicros = obx.QueryIntegerProperty<SyncJournalRecord>(
    _entities[2].properties[3],
  );
  static final fact = obx.QueryStringProperty<SyncJournalRecord>(
    _entities[2].properties[4],
  );
  static final datasetKey = obx.QueryStringProperty<SyncJournalRecord>(
    _entities[2].properties[5],
  );
  static final hasDatasetKey = obx.QueryBooleanProperty<SyncJournalRecord>(
    _entities[2].properties[6],
  );
}

class SyncCheckpointRecord_ {
  static final id = obx.QueryIntegerProperty<SyncCheckpointRecord>(
    _entities[3].properties[0],
  );
  static final datasetKey = obx.QueryStringProperty<SyncCheckpointRecord>(
    _entities[3].properties[1],
  );
  static final checkpoint = obx.QueryIntegerProperty<SyncCheckpointRecord>(
    _entities[3].properties[2],
  );
  static final fencingToken = obx.QueryIntegerProperty<SyncCheckpointRecord>(
    _entities[3].properties[3],
  );
}
