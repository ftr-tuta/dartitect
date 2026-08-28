import 'dart:async';
import 'dart:collection';

import 'package:dartitect/dartitect.dart';

/// Supported checksum identifiers carried by a chunk.
enum TransferChecksumAlgorithm {
  /// IEEE CRC-32.
  crc32,

  /// SHA-256.
  sha256,
}

/// Immutable expected checksum for one chunk.
final class TransferChecksum {
  /// Creates a non-empty encoded checksum.
  TransferChecksum({required this.algorithm, required List<int> value})
    : value = UnmodifiableListView<int>(List<int>.of(value)) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Must not be empty.');
    }
  }

  /// Algorithm used to produce [value].
  final TransferChecksumAlgorithm algorithm;

  /// Consumer/provider-neutral encoded checksum bytes.
  final List<int> value;
}

/// Immutable contiguous transfer chunk.
final class TransferChunk {
  /// Creates a non-empty chunk beginning at [offset].
  TransferChunk({required this.offset, required List<int> bytes, this.checksum})
    : bytes = UnmodifiableListView<int>(List<int>.of(bytes)) {
    if (offset < 0 ||
        bytes.isEmpty ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Transfer chunk offset or bytes are invalid.');
    }
  }

  /// Inclusive zero-based byte offset.
  final int offset;

  /// Immutable byte payload delivered only to the configured transport.
  final List<int> bytes;

  /// Optional checksum verified before transport.
  final TransferChecksum? checksum;

  /// Exclusive end offset.
  int get nextOffset => offset + bytes.length;
}

/// Durable resume point for one transfer.
final class TransferCheckpoint {
  /// Creates a checkpoint at [committedOffset].
  TransferCheckpoint({
    required this.transferId,
    required this.committedOffset,
    required this.revision,
  }) {
    if (transferId.trim().isEmpty || committedOffset < 0 || revision < 0) {
      throw ArgumentError('Transfer checkpoint fields are invalid.');
    }
  }

  /// Consumer-safe transfer identity.
  final String transferId;

  /// Exclusive offset durably committed by the transport.
  final int committedOffset;

  /// Monotonic local checkpoint revision.
  final int revision;
}

/// Consumer-owned durable checkpoint storage.
abstract interface class TransferCheckpointStore {
  /// Loads the last durable checkpoint, or returns `null` for a new transfer.
  Future<TransferCheckpoint?> load(String transferId);

  /// Persists a checkpoint after the matching chunk is durably committed.
  Future<void> save(TransferCheckpoint checkpoint);
}

/// Reads chunks from a source starting at consumer-approved offsets.
abstract interface class TransferSource {
  /// Returns the next chunk, or `null` at end of source.
  Future<TransferChunk?> read({
    required int offset,
    required int maxBytes,
    required CancellationSignal cancellation,
  });
}

/// Durable acknowledgement from a sink or remote transport.
final class TransferCommit {
  /// Creates an acknowledgement for an exclusive durable offset.
  const TransferCommit(this.durableOffset) : assert(durableOffset >= 0);

  /// Exclusive offset durably committed by the destination.
  final int durableOffset;
}

/// Receives chunks into a consumer-owned durable destination.
abstract interface class TransferSink<F extends Object> {
  /// Commits [chunk] durably before returning a successful acknowledgement.
  Future<Result<TransferCommit, F>> commit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  );
}

/// Transports chunks without defining a universal remote protocol.
abstract interface class TransferTransport<F extends Object> {
  /// Commits [chunk] and reports the destination's durable offset.
  Future<Result<TransferCommit, F>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  );
}

/// Adapts a local or consumer-specific [TransferSink] to a transport.
final class SinkTransferTransport<F extends Object>
    implements TransferTransport<F> {
  /// Creates a borrowing adapter around [sink].
  const SinkTransferTransport(this.sink);

  /// Borrowed sink; its provider owns teardown.
  final TransferSink<F> sink;

  @override
  Future<Result<TransferCommit, F>> transmit(
    TransferChunk chunk,
    CancellationSignal cancellation,
  ) => sink.commit(chunk, cancellation);
}

/// Consumer-injected checksum verification.
abstract interface class TransferChecksumVerifier {
  /// Returns whether [bytes] match [expected].
  bool verify(List<int> bytes, TransferChecksum expected);
}

/// Typed progress phase without byte payloads or remote identifiers.
enum TransferProgressPhase {
  /// A run was admitted.
  started,

  /// A source chunk was read and validated.
  chunkRead,

  /// A chunk was durably committed and checkpointed.
  chunkCommitted,

  /// Execution is waiting for an explicit resume.
  paused,

  /// The source reached its end.
  completed,
}

/// Payload-free progress counters for one transfer execution.
final class TransferProgress {
  /// Creates a progress snapshot.
  const TransferProgress({
    required this.phase,
    required this.committedBytes,
    required this.chunkCount,
  });

  /// Current closed phase.
  final TransferProgressPhase phase;

  /// Total bytes durably committed from offset zero.
  final int committedBytes;

  /// Number of chunks committed by this run.
  final int chunkCount;
}

/// Successful transfer report.
final class TransferReport {
  /// Creates a terminal report.
  const TransferReport({
    required this.transferId,
    required this.committedBytes,
    required this.chunkCount,
    required this.checkpointRevision,
  });

  /// Consumer-safe transfer identity.
  final String transferId;

  /// Final exclusive durable offset.
  final int committedBytes;

  /// Chunks committed during this run.
  final int chunkCount;

  /// Final local checkpoint revision.
  final int checkpointRevision;
}

/// Integrity or protocol invariant failure, never an expected remote failure.
final class TransferProtocolException implements Exception {
  /// Creates an invariant failure with a static [message].
  const TransferProtocolException(this.message);

  /// Static explanation without remote payload data.
  final String message;

  @override
  String toString() => 'TransferProtocolException($message)';
}

/// Running transfer plus cooperative pause, resume, and cancellation controls.
final class TransferRun<F extends Object> {
  TransferRun._(this.done, this._control);

  /// Terminal success or expected typed transport failure.
  final Future<Result<TransferReport, F>> done;

  final _TransferControl _control;

  /// Whether the run is currently paused.
  bool get isPaused => _control.isPaused;

  /// Prevents the next source read or transport call until [resume].
  bool pause() => _control.pause();

  /// Releases a paused run.
  bool resume() => _control.resume();

  /// Requests cooperative cancellation.
  bool cancel([Object? reason]) => _control.cancel(reason);
}

/// One-transfer-at-a-time resumable chunk orchestrator.
final class TransferEngine<F extends Object> implements AsyncDisposable {
  /// Creates an engine with positive bounded [chunkSize].
  TransferEngine({
    required this.source,
    required this.transport,
    required this.checkpoints,
    this.checksumVerifier,
    this.chunkSize = 256 * 1024,
    ProgressReporter<TransferProgress> progress =
        const NoOpProgressReporter<Never>(),
  }) : _progress = SafeProgressReporter<TransferProgress>(reporter: progress) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Must be positive.');
    }
  }

  /// Borrowed source.
  final TransferSource source;

  /// Borrowed destination transport.
  final TransferTransport<F> transport;

  /// Borrowed durable checkpoint store.
  final TransferCheckpointStore checkpoints;

  /// Optional verifier required for chunks carrying checksums.
  final TransferChecksumVerifier? checksumVerifier;

  /// Maximum bytes requested from the source per chunk.
  final int chunkSize;

  final ProgressReporter<TransferProgress> _progress;
  _TransferControl? _active;
  var _executionId = 0;
  var _disposed = false;
  Future<void>? _disposal;

  /// Whether a transfer is active.
  bool get isRunning => _active != null;

  /// Starts or resumes [transferId] from its durable checkpoint.
  TransferRun<F> start(String transferId, {DateTime? deadline}) {
    if (_disposed) throw StateError('TransferEngine is disposed.');
    if (_active != null) throw StateError('A transfer is already running.');
    if (transferId.trim().isEmpty) {
      throw ArgumentError.value(transferId, 'transferId', 'Must not be empty.');
    }
    if (deadline != null && !deadline.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
    final control = _TransferControl();
    _active = control;
    final done = _execute(transferId, deadline, ++_executionId, control);
    control.done = done.then<void>((_) {}, onError: (_, _) {});
    return TransferRun<F>._(done, control);
  }

  Future<Result<TransferReport, F>> _execute(
    String transferId,
    DateTime? deadline,
    int executionId,
    _TransferControl control,
  ) async {
    Timer? deadlineTimer;
    try {
      if (deadline != null) {
        final remaining = deadline.difference(DateTime.now().toUtc());
        if (remaining <= Duration.zero) {
          throw OperationDeadlineExceededException(deadline);
        }
        deadlineTimer = Timer(
          remaining,
          () => control.cancel('Transfer deadline exceeded'),
        );
      }
      final command = CommandExecutionContext<TransferProgress>(
        executionId: executionId,
        cancellation: control.source.signal,
        deadline: deadline,
        progress: _progress,
      );
      var checkpoint = await checkpoints.load(transferId);
      if (checkpoint != null && checkpoint.transferId != transferId) {
        throw const TransferProtocolException('Checkpoint ID mismatch.');
      }
      var offset = checkpoint?.committedOffset ?? 0;
      var revision = checkpoint?.revision ?? 0;
      var chunkCount = 0;
      command.publish(
        TransferProgress(
          phase: TransferProgressPhase.started,
          committedBytes: offset,
          chunkCount: chunkCount,
        ),
      );
      while (true) {
        final didPause = await control.waitUntilRunning();
        command.throwIfUnavailable();
        if (didPause) {
          command.publish(
            TransferProgress(
              phase: TransferProgressPhase.paused,
              committedBytes: offset,
              chunkCount: chunkCount,
            ),
          );
        }
        final chunk = await source.read(
          offset: offset,
          maxBytes: chunkSize,
          cancellation: control.source.signal,
        );
        command.throwIfUnavailable();
        if (chunk == null) break;
        if (chunk.offset != offset || chunk.bytes.length > chunkSize) {
          throw const TransferProtocolException(
            'Source returned a non-contiguous or oversized chunk.',
          );
        }
        final checksum = chunk.checksum;
        if (checksum != null) {
          final verifier = checksumVerifier;
          if (verifier == null || !verifier.verify(chunk.bytes, checksum)) {
            throw const TransferProtocolException('Chunk checksum mismatch.');
          }
        }
        command.publish(
          TransferProgress(
            phase: TransferProgressPhase.chunkRead,
            committedBytes: offset,
            chunkCount: chunkCount,
          ),
        );
        await control.waitUntilRunning();
        command.throwIfUnavailable();
        final result = await transport.transmit(chunk, control.source.signal);
        switch (result) {
          case Err<Object>(:final failure, :final stackTrace):
            return Err<F>(failure as F, stackTrace);
          case Ok<dynamic>(:final value):
            final commit = value as TransferCommit;
            if (commit.durableOffset != chunk.nextOffset) {
              throw const TransferProtocolException(
                'Transport acknowledged a non-contiguous durable offset.',
              );
            }
        }
        offset = chunk.nextOffset;
        revision += 1;
        chunkCount += 1;
        checkpoint = TransferCheckpoint(
          transferId: transferId,
          committedOffset: offset,
          revision: revision,
        );
        await checkpoints.save(checkpoint);
        command.publish(
          TransferProgress(
            phase: TransferProgressPhase.chunkCommitted,
            committedBytes: offset,
            chunkCount: chunkCount,
          ),
        );
      }
      command.publish(
        TransferProgress(
          phase: TransferProgressPhase.completed,
          committedBytes: offset,
          chunkCount: chunkCount,
        ),
      );
      return Ok<TransferReport>(
        TransferReport(
          transferId: transferId,
          committedBytes: offset,
          chunkCount: chunkCount,
          checkpointRevision: revision,
        ),
      );
    } finally {
      deadlineTimer?.cancel();
      control.source.dispose();
      if (identical(_active, control)) _active = null;
    }
  }

  /// Cancels and drains the active transfer.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    final active = _active;
    active?.cancel('TransferEngine disposed');
    await active?.done;
  }
}

final class _TransferControl {
  final CancellationSource source = CancellationSource();
  Completer<void>? _resume;
  Future<void>? done;

  bool get isPaused => _resume != null;

  bool pause() {
    if (source.signal.isCancelled || _resume != null) return false;
    _resume = Completer<void>();
    return true;
  }

  bool resume() {
    final resume = _resume;
    if (resume == null) return false;
    _resume = null;
    resume.complete();
    return true;
  }

  bool cancel(Object? reason) {
    if (source.signal.isCancelled) return false;
    source.cancel(reason ?? 'Transfer cancelled');
    resume();
    return true;
  }

  Future<bool> waitUntilRunning() async {
    final resume = _resume;
    if (resume == null) return false;
    await Future.any<void>(<Future<void>>[
      resume.future,
      source.signal.whenCancelled.then<void>((_) {}),
    ]);
    source.signal.throwIfCancelled();
    return true;
  }
}
