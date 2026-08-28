# Conformance audit

Start with read-only CLI operations. `inspect`, `scan`, and `doctor` do not write.
Run `scan --no-baseline` as the canonical gate. A reviewed baseline may describe
known debt for other workflows, but it never changes conformance evidence.

The local MCP may assist discovery with bounded inspect, scan, doctor, explain,
conformance, and preview tools. `dartitect_audit_conformance` reports evidence
and incremental-adoption status; it never performs migration. Preview/apply
tools are separate capabilities and are outside a conformance audit.

Report constructor boundaries, ownership, provider leakage, runtime conflicts,
and missing evidence. Riverpod, BLoC, Provider, GetIt, MobX, Signals, and
equivalents are overlap warnings when merely installed. Provider leakage,
service location, duplicate ownership, concrete boundary crossings, and
dual-write remain errors.
