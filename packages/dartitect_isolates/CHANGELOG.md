# Changelog

## 1.0.0-rc.3

- Upgrade the worker protocol to version 2 and correlate wire envelopes with a
  generation-local, monotonic internal nonce instead of the reusable public
  request ID.
- Make acceptance and result Futures safe to await independently while
  preserving their original terminal errors for direct callers.

## 1.0.0-rc.2

- Promote the lockstep candidate cohort without public Dart API changes and
  bind release validation to the RC.2 source and evidence matrix.

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Use an injected core `IdGenerator` for supervisor request correlation.
- Add versioned typed workers, readiness, ACK correlation, heartbeat,
  deadlines, remote failure/crash handling, and safe-stop lifecycle.
