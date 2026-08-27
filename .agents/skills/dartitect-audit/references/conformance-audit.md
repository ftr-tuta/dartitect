# Conformance audit

Start with read-only CLI operations. `inspect`, `scan`, and `doctor` do not write.
Run `scan --no-baseline` as the canonical gate. A reviewed baseline may describe
known debt for other workflows, but it never changes conformance evidence.

The local MCP may assist discovery with bounded inspect, scan, doctor, explain,
conformance, and preview tools. `dartitect_audit_conformance` reports only
evidence and declares existing projects `audit_only`; it never returns migration
steps. Preview/apply tools are separate capabilities and are outside a
conformance audit.

Report constructor boundaries, ownership, provider leakage, runtime conflicts,
and missing evidence. Do not recommend compatibility shims or coexistence with
Riverpod, BLoC, Provider, GetIt, MobX, Signals, or another competing runtime.
