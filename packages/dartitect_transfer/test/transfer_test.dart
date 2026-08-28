import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';
import 'package:test/test.dart';

void main() {
  test('checkpoint advances only after durable chunk commit', () async {
    final events = <String>[];
    final checkpoints = _Checkpoints(events);
    final transport = _Transport(events);
    final progress = BoundedProgressReporter<TransferProgress>();
    final engine = TransferEngine<_Failure>(
      source: _BytesSource(<int>[1, 2, 3, 4, 5]),
      transport: transport,
      checkpoints: checkpoints,
      chunkSize: 2,
      progress: progress,
    );

    final result = await engine.start('asset').done;
    expect((result as Ok<TransferReport>).value.committedBytes, 5);
    expect(events, <String>[
      'commit:2',
      'save:2',
      'commit:4',
      'save:4',
      'commit:5',
      'save:5',
    ]);
    expect(progress.events.last.payload.phase, TransferProgressPhase.completed);
    await engine.disposeAsync();
  });

  test('resume begins at the last durable checkpoint', () async {
    final checkpoints = _Checkpoints(<String>[])
      ..value = TransferCheckpoint(
        transferId: 'asset',
        committedOffset: 2,
        revision: 4,
      );
    final source = _BytesSource(<int>[1, 2, 3, 4]);
    final engine = TransferEngine<_Failure>(
      source: source,
      transport: _Transport(<String>[]),
      checkpoints: checkpoints,
      chunkSize: 2,
    );

    final result = await engine.start('asset').done as Ok<TransferReport>;
    expect(source.offsets.first, 2);
    expect(result.value.checkpointRevision, 5);
    await engine.disposeAsync();
  });

  test('pause blocks the next read and resume releases it', () async {
    final source = _GateSource();
    final engine = TransferEngine<_Failure>(
      source: source,
      transport: _Transport(<String>[]),
      checkpoints: _Checkpoints(<String>[]),
    );
    final run = engine.start('asset');
    await source.firstRead.future;
    expect(run.pause(), isTrue);
    source.release.complete();
    await Future<void>.delayed(Duration.zero);
    expect(source.readCount, 1);
    expect(run.resume(), isTrue);
    expect(await run.done, isA<Ok<TransferReport>>());
    await engine.disposeAsync();
  });

  test('expected transport failure does not persist a checkpoint', () async {
    final checkpoints = _Checkpoints(<String>[]);
    final engine = TransferEngine<_Failure>(
      source: _BytesSource(<int>[1]),
      transport: _FailingTransport(),
      checkpoints: checkpoints,
    );
    expect(await engine.start('asset').done, isA<Err<_Failure>>());
    expect(checkpoints.value, isNull);
    await engine.disposeAsync();
  });

  test(
    'checksum mismatch fails before transport or checkpoint writes',
    () async {
      final checkpoints = _Checkpoints(<String>[]);
      final transport = _Transport(<String>[]);
      final engine = TransferEngine<_Failure>(
        source: _ChecksummedSource(),
        transport: transport,
        checkpoints: checkpoints,
        checksumVerifier: _RejectingVerifier(),
      );
      await expectLater(
        engine.start('asset').done,
        throwsA(isA<TransferProtocolException>()),
      );
      expect(transport.events, isEmpty);
      expect(checkpoints.value, isNull);
      await engine.disposeAsync();
    },
  );

  test('cancel wakes a paused run and drains disposal', () async {
    final source = _GateSource();
    final engine = TransferEngine<_Failure>(
      source: source,
      transport: _Transport(<String>[]),
      checkpoints: _Checkpoints(<String>[]),
    );
    final run = engine.start('asset');
    await source.firstRead.future;
    run.pause();
    source.release.complete();
    await Future<void>.delayed(Duration.zero);
    expect(run.cancel('test'), isTrue);
    await expectLater(run.done, throwsA(isA<CancellationException>()));
    await engine.disposeAsync();
  });
}

final class _Failure implements Exception {}

final class _BytesSource implements TransferSource {
  _BytesSource(this.bytes);

  final List<int> bytes;
  final List<int> offsets = <int>[];

  @override
  Future<TransferChunk?> read({
    required int offset,
    required int maxBytes,
    required CancellationSignal cancellation,
  }) async {
    offsets.add(offset);
    if (offset == bytes.length) return null;
    final end = (offset + maxBytes).clamp(0, bytes.length);
    return TransferChunk(offset: offset, bytes: bytes.sublist(offset, end));
  }
}

final class _GateSource implements TransferSource {
  final Completer<void> firstRead = Completer<void>();
  final Completer<void> release = Completer<void>();
  var readCount = 0;

  @override
  Future<TransferChunk?> read({
    required int offset,
    required int maxBytes,
    required CancellationSignal cancellation,
  }) async {
    readCount += 1;
    if (readCount > 1) return null;
    firstRead.complete();
    await release.future;
    return TransferChunk(offset: offset, bytes: <int>[1]);
  }
}

final class _ChecksummedSource implements TransferSource {
  @override
  Future<TransferChunk?> read({
    required int offset,
    required int maxBytes,
    required CancellationSignal cancellation,
  }) async => offset == 0
      ? TransferChunk(
          offset: 0,
          bytes: <int>[1],
          checksum: TransferChecksum(
            algorithm: TransferChecksumAlgorithm.sha256,
            value: <int>[2],
          ),
        )
      : null;
}

final class _RejectingVerifier implements TransferChecksumVerifier {
  @override
  bool verify(List<int> bytes, TransferChecksum expected) => false;
}

final class _Transport implements TransferTransport<_Failure> {
  _Transport(this.events);

  final List<String> events;

  @override
  Future<Result<TransferCommit, _Failure>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  ) async {
    events.add('commit:${chunk.nextOffset}');
    return Ok<TransferCommit>(TransferCommit(chunk.nextOffset));
  }
}

final class _FailingTransport implements TransferTransport<_Failure> {
  @override
  Future<Result<TransferCommit, _Failure>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  ) async => Err<_Failure>(_Failure(), StackTrace.current);
}

final class _Checkpoints implements TransferCheckpointStore {
  _Checkpoints(this.events);

  final List<String> events;
  TransferCheckpoint? value;

  @override
  Future<TransferCheckpoint?> load(String transferId) async => value;

  @override
  Future<void> save(TransferCheckpoint checkpoint) async {
    events.add('save:${checkpoint.committedOffset}');
    value = checkpoint;
  }
}
