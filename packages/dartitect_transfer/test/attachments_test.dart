import 'package:dartitect/dartitect.dart';
import 'package:dartitect_transfer/dartitect_attachments.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';
import 'package:test/test.dart';

void main() {
  test(
    'staging commits temp metadata plus outbox and upload resumes',
    () async {
      final files = _Files();
      final metadata = _Metadata();
      final coordinator = AttachmentCoordinator<_Failure>(
        files: files,
        metadata: metadata,
        createTransferGraph: (attachment) => ResourceTransaction.create((tx) {
          final engine = TransferEngine<_Failure>(
            source: _Source(),
            transport: _Transport(),
            checkpoints: _Checkpoints(),
          );
          tx.own(engine, (value) => value.disposeAsync());
          return engine;
        }),
      );

      final staged = await coordinator.stage(
        attachmentId: 'attachment-1',
        selection: AttachmentSelection(
          source: 'picker-ref',
          mediaType: 'image/png',
        ),
      );
      final attachment = (staged as Ok<AttachmentRecord>).value;
      expect(attachment.status, AttachmentStatus.pending);
      expect(metadata.statuses, <AttachmentStatus>[AttachmentStatus.pending]);

      final run = coordinator.upload(attachment);
      expect(run.pause(), isTrue);
      expect(run.resume(), isTrue);
      final uploaded = await run.done;
      expect(
        (uploaded as Ok<AttachmentRecord>).value.status,
        AttachmentStatus.uploaded,
      );
      expect(metadata.statuses, <AttachmentStatus>[
        AttachmentStatus.pending,
        AttachmentStatus.uploading,
        AttachmentStatus.uploaded,
      ]);
      await coordinator.disposeAsync();
    },
  );

  test('failed atomic stage discards its temporary file', () async {
    final files = _Files();
    final metadata = _Metadata()..failStage = true;
    final coordinator = AttachmentCoordinator<_Failure>(
      files: files,
      metadata: metadata,
      createTransferGraph: (_) => throw UnimplementedError(),
    );

    expect(
      await coordinator.stage(
        attachmentId: 'attachment-1',
        selection: AttachmentSelection(
          source: 'picker-ref',
          mediaType: 'image/png',
        ),
      ),
      isA<Err<_Failure>>(),
    );
    expect(files.discarded, <String>['temporary-ref']);
    await coordinator.disposeAsync();
  });
}

final class _Failure {
  const _Failure();
}

final class _Files implements AttachmentFilePort<_Failure> {
  final List<String> discarded = <String>[];

  @override
  Future<Result<AttachmentTemporaryFile, _Failure>> createTemporary(
    AttachmentSelection selection,
    CancellationSignal cancellation,
  ) async => Ok<AttachmentTemporaryFile>(
    AttachmentTemporaryFile(reference: 'temporary-ref', byteLength: 3),
  );

  @override
  Future<void> discardTemporary(String reference) async {
    discarded.add(reference);
  }
}

final class _Metadata implements AttachmentMetadataOutboxStore<_Failure> {
  final List<AttachmentStatus> statuses = <AttachmentStatus>[];
  var failStage = false;

  @override
  Future<Result<AttachmentRecord, _Failure>> stage(
    AttachmentRecord attachment,
    CancellationSignal cancellation,
  ) async {
    if (failStage) return Err<_Failure>(const _Failure(), StackTrace.current);
    statuses.add(attachment.status);
    return Ok<AttachmentRecord>(attachment);
  }

  @override
  Future<Result<AttachmentRecord, _Failure>> transition(
    AttachmentRecord attachment,
    AttachmentStatus status,
    CancellationSignal cancellation,
  ) async {
    statuses.add(status);
    return Ok<AttachmentRecord>(
      AttachmentRecord(
        attachmentId: attachment.attachmentId,
        temporaryFile: attachment.temporaryFile,
        mediaType: attachment.mediaType,
        byteLength: attachment.byteLength,
        revision: attachment.revision + 1,
        status: status,
      ),
    );
  }
}

final class _Source implements TransferSource {
  @override
  Future<TransferChunk?> read({
    required int offset,
    required int maxBytes,
    required CancellationSignal cancellation,
  }) async =>
      offset == 0 ? TransferChunk(offset: 0, bytes: <int>[1, 2, 3]) : null;
}

final class _Transport implements TransferTransport<_Failure> {
  @override
  Future<Result<TransferCommit, _Failure>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  ) async => Ok<TransferCommit>(TransferCommit(chunk.nextOffset));
}

final class _Checkpoints implements TransferCheckpointStore {
  TransferCheckpoint? value;

  @override
  Future<TransferCheckpoint?> load(String transferId) async => value;

  @override
  Future<void> save(TransferCheckpoint checkpoint) async => value = checkpoint;
}
