# Changelog

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Use an injected core `IdGenerator` for supervisor request correlation.
- Add versioned typed workers, readiness, ACK correlation, heartbeat,
  deadlines, remote failure/crash handling, and safe-stop lifecycle.
