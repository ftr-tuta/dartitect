import 'dart:async';
import 'dart:collection';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

/// Current asynchronous form operation.
enum DartitectFormPhase {
  /// No asynchronous operation is active.
  idle,

  /// Restart-latest validation is active.
  validating,

  /// Submission is active.
  submitting,

  /// The latest submission succeeded.
  submitted,

  /// Validation or submission returned an expected failure.
  failed,
}

/// Versioned consumer-owned draft.
final class DartitectFormDraft<T> {
  /// Creates a restored draft.
  const DartitectFormDraft({required this.version, required this.value});

  /// Consumer schema version.
  final int version;

  /// Restored form value.
  final T value;
}

/// Consumer-owned durable draft storage.
abstract interface class DartitectFormDraftStore<T, F extends Object> {
  /// Loads a draft or `null` when none exists.
  Future<Result<DartitectFormDraft<T>?, F>> load(
    CancellationSignal cancellation,
  );

  /// Persists the complete current value under [DartitectFormDraft.version].
  Future<Result<void, F>> save(
    DartitectFormDraft<T> draft,
    CancellationSignal cancellation,
  );

  /// Deletes a saved draft after submit or explicit discard.
  Future<Result<void, F>> clear(CancellationSignal cancellation);
}

/// Immutable presentation state for [DartitectFormController].
final class DartitectFormSnapshot<T, F extends Object> {
  /// Creates a snapshot.
  const DartitectFormSnapshot({
    required this.original,
    required this.current,
    required this.dirty,
    required this.touched,
    required this.phase,
    required this.validationFailure,
    required this.submissionFailure,
    required this.draftVersion,
    required this.canUndo,
    required this.canRedo,
  });

  /// Value last accepted as clean.
  final T original;

  /// Editable value.
  final T current;

  /// Whether [current] differs from [original].
  final bool dirty;

  /// Whether the user has interacted with the form.
  final bool touched;

  /// Current asynchronous phase.
  final DartitectFormPhase phase;

  /// Latest expected sync/async validation failure.
  final F? validationFailure;

  /// Latest expected submit failure.
  final F? submissionFailure;

  /// Consumer draft schema version.
  final int draftVersion;

  /// Whether history has an earlier state.
  final bool canUndo;

  /// Whether history has a later state.
  final bool canRedo;
}

/// Synchronous validation boundary.
typedef DartitectSyncFormValidator<T, F extends Object> =
    Result<void, F> Function(T value);

/// Restart-latest asynchronous validation boundary.
typedef DartitectAsyncFormValidator<T, F extends Object> =
    Future<Result<void, F>> Function(T value, CancellationSignal cancellation);

/// Submit boundary with explicit cancellation and typed expected failures.
typedef DartitectFormSubmitter<T, F extends Object> =
    Future<Result<void, F>> Function(T value, CancellationSignal cancellation);

/// Forms workflow owning original/current state, history, and async lifetimes.
final class DartitectFormController<T, F extends Object> extends ChangeNotifier
    implements AsyncDisposable {
  /// Creates a form controller.
  DartitectFormController({
    required T original,
    required this.equals,
    required this.submitter,
    this.syncValidator,
    this.asyncValidator,
    this.drafts,
    this.draftVersion = 1,
    this.historyLimit = 50,
  }) : _original = original,
       _current = original,
       _history = ListQueue<T>.from(<T>[original]) {
    if (draftVersion <= 0 || historyLimit <= 0) {
      throw ArgumentError('Draft version and history limit must be positive.');
    }
  }

  /// Consumer equality used for dirty tracking and history deduplication.
  final bool Function(T left, T right) equals;

  /// Required submission boundary.
  final DartitectFormSubmitter<T, F> submitter;

  /// Optional synchronous validation.
  final DartitectSyncFormValidator<T, F>? syncValidator;

  /// Optional restart-latest asynchronous validation.
  final DartitectAsyncFormValidator<T, F>? asyncValidator;

  /// Optional durable draft store.
  final DartitectFormDraftStore<T, F>? drafts;

  /// Consumer draft schema version.
  final int draftVersion;

  /// Maximum values retained by undo/redo history.
  final int historyLimit;

  final CancellationSource _lifetime = CancellationSource();
  CancellationSource? _validation;
  CancellationSource? _submission;
  T _original;
  T _current;
  final ListQueue<T> _history;
  var _historyIndex = 0;
  var _touched = false;
  var _phase = DartitectFormPhase.idle;
  F? _validationFailure;
  F? _submissionFailure;
  var _validationGeneration = 0;
  var _disposed = false;

  /// Complete immutable state for widgets and restoration.
  DartitectFormSnapshot<T, F> get snapshot => DartitectFormSnapshot<T, F>(
    original: _original,
    current: _current,
    dirty: !equals(_original, _current),
    touched: _touched,
    phase: _phase,
    validationFailure: _validationFailure,
    submissionFailure: _submissionFailure,
    draftVersion: draftVersion,
    canUndo: _historyIndex > 0,
    canRedo: _historyIndex < _history.length - 1,
  );

  /// Whether navigation should consult an unsaved-changes policy.
  bool get hasUnsavedChanges => snapshot.dirty;

  /// Updates current state and appends a bounded undo checkpoint.
  void update(T value, {bool touched = true}) {
    _ensureOpen();
    if (equals(_current, value)) {
      if (touched && !_touched) {
        _touched = true;
        notifyListeners();
      }
      return;
    }
    _cancelValidation('Form value changed');
    if (_historyIndex < _history.length - 1) {
      while (_history.length > _historyIndex + 1) {
        _history.removeLast();
      }
    }
    _history.addLast(value);
    if (_history.length > historyLimit) _history.removeFirst();
    _historyIndex = _history.length - 1;
    _current = value;
    _touched = _touched || touched;
    _phase = DartitectFormPhase.idle;
    _validationFailure = null;
    _submissionFailure = null;
    notifyListeners();
  }

  /// Marks the form as interacted with.
  void touch() {
    _ensureOpen();
    if (_touched) return;
    _touched = true;
    notifyListeners();
  }

  /// Moves to the previous retained value.
  bool undo() {
    _ensureOpen();
    if (_historyIndex == 0) return false;
    _cancelValidation('Form history changed');
    _historyIndex -= 1;
    _current = _history.elementAt(_historyIndex);
    _phase = DartitectFormPhase.idle;
    notifyListeners();
    return true;
  }

  /// Moves to the next retained value.
  bool redo() {
    _ensureOpen();
    if (_historyIndex >= _history.length - 1) return false;
    _cancelValidation('Form history changed');
    _historyIndex += 1;
    _current = _history.elementAt(_historyIndex);
    _phase = DartitectFormPhase.idle;
    notifyListeners();
    return true;
  }

  /// Runs sync validation followed by restart-latest async validation.
  Future<Result<void, F>> validate() async {
    _ensureOpen();
    final value = _current;
    final sync = syncValidator?.call(value) ?? const Ok<void>(null);
    if (sync case Err<Object>(:final failure, :final stackTrace)) {
      _validationFailure = failure as F;
      _phase = DartitectFormPhase.failed;
      notifyListeners();
      return Err<F>(failure, stackTrace);
    }
    final validator = asyncValidator;
    if (validator == null) {
      _validationFailure = null;
      _phase = DartitectFormPhase.idle;
      notifyListeners();
      return const Ok<void>(null);
    }
    _cancelValidation('New form validation started');
    final generation = ++_validationGeneration;
    final source = CancellationSource();
    _validation = source;
    final registration = _lifetime.signal.register(source.cancel);
    _phase = DartitectFormPhase.validating;
    _validationFailure = null;
    notifyListeners();
    try {
      final result = await validator(value, source.signal);
      if (_disposed || generation != _validationGeneration) return result;
      switch (result) {
        case Ok<dynamic>():
          _validationFailure = null;
          _phase = DartitectFormPhase.idle;
        case Err<Object>(:final failure):
          _validationFailure = failure as F;
          _phase = DartitectFormPhase.failed;
      }
      notifyListeners();
      return result;
    } finally {
      registration.dispose();
      if (identical(_validation, source)) _validation = null;
      source.dispose();
    }
  }

  /// Validates and submits, promoting the successful value to [original].
  Future<Result<void, F>> submit({bool clearDraft = true}) async {
    _ensureOpen();
    final validation = await validate();
    if (validation case Err<Object>(:final failure, :final stackTrace)) {
      return Err<F>(failure as F, stackTrace);
    }
    final source = CancellationSource();
    _submission = source;
    final registration = _lifetime.signal.register(source.cancel);
    _phase = DartitectFormPhase.submitting;
    _submissionFailure = null;
    notifyListeners();
    try {
      final result = await submitter(_current, source.signal);
      switch (result) {
        case Ok<dynamic>():
          _original = _current;
          _phase = DartitectFormPhase.submitted;
          if (clearDraft && drafts != null) {
            final cleared = await drafts!.clear(source.signal);
            if (cleared case Err<Object>(:final failure, :final stackTrace)) {
              _submissionFailure = failure as F;
              _phase = DartitectFormPhase.failed;
              notifyListeners();
              return Err<F>(failure, stackTrace);
            }
          }
        case Err<Object>(:final failure):
          _submissionFailure = failure as F;
          _phase = DartitectFormPhase.failed;
      }
      notifyListeners();
      return result;
    } finally {
      registration.dispose();
      if (identical(_submission, source)) _submission = null;
      source.dispose();
    }
  }

  /// Saves the current value as a versioned durable draft.
  Future<Result<void, F>> saveDraft() async {
    _ensureOpen();
    final store = drafts;
    if (store == null) throw StateError('No draft store is configured.');
    return store.save(
      DartitectFormDraft<T>(version: draftVersion, value: _current),
      _lifetime.signal,
    );
  }

  /// Restores a matching draft and records it in history.
  Future<Result<bool, F>> restoreDraft() async {
    _ensureOpen();
    final store = drafts;
    if (store == null) throw StateError('No draft store is configured.');
    final loaded = await store.load(_lifetime.signal);
    switch (loaded) {
      case Err<Object>(:final failure, :final stackTrace):
        return Err<F>(failure as F, stackTrace);
      case Ok<dynamic>(:final value):
        final draft = value as DartitectFormDraft<T>?;
        if (draft == null || draft.version != draftVersion) {
          return const Ok<bool>(false);
        }
        update(draft.value, touched: false);
        return const Ok<bool>(true);
    }
  }

  /// Discards edits and returns to the latest accepted original value.
  void reset() {
    _ensureOpen();
    _cancelValidation('Form reset');
    _current = _original;
    _history
      ..clear()
      ..add(_original);
    _historyIndex = 0;
    _touched = false;
    _phase = DartitectFormPhase.idle;
    _validationFailure = null;
    _submissionFailure = null;
    notifyListeners();
  }

  void _cancelValidation(Object reason) {
    _validationGeneration += 1;
    _validation?.cancel(reason);
    _validation = null;
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('DartitectFormController is disposed.');
  }

  /// Cancels validation/submission and releases listeners.
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    _lifetime.cancel('DartitectFormController disposed');
    _cancelValidation('DartitectFormController disposed');
    _submission?.cancel('DartitectFormController disposed');
    _submission = null;
    _lifetime.dispose();
    super.dispose();
  }

  // The async path is authoritative and releases cooperative operations.
  @override
  // ignore: must_call_super
  void dispose() => unawaited(disposeAsync());
}
