# Changelog

## 1.0.0-rc.3

- Add `DiagnosticsTopologyHarness` for reconstructing protocol-v1 topology and
  lifecycle from opaque payload-free events.

## 1.0.0-rc.2

- Promote the lockstep candidate cohort without public Dart API changes and
  bind release validation to the RC.2 source and evidence matrix.

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Add an instance-owned deterministic core `IdGenerator` implementation.
- Add deterministic owned-graph and sync harnesses with checkpoint crash
  points, sequence IDs, manual fencing leases, and contract matrices.
- Initial testing helpers.
