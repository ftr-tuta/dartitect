# Changelog

## 1.0.0-rc.4

- Promote primary-constructor data carriers and the modular modeling cohort
  without changing provider ownership or persisted sync schemas.

## 1.0.0-rc.3

- Expose optional `SyncAuthority` in each dataset context so fencing-capable
  consumer transactions can ensure/renew authority and atomically validate the
  token at the real dataset commit.
- Add application, checkpoint, journal, lease-release, and cleanup receipts;
  unexpected terminals now throw `SyncRunTerminalException` with the complete
  partial report and original cause/stack.

## 1.0.0-rc.2

- Promote the lockstep candidate cohort without public Dart API changes and
  bind release validation to the RC.2 source and evidence matrix.

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Use the core `IdGenerator` contract for sync runs and mutation idempotency.
- Add experimental dataset DAG, run, checkpoint, lease, progress, report, and
  headless command primitives.
