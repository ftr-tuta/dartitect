# Measurement and evidence

Start with structural gates: bounded queues/retention, one classification per
node, no quadratic readiness scan, backpressure, exact cleanup, no late
publication, and no residual request/worker. These are portable correctness
claims and may block release.

Use a curated matrix rather than a full Cartesian product. Cover 0, 1, 32,
1,000, and 100,000 emissions where practical; eager inputs, generators, and
batches; slow consumers and cancellation; multiple telemetry destinations;
and representative Flutter, sync, isolate, and CLI paths. Measure first item,
total time, RSS or retained state, throughput, and p50/p95 where the harness can
do so reproducibly.

Record SDK/runtime, OS, CPU architecture, mode, warmup, iteration count, input,
and bounds. Treat absolute time and memory as informational across different
runners. Compare regressions only on the same runner and preserve raw receipts
or machine-readable summaries needed to reproduce the conclusion.
