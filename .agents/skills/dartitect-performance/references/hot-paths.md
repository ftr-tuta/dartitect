# Hot paths and bounded state

Use `ListQueue` for FIFO admission and `BoundedRingBuffer<T>` for explicit
ordered recent retention. Do not use `List.removeAt(0)` or rebuild a retained
collection merely to append or evict. Track cumulative retained weight during
insert/evict rather than rescanning history.

For listeners, keep stable registrations with tombstones. Dispatch over the
current stable registry once, allow removal during callbacks, defer compaction
while dispatch is nested, and isolate one callback failure without a snapshot
plus repeated membership checks.

For DAG work, compile a dependent map and indegree count once. Admit ready nodes
through a stable queue, update only their dependents, and preserve declared
topological order in reports. For destination policy, compile winner lookup and
sanitize a classified/projected structure once before fan-out.

Run `dartitect inspect execution-model [--json]` for DT2200-DT2211 evidence.
Heuristics are informational; structurally strong findings may warn, but the
inspection remains non-blocking unless usage or internal execution fails.
