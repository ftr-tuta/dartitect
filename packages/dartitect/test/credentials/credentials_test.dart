import 'dart:async';

import 'package:dartitect/dartitect_credentials.dart';
import 'package:test/test.dart';

void main() {
  test('refresh is single-flight and persisted before publication', () async {
    final store = _Store();
    final refresher = _Refresher();
    final events = <String>[];
    store.events = events;
    refresher.events = events;
    final controller = CredentialsController<String, _Failure>(
      store: store,
      refresher: refresher,
      now: () => DateTime.utc(2026),
    );

    final first = controller.load();
    final second = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(refresher.calls, 1);
    refresher.completer.complete(
      Ok<CredentialRecord<String>>(
        CredentialRecord<String>(value: 'token', expiresAt: DateTime.utc(2027)),
      ),
    );

    expect((await first as Ok<CredentialRecord<String>>).value.value, 'token');
    expect((await second as Ok<CredentialRecord<String>>).value.value, 'token');
    expect(events, <String>['refresh', 'write']);
    expect(store.value?.value, 'token');
    await controller.disposeAsync();
  });

  test(
    'expiry refresh, invalidation, and forced logout are explicit',
    () async {
      final store = _Store()
        ..value = CredentialRecord<String>(
          value: 'expired',
          expiresAt: DateTime.utc(2025),
        );
      final refresher = _Refresher();
      final forced = <CredentialInvalidationCause>[];
      final controller = CredentialsController<String, _Failure>(
        store: store,
        refresher: refresher,
        now: () => DateTime.utc(2026),
        forcedLogout: (cause, _) => forced.add(cause),
      );

      final loading = controller.load();
      await Future<void>.delayed(Duration.zero);
      refresher.completer.complete(
        Ok<CredentialRecord<String>>(CredentialRecord<String>(value: 'fresh')),
      );
      expect(
        (await loading as Ok<CredentialRecord<String>>).value.value,
        'fresh',
      );
      expect(
        await controller.invalidate(
          CredentialInvalidationCause.providerRejected,
        ),
        isA<Ok<void>>(),
      );
      expect(store.value, isNull);
      expect(forced, <CredentialInvalidationCause>[
        CredentialInvalidationCause.providerRejected,
      ]);
      await controller.disposeAsync();
    },
  );
}

final class _Failure {
  const _Failure();
}

final class _Store implements CredentialStore<String, _Failure> {
  CredentialRecord<String>? value;
  List<String>? events;

  @override
  Future<Result<void, _Failure>> clear(CancellationSignal cancellation) async {
    cancellation.throwIfCancelled();
    value = null;
    return const Ok<void>(null);
  }

  @override
  Future<Result<CredentialRecord<String>?, _Failure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<CredentialRecord<String>?>(value);
  }

  @override
  Future<Result<void, _Failure>> write(
    CredentialRecord<String> credential,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    events?.add('write');
    value = credential;
    return const Ok<void>(null);
  }
}

final class _Refresher implements CredentialRefresher<String, _Failure> {
  final Completer<Result<CredentialRecord<String>, _Failure>> completer =
      Completer<Result<CredentialRecord<String>, _Failure>>();
  List<String>? events;
  var calls = 0;

  @override
  Future<Result<CredentialRecord<String>, _Failure>> refresh(
    CredentialRecord<String>? previous,
    CancellationSignal cancellation,
  ) {
    cancellation.throwIfCancelled();
    calls += 1;
    events?.add('refresh');
    return completer.future;
  }
}
