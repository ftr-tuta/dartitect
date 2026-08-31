// GENERATED CODE - DO NOT EDIT BY HAND.
// Bounded OpenAPI 3.1 DTOs and Dio endpoint clients.
// ignore_for_file: public_member_api_docs, prefer_single_quotes

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';

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

/// Declared status union for getTask.
sealed class GetTaskResponse {
  const GetTaskResponse();
  int get statusCode;
}

/// Declared HTTP 200 response.
final class GetTaskResponseStatus200 extends GetTaskResponse {
  const GetTaskResponseStatus200(this.payload);
  final TaskDto payload;
  @override
  int get statusCode => 200;
}

/// Declared HTTP 404 response.
final class GetTaskResponseStatus404 extends GetTaskResponse {
  const GetTaskResponseStatus404(this.payload);
  final ApiErrorDto payload;
  @override
  int get statusCode => 404;
}

/// Expands the local OpenAPI route template.
String updateTaskRoute({required String id}) =>
    "/tasks/${Uri.encodeComponent(id.toString())}";

/// Declared status union for updateTask.
sealed class UpdateTaskResponse {
  const UpdateTaskResponse();
  int get statusCode;
}

/// Declared HTTP 204 response.
final class UpdateTaskResponseStatus204 extends UpdateTaskResponse {
  const UpdateTaskResponseStatus204();
  @override
  int get statusCode => 204;
}

/// Declared HTTP 409 response.
final class UpdateTaskResponseStatus409 extends UpdateTaskResponse {
  const UpdateTaskResponseStatus409(this.payload);
  final ApiErrorDto payload;
  @override
  int get statusCode => 409;
}

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

/// Borrowed typed client with explicit per-attempt context.
final class TaskContractCanaryClient {
  const TaskContractCanaryClient(this._client);

  final DioJsonClient _client;

  static final DioEndpoint<GetTaskResponse> _getTaskEndpoint =
      DioEndpoint<GetTaskResponse>(
        method: "GET",
        route: RouteTemplate("/tasks/{id}"),
        acceptedStatusCodes: const <int>{200, 404},
        statusDecoders: <int, DioStatusDecoder<GetTaskResponse>>{
          200: (json) => GetTaskResponseStatus200(
            TaskDto.fromJson((json! as Map).cast<String, Object?>()),
          ),
          404: (json) => GetTaskResponseStatus404(
            ApiErrorDto.fromJson((json! as Map).cast<String, Object?>()),
          ),
        },
      );

  /// Calls GET /tasks/{id}.
  Future<Result<DioResponse<GetTaskResponse>, DioFailure>> getTask({
    required String id,
    bool? includeHistory,
    String? xTrace,
    DioRequestContext? context,
  }) => _client.execute<GetTaskResponse>(
    _getTaskEndpoint,
    pathParameters: <String, String>{"id": id.toString()},
    query: <String, Object?>{
      if (includeHistory != null) "include_history": includeHistory,
    },
    headers: <String, Object?>{if (xTrace != null) "X-Trace": xTrace},
    context: context,
  );

  static final DioEndpoint<UpdateTaskResponse> _updateTaskEndpoint =
      DioEndpoint<UpdateTaskResponse>(
        method: "PUT",
        route: RouteTemplate("/tasks/{id}"),
        acceptedStatusCodes: const <int>{204, 409},
        statusDecoders: <int, DioStatusDecoder<UpdateTaskResponse>>{
          204: (json) => const UpdateTaskResponseStatus204(),
          409: (json) => UpdateTaskResponseStatus409(
            ApiErrorDto.fromJson((json! as Map).cast<String, Object?>()),
          ),
        },
      );

  /// Calls PUT /tasks/{id}.
  Future<Result<DioResponse<UpdateTaskResponse>, DioFailure>> updateTask({
    required String id,
    required TaskUpdateDto body,
    DioRequestContext? context,
  }) => _client.execute<UpdateTaskResponse>(
    _updateTaskEndpoint,
    pathParameters: <String, String>{"id": id.toString()},
    query: <String, Object?>{},
    headers: <String, Object?>{},
    jsonBody: body.toJson(),
    context: context,
  );
}

/// Narrow callable client for only getTask.
final class GetTaskOperation {
  GetTaskOperation(DioJsonClient client)
    : _contract = TaskContractCanaryClient(client);

  final TaskContractCanaryClient _contract;

  Future<Result<DioResponse<GetTaskResponse>, DioFailure>> call({
    required String id,
    bool? includeHistory,
    String? xTrace,
    DioRequestContext? context,
  }) => _contract.getTask(
    id: id,
    includeHistory: includeHistory,
    xTrace: xTrace,
    context: context,
  );
}

/// Narrow callable client for only updateTask.
final class UpdateTaskOperation {
  UpdateTaskOperation(DioJsonClient client)
    : _contract = TaskContractCanaryClient(client);

  final TaskContractCanaryClient _contract;

  Future<Result<DioResponse<UpdateTaskResponse>, DioFailure>> call({
    required String id,
    required TaskUpdateDto body,
    DioRequestContext? context,
  }) => _contract.updateTask(id: id, body: body, context: context);
}
