# Conformance audit

Start with read-only CLI operations. `inspect`, `scan`, and `doctor` do not write.
Run `dartitect scan` as the canonical gate. Greenfield projects cannot hide
architecture findings behind debt baselines.

The local MCP may assist discovery with bounded inspect, scan, doctor, explain,
conformance, and preview tools. `dartitect_audit_conformance` reports strict
evidence; it never performs migration. Preview/apply
tools are separate capabilities and are outside a conformance audit.

Report constructor boundaries, ownership, provider leakage, runtime conflicts,
and missing evidence. Riverpod, BLoC, Provider, GetIt, MobX, Signals, and
equivalent architecture runtimes are prohibited. Provider leakage, service
location, duplicate ownership, concrete boundary crossings, and dual-write are
errors.
