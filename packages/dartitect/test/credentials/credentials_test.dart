import 'dart:async';

import 'package:dartitect/dartitect_credentials.dart';
import 'package:test/test.dart';

void main() {
  test('single-flight gives every waiter independent cancellation', () async {
    final store = _Store();
    final refresher = _Refresher();
    final controller = _controller(store, refresher);
    final firstCancellation = CancellationSource();
    final secondCancellation = CancellationSource();

    final first = controller.load(cancellation: firstCancellation.signal);
    final second = controller.load(cancellation: secondCancellation.signal);
    await _flush();
    expect(refresher.calls, 1);
    expect(store.readCalls, 1);

    firstCancellation.cancel('first waiter left');
    await expectLater(first, throwsA(isA<CancellationException>()));
    expect(refresher.cancellation?.isCancelled, isFalse);

    refresher.complete('token');
    final lease = (await second as Ok<CredentialLease<String>>).value;
    expect(lease.value, 'token');
    expect(lease.generation.value, 1);
    expect(store.events, <String>['read', 'write-start', 'write-end']);
    expect(controller.currentLease, same(lease));

    firstCancellation.dispose();
    secondCancellation.dispose();
    await controller.disposeAsync();
  });

  test('invalidation fences delayed persistence before clear/logout', () async {
    final store = _Store()..writeGate = Completer<void>();
    final refresher = _Refresher();
    final forced = <CredentialInvalidationCause>[];
    final controller = _controller(
      store,
      refresher,
      forcedLogout: (cause, _) => forced.add(cause),
    );

    final loading = controller.load();
    await _flush();
    refresher.complete('late-token');
    await _waitForEvent(store.events, 'write-start');

    final invalidating = controller.invalidate(
      CredentialInvalidationCause.signOut,
    );
    await _flush();
    expect(store.clearCalls, 0);
    expect(controller.currentLease, isNull);

    store.writeGate!.complete();
    await expectLater(loading, throwsA(isA<CancellationException>()));
    expect(await invalidating, isA<Ok<void>>());
    expect(store.value, isNull);
    expect(store.events, <String>['read', 'write-start', 'write-end', 'clear']);
    expect(forced, <CredentialInvalidationCause>[
      CredentialInvalidationCause.signOut,
    ]);
    await controller.disposeAsync();
  });

  test(
    'old generations are no-ops and logout deduplicates per generation',
    () async {
      final store = _Store()
        ..value = CredentialRecord<String>(
          value: 'old',
          expiresAt: DateTime.utc(2030),
        );
      final refresher = _Refresher();
      final forced = <CredentialInvalidationCause>[];
      final controller = _controller(
        store,
        refresher,
        forcedLogout: (cause, _) => forced.add(cause),
      );
      final old =
          (await controller.load() as Ok<CredentialLease<String>>).value;

      store.clearGate = Completer<void>();
      final first = controller.invalidateIfCurrent(
        old.generation,
        CredentialInvalidationCause.providerRejected,
      );
      final second = controller.invalidateIfCurrent(
        old.generation,
        CredentialInvalidationCause.providerRejected,
      );
      await _waitForEvent(store.events, 'clear-start');
      expect(store.clearCalls, 1);
      store.clearGate!.complete();
      expect(await first, isA<Ok<void>>());
      expect(await second, isA<Ok<void>>());
      expect(forced, hasLength(1));

      final nextLoad = controller.load();
      await _flush();
      refresher.complete('new');
      final current = (await nextLoad as Ok<CredentialLease<String>>).value;
      expect(current.generation.value, greaterThan(old.generation.value));
      expect(
        await controller.invalidateIfCurrent(
          old.generation,
          CredentialInvalidationCause.providerRejected,
        ),
        isA<Ok<void>>(),
      );
      expect(controller.currentLease, same(current));
      expect(store.clearCalls, 1);
      expect(forced, hasLength(1));
      await controller.disposeAsync();
    },
  );

  test('dispose invalidates then cancels and drains acquisition', () async {
    final store = _Store();
    final refresher = _Refresher(cancelOnSignal: true);
    final controller = _controller(store, refresher);
    final loading = controller.load();
    await _flush();

    await controller.disposeAsync();

    await expectLater(loading, throwsA(isA<CancellationException>()));
    expect(refresher.cancellation?.isCancelled, isTrue);
    expect(controller.currentLease, isNull);
    expect(() => controller.load(), throwsStateError);
  });

  test('public credential invariants are active without asserts', () {
    expect(
      () => CredentialRecord<String>(value: 'token', expiresAt: DateTime(2030)),
      throwsArgumentError,
    );
    final record = CredentialRecord<String>(
      value: 'token',
      expiresAt: DateTime.utc(2030),
    );
    expect(
      () => record.isExpiredAt(
        DateTime.utc(2029),
        skew: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
  });
}

CredentialsController<String, _Failure> _controller(
  _Store store,
  _Refresher refresher, {
  CredentialForcedLogout? forcedLogout,
}) => CredentialsController<String, _Failure>(
  store: store,
  refresher: refresher,
  now: () => DateTime.utc(2026),
  forcedLogout: forcedLogout,
);

final class _Failure {
  const _Failure();
}

final class _Store implements CredentialStore<String, _Failure> {
  CredentialRecord<String>? value;
  Completer<void>? writeGate;
  Completer<void>? clearGate;
  final events = <String>[];
  var readCalls = 0;
  var clearCalls = 0;

  @override
  Future<Result<void, _Failure>> clear(CancellationSignal cancellation) async {
    cancellation.throwIfCancelled();
    clearCalls += 1;
    if (clearGate != null) {
      events.add('clear-start');
      await clearGate!.future;
    }
    value = null;
    events.add('clear');
    return const Ok<void>(null);
  }

  @override
  Future<Result<CredentialRecord<String>?, _Failure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    readCalls += 1;
    events.add('read');
    return Ok<CredentialRecord<String>?>(value);
  }

  @override
  Future<Result<void, _Failure>> write(
    CredentialRecord<String> credential,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    events.add('write-start');
    await writeGate?.future;
    value = credential;
    events.add('write-end');
    return const Ok<void>(null);
  }
}

final class _Refresher implements CredentialRefresher<String, _Failure> {
  _Refresher({this.cancelOnSignal = false});

  final bool cancelOnSignal;
  Completer<Result<CredentialRecord<String>, _Failure>> _completion =
      Completer<Result<CredentialRecord<String>, _Failure>>();
  CancellationSignal? cancellation;
  var calls = 0;

  void complete(String value) {
    _completion.complete(
      Ok<CredentialRecord<String>>(CredentialRecord<String>(value: value)),
    );
    _completion = Completer<Result<CredentialRecord<String>, _Failure>>();
  }

  @override
  Future<Result<CredentialRecord<String>, _Failure>> refresh(
    CredentialRecord<String>? previous,
    CancellationSignal cancellation,
  ) {
    cancellation.throwIfCancelled();
    calls += 1;
    this.cancellation = cancellation;
    if (cancelOnSignal) {
      return cancellation.whenCancelled
          .then<Result<CredentialRecord<String>, _Failure>>(
            (reason) => throw CancellationException(reason),
          );
    }
    return _completion.future;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _waitForEvent(List<String> events, String event) async {
  for (var attempt = 0; attempt < 20 && !events.contains(event); attempt += 1) {
    await _flush();
  }
  if (!events.contains(event))
    throw StateError('Missing event $event: $events');
}
