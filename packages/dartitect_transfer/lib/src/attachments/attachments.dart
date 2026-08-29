import 'dart:async';

import 'package:dartitect/dartitect.dart';

import '../../dartitect_transfer.dart';

/// Lifecycle of attachment metadata and its durable outbox row.
enum AttachmentStatus {
  /// Temporary file and outbox row were committed atomically.
  pending,

  /// A foreground or background transfer is active.
  uploading,

  /// Remote commit and local metadata update completed.
  uploaded,

  /// An expected transport or persistence failure occurred.
  failed,
}

/// Consumer-independent metadata for one staged attachment.
// Primary constructors currently trigger a duplicate constructor-doc lint.
// ignore: public_member_api_docs
final class AttachmentRecord({
  /// Stable local attachment identifier.
  required final String attachmentId,

  /// Opaque temporary-file reference interpreted by consumer ports.
  required final String temporaryFile,

  /// Media type supplied by the consumer.
  required final String mediaType,

  /// Total local size.
  required final int byteLength,

  /// Durable workflow revision.
  required final int revision,

  /// Current outbox state.
  required final AttachmentStatus status,
});

/// Picker result copied into a Dartitect-managed staging workflow.
// Primary constructors currently trigger a duplicate constructor-doc lint.
// ignore: public_member_api_docs
final class AttachmentSelection({
  /// Consumer-owned opaque source reference.
  required final Object source,

  /// Validated media type.
  required final String mediaType,
});

/// Temporary file produced before metadata/outbox commit.
// Primary constructors currently trigger a duplicate constructor-doc lint.
// ignore: public_member_api_docs
final class AttachmentTemporaryFile({
  /// Opaque path or URI known only to the consumer file port.
  required final String reference,

  /// Exact copied size.
  required final int byteLength,
});

/// Consumer-owned picker boundary.
abstract interface class AttachmentPickerPort {
  /// Returns a selection or `null` when the user cancels.
  Future<AttachmentSelection?> pick(CancellationSignal cancellation);
}

/// Consumer-owned share boundary.
abstract interface class AttachmentSharePort {
  /// Shares a committed attachment using application policy.
  Future<void> share(AttachmentRecord attachment);
}

/// Consumer-owned gallery boundary.
abstract interface class AttachmentGalleryPort {
  /// Saves a committed attachment using application policy.
  Future<void> save(AttachmentRecord attachment);
}

/// Consumer-owned temporary-file boundary.
abstract interface class AttachmentFilePort<F extends Object> {
  /// Copies a selection into a temporary file before outbox commit.
  Future<Result<AttachmentTemporaryFile, F>> createTemporary(
    AttachmentSelection selection,
    CancellationSignal cancellation,
  );

  /// Removes a temporary file after rollback or explicit cleanup.
  Future<void> discardTemporary(String reference);
}

/// Consumer store that atomically owns attachment metadata and its outbox row.
abstract interface class AttachmentMetadataOutboxStore<F extends Object> {
  /// Atomically inserts metadata and the matching pending outbox operation.
  Future<Result<AttachmentRecord, F>> stage(
    AttachmentRecord attachment,
    CancellationSignal cancellation,
  );

  /// Atomically updates metadata and its outbox state.
  Future<Result<AttachmentRecord, F>> transition(
    AttachmentRecord attachment,
    AttachmentStatus status,
    CancellationSignal cancellation,
  );
}

/// Versioned background-upload request.
// Primary constructors currently trigger a duplicate constructor-doc lint.
// ignore: public_member_api_docs
final class AttachmentBackgroundRequest({
  /// Protocol version interpreted by consumer background wiring.
  required final int protocolVersion,

  /// Attachment identity; no path, token, or credential is serialized.
  required final String attachmentId,

  /// Absolute UTC deadline.
  required final DateTime deadline,
});

/// Consumer-owned bridge to Workmanager or another scheduler.
abstract interface class AttachmentBackgroundScheduler<F extends Object> {
  /// Schedules a resumable upload by safe identifier.
  Future<Result<void, F>> schedule(
    AttachmentBackgroundRequest request,
    CancellationSignal cancellation,
  );
}

/// Builds one owned transfer graph for every foreground/background attempt.
typedef AttachmentTransferGraphFactory<F extends Object> =
    Future<OwnedGraph<TransferEngine<F>>> Function(AttachmentRecord attachment);

/// Running attachment upload with pause, resume, and cancellation.
final class AttachmentUploadRun<F extends Object> {
  AttachmentUploadRun._(this.done, this._control);

  /// Terminal uploaded record or expected typed failure.
  final Future<Result<AttachmentRecord, F>> done;

  final _AttachmentUploadControl<F> _control;

  /// Pauses before the next source/transport operation.
  bool pause() => _control.pause();

  /// Resumes a paused upload.
  bool resume() => _control.resume();

  /// Cooperatively cancels the attempt.
  bool cancel([Object? reason]) => _control.cancel(reason);
}

/// Attachment staging and resumable-upload coordinator.
final class AttachmentCoordinator<F extends Object> implements AsyncDisposable {
  /// Creates a coordinator over consumer-owned storage and file boundaries.
  AttachmentCoordinator({
    required this.files,
    required this.metadata,
    required this.createTransferGraph,
    this.background,
  });

  /// Temporary-file boundary.
  final AttachmentFilePort<F> files;

  /// Atomic metadata/outbox boundary.
  final AttachmentMetadataOutboxStore<F> metadata;

  /// Fresh graph factory per transfer attempt.
  final AttachmentTransferGraphFactory<F> createTransferGraph;

  /// Optional background scheduler.
  final AttachmentBackgroundScheduler<F>? background;

  final Map<String, _AttachmentUploadControl<F>> _active =
      <String, _AttachmentUploadControl<F>>{};
  var _disposed = false;

  /// Copies a selection, then atomically commits metadata plus outbox.
  Future<Result<AttachmentRecord, F>> stage({
    required String attachmentId,
    required AttachmentSelection selection,
    CancellationSignal? cancellation,
  }) async {
    _ensureOpen();
    final owned = cancellation == null ? CancellationSource() : null;
    final signal = cancellation ?? owned!.signal;
    try {
      final copied = await files.createTemporary(selection, signal);
      switch (copied) {
        case Err<Object>(:final failure, :final stackTrace):
          return Err<F>(failure as F, stackTrace);
        case Ok<dynamic>(:final value):
          final temporary = value as AttachmentTemporaryFile;
          final candidate = AttachmentRecord(
            attachmentId: attachmentId,
            temporaryFile: temporary.reference,
            mediaType: selection.mediaType,
            byteLength: temporary.byteLength,
            revision: 0,
            status: AttachmentStatus.pending,
          );
          final staged = await metadata.stage(candidate, signal);
          if (staged case Err<Object>()) {
            await files.discardTemporary(temporary.reference);
          }
          return staged;
      }
    } finally {
      owned?.dispose();
    }
  }

  /// Starts or resumes an upload from the transfer's durable checkpoint.
  AttachmentUploadRun<F> upload(AttachmentRecord attachment) {
    _ensureOpen();
    if (_active.containsKey(attachment.attachmentId)) {
      throw StateError('This attachment already has an active upload.');
    }
    final control = _AttachmentUploadControl<F>();
    _active[attachment.attachmentId] = control;
    final done = _upload(attachment, control);
    control.done = done.then<void>((_) {}, onError: (_, _) {});
    return AttachmentUploadRun<F>._(done, control);
  }

  /// Retries using the same transfer ID and durable checkpoint.
  AttachmentUploadRun<F> retry(AttachmentRecord attachment) =>
      upload(attachment);

  /// Schedules a background attempt without serializing file paths.
  Future<Result<void, F>> scheduleBackground(
    AttachmentRecord attachment, {
    required DateTime deadline,
    CancellationSignal? cancellation,
  }) async {
    _ensureOpen();
    if (!deadline.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
    final scheduler = background;
    if (scheduler == null) {
      throw StateError('No attachment background scheduler is configured.');
    }
    final owned = cancellation == null ? CancellationSource() : null;
    try {
      return await scheduler.schedule(
        AttachmentBackgroundRequest(
          protocolVersion: 1,
          attachmentId: attachment.attachmentId,
          deadline: deadline,
        ),
        cancellation ?? owned!.signal,
      );
    } finally {
      owned?.dispose();
    }
  }

  Future<Result<AttachmentRecord, F>> _upload(
    AttachmentRecord attachment,
    _AttachmentUploadControl<F> control,
  ) async {
    OwnedGraph<TransferEngine<F>>? graph;
    try {
      final uploading = await metadata.transition(
        attachment,
        AttachmentStatus.uploading,
        control.source.signal,
      );
      if (uploading case Err<Object>(:final failure, :final stackTrace)) {
        return Err<F>(failure as F, stackTrace);
      }
      final active = (uploading as Ok<AttachmentRecord>).value;
      graph = await createTransferGraph(active);
      final transfer = graph.root.start(active.attachmentId);
      control.attach(transfer);
      final result = await transfer.done;
      switch (result) {
        case Err<Object>(:final failure, :final stackTrace):
          await metadata.transition(
            active,
            AttachmentStatus.failed,
            control.source.signal,
          );
          return Err<F>(failure as F, stackTrace);
        case Ok<dynamic>():
          return await metadata.transition(
            active,
            AttachmentStatus.uploaded,
            control.source.signal,
          );
      }
    } finally {
      await graph?.disposeAsync();
      control.dispose();
      _active.remove(attachment.attachmentId);
    }
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('AttachmentCoordinator is disposed.');
  }

  /// Cancels and drains every active upload.
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    final active = _active.values.toList(growable: false);
    for (final control in active) {
      control.cancel('AttachmentCoordinator disposed');
    }
    await Future.wait(active.map((control) => control.done));
  }
}

final class _AttachmentUploadControl<F extends Object> {
  final CancellationSource source = CancellationSource();
  TransferRun<F>? _transfer;
  var _pauseRequested = false;
  late Future<void> done;

  void attach(TransferRun<F> transfer) {
    _transfer = transfer;
    if (_pauseRequested) transfer.pause();
    if (source.signal.isCancelled) transfer.cancel(source.signal.reason);
  }

  bool pause() {
    if (_pauseRequested) return false;
    _pauseRequested = true;
    return _transfer?.pause() ?? true;
  }

  bool resume() {
    if (!_pauseRequested) return false;
    _pauseRequested = false;
    return _transfer?.resume() ?? true;
  }

  bool cancel(Object? reason) {
    if (source.signal.isCancelled) return false;
    source.cancel(reason ?? 'Attachment upload cancelled');
    _transfer?.cancel(reason);
    return true;
  }

  void dispose() => source.dispose();
}
