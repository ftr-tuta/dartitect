# Sync tests

Use `OwnedGraphHarness` to prove rollback, drain-before-close, failed swap
retention, and exact zero admitted work. Use `SyncContractHarness` with manual
clock, sequence IDs, checkpoints, crash fault points, and fencing leases for a
deterministic DAG matrix.

Cover missing/duplicate/cyclic dependencies, stable plan order, downstream-only
blocking, independent branches, cancellation, deadlines, lease refusal/loss,
stale fencing rejection, checkpoint write failure, progress bounds, unexpected
rethrow with original stack, duplicate headless requests, protocol rejection,
fresh graph per accepted request, and shutdown drain. Add one real generated
storage fixture for checkpoint transactions without moving consumer schema or
conflict policy into the adapter.
