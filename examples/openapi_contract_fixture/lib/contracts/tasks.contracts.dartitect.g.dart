// GENERATED CODE - DO NOT EDIT BY HAND.
// Bounded OpenAPI 3.1 DTOs and Dio endpoint clients.
// ignore_for_file: public_member_api_docs, prefer_single_quotes

import 'package:dio/dio.dart';

const String taskContractCanaryOpenApiSource = "contracts/tasks.yaml";
const String taskContractCanaryOpenApiVersion = "3.1.1";

/// Generated JSON DTO; semantic domain mapping stays consumer-owned.
final class const ApiErrorDto({
  required final String code,
  required final String message,
}) {
  this;

  factory ApiErrorDto.fromJson(Map<String, Object?> json) => ApiErrorDto(
    code: json["code"]! as String,
    message: json["message"]! as String,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    "code": code,
    "message": message,
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? apiErrorOpenApiFixture = <String, Object?>{
  "code": "fixture",
  "message": "fixture",
};

/// Generated JSON DTO; semantic domain mapping stays consumer-owned.
final class const BaseTaskDto({
  required final String id,
  required final int version,
}) {
  this;

  factory BaseTaskDto.fromJson(Map<String, Object?> json) =>
      BaseTaskDto(id: json["id"]! as String, version: json["version"]! as int);

  Map<String, Object?> toJson() => <String, Object?>{
    "id": id,
    "version": version,
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? baseTaskOpenApiFixture = <String, Object?>{
  "id": "fixture",
  "version": 0,
};

/// Generated JSON DTO; semantic domain mapping stays consumer-owned.
final class const CatDto({
  required final String kind,
  required final int lives,
}) {
  this;

  factory CatDto.fromJson(Map<String, Object?> json) =>
      CatDto(kind: json["kind"]! as String, lives: json["lives"]! as int);

  Map<String, Object?> toJson() => <String, Object?>{
    "kind": kind,
    "lives": lives,
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? catOpenApiFixture = <String, Object?>{
  "kind": "fixture",
  "lives": 0,
};

/// Generated JSON DTO; semantic domain mapping stays consumer-owned.
final class const DogDto({
  required final bool good,
  required final String kind,
}) {
  this;

  factory DogDto.fromJson(Map<String, Object?> json) =>
      DogDto(good: json["good"]! as bool, kind: json["kind"]! as String);

  Map<String, Object?> toJson() => <String, Object?>{
    "good": good,
    "kind": kind,
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? dogOpenApiFixture = <String, Object?>{
  "kind": "fixture",
  "good": false,
};

/// Generated JSON DTO; semantic domain mapping stays consumer-owned.
final class const NodeDto({required final String id, final NodeDto? next}) {
  this;

  factory NodeDto.fromJson(Map<String, Object?> json) => NodeDto(
    id: json["id"]! as String,
    next: json["next"] == null
        ? null
        : NodeDto.fromJson((json["next"]! as Map).cast<String, Object?>()),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    "id": id,
    if (next != null) "next": next!.toJson(),
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? nodeOpenApiFixture = <String, Object?>{"id": "fixture"};

/// Generated discriminated oneOf value.
final class const PetDto({required final Object value}) {
  this;

  factory PetDto.fromJson(Map<String, Object?> json) {
    return switch (json["kind"]) {
      "cat" => PetDto(value: CatDto.fromJson(json)),
      "dog" => PetDto(value: DogDto.fromJson(json)),
      final value => throw FormatException(
        'Unknown PetDto discriminator: $value',
      ),
    };
  }

  Map<String, Object?> toJson() => switch (value) {
    final CatDto value => value.toJson(),
    final DogDto value => value.toJson(),
    _ => throw StateError('Unsupported PetDto runtime value.'),
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? petOpenApiFixture = <String, Object?>{
  "kind": "fixture",
  "lives": 0,
};

/// Generated bounded OpenAPI enum.
enum StatusDto {
  open,
  completed;

  factory StatusDto.fromJson(Object? value) => switch (value) {
    "open" => StatusDto.open,
    "completed" => StatusDto.completed,
    _ => throw FormatException('Unknown StatusDto value: $value'),
  };

  Object toJson() => switch (this) {
    StatusDto.open => "open",
    StatusDto.completed => "completed",
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? statusOpenApiFixture = "open";

/// Generated JSON DTO; semantic domain mapping stays consumer-owned.
final class const TaskDto({
  required final String id,
  final String? note,
  required final StatusDto status,
  required final String title,
  required final int version,
}) {
  this;

  factory TaskDto.fromJson(Map<String, Object?> json) => TaskDto(
    id: json["id"]! as String,
    note: json["note"] == null ? null : json["note"]! as String,
    status: StatusDto.fromJson(json["status"]),
    title: json["title"]! as String,
    version: json["version"]! as int,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    "id": id,
    if (note != null) "note": note,
    "status": status.toJson(),
    "title": title,
    "version": version,
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? taskOpenApiFixture = <String, Object?>{
  "id": "fixture",
  "version": 0,
  "title": "fixture",
  "status": "open",
};

/// Generated scalar contract alias for "TaskList".
typedef TaskListDto = List<TaskDto>;

/// Deterministic bounded JSON fixture for contract tests.
const Object? taskListOpenApiFixture = const <Object?>[];

/// Generated JSON DTO; semantic domain mapping stays consumer-owned.
final class const TaskUpdateDto({
  required final int expectedVersion,
  required final String title,
}) {
  this;

  factory TaskUpdateDto.fromJson(Map<String, Object?> json) => TaskUpdateDto(
    expectedVersion: json["expectedVersion"]! as int,
    title: json["title"]! as String,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    "expectedVersion": expectedVersion,
    "title": title,
  };
}

/// Deterministic bounded JSON fixture for contract tests.
const Object? taskUpdateOpenApiFixture = <String, Object?>{
  "title": "fixture",
  "expectedVersion": 0,
};

/// Generated endpoint metadata without automatic security execution.
final class const OpenApiEndpointDescriptor({
  required final String operationId,
  required final String method,
  required final String routeTemplate,
  required final Map<int, String> responseTypes,
}) {
  this;
}

/// Expands the local OpenAPI route template.
String getTaskRoute({required String id}) =>
    "/tasks/${Uri.encodeComponent(id.toString())}";

/// Expands the local OpenAPI route template.
String updateTaskRoute({required String id}) =>
    "/tasks/${Uri.encodeComponent(id.toString())}";

/// Generated status mappings and endpoint descriptors.
const List<OpenApiEndpointDescriptor> taskContractCanaryEndpoints =
    <OpenApiEndpointDescriptor>[
      OpenApiEndpointDescriptor(
        operationId: "getTask",
        method: "GET",
        routeTemplate: "/tasks/{id}",
        responseTypes: <int, String>{200: "TaskDto", 404: "ApiErrorDto"},
      ),
      OpenApiEndpointDescriptor(
        operationId: "updateTask",
        method: "PUT",
        routeTemplate: "/tasks/{id}",
        responseTypes: <int, String>{204: "void", 409: "ApiErrorDto"},
      ),
    ];

/// Borrowed-Dio client; credentials remain in their explicit pipeline.
final class TaskContractCanaryClient {
  const TaskContractCanaryClient(this._dio);

  final Dio _dio;

  /// Calls GET /tasks/{id}.
  Future<Response<Object?>> getTask({
    required String id,
    bool? includeHistory,
    String? xTrace,
  }) => _dio.request<Object?>(
    getTaskRoute(id: id),
    queryParameters: <String, Object?>{
      if (includeHistory != null) "include_history": includeHistory,
    },
    options: Options(
      method: "GET",
      headers: <String, Object?>{if (xTrace != null) "X-Trace": xTrace},
    ),
  );

  /// Calls PUT /tasks/{id}.
  Future<Response<Object?>> updateTask({
    required String id,
    required TaskUpdateDto body,
  }) => _dio.request<Object?>(
    updateTaskRoute(id: id),
    queryParameters: <String, Object?>{},
    options: Options(method: "PUT", headers: <String, Object?>{}),
    data: body.toJson(),
  );
}
