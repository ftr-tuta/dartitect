import 'package:dartitect/dartitect.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';

void main() async {
  final engine = TransferEngine<StateError>(
    source: _EmptySource(),
    transport: _NoOpTransport(),
    checkpoints: _MemoryCheckpoints(),
  );
  final result = await engine.start('example').done;
  assert(result is Ok<TransferReport>);
  await engine.disposeAsync();
}

final class _EmptySource implements TransferSource {
  @override
  Future<TransferChunk?> read({
    required int offset,
    required int maxBytes,
    required CancellationSignal cancellation,
  }) async => null;
}

final class _NoOpTransport implements TransferTransport<StateError> {
  @override
  Future<Result<TransferCommit, StateError>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  ) async => Ok<TransferCommit>(TransferCommit(chunk.nextOffset));
}

final class _MemoryCheckpoints implements TransferCheckpointStore {
  @override
  Future<TransferCheckpoint?> load(String transferId) async => null;

  @override
  Future<void> save(TransferCheckpoint checkpoint) async {}
}
