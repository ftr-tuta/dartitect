# Incremental migration

Start with read-only CLI operations. `inspect`, `scan`, and `doctor` do not write.
Run `scan --no-baseline` before deciding whether a baseline is warranted. Preview
baselines, generators, and Codex sync before applying them. Stable config v1 is
recreated and reviewed; experimental configs are never migrated.

The local MCP may assist discovery with bounded inspect, scan, doctor, explain,
adoption, and preview tools. It is read-only by default. A write requires server
opt-in, a reviewed preview, an opaque unexpired single-use plan, explicit
confirmation, client approval, full revalidation, serialization, and a lock.

Migrate constructor boundaries before replacing behavior. Add one provider
adapter at a time, with consumer ownership explicit. Reject duplicate Sentry or
Dio instrumentation. Keep compatibility shims narrow, tested, and scheduled for
removal. Never broaden the slice merely to make the migration look complete.
