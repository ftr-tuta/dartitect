import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'forwards owned command notifications and detaches before cleanup',
    () async {
      final events = <String>[];
      final viewModel = _TestViewModel();
      final first = viewModel.addCommand(_FakeCommand('first', events));
      final second = viewModel.addCommand(_FakeCommand('second', events));
      var notifications = 0;
      viewModel.addListener(() => notifications += 1);

      first.publish();
      second.publish();
      expect(notifications, 2);
      expect(viewModel.ownedResourceCount, 2);
      expect(viewModel.forwardedListenerCount, 2);

      await viewModel.disposeAsync();

      expect(events, <String>['dispose:second', 'dispose:first']);
      expect(notifications, 2, reason: 'cleanup publications must be detached');
      expect(viewModel.ownedResourceCount, 0);
      expect(viewModel.forwardedListenerCount, 0);
      expect(viewModel.isDisposed, isTrue);
    },
  );

  test(
    'cancels and drains running commands in reverse ownership order',
    () async {
      final events = <String>[];
      final viewModel = _TestViewModel();
      final first = viewModel.addCommand(
        _cancellableCommand('first', events),
        label: 'firstCommand',
      );
      final second = viewModel.addCommand(
        _cancellableCommand('second', events),
        label: 'secondCommand',
      );

      final firstExecution = first.execute();
      final secondExecution = second.execute();
      await _eventually(
        () => events.contains('start:first') && events.contains('start:second'),
      );

      await viewModel.disposeAsync();
      await Future.wait(<Future<Object?>>[firstExecution, secondExecution]);

      expect(events, <String>[
        'start:first',
        'start:second',
        'cancel:second',
        'drain:second',
        'cancel:first',
        'drain:first',
      ]);
    },
  );

  test(
    'owns generic resources and only borrows forwarded listenables',
    () async {
      final events = <String>[];
      final borrowed = ChangeNotifier();
      final viewModel = _TestViewModel();
      viewModel
        ..addResource('resource', (value) => events.add('dispose:$value'))
        ..addForwarding(borrowed);
      var notifications = 0;
      viewModel.addListener(() => notifications += 1);

      borrowed.notifyListeners();
      expect(notifications, 1);
      await viewModel.disposeAsync();
      borrowed.notifyListeners();

      expect(events, <String>['dispose:resource']);
      expect(notifications, 1);
      borrowed.dispose();
    },
  );

  test(
    'reports cleanup crashes and preserves them as cleanup exceptions',
    () async {
      final reporter = _CrashReporter();
      final viewModel = _TestViewModel(reporter: reporter);
      final crash = StateError('cleanup crash');
      viewModel.addResource<Object>(
        Object(),
        (_) => throw crash,
        label: 'store',
      );

      final error = await _captureError(viewModel.disposeAsync());

      expect(error, isA<ResourceCleanupException>());
      final cleanup = error as ResourceCleanupException;
      expect(cleanup.first.error, same(crash));
      expect(cleanup.first.resourceLabel, 'store');
      expect(reporter.errors.single, same(crash));
      expect(reporter.operations, <String>['store']);
      expect(viewModel.isDisposed, isTrue);
    },
  );

  test(
    'reports an unexpected boundary crash and rethrows the same object',
    () async {
      final reporter = _CrashReporter();
      final viewModel = _TestViewModel(reporter: reporter);
      final crash = ArgumentError('boundary crash');

      final error = await _captureError(
        viewModel.runBoundary('refresh', () => throw crash),
      );

      expect(error, same(crash));
      expect(reporter.errors.single, same(crash));
      expect(reporter.operations, <String>['refresh']);
      await viewModel.disposeAsync();
    },
  );

  test('emits owner diagnostics without exposing resource values', () async {
    final buffer = DartitectDiagnosticBuffer();
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
      detail: DartitectDiagnosticDetail.topology,
    );
    final subject = emitter.subject(DartitectDiagnosticSubjectKind.owner);
    final secretValue = Object();
    final viewModel = _TestViewModel(diagnostics: subject);
    viewModel.addResource(secretValue, (_) {});

    await viewModel.disposeAsync();

    expect(
      buffer.events.map((event) => event.phase),
      <DartitectDiagnosticPhase>[
        DartitectDiagnosticPhase.created,
        DartitectDiagnosticPhase.updated,
        DartitectDiagnosticPhase.started,
        DartitectDiagnosticPhase.disposed,
      ],
    );
    expect(
      buffer.events.every(
        (event) => event.subjectKind == DartitectDiagnosticSubjectKind.owner,
      ),
      isTrue,
    );
    expect(buffer.events.join(), isNot(contains(secretValue.toString())));
    await emitter.disposeAsync();
    buffer.dispose();
  });

  test('isolates reporter failures from the original crash', () async {
    final original = StateError('original');
    final viewModel = _TestViewModel(reporter: _ThrowingCrashReporter());

    final error = await _captureError(
      viewModel.runBoundary('load', () => throw original),
    );

    expect(error, same(original));
    expect(viewModel.reporterFailureCount, 1);
    await viewModel.disposeAsync();
  });

  test('shares one idempotent disposal and rejects late ownership', () async {
    final release = Completer<void>();
    var calls = 0;
    final viewModel = _TestViewModel();
    viewModel.addResource<Object>(Object(), (_) {
      calls += 1;
      return release.future;
    });

    final first = viewModel.disposeAsync();
    final second = viewModel.disposeAsync();
    expect(identical(first, second), isTrue);
    expect(viewModel.isDisposing, isTrue);
    expect(() => viewModel.addResource('late', (_) {}), throwsStateError);

    release.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(calls, 1);
    expect(viewModel.isDisposed, isTrue);
  });
}

final class _TestViewModel extends DartitectViewModel {
  _TestViewModel({DartitectViewModelCrashReporter? reporter, super.diagnostics})
    : super(
        crashReporter: reporter ?? const NoOpDartitectViewModelCrashReporter(),
      );

  T addCommand<T extends DartitectObservableResource>(
    T command, {
    String? label,
  }) => ownCommand(command, label: label);

  T addResource<T extends Object>(
    T resource,
    FutureOr<void> Function(T resource) release, {
    String? label,
  }) => own(resource, release, label: label);

  T addForwarding<T extends Listenable>(T listenable) => forward(listenable);

  Future<T> runBoundary<T>(String operation, FutureOr<T> Function() body) =>
      runReportingCrashes(operation, body);
}

final class _FakeCommand extends ChangeNotifier
    implements DartitectObservableResource {
  _FakeCommand(this.label, this.events);

  final String label;
  final List<String> events;
  var _disposed = false;

  @override
  bool get isDisposed => _disposed;

  void publish() => notifyListeners();

  @override
  Future<void> disposeAsync() async {
    _disposed = true;
    events.add('dispose:$label');
    notifyListeners();
    super.dispose();
  }
}

Command0<void, String> _cancellableCommand(String label, List<String> events) =>
    Command0<void, String>.cancellable((signal) async {
      events.add('start:$label');
      await signal.whenCancelled;
      events.add('cancel:$label');
      await Future<void>.delayed(Duration.zero);
      events.add('drain:$label');
      signal.throwIfCancelled();
      return const Ok<void>(null);
    });

final class _CrashReporter implements DartitectViewModelCrashReporter {
  final errors = <Object>[];
  final operations = <String>[];

  @override
  void report(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    errors.add(error);
    operations.add(operation);
  }
}

final class _ThrowingCrashReporter implements DartitectViewModelCrashReporter {
  @override
  void report(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    throw StateError('reporter failed');
  }
}

Future<Object> _captureError(Future<void> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  throw StateError('Expected the future to fail.');
}

Future<void> _eventually(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition was not reached.');
}
