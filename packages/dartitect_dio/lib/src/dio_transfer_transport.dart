import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';
import 'package:dio/dio.dart';

import 'cancellation_binding.dart';
import 'result_mapping.dart';

/// Consumer-owned Dio request execution for one transfer chunk.
///
/// The callback owns URL, method, headers, Range/ETag, authentication,
/// idempotency, and body encoding. The adapter does not inspect or retain them.
typedef DioTransferRequest = FutureOr<Response<Object?>> Function(
  Dio dio,
  TransferChunk chunk,
  CancelToken cancellation,
);

/// Consumer-owned durable-commit interpretation for a Dio response.
typedef DioTransferCommitDecoder = TransferCommit Function(
  Response<Object?> response,
  TransferChunk chunk,
);

/// Dio-backed transfer transport without a built-in remote protocol.
///
/// Only [DioException] becomes a payload-free [DioFailure]. Consumer decoder
/// errors and programming defects continue to throw with their original stack.
final class DioTransferTransport implements TransferTransport<DioFailure> {
  /// Creates a borrowing adapter around [dio].
  const DioTransferTransport({
    required this.dio,
    required this.request,
    required this.decodeCommit,
  });

  /// Borrowed Dio client; its provider owns configuration and teardown.
  final Dio dio;

  /// Consumer request policy invoked per chunk.
  final DioTransferRequest request;

  /// Consumer response policy that confirms durable commit.
  final DioTransferCommitDecoder decodeCommit;

  @override
  Future<Result<TransferCommit, DioFailure>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final binding = DioCancellationBinding(
      cancellation,
      reason: 'Dartitect transfer cancelled',
    );
    try {
      return await captureDioException<TransferCommit>(() async {
        final response = await request(dio, chunk, binding.token);
        return decodeCommit(response, chunk);
      });
    } finally {
      binding.dispose();
    }
  }
}
