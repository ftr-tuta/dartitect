import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_adapters_app/features/catalog/catalog_model.dart';
import 'package:dartitect_adapters_app/features/catalog/catalog_remote.dart';
import 'package:dartitect_adapters_app/features/catalog/catalog_view_model.dart';
import 'package:dartitect_adapters_app/runtime/adapters_runtime.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote catalog writes through local authority and paginates', () async {
    final runtime = AdaptersRuntime.create();
    final catalog = runtime.catalog;
    final effects = <CatalogEffect>[];
    final effectSubscription = catalog.effects.listen(effects.add);

    await _waitForCommand(catalog.refreshCommand);
    expect(
      catalog.refreshCommand.state,
      isA<CommandSuccessState<Object?, Object>>(),
    );
    expect(catalog.paged.collection.length.value, 25);

    await catalog.loadMoreCommand.execute();
    expect(catalog.paged.collection.length.value, 50);
    await catalog.loadMoreCommand.execute();
    expect(catalog.paged.collection.length.value, 75);
    await catalog.loadMoreCommand.execute();
    expect(effects, <CatalogEffect>[CatalogEffect.endOfList]);

    await catalog.searchCommand.execute('item 7');
    expect(catalog.paged.collection.keys.value, isNotEmpty);
    expect(
      catalog.paged.collection.keys.value.map(
        (key) => catalog.paged.collection.item(key).value!.title,
      ),
      everyElement(contains('7')),
    );

    effectSubscription.dispose();
    await runtime.disposeAsync();
    expect(catalog.paged.isDisposed, isTrue);
    expect(catalog.local.isDisposed, isTrue);
    expect(catalog.refreshCommand.isDisposed, isTrue);
    expect(catalog.loadMoreCommand.isDisposed, isTrue);
    expect(catalog.searchCommand.isDisposed, isTrue);
    expect(catalog.effects.isDisposed, isTrue);
    expect(runtime.instrumentation.activeRequestCount, 0);
  });

  test(
    'remote expected failure remains typed and preserves local authority',
    () async {
      final catalog = CatalogViewModel(
        _CatalogRemoteFake(
          (_, _) async => Err<CatalogFailure>(
            const CatalogFailure('offline'),
            StackTrace.current,
          ),
        ),
      );

      final execution = await catalog.refreshCommand.execute();

      expect(execution, isA<CommandExecutionFailed<Object?, CatalogFailure>>());
      expect(
        (catalog.refreshCommand.state
                as CommandFailureState<Object?, CatalogFailure>)
            .failure
            .code,
        'offline',
      );
      expect(catalog.paged.lastFailure?.code, 'offline');
      expect(catalog.paged.collection.length.value, 0);
      await catalog.disposeAsync();
    },
  );

  test('remote crash is reported once and keeps its original stack', () async {
    final crash = StateError('catalog-crash');
    final reporter = _RecordingPagedCrashReporter();
    final catalog = CatalogViewModel(
      _CatalogRemoteFake((_, _) async => throw crash),
      reporter: reporter,
    );

    await expectLater(catalog.refreshCommand.execute(), throwsA(same(crash)));

    final state =
        catalog.refreshCommand.state
            as CommandCrashState<Object?, CatalogFailure>;
    expect(state.error, same(crash));
    expect(state.stackTrace, isNot(StackTrace.empty));
    expect(catalog.paged.crash, same(crash));
    expect(reporter.errors, <Object>[crash]);
    await catalog.disposeAsync();
  });

  test(
    'catalog generation swap drains admitted work before old teardown',
    () async {
      final oldRequest =
          Completer<
            Result<PageBatch<CatalogCursor, CatalogItem>, CatalogFailure>
          >();
      final oldCalled = Completer<void>();
      final first = CatalogViewModel(
        _CatalogRemoteFake((_, _) {
          if (!oldCalled.isCompleted) oldCalled.complete();
          return oldRequest.future;
        }),
      );
      final second = CatalogViewModel(_CatalogRemoteFake(_successfulPage));
      final slot = OwnedRuntimeSlot<CatalogViewModel>(label: 'catalog-session');
      await slot.replace((transaction) {
        transaction.own(first, (value) => value.disposeAsync());
        return first;
      });

      final oldWork = slot.use((catalog) => catalog.refreshCommand.execute());
      await oldCalled.future;
      final replacement = slot.replace((transaction) {
        transaction.own(second, (value) => value.disposeAsync());
        return second;
      });
      await _waitForGeneration(slot, 2);

      expect(await slot.use((catalog) => identical(catalog, second)), isTrue);
      expect(first.paged.isDisposed, isFalse);
      oldRequest.complete(
        await _successfulPage(
          const PageRequest<CatalogCursor>(
            operation: PageOperation.refresh,
            cursor: CatalogCursor(),
            reset: true,
          ),
          CancellationSource().signal,
        ),
      );
      expect(
        await oldWork,
        isA<CommandExecutionSucceeded<Object?, CatalogFailure>>(),
      );
      await replacement;
      expect(first.paged.isDisposed, isTrue);

      await slot.disposeAsync();
      expect(second.paged.isDisposed, isTrue);
    },
  );
}

Future<void> _waitForCommand<T, F extends Object>(Command0<T, F> command) {
  if (!command.isRunning) return Future<void>.value();
  final complete = Completer<void>();
  void changed() {
    if (!command.isRunning && !complete.isCompleted) complete.complete();
  }

  command.addListener(changed);
  if (!command.isRunning && !complete.isCompleted) complete.complete();
  return complete.future.whenComplete(() => command.removeListener(changed));
}

Future<void> _waitForGeneration(
  OwnedRuntimeSlot<CatalogViewModel> slot,
  int generation,
) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (slot.generation == generation) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Catalog slot did not reach generation $generation.');
}

Future<Result<PageBatch<CatalogCursor, CatalogItem>, CatalogFailure>>
_successfulPage(
  PageRequest<CatalogCursor> request,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<PageBatch<CatalogCursor, CatalogItem>>(
    PageBatch<CatalogCursor, CatalogItem>(
      items: const <CatalogItem>[
        CatalogItem(id: 1, title: 'Catalog item 1', version: 1),
      ],
      nextCursor: null,
    ),
  );
}

final class _CatalogRemoteFake implements CatalogRemote {
  const _CatalogRemoteFake(this.callback);

  final Future<Result<PageBatch<CatalogCursor, CatalogItem>, CatalogFailure>>
  Function(PageRequest<CatalogCursor>, CancellationSignal)
  callback;

  @override
  Future<Result<PageBatch<CatalogCursor, CatalogItem>, CatalogFailure>> page(
    PageRequest<CatalogCursor> request,
    CancellationSignal cancellation,
  ) => callback(request, cancellation);
}

final class _RecordingPagedCrashReporter implements PagedResourceCrashReporter {
  final List<Object> errors = <Object>[];

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}
