import 'package:dartitect/dartitect_incremental.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';

import '../models.dart';
import '../ports.dart';
import 'codec.dart';
import 'json.dart';

/// A validated HTTP document and its observed byte count, without headers.
final class TitectSyncResponse {
  TitectSyncResponse._(this.document, this.receivedBytes, this._budget);

  final TitectReadBudget? _budget;

  /// Counts bytes while the bounded codec reads the consumer-owned body.
  static Future<TitectSyncResponse> read(
    Stream<List<int>> body, {
    required TitectSyncCodec codec,
    TitectReadBudget? budget,
  }) async {
    var count = 0;
    final document = await codec.read(
      body.map((chunk) {
        budget?.admit(chunk.length);
        count += chunk.length;
        return chunk;
      }),
    );
    return TitectSyncResponse._(document, count, budget);
  }

  /// One of the eleven validated document kinds.
  final TitectSyncDocument document;

  /// Actual bytes received; never taken from Content-Length.
  final int receivedBytes;
}

/// Finite byte admission shared across page reads and retries in one traversal.
///
/// Rejected chunks are not retained. Bytes admitted before failed parsing remain
/// charged. This value owns no stream or transport.
final class TitectReadBudget {
  /// Creates a positive cumulative byte limit.
  TitectReadBudget(this.maximumBytes) {
    if (maximumBytes <= 0) throw ArgumentError.value(maximumBytes);
  }

  /// Maximum bytes admitted for parsing during this traversal.
  final int maximumBytes;
  var _admittedBytes = 0;

  /// Bytes already admitted, including failed parsing attempts.
  int get admittedBytes => _admittedBytes;

  /// Remaining bytes; retries never replenish this amount.
  int get remainingBytes => maximumBytes - _admittedBytes;

  /// Charges a chunk before any parser retains it.
  void admit(int bytes) {
    if (bytes < 0) throw ArgumentError.value(bytes);
    if (bytes > remainingBytes) {
      throw const TitectWireException(TitectWireProblem.limit);
    }
    _admittedBytes += bytes;
  }
}

/// Why an incremental Titect binding stopped before its next checkpoint.
enum TitectSyncStop {
  /// A consumer transport or transaction returned its expected failure.
  consumer,

  /// A bounded codec rejected a response.
  wire,

  /// A reset or generation-mismatch document needs consumer policy.
  reset,

  /// The response kind, dataset, or generation differs from the selected run.
  selection,

  /// The finite page or cumulative received-byte bound was reached.
  limit,

  /// The current lease could not prove authority before application.
  authority,
}

/// Typed binding failure preserving consumer failures and protocol decisions.
final class TitectSyncFailure<F extends Object> {
  const TitectSyncFailure._(
    this.reason, {
    this.failure,
    this.wire,
    this.document,
  });

  /// Stable stopping category.
  final TitectSyncStop reason;

  /// Original expected transport or application failure, when present.
  final F? failure;

  /// Payload-free codec failure, when present.
  final TitectWireException? wire;

  /// Reset or mismatched selection for explicit consumer recovery policy.
  final TitectSyncDocument? document;
}

/// Binds a selected Titect dataset to existing incremental sync and checkpoints.
///
/// The binding borrows every callback and resilience resource. [fetch] performs
/// one transport attempt; this binding owns its retry loop, with the same
/// [retryBudget] used by participating refresh, reconnect, and outbox leaves.
/// Transaction failures never replay automatically. [apply] must atomically
/// validate persistent session/fencing authority, apply data and an application
/// receipt, then return a consumer checkpoint. The engine confirms that
/// checkpoint before pulling another page. A local authority check alone does
/// not fence a database writer. Cryptographic verification, authorization,
/// mutation reconciliation, schemas and conflicts remain consumer policy.
SyncDataset<K, C, TitectSyncFailure<F>>
titectSyncDataset<K, C, F extends Object>({
  required K key,
  required String datasetId,
  required BigInt generation,
  required String? Function(C? checkpoint) cursorOf,
  required Future<Result<TitectSyncResponse, F>> Function(
    SyncDatasetContext<K, C> context,
    String? cursor,
    int attempt,
    CancellationSignal cancellation,
    TitectReadBudget readBudget,
  )
  fetch,
  required Future<Result<C, F>> Function(
    SyncDatasetContext<K, C> context,
    TitectPage page,
  )
  apply,
  required RetryExecutor retryExecutor,
  required RetryPolicy<F> retryPolicy,
  required RetryBudget retryBudget,
  required int maxPages,
  required int maxReceivedBytes,
  SyncClock clock = const SystemSyncClock(),
}) {
  if (maxPages <= 0 ||
      maxReceivedBytes <= 0 ||
      generation.isNegative ||
      datasetId.isEmpty) {
    throw ArgumentError('Invalid Titect dataset selection or bounds.');
  }
  return SyncDataset<K, C, TitectSyncFailure<F>>.incremental(
    key: key,
    synchronize: (context) => IncrementalOperation.async(
      () async* {
        var cursor = cursorOf(context.checkpoint);
        final readBudget = TitectReadBudget(maxReceivedBytes);
        void check() {
          context.cancellation.throwIfCancelled();
          final deadline = context.deadline;
          if (deadline != null && !clock.now().isBefore(deadline)) {
            throw OperationDeadlineExceededException(deadline);
          }
        }

        for (var index = 0; index < maxPages; index++) {
          check();
          if (readBudget.remainingBytes == 0) {
            yield Err(
              TitectSyncFailure<F>._(TitectSyncStop.limit),
              StackTrace.current,
            );
            return;
          }
          Result<TitectSyncResponse, F> fetched;
          try {
            fetched = await retryExecutor.execute<TitectSyncResponse, F>(
              operation: (attempt, cancellation) =>
                  fetch(context, cursor, attempt, cancellation, readBudget),
              policy: retryPolicy,
              cancellation: context.cancellation,
              deadline: context.deadline,
              budget: retryBudget,
            );
          } on TitectWireException catch (failure, stackTrace) {
            yield Err(
              TitectSyncFailure<F>._(TitectSyncStop.wire, wire: failure),
              stackTrace,
            );
            return;
          }
          check();
          if (fetched case Err<Object>(:final failure, :final stackTrace)) {
            yield Err(
              TitectSyncFailure<F>._(
                TitectSyncStop.consumer,
                failure: failure as F,
              ),
              stackTrace,
            );
            return;
          }
          final response = (fetched as Ok<TitectSyncResponse>).value;
          if (!identical(response._budget, readBudget)) {
            throw StateError(
              'Pass the supplied read budget to TitectSyncResponse.read.',
            );
          }
          final document = response.document;
          if (document is TitectResetRequired ||
              document is TitectGenerationMismatch) {
            yield Err(
              TitectSyncFailure<F>._(TitectSyncStop.reset, document: document),
              StackTrace.current,
            );
            return;
          }
          if (document is! TitectPage ||
              document.datasetId != datasetId ||
              document.generation != generation) {
            yield Err(
              TitectSyncFailure<F>._(
                TitectSyncStop.selection,
                document: document,
              ),
              StackTrace.current,
            );
            return;
          }
          if (context.authority != null &&
              !await context.authority!.ensureAuthority()) {
            yield Err(
              TitectSyncFailure<F>._(TitectSyncStop.authority),
              StackTrace.current,
            );
            return;
          }
          check();
          final committed = await apply(context, document);
          check();
          if (committed case Err<Object>(:final failure, :final stackTrace)) {
            yield Err(
              TitectSyncFailure<F>._(
                TitectSyncStop.consumer,
                failure: failure as F,
              ),
              stackTrace,
            );
            return;
          }
          final checkpoint = (committed as Ok<C>).value;
          yield Ok(SyncDatasetOutcome<C>.checkpoint(checkpoint));
          cursor = document.nextCursor;
          if (cursor == null) return;
        }
        yield Err(
          TitectSyncFailure<F>._(TitectSyncStop.limit),
          StackTrace.current,
        );
      },
      limits: IncrementalLimits(
        maxEmissions: maxPages + 1,
        maxWeight: maxPages + 1,
      ),
    ),
  );
}
