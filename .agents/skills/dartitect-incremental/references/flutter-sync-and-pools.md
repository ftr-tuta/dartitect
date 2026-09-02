# Flutter, sync, and worker pools

Import `dartitect_flutter_incremental.dart` for the no-argument
`IncrementalCommand`. Each execution begins from a fresh initial aggregate.
Choose `everyEmission`, `coalesceMicrotask`, or `coalesceFrame`; coalescing never
skips reducer calls. Terminal states retain the partial aggregate, count,
weight, execution ID, and payload-free receipt. Use `restartLatest` only when
old execution publication is generation-fenced. The state builder accepts a
static child and stays Material-neutral.

`SyncDataset.incremental` serializes each successful checkpoint before asking
for another item. Sequential is the default; bounded DAG parallelism admits
ready nodes in plan order, runs only independent nodes, continues unrelated
branches after typed failure, blocks descendants, and fails fast on crashes.
Checkpoint, lease, and journal ports remain single-flight even when nodes run
in parallel.

`IsolateWorkerPool.spawn` requires explicit size, in-flight, and queue bounds.
`mapSequence` pauses input at capacity and bounds completed values waiting for
preserved order. Consumer cancellation drains input and admitted requests.
`failPool` is the default crash policy; `replaceWorker` spends a finite budget
without replaying an uncertain request. `disposeAsync` closes admission, drains,
then safely stops workers.
