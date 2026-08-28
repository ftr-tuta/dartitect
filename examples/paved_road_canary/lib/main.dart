import 'package:dartitect/dartitect.dart';
import 'package:dartitect_devtools/dartitect_devtools.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    ApplicationHost<CanaryRuntime>.create(
      create: createCanaryCoordinator,
      loading: (_) => const MaterialApp(home: _Status('Bootstrapping')),
      failure: (_, _, retry) =>
          MaterialApp(home: _Status('Bootstrap failed', action: retry)),
      ready: (_, runtime) => CanaryApp(runtime: runtime),
    ),
  );
}

/// Creates the synthetic application graph used by the canary.
BootstrapCoordinator<CanaryRuntime> createCanaryCoordinator() {
  DartitectDiagnosticBuffer? buffer;
  DartitectDiagnosticsEmitter? emitter;
  ReactiveOwner? owner;
  return BootstrapCoordinator<CanaryRuntime>(
    stages: <BootstrapStage>[
      BootstrapStage(
        name: 'diagnostics',
        run: (transaction, context) {
          context.throwIfUnavailable();
          buffer = transaction.own<DartitectDiagnosticBuffer>(
            DartitectDiagnosticBuffer(capacity: 32),
            (value) => value.dispose(),
            label: 'diagnostic-buffer',
          );
          emitter = transaction.own<DartitectDiagnosticsEmitter>(
            DartitectDiagnosticsEmitter(
              detail: DartitectDiagnosticDetail.topology,
              reporter: DartitectDiagnosticReporterRegistration.borrowed(
                buffer!,
              ),
            ),
            (value) => value.disposeAsync(),
            label: 'diagnostic-emitter',
          );
        },
      ),
      BootstrapStage(
        name: 'reactive-runtime',
        run: (transaction, context) {
          context.throwIfUnavailable();
          owner = transaction.own<ReactiveOwner>(
            ReactiveOwner(
              diagnostics: emitter!.subject(
                DartitectDiagnosticSubjectKind.owner,
              ),
            ),
            (value) => value.dispose(),
            label: 'reactive-owner',
          );
        },
      ),
    ],
    buildRoot: (transaction, context) {
      context.throwIfUnavailable();
      final history = transaction.own(
        BoundedLocalHistory<int>(initialValue: 0, maxEntries: 8),
        (value) => value.dispose(),
        label: 'local-history',
      );
      final counter = owner!.value<int>(0);
      final doubled = owner!.lazyComputed<int>(
        label: 'canary.counter.doubled',
        dependencies: () => <ReactiveValue<int>>[counter],
        compute: (read) => read.read(counter) * 2,
      );
      var developmentMode = false;
      assert(() {
        developmentMode = true;
        return true;
      }());
      final devtools = transaction.own(
        DartitectDevToolsRegistration.register(
          enabled: developmentMode,
          buffer: buffer!,
          detail: DartitectDiagnosticDetail.topology,
        ),
        (value) => value.dispose(),
        label: 'devtools-registration',
      );
      return CanaryRuntime(
        owner: owner!,
        counter: counter,
        doubled: doubled,
        history: history,
        devtools: devtools,
      );
    },
  );
}

/// Owned state exposed only after the complete application graph commits.
final class CanaryRuntime {
  const CanaryRuntime({
    required this.owner,
    required this.counter,
    required this.doubled,
    required this.history,
    required this.devtools,
  });

  final ReactiveOwner owner;
  final ReactiveValue<int> counter;
  final ReactiveLazyComputed<int> doubled;
  final BoundedLocalHistory<int> history;
  final DartitectDevToolsRegistration devtools;

  void increment() {
    owner.update<void>((write) => write.set(counter, counter.value + 1));
    history.edit(counter.value);
  }
}

final class CanaryApp extends StatelessWidget {
  const CanaryApp({required this.runtime, super.key});

  final CanaryRuntime runtime;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Dartitect paved-road canary')),
      body: Center(
        child: ListenableBuilder(
          listenable: runtime.doubled,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('value ${runtime.counter.value}'),
              Text('lazy ${runtime.doubled.value}'),
              Text(
                runtime.devtools.isRegistered
                    ? 'read-only diagnostics enabled'
                    : 'diagnostics extension disabled',
              ),
              FilledButton(
                onPressed: runtime.increment,
                child: const Text('Increment local state'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _Status extends StatelessWidget {
  const _Status(this.label, {this.action});

  final String label;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: action == null
          ? Text(label)
          : FilledButton(onPressed: action, child: Text(label)),
    ),
  );
}
