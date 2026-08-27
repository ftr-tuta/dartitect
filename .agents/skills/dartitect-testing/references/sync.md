# Sync tests

Use `OwnedGraphHarness` to prove rollback, drain-before-close, failed swap
retention, and exact zero admitted work. Use `SyncContractHarness` with manual
clock, sequence IDs, checkpoints, crash fault points, and fencing leases for a
deterministic DAG matrix.

Cover missing/duplicate/cyclic dependencies, stable plan order, downstream-only
blocking, independent branches, cancellation, deadlines, lease refusal/loss,
authority expiry, atomic stale-token rejection at the dataset commit, checkpoint
write failure, journal/release/cleanup fault injection, receipt boundaries,
progress bounds, terminal exception with original cause/stack, duplicate
headless requests, protocol rejection, fresh graph per accepted request, and
shutdown drain. Add one real generated storage fixture for fencing-capable
dataset/checkpoint transactions without moving consumer schema or conflict
policy into the adapter.
