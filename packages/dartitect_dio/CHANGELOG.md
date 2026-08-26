# Changelog

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Add explicit typed JSON endpoints/clients for GET, POST, PUT, PATCH, and
  DELETE with path encoding, accepted statuses, decoding, and cancellation.
- Add an explicit disposable cancellation binding and consumer-callback
  `DioSyncDatasetAdapter` with typed provider failures.
- Bind pure-Dart cooperative cancellation explicitly to a shareable Dio token.
- Initial Dio adapter.
