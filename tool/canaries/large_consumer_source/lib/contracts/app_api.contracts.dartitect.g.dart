// GENERATED CODE - DO NOT EDIT BY HAND.
// Bounded OpenAPI 3.1 DTOs and Dio endpoint clients.
// ignore_for_file: public_member_api_docs, prefer_single_quotes

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';

const String largeProbeOpenApiSource = "contracts/app_api.json";
const String largeProbeOpenApiVersion = "3.1.0";

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
String getProbeRoute({required String id}) =>
    "/probe/${Uri.encodeComponent(id.toString())}";

/// Declared status union for getProbe.
sealed class GetProbeResponse {
  const GetProbeResponse();
  int get statusCode;
}

/// Declared HTTP 200 response.
final class GetProbeResponseStatus200 extends GetProbeResponse {
  const GetProbeResponseStatus200();
  @override
  int get statusCode => 200;
}

/// Declared HTTP 404 response.
final class GetProbeResponseStatus404 extends GetProbeResponse {
  const GetProbeResponseStatus404();
  @override
  int get statusCode => 404;
}

/// Generated status mappings and endpoint descriptors.
const List<OpenApiEndpointDescriptor> largeProbeEndpoints =
    <OpenApiEndpointDescriptor>[
      OpenApiEndpointDescriptor(
        operationId: "getProbe",
        method: "GET",
        routeTemplate: "/probe/{id}",
        responseTypes: <int, String>{200: "void", 404: "void"},
      ),
    ];

/// Borrowed typed client with explicit per-attempt context.
final class LargeProbeClient {
  const LargeProbeClient(this._client);

  final DioJsonClient _client;

  static final DioEndpoint<GetProbeResponse> _getProbeEndpoint =
      DioEndpoint<GetProbeResponse>(
        method: "GET",
        route: RouteTemplate("/probe/{id}"),
        acceptedStatusCodes: const <int>{200, 404},
        statusDecoders: <int, DioStatusDecoder<GetProbeResponse>>{
          200: (json) => const GetProbeResponseStatus200(),
          404: (json) => const GetProbeResponseStatus404(),
        },
      );

  /// Calls GET /probe/{id}.
  Future<Result<DioResponse<GetProbeResponse>, DioFailure>> getProbe({
    required String id,
    DioRequestContext? context,
  }) => _client.execute<GetProbeResponse>(
    _getProbeEndpoint,
    pathParameters: <String, String>{"id": id.toString()},
    query: <String, Object?>{},
    headers: <String, Object?>{},
    context: context,
  );
}

/// Narrow callable client for only getProbe.
final class GetProbeOperation {
  GetProbeOperation(DioJsonClient client)
    : _contract = LargeProbeClient(client);

  final LargeProbeClient _contract;

  Future<Result<DioResponse<GetProbeResponse>, DioFailure>> call({
    required String id,
    DioRequestContext? context,
  }) => _contract.getProbe(id: id, context: context);
}
